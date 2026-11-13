// Config-level tests of the server the shell starts (task 4.7): the limits
// that are set once at start-up and apply to every request.
#include <string>

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

// Status of a GET with [extraHeaders], or 0 when the connection was refused or
// closed without an answer.
int statusOf(int port, const std::string& extraHeaders = "") {
  char err[256] = "";
  mg_connection* c = mg_download("127.0.0.1", port, 0, err, sizeof err,
                                 "GET /v1/hello HTTP/1.1\r\nHost: 127.0.0.1\r\n%sConnection: close\r\n\r\n",
                                 extraHeaders.c_str());
  if (c == nullptr) return 0;
  const int status = mg_get_response_info(c)->status_code;
  mg_close_connection(c);
  return status;
}

}  // namespace

TEST_CASE("source outside the allowed ranges is refused (ACL configured to exclude loopback)") {
  Cache cache;
  std::string error;
  ServerConfig open = loopbackConfig();
  auto reachable = Server::start(open, cache, &error);
  REQUIRE(reachable != nullptr);
  CHECK(statusOf(reachable->port()) == 200);  // the default list lets loopback in
  reachable->stop();

  // The same code path with the loopback range left out of the list.
  ServerConfig closed = loopbackConfig();
  closed.accessControlList = "-0.0.0.0/0,+10.0.0.0/8,+192.168.0.0/16";
  auto refusing = Server::start(closed, cache, &error);
  REQUIRE(refusing != nullptr);
  CHECK(statusOf(refusing->port()) != 200);
}

TEST_CASE("the default list is the one from address_filter") {
  ServerConfig c;
  CHECK(c.accessControlList.empty());
  CHECK(c.lanOnly);
}

TEST_CASE("pool size is 8") {
  CHECK(ServerConfig().workerThreads == 8);
  Cache cache;
  std::string error;
  auto server = Server::start(loopbackConfig(), cache, &error);
  REQUIRE(server != nullptr);
  CHECK(server->config().workerThreads == 8);
}

TEST_CASE("oversize request header is refused") {
  Cache cache;
  std::string error;
  auto server = Server::start(loopbackConfig(), cache, &error);
  REQUIRE(server != nullptr);
  CHECK(statusOf(server->port()) == 200);
  const std::string huge = "X-Padding: " + std::string(40000, 'a') + "\r\n";
  CHECK(statusOf(server->port(), huge) != 200);
  CHECK(statusOf(server->port()) == 200);  // and the server is still fine
}
