#include "doctest.h"
#include "handlers.h"
#include "test_util.h"

using namespace flightsim_aide;

namespace {

Request get(const std::string& path, const std::string& method = "GET") {
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

}  // namespace

TEST_CASE("hello matches golden") {
  const Response r = handleHello(get("/v1/hello"), info());
  CHECK(r.status == 200);
  CHECK(r.body == readFixture("hello.json"));
  CHECK(r.header("Content-Type") == "application/json; charset=utf-8");
  CHECK(r.header("Cache-Control") == "no-store");
  CHECK(r.header("Content-Length") == std::to_string(r.body.size()));
}

TEST_CASE("hello port is the bound port") {
  ServerInfo i = info();
  i.port = 18089;
  CHECK(handleHello(get("/v1/hello"), i).body.find("\"port\":18089,") != std::string::npos);
}

TEST_CASE("aircraft response matches golden") {
  const Response r = handleAircraft(get("/v1/aircraft"), cessna());
  CHECK(r.status == 200);
  CHECK(r.body == readFixture("aircraft_with_checklist.json"));
  CHECK(r.header("Content-Type") == "application/json; charset=utf-8");
  CHECK(r.header("Cache-Control") == "no-store");
}

TEST_CASE("no checklist omits fields") {
  CacheData d = cessna();
  d.hasChecklist = false;
  d.checklistText.clear();
  const Response r = handleAircraft(get("/v1/aircraft"), d);
  CHECK(r.body == readFixture("aircraft_no_checklist.json"));
}

TEST_CASE("head has headers and no body") {
  const Response h = handleAircraft(get("/v1/aircraft", "HEAD"), cessna());
  const Response g = handleAircraft(get("/v1/aircraft"), cessna());
  CHECK(h.status == 200);
  CHECK(h.body.empty());
  CHECK(h.header("Content-Type") == "application/json; charset=utf-8");
  CHECK(h.header("Content-Length") == std::to_string(g.body.size()));
  const Response hh = handleHello(get("/v1/hello", "HEAD"), info());
  CHECK(hh.body.empty());
  CHECK(hh.header("Content-Length") ==
        std::to_string(handleHello(get("/v1/hello"), info()).body.size()));
}

TEST_CASE("generation is in the body") {
  CacheData d = cessna();
  d.generation = 2147483647;
  CHECK(handleAircraft(get("/v1/aircraft"), d).body.find("\"generation\":2147483647,") !=
        std::string::npos);
}

TEST_CASE("http date is formatted in GMT") {
  CHECK(httpDate(1761206400123) == "Thu, 23 Oct 2025 08:00:00 GMT");
  CHECK(httpDate(0) == "Thu, 01 Jan 1970 00:00:00 GMT");
}

// ---- GET /v1/checklist (task 3.8) ----

TEST_CASE("200 has bytes and all headers") {
  const Response r = handleChecklist(get("/v1/checklist"), cessna());
  CHECK(r.status == 200);
  CHECK(r.body == readFixture("checklist_sample.txt"));
  CHECK(r.header("Content-Type") == "text/plain");
  CHECK(r.header("ETag") == "\"1761206400123-267\"");
  CHECK(r.header("Last-Modified") == "Thu, 23 Oct 2025 08:00:00 GMT");
  CHECK(r.header("X-Aircraft-Generation") == "12");
  CHECK(r.header("Content-Length") == "267");
}

TEST_CASE("304 has etag and no body") {
  Request q = get("/v1/checklist");
  q.headers = {{"If-None-Match", "\"1-1\", W/\"1761206400123-267\""}};
  const Response r = handleChecklist(q, cessna());
  CHECK(r.status == 304);
  CHECK(r.body.empty());
  CHECK(r.header("ETag") == "\"1761206400123-267\"");
  q.headers = {{"If-None-Match", "*"}};
  CHECK(handleChecklist(q, cessna()).status == 304);
  q.headers = {{"if-none-match", "\"1761206400123-268\""}};
  CHECK(handleChecklist(q, cessna()).status == 200);
  q.headers = {{"If-None-Match", "garbage,,\""}};
  CHECK(handleChecklist(q, cessna()).status == 200);
}

TEST_CASE("404 has error body") {
  CacheData d = cessna();
  d.hasChecklist = false;
  d.checklistText.clear();
  const Response r = handleChecklist(get("/v1/checklist"), d);
  CHECK(r.status == 404);
  CHECK(r.body == readFixture("error_404.json"));
  CHECK(r.header("Content-Type") == "application/json; charset=utf-8");
}

TEST_CASE("3 MB file gives 413") {
  CacheData d = cessna();
  d.checklistSize = 3 * 1024 * 1024;
  d.checklistText.clear();  // the shell does not even read an oversize file
  const Response r = handleChecklist(get("/v1/checklist"), d);
  CHECK(r.status == 413);
  CHECK(r.body.find("\"error\":\"too_large\"") != std::string::npos);
  d.checklistSize = kMaxChecklistBytes;  // exactly 2 MB is still served
  d.checklistText = std::string(static_cast<size_t>(kMaxChecklistBytes), 'x');
  CHECK(handleChecklist(get("/v1/checklist"), d).status == 200);
  d.checklistSize = kMaxChecklistBytes + 1;
  d.checklistText.push_back('x');
  CHECK(handleChecklist(get("/v1/checklist"), d).status == 413);
}

TEST_CASE("head has content-length but no body") {
  const Response r = handleChecklist(get("/v1/checklist", "HEAD"), cessna());
  CHECK(r.status == 200);
  CHECK(r.body.empty());
  CHECK(r.header("Content-Length") == "267");
  CHECK(r.header("ETag") == "\"1761206400123-267\"");
}

TEST_CASE("crlf file is served byte for byte") {
  CacheData d = cessna();
  d.checklistText = std::string("a\r\nb\rc\n\xE9\x00z", 10);
  d.checklistSize = 10;
  const Response r = handleChecklist(get("/v1/checklist"), d);
  CHECK(r.body == d.checklistText);
  CHECK(r.body.size() == 10);
  CHECK(r.header("Content-Length") == "10");
}

TEST_CASE("hello reports the simulator kind the companion was configured with") {
  ServerInfo i = info();
  i.simKind = "msfs";
  const Response r = handleHello(get("/v1/hello"), i);
  CHECK(r.status == 200);
  CHECK(r.body.find("\"sim\":{\"kind\":\"msfs\"") != std::string::npos);
  // The default stays xplane, so the plugin and the golden file are unchanged.
  CHECK(handleHello(get("/v1/hello"), info()).body.find("\"kind\":\"xplane\"") != std::string::npos);
}
