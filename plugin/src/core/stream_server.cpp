#include <chrono>
#include <cstring>
#include "stream_server.h"

#include <map>
#include <vector>

#include "address_filter.h"
#include "civetweb.h"
#include "json_writer.h"
#include "router.h"

namespace flightsim_aide {

namespace {

// How long an aircraft request waits for the sim thread to re-check the file.
constexpr std::chrono::milliseconds kRefreshWait{500};

Instant monotonicNow() {
  return std::chrono::duration_cast<Instant>(std::chrono::steady_clock::now().time_since_epoch());
}

int64_t epochMillisNow() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

const char* statusText(int status) {
  switch (status) {
    case 200: return "OK";
    case 304: return "Not Modified";
    case 400: return "Bad Request";
    case 404: return "Not Found";
    case 405: return "Method Not Allowed";
    case 413: return "Payload Too Large";
    case 503: return "Service Unavailable";
    default: return "Error";
  }
}

}  // namespace

// One connected stream client: the CivetWeb connection and the thread that
// writes to it.
struct StreamClient {
  StreamHub::ClientId id = 0;
  mg_connection* conn = nullptr;
  std::thread writer;
  std::mutex mutex;
  std::condition_variable wake;
  bool stopping = false;
};

struct Server::Impl {
  Server* owner = nullptr;
  mg_context* ctx = nullptr;
  std::atomic<int> boundPort{0};
  std::atomic<bool> stopped{false};

  // ---- HTTP

  static int httpHandler(mg_connection* conn, void* userData) {
    Impl* self = static_cast<Impl*>(userData);
    const mg_request_info* info = mg_get_request_info(conn);

    Request request;
    request.method = info->request_method ? info->request_method : "";
    // The raw request target: never decoded, never normalised.
    request.path = info->request_uri ? info->request_uri : "";
    for (int i = 0; i < info->num_headers; ++i) {
      request.headers.emplace_back(info->http_headers[i].name, info->http_headers[i].value);
    }

    ServerInfo serverInfo;
    serverInfo.port = self->boundPort;
    serverInfo.simKind = self->owner->config_.simKind;
    serverInfo.simVersion = self->owner->config_.simVersion;
    serverInfo.os = self->owner->config_.os;
    serverInfo.pluginVersion = self->owner->config_.pluginVersion;
    serverInfo.runId = self->owner->config_.runId;

    // The checklist file's size and time must be current: ask the sim thread to
    // re-check the file now instead of waiting for its next scheduled look.
    if (request.path == "/v1/aircraft") self->owner->cache_.requestRefresh(kRefreshWait);

    const Response response = route(request, self->owner->cache_.snapshot(), serverInfo);
    self->send(conn, response);
    return response.status;
  }

  static void send(mg_connection* conn, const Response& r) {
    mg_response_header_start(conn, r.status);
    for (const auto& h : r.headers) {
      mg_response_header_add(conn, h.first.c_str(), h.second.c_str(), -1);
    }
    mg_response_header_send(conn);
    if (!r.body.empty()) mg_write(conn, r.body.data(), r.body.size());
  }

  // ---- WebSocket

  std::mutex clientsMutex;
  std::map<StreamHub::ClientId, std::unique_ptr<StreamClient>> clients;

  static int wsConnect(const mg_connection* connConst, void* userData) {
    Impl* self = static_cast<Impl*>(userData);
    mg_connection* conn = const_cast<mg_connection*>(connConst);
    const std::optional<StreamHub::ClientId> id = self->owner->hub_.connect(monotonicNow());
    if (!id) {
      const std::string body = errorJson("limit", "At most 4 stream clients at once.");
      mg_printf(conn,
                "HTTP/1.1 503 Service Unavailable\r\n"
                "Content-Type: application/json; charset=utf-8\r\n"
                "Cache-Control: no-store\r\n"
                "Content-Length: %d\r\n"
                "Connection: close\r\n\r\n%s",
                static_cast<int>(body.size()), body.c_str());
      return 1;  // no handshake
    }
    auto client = std::make_unique<StreamClient>();
    client->id = *id;
    client->conn = conn;
    StreamClient* raw = client.get();
    {
      std::lock_guard<std::mutex> lock(self->clientsMutex);
      self->clients[*id] = std::move(client);
    }
    mg_set_user_connection_data(conn, raw);
    return 0;
  }

  static void wsReady(mg_connection* conn, void* userData) {
    Impl* self = static_cast<Impl*>(userData);
    StreamClient* client = static_cast<StreamClient*>(mg_get_user_connection_data(conn));
    if (client == nullptr) return;
    client->writer = std::thread([self, client] { self->writeLoop(client); });
  }

  static int wsData(mg_connection* conn, int bits, char* data, size_t len, void* userData) {
    Impl* self = static_cast<Impl*>(userData);
    StreamClient* client = static_cast<StreamClient*>(mg_get_user_connection_data(conn));
    if (client == nullptr) return 0;
    const int opcode = bits & 0xF;
    switch (opcode) {
      case MG_WEBSOCKET_OPCODE_TEXT:
        self->owner->hub_.onClientMessage(client->id, std::string(data, len), monotonicNow());
        return 1;
      case MG_WEBSOCKET_OPCODE_PING:
        self->owner->hub_.onClientActivity(client->id, monotonicNow());
        mg_websocket_write(conn, MG_WEBSOCKET_OPCODE_PONG, data, len);
        return 1;
      case MG_WEBSOCKET_OPCODE_PONG:
        self->owner->hub_.onClientActivity(client->id, monotonicNow());
        return 1;
      case MG_WEBSOCKET_OPCODE_CONNECTION_CLOSE:
        return 0;
      default:
        // Binary and continuation frames are not part of the protocol.
        self->owner->hub_.onClientMessage(client->id, "", monotonicNow());
        return 1;
    }
  }

