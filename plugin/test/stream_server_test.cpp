#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <functional>
#include <map>
#include <mutex>
#include <thread>

#include "civetweb.h"
#include "doctest.h"
#include "stream_server.h"
#include "test_util.h"

using namespace flightsim_aide;
using namespace std::chrono_literals;

namespace {

const char* kOnGround = "sim/flightmodel/failures/onground_any";

class FakeSource : public ValueSource {
 public:
  Resolution resolve(const std::string& name, int) override {
    Resolution r;
    if (name == kOnGround) {
      r.status = Resolution::Status::ok;
      r.handle = 1;
    }
    return r;
  }
  double read(uint64_t) override { return 1; }
};

CacheData cessna() {
  CacheData d;
  d.icao = "C172";
  d.description = "Cessna Skyhawk 172SP";
  d.aircraftPath = "Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf";
  d.hasChecklist = true;
  d.checklistPath = "Aircraft/Laminar Research/Cessna 172SP/clist.txt";
  d.checklistModified = 1761206400123;
  d.checklistSize = 267;
  d.checklistText = readFixture("checklist_sample.txt");
  return d;
}

// A WebSocket client over CivetWeb's own client API. [block] makes the data
// callback wait, which makes a reader that has stopped reading.
class WsClient {
 public:
  static std::unique_ptr<WsClient> connect(int port) {
    std::unique_ptr<WsClient> c(new WsClient);
    char err[256] = "";
    c->conn_ = mg_connect_websocket_client("127.0.0.1", port, 0, err, sizeof err, "/v1/stream", nullptr,
                                           &WsClient::onData, &WsClient::onClose, c.get());
    if (c->conn_ == nullptr) return nullptr;
    return c;
  }

  ~WsClient() {
    release();
    if (conn_ != nullptr) mg_close_connection(conn_);
  }

  void send(const std::string& text) {
    mg_websocket_client_write(conn_, MG_WEBSOCKET_OPCODE_TEXT, text.data(), text.size());
  }

  // The first frame at or after index [from] that satisfies [pred], waiting up to [timeout].
  bool waitFor(const std::function<bool(const std::string&)>& pred, std::chrono::milliseconds timeout,
               std::string* found = nullptr, size_t from = 0) {
    std::unique_lock<std::mutex> lock(mutex_);
    size_t next = from;
    return cv_.wait_for(lock, timeout, [&] {
      for (; next < frames_.size(); ++next) {
        if (pred(frames_[next])) {
          if (found != nullptr) *found = frames_[next];
          return true;
        }
      }
      return false;
    });
  }

  bool waitForText(const std::string& needle, std::chrono::milliseconds timeout = 3000ms,
                   std::string* found = nullptr) {
    return waitFor([&](const std::string& f) { return f.find(needle) != std::string::npos; }, timeout,
                   found);
  }

  bool waitClosed(std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lock(mutex_);
    return cv_.wait_for(lock, timeout, [&] { return closed_; });
  }

  size_t frameCount() {
    std::lock_guard<std::mutex> lock(mutex_);
    return frames_.size();
  }

  std::vector<std::string> frames() {
    std::lock_guard<std::mutex> lock(mutex_);
    return frames_;
  }

  void setBlocking(bool block) {
    std::lock_guard<std::mutex> lock(mutex_);
    block_ = block;
    cv_.notify_all();
  }

  void release() { setBlocking(false); }

 private:
  WsClient() = default;

  static int onData(mg_connection*, int bits, char* data, size_t len, void* self) {
    WsClient* c = static_cast<WsClient*>(self);
    if ((bits & 0xF) != MG_WEBSOCKET_OPCODE_TEXT) return 1;
    std::unique_lock<std::mutex> lock(c->mutex_);
    c->frames_.emplace_back(data, len);
    c->cv_.notify_all();
    c->cv_.wait(lock, [&] { return !c->block_; });
    return 1;
  }

  static void onClose(const mg_connection*, void* self) {
    WsClient* c = static_cast<WsClient*>(self);
    std::lock_guard<std::mutex> lock(c->mutex_);
    c->closed_ = true;
    c->cv_.notify_all();
  }

  mg_connection* conn_ = nullptr;
  std::mutex mutex_;
  std::condition_variable cv_;
  std::vector<std::string> frames_;
  bool closed_ = false;
  bool block_ = false;
};

struct HttpResult {
  int status = 0;
  std::string body;
  std::string error;
};

HttpResult httpGet(int port, const std::string& path, const std::string& extraHeaders = "") {
  HttpResult r;
  char err[256] = "";
  mg_connection* c = mg_download("127.0.0.1", port, 0, err, sizeof err,
                                 "GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\n%sConnection: close\r\n\r\n",
                                 path.c_str(), extraHeaders.c_str());
  if (c == nullptr) {
    r.error = err;
    return r;
  }
  r.status = mg_get_response_info(c)->status_code;
  char buf[4096];
  int n;
  while ((n = mg_read(c, buf, sizeof buf)) > 0) r.body.append(buf, static_cast<size_t>(n));
  mg_close_connection(c);
  return r;
}

HttpResult upgradeRequest(int port) {
  return httpGet(port, "/v1/stream",
                 "Upgrade: websocket\r\nSec-WebSocket-Version: 13\r\n"
                 "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n"
                 "Connection: Upgrade\r\n");
}

std::string sub(int id, const std::string& name, int hz) {
  return "{\"op\":\"subscribe\",\"id\":" + std::to_string(id) + ",\"name\":\"" + name +
         "\",\"hz\":" + std::to_string(hz) + "}";
}

struct Rig {
  Cache cache;
  FakeSource source;
  std::unique_ptr<Server> server;
  std::unique_ptr<TickThread> ticker;

