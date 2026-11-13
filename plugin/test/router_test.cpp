#include "doctest.h"
#include "router.h"
#include "test_util.h"

using namespace flightsim_aide;

namespace {

Request req(const std::string& method, const std::string& path) {
  Request r;
  r.method = method;
  r.path = path;
  return r;
}

CacheData cessna() {
  CacheData d;
  d.generation = 12;
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

ServerInfo info() {
  ServerInfo i;
  i.port = 18086;
  i.simVersion = "12.1.4";
  i.os = "windows";
  i.pluginVersion = "0.1.0";
  i.runId = "a1b2c3d4e5f60718";
  return i;
}

Response go(const std::string& method, const std::string& path) {
  return route(req(method, path), cessna(), info());
}

bool hasError(const Response& r, const std::string& code) {
  return r.body.find("\"error\":\"" + code + "\"") != std::string::npos;
}

}  // namespace

TEST_CASE("the three http paths are served") {
  CHECK(go("GET", "/v1/hello").body == readFixture("hello.json"));
  CHECK(go("GET", "/v1/aircraft").body == readFixture("aircraft_with_checklist.json"));
  CHECK(go("GET", "/v1/checklist").body == readFixture("checklist_sample.txt"));
  CHECK(go("HEAD", "/v1/checklist").status == 200);
}

TEST_CASE("POST/PUT/DELETE give 405") {
  for (const char* path : {"/v1/hello", "/v1/aircraft", "/v1/checklist", "/v1/stream"}) {
    for (const char* method : {"POST", "PUT", "DELETE", "PATCH", "OPTIONS"}) {
      CAPTURE(path);
      CAPTURE(method);
      const Response r = go(method, path);
      CHECK(r.status == 405);
      CHECK(hasError(r, "method_not_allowed"));
      CHECK(r.header("Allow") == "GET, HEAD");
    }
  }
}

TEST_CASE("unknown path gives 404") {
  for (const char* path : {"/", "/v1", "/v1/", "/v1/other", "/v2/aircraft", "/nothing", "/v1/aircraft/",
                           "/v1/Aircraft", "/V1/aircraft", "", "v1/aircraft", "/v1/hello/x"}) {
    CAPTURE(path);
    const Response r = go("GET", path);
    CHECK(r.status == 404);
    CHECK(hasError(r, "not_found"));
  }
  CHECK(go("POST", "/nothing").status == 404);
  CHECK(go("DELETE", "/").status == 404);
}

TEST_CASE("traversal-style paths give 404") {
  for (const char* path : {"/v1/checklist/..%2f..%2fetc%2fpasswd", "/v1/../v1/aircraft", "/../v1/aircraft",
                           "/v1/checklist/../../etc/passwd", "/v1/..%5caircraft",
                           "/v1/checklist%00.txt"}) {
    CAPTURE(path);
    CHECK(go("GET", path).status == 404);
  }
}

TEST_CASE("query string does not change the response") {
  CHECK(go("GET", "/v1/aircraft?icao=B738&path=../x").body ==
        go("GET", "/v1/aircraft").body);
  CHECK(go("GET", "/v1/checklist?path=../x").body == go("GET", "/v1/checklist").body);
  CHECK(go("GET", "/v1/hello?").status == 200);
  CHECK(go("GET", "/v1/other?x=/v1/aircraft").status == 404);
}

TEST_CASE("double slash path gives 404") {
  CHECK(go("GET", "//v1/aircraft").status == 404);
  CHECK(go("GET", "/v1//aircraft").status == 404);
}

TEST_CASE("percent-encoded dots give 404") {
  CHECK(go("GET", "/v1/%2e%2e/aircraft").status == 404);
  CHECK(go("GET", "/v1/%2E%2E/aircraft").status == 404);
  CHECK(go("GET", "/v1/%61ircraft").status == 404);  // %61 is "a": never decoded
}

TEST_CASE("plain GET on the stream path gives 400") {
  const Response r = go("GET", "/v1/stream");
  CHECK(r.status == 400);
  CHECK(hasError(r, "upgrade_required"));
  CHECK(go("HEAD", "/v1/stream").status == 400);
  CHECK(go("GET", "/v1/stream?x=1").status == 400);
}

TEST_CASE("POST to the stream path gives 405") {
  const Response r = go("POST", "/v1/stream");
  CHECK(r.status == 405);
  CHECK(hasError(r, "method_not_allowed"));
}

TEST_CASE("error responses are json and not cached") {
  const Response r = go("GET", "/nope");
  CHECK(r.header("Content-Type") == "application/json; charset=utf-8");
  CHECK(r.header("Cache-Control") == "no-store");
  CHECK(r.header("Content-Length") == std::to_string(r.body.size()));
}
