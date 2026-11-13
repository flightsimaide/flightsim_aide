#include <set>
#include <string>
#include <vector>

#include "civetweb.h"
#include "doctest.h"
#include "server_lifecycle.h"

using namespace flightsim_aide;

namespace {

ServerConfig loopbackConfig() {
  ServerConfig c;
  c.bindAddress = "127.0.0.1";
  c.simVersion = "12.1.4";
  c.pluginVersion = "0.1.0";
  return c;
}

// A free port, found by binding to 0 and letting go again.
int freePort() {
  Cache cache;
  std::string error;
  auto s = Server::start(loopbackConfig(), cache, &error);
  REQUIRE(s != nullptr);
  const int port = s->port();
  s->stop();
  return port;
}

std::string httpGetBody(int port, const std::string& path, int* status = nullptr) {
  char err[256] = "";
  mg_connection* c = mg_download("127.0.0.1", port, 0, err, sizeof err,
                                 "GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n", path.c_str());
  if (c == nullptr) {
    if (status != nullptr) *status = 0;
    return "";
  }
  if (status != nullptr) *status = mg_get_response_info(c)->status_code;
  std::string body;
  char buf[2048];
  int n;
  while ((n = mg_read(c, buf, sizeof buf)) > 0) body.append(buf, static_cast<size_t>(n));
  mg_close_connection(c);
  return body;
}

// A bind function that refuses the ports in [busy] and records every attempt.
// The "bound" server listens on an OS port: only the decision is under test.
struct FakeBind {
  std::set<int> busy;
  std::vector<int> tried;
  BindFn fn() {
    return [this](const ServerConfig& config, Cache& cache, std::string* error) -> std::unique_ptr<Server> {
      tried.push_back(config.port);
      if (busy.count(config.port) != 0) {
        *error = "busy";
        return nullptr;
      }
      ServerConfig os = config;
      os.port = 0;
      return Server::start(os, cache, error);
    };
  }
};

const std::vector<int> kPlugin = {18086, 18087, 18088, 18089, 18090, 18091, 18092, 18093};

}  // namespace

TEST_CASE("the default ports are 18086 to 18093") { CHECK(ServerLifecycle::defaultPorts() == kPlugin); }

TEST_CASE("preferred port free is chosen") {
  Cache cache;
  FakeBind bind;
  ServerLifecycle life(cache, loopbackConfig(), bind.fn());
  CHECK(life.start());
  CHECK(life.running());
  CHECK(bind.tried == std::vector<int>{18086});
}

TEST_CASE("preferred busy picks the next") {
  Cache cache;
  FakeBind bind;
  bind.busy = {18086, 18087};
  ServerLifecycle life(cache, loopbackConfig(), bind.fn());
  CHECK(life.start());
  CHECK(bind.tried == std::vector<int>{18086, 18087, 18088});
}

TEST_CASE("all eight busy gives none and a reason") {
  Cache cache;
  FakeBind bind;
  bind.busy.insert(kPlugin.begin(), kPlugin.end());
  ServerLifecycle life(cache, loopbackConfig(), bind.fn());
  CHECK_FALSE(life.start());
  CHECK_FALSE(life.running());
  CHECK(life.port() == 0);
  CHECK(bind.tried == kPlugin);  // never an OS-assigned port (D-38)
  CHECK(life.failureReason().find("18086") != std::string::npos);
  CHECK(life.failureReason().find("18093") != std::string::npos);
}

TEST_CASE("hello reports the bound port") {
  const int busyPort = freePort();
  Cache holderCache;
  std::string error;
  ServerConfig holderConfig = loopbackConfig();
  holderConfig.port = busyPort;
  auto holder = Server::start(holderConfig, holderCache, &error);
  REQUIRE(holder != nullptr);
  const int goodPort = freePort();

  Cache cache;
  ServerLifecycle life(cache, loopbackConfig(), nullptr, {busyPort, goodPort});
  REQUIRE(life.start());
  CHECK(life.port() == goodPort);
  int status = 0;
  const std::string body = httpGetBody(goodPort, "/v1/hello", &status);
  CHECK(status == 200);
  CHECK(body.find("\"port\":" + std::to_string(goodPort)) != std::string::npos);
}

TEST_CASE("stop joins every thread") {
  const int port = freePort();
  Cache cache;
  ServerLifecycle life(cache, loopbackConfig(), nullptr, {port});
  REQUIRE(life.start());
  int status = 0;
  httpGetBody(port, "/v1/hello", &status);
  CHECK(status == 200);
  life.stop();
  CHECK_FALSE(life.running());
  CHECK(life.port() == 0);
  httpGetBody(port, "/v1/hello", &status);
  CHECK(status == 0);  // nothing listens any more
  life.stop();         // idempotent
}

TEST_CASE("restart after stop binds again") {
  const int port = freePort();
  Cache cache;
  ServerLifecycle life(cache, loopbackConfig(), nullptr, {port});
  for (int i = 0; i < 3; ++i) {
    REQUIRE(life.start());
    CHECK(life.port() == port);
    int status = 0;
    httpGetBody(port, "/v1/hello", &status);
    CHECK(status == 200);
    life.stop();
  }
}

TEST_CASE("start while running does nothing") {
  Cache cache;
  FakeBind bind;
  ServerLifecycle life(cache, loopbackConfig(), bind.fn());
  REQUIRE(life.start());
  CHECK(life.start());
  CHECK(bind.tried.size() == 1);
}

TEST_CASE("tick without a server is harmless") {
  struct Nothing : ValueSource {
    Resolution resolve(const std::string&, int) override { return Resolution(); }
    double read(uint64_t) override { return 0; }
  } source;
  Cache cache;
  FakeBind bind;
  ServerLifecycle life(cache, loopbackConfig(), bind.fn());
  life.tick(source);  // not started
  REQUIRE(life.start());
  life.tick(source);
}