  Rig() {
    cache.update(cessna());
    cache.setGeneration(12);
    ServerConfig config;
    config.bindAddress = "127.0.0.1";
    config.simVersion = "12.1.4";
    config.pluginVersion = "0.1.0";
    std::string error;
    server = Server::start(config, cache, &error);
    REQUIRE_MESSAGE(server != nullptr, error);
    ticker = std::make_unique<TickThread>(*server, source, 10ms);
  }

  ~Rig() {
    ticker->stop();
    server->stop();
  }

  int port() const { return server->port(); }
};

}  // namespace

TEST_CASE("http answers over a real socket") {
  Rig r;
  const HttpResult hello = httpGet(r.port(), "/v1/hello");
  CHECK(hello.status == 200);
  CHECK(hello.body.find("\"port\":" + std::to_string(r.port())) != std::string::npos);
  CHECK(httpGet(r.port(), "/v1/aircraft").body == readFixture("aircraft_with_checklist.json"));
  CHECK(httpGet(r.port(), "/v1/checklist").body == readFixture("checklist_sample.txt"));
  CHECK(httpGet(r.port(), "/v1/nothing").status == 404);
  CHECK(httpGet(r.port(), "/v1/stream").status == 400);
}

TEST_CASE("GET /v1/aircraft asks the sim thread to re-check the file first") {
  Rig r;
  r.cache.enableRefreshRequests();
  std::atomic<bool> stop{false};
  std::thread sim([&] {
    while (!stop) {
      if (const int64_t ticket = r.cache.pendingRefresh()) {
        CacheData d = cessna();
        d.checklistSize = 288;  // the file was edited on disk
        r.cache.update(d);
        r.cache.refreshServed(ticket);
      }
      std::this_thread::sleep_for(1ms);
    }
  });
  const HttpResult aircraft = httpGet(r.port(), "/v1/aircraft");
  stop = true;
  sim.join();
  CHECK(aircraft.body.find("\"checklistSize\":288") != std::string::npos);
}

TEST_CASE("GET /v1/hello does not wait for a refresh") {
  Rig r;
  r.cache.enableRefreshRequests();  // nobody serves it
  const auto start = std::chrono::steady_clock::now();
  CHECK(httpGet(r.port(), "/v1/hello").status == 200);
  CHECK(std::chrono::steady_clock::now() - start < 400ms);
}

TEST_CASE("subscribe over a real socket gets subscribed and values") {
  Rig r;
  auto c = WsClient::connect(r.port());
  REQUIRE(c != nullptr);
  c->send(sub(1, kOnGround, 10));
  CHECK(c->waitForText("{\"op\":\"subscribed\",\"id\":1}"));
  CHECK(c->waitForText("\"v\":{\"1\":1}"));
  CHECK(c->waitForText("{\"op\":\"pong\"}", 200ms) == false);
  c->send("{\"op\":\"ping\"}");
  CHECK(c->waitForText("{\"op\":\"pong\"}"));
}

TEST_CASE("unknown name gets unknown_name over the socket") {
  Rig r;
  auto c = WsClient::connect(r.port());
  REQUIRE(c != nullptr);
  c->send(sub(2, "no/such", 1));
  std::string frame;
  REQUIRE(c->waitForText("unknown_name", 3000ms, &frame));
  CHECK(frame.find("\"id\":2") != std::string::npos);
}

TEST_CASE("an idle client gets heartbeats") {
  Rig r;
  auto c = WsClient::connect(r.port());
  REQUIRE(c != nullptr);
  CHECK(c->waitForText("{\"op\":\"hb\"}", 2500ms));
}

TEST_CASE("fifth client is refused with 503") {
  Rig r;
  std::vector<std::unique_ptr<WsClient>> clients;
  for (int i = 0; i < 4; ++i) {
    clients.push_back(WsClient::connect(r.port()));
    REQUIRE(clients.back() != nullptr);
  }
  const HttpResult fifth = upgradeRequest(r.port());
  CHECK(fifth.status == 503);
  CHECK(fifth.body.find("\"error\":\"limit\"") != std::string::npos);

  // A closed client frees its slot.
  clients[0].reset();
  bool accepted = false;
  for (int i = 0; i < 50 && !accepted; ++i) {
    std::this_thread::sleep_for(100ms);
    auto again = WsClient::connect(r.port());
    if (again != nullptr) {
      accepted = true;
      clients.push_back(std::move(again));
    }
  }
  CHECK(accepted);
}