  static void wsClose(const mg_connection* connConst, void* userData) {
    Impl* self = static_cast<Impl*>(userData);
    mg_connection* conn = const_cast<mg_connection*>(connConst);
    StreamClient* client = static_cast<StreamClient*>(mg_get_user_connection_data(conn));
    if (client == nullptr) return;
    {
      std::lock_guard<std::mutex> lock(client->mutex);
      client->stopping = true;
    }
    client->wake.notify_all();
    // The connection stays valid until this handler returns, so the writer
    // must be gone first.
    if (client->writer.joinable()) client->writer.join();
    self->owner->hub_.disconnect(client->id);
    mg_set_user_connection_data(conn, nullptr);
    std::lock_guard<std::mutex> lock(self->clientsMutex);
    self->clients.erase(client->id);  // destroys *client
  }

  void writeLoop(StreamClient* client) {
    while (true) {
      {
        std::unique_lock<std::mutex> lock(client->mutex);
        if (client->wake.wait_for(lock, owner->config_.senderInterval,
                                  [&] { return client->stopping; })) {
          return;
        }
      }
      const StreamHub::Outgoing out = owner->hub_.collectOutgoing(client->id, monotonicNow());
      for (const std::string& frame : out.frames) {
        if (mg_websocket_write(client->conn, MG_WEBSOCKET_OPCODE_TEXT, frame.data(), frame.size()) <= 0) {
          mg_close_connection(client->conn);  // asks the read loop to end
          return;
        }
      }
      if (out.sendPing) {
        mg_websocket_write(client->conn, MG_WEBSOCKET_OPCODE_PING, nullptr, 0);
      }
      if (out.close) {
        mg_websocket_write(client->conn, MG_WEBSOCKET_OPCODE_CONNECTION_CLOSE, nullptr, 0);
        mg_close_connection(client->conn);
        return;
      }
    }
  }
};

Server::Server(const ServerConfig& config, Cache& cache)
    : impl_(new Impl), config_(config), cache_(cache) {
  impl_->owner = this;
}

std::unique_ptr<Server> Server::start(const ServerConfig& config, Cache& cache, std::string* error) {
  std::unique_ptr<Server> server(new Server(config, cache));
  Impl* impl = server->impl_.get();

  mg_init_library(0);
  const std::string listen = config.bindAddress + ":" + std::to_string(config.port);
  const std::string threads = std::to_string(config.workerThreads);
  const std::string acl =
      config.accessControlList.empty() ? flightsim_aide::accessControlList() : config.accessControlList;
  std::vector<const char*> options = {
      "listening_ports", listen.c_str(),
      "num_threads", threads.c_str(),
      "enable_keep_alive", "yes",
      "keep_alive_timeout_ms", "2000",
      "request_timeout_ms", "5000",
      // The read loop wakes this often, which bounds how long a forced close
      // (mg_close_connection from the writer) and a shutdown take.
      "websocket_timeout_ms", "1000",
      "enable_websocket_ping_pong", "no",
  };
  if (config.lanOnly) {
    options.push_back("access_control_list");
    options.push_back(acl.c_str());
  }
  options.push_back(nullptr);

  mg_callbacks callbacks;
  std::memset(&callbacks, 0, sizeof callbacks);
  impl->ctx = mg_start(&callbacks, impl, options.data());
  if (impl->ctx == nullptr) {
    if (error != nullptr) *error = "Could not listen on " + listen + ".";
    return nullptr;
  }

  mg_server_port ports[4];
  const int n = mg_get_server_ports(impl->ctx, 4, ports);
  if (n < 1) {
    if (error != nullptr) *error = "Could not read the bound port.";
    server->stop();
    return nullptr;
  }
  server->port_ = ports[0].port;
  impl->boundPort = ports[0].port;

  mg_set_request_handler(impl->ctx, "**", &Impl::httpHandler, impl);
  mg_set_websocket_handler(impl->ctx, "/v1/stream", &Impl::wsConnect, &Impl::wsReady, &Impl::wsData,
                           &Impl::wsClose, impl);
  return server;
}

void Server::tick(ValueSource& source) {
  hub_.tick(source, cache_.generation(), monotonicNow(), epochMillisNow());
}

void Server::stop() {
  if (impl_ == nullptr || impl_->stopped.exchange(true)) return;
  if (impl_->ctx != nullptr) {
    mg_stop(impl_->ctx);  // runs the close handlers, which join the writers
    impl_->ctx = nullptr;
  }
}

Server::~Server() { stop(); }

TickThread::TickThread(Server& server, ValueSource& source, std::chrono::milliseconds interval)
    : thread_([this, &server, &source, interval] {
        while (!stop_) {
          server.tick(source);
          std::unique_lock<std::mutex> lock(mutex_);
          wake_.wait_for(lock, interval, [this] { return stop_.load(); });
        }
      }) {}

TickThread::~TickThread() { stop(); }

void TickThread::stop() {
  stop_ = true;
  wake_.notify_all();
  if (thread_.joinable()) thread_.join();
}

}  // namespace flightsim_aide
