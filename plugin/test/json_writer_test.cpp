#include "doctest.h"
#include "json_writer.h"
#include "test_util.h"

using namespace flightsim_aide;

namespace {
AircraftInfo cessna() {
  AircraftInfo a;
  a.generation = 12;
  a.icao = "C172";
  a.description = "Cessna Skyhawk 172SP";
  a.aircraftPath = "Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf";
  a.hasChecklist = true;
  a.checklistPath = "Aircraft/Laminar Research/Cessna 172SP/clist.txt";
  a.checklistModified = 1761206400123;
  a.checklistSize = 267;
  return a;
}
}  // namespace

TEST_CASE("escapes quotes and backslashes") {
  CHECK(jsonString("a\"b\\c") == "\"a\\\"b\\\\c\"");
}

TEST_CASE("escapes control characters") {
  CHECK(jsonString(std::string("a\n\r\t\b\f") + '\x01' + '\x1f' + "z") ==
        "\"a\\n\\r\\t\\b\\f\\u0001\\u001fz\"");
  CHECK(jsonString(std::string(1, '\x7f')) == "\"\x7f\"");
}

TEST_CASE("non-ascii path passes through as utf8") {
  const std::string path = "Aircraft/B\xC3\xBCro \xE2\x9C\x88/a.acf";
  CHECK(jsonString(path) == "\"" + path + "\"");
}

TEST_CASE("mtime of 1761206400123 prints exactly") {
  AircraftInfo a = cessna();
  CHECK(aircraftJson(a).find("\"checklistModified\":1761206400123,") != std::string::npos);
  a.checklistModified = 9007199254740993LL;  // 2^53 + 1 would not survive a double
  CHECK(aircraftJson(a).find(":9007199254740993,") != std::string::npos);
}

TEST_CASE("absent checklist omits three fields") {
  AircraftInfo a = cessna();
  a.hasChecklist = false;
  const std::string j = aircraftJson(a);
  CHECK(j.find("checklistPath") == std::string::npos);
  CHECK(j.find("checklistModified") == std::string::npos);
  CHECK(j.find("checklistSize") == std::string::npos);
  CHECK(j == readFixture("aircraft_no_checklist.json"));
}

TEST_CASE("output equals aircraft_with_checklist.json golden byte for byte") {
  CHECK(aircraftJson(cessna()) == readFixture("aircraft_with_checklist.json"));
}

TEST_CASE("hello equals hello.json byte for byte") {
  HelloInfo h;
  h.simKind = "xplane";
  h.simVersion = "12.1.4";
  h.os = "windows";
  h.pluginVersion = "0.1.0";
  h.runId = "a1b2c3d4e5f60718";
  h.port = 18086;
  CHECK(helloJson(h) == readFixture("hello.json"));
}

TEST_CASE("hello leaves os out when it is empty") {
  HelloInfo h;
  h.simVersion = "12.1.4";
  h.pluginVersion = "0.1.0";
  h.port = 18086;
  CHECK(helloJson(h).find("\"os\"") == std::string::npos);
}

TEST_CASE("error body has code and message") {
  CHECK(errorJson("not_found", "No such path.") ==
        "{\"error\":\"not_found\",\"message\":\"No such path.\"}");
  CHECK(errorJson("no_checklist", "The loaded aircraft has no checklist file.") ==
        readFixture("error_404.json"));
}