TEST_CASE("closing the client removes its subscriptions") {
  Rig r;
  auto c = WsClient::connect(r.port());
  REQUIRE(c != nullptr);
  c->send(sub(1, kOnGround, 10));
  REQUIRE(c->waitForText("subscribed"));
  CHECK(r.server->hub().requestedNames().size() == 1);
  c.reset();
  bool gone = false;
  for (int i = 0; i < 50 && !gone; ++i) {
    std::this_thread::sleep_for(100ms);
    gone = r.server->hub().requestedNames().empty() && r.server->hub().clientCount() == 0;
  }
  CHECK(gone);
}

TEST_CASE("http still answers while four stream clients are connected") {
  Rig r;
  std::vector<std::unique_ptr<WsClient>> clients;
  for (int i = 0; i < 4; ++i) {
    clients.push_back(WsClient::connect(r.port()));
    REQUIRE(clients.back() != nullptr);
    clients.back()->send(sub(1, kOnGround, 30));
  }
  for (int i = 0; i < 20; ++i) {
    CHECK(httpGet(r.port(), "/v1/hello").status == 200);
    CHECK(httpGet(r.port(), "/v1/checklist").body == readFixture("checklist_sample.txt"));
  }
}

TEST_CASE("a stalled reader does not block another client") {
  Rig r;
  // The stalled client subscribes to the maximum and then stops reading.
  auto stalled = WsClient::connect(r.port());
  REQUIRE(stalled != nullptr);
  for (int i = 1; i <= 128; ++i) stalled->send(sub(i, kOnGround, 60));
  REQUIRE(stalled->waitForText("\"v\":{"));
  stalled->setBlocking(true);

  auto healthy = WsClient::connect(r.port());
  REQUIRE(healthy != nullptr);
  healthy->send(sub(1, kOnGround, 20));
  REQUIRE(healthy->waitForText("subscribed"));

  // Watch the healthy client for long enough that the stalled one's socket
  // buffers fill up and its writer blocks.
  const auto start = std::chrono::steady_clock::now();
  size_t seen = healthy->frameCount();
  auto lastProgress = start;
  std::chrono::milliseconds longestGap{0};
  while (std::chrono::steady_clock::now() - start < 9s) {
    std::this_thread::sleep_for(25ms);
    const size_t now = healthy->frameCount();
    const auto t = std::chrono::steady_clock::now();
    if (now != seen) {
      longestGap = std::max(longestGap, std::chrono::duration_cast<std::chrono::milliseconds>(t - lastProgress));
      lastProgress = t;
      seen = now;
    }
  }
  CHECK(longestGap < 400ms);
  // About 20 per second for 9 s on an idle machine. A slow CI runner gave 127,
  // so the bound is low; a blocked writer would give almost none.
  CHECK(seen > 90);
  stalled->release();
}

TEST_CASE("shutdown closes clients and joins all threads") {
  Cache cache;
  cache.update(cessna());
  FakeSource source;
  ServerConfig config;
  config.bindAddress = "127.0.0.1";
  std::string error;
  auto server = Server::start(config, cache, &error);
  REQUIRE(server != nullptr);
  auto ticker = std::make_unique<TickThread>(*server, source, 10ms);

  auto a = WsClient::connect(server->port());
  auto b = WsClient::connect(server->port());
  REQUIRE(a != nullptr);
  REQUIRE(b != nullptr);
  a->send(sub(1, kOnGround, 30));
  REQUIRE(a->waitForText("\"v\":{"));

  const auto start = std::chrono::steady_clock::now();
  ticker->stop();
  server->stop();
  CHECK(std::chrono::steady_clock::now() - start < 4s);
  CHECK(a->waitClosed(3000ms));
  CHECK(b->waitClosed(3000ms));
  CHECK(server->hub().clientCount() == 0);
  // The port is free again.
  const int port = server->port();
  server.reset();
  ServerConfig again = config;
  again.port = port;
  CHECK(Server::start(again, cache, &error) != nullptr);
}

TEST_CASE("a port that is taken is reported, not fatal") {
  Rig r;
  Cache cache;
  ServerConfig config;
  config.bindAddress = "127.0.0.1";
  config.port = r.port();
  std::string error;
  CHECK(Server::start(config, cache, &error) == nullptr);
  CHECK_FALSE(error.empty());
}

TEST_CASE("a quiet but responsive client is not closed") {
  Rig r;
  auto c = WsClient::connect(r.port());
  REQUIRE(c != nullptr);
  std::this_thread::sleep_for(1500ms);
  CHECK_FALSE(c->waitClosed(10ms));
  c->send("{\"op\":\"ping\"}");
  CHECK(c->waitForText("pong"));
}
