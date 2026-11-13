#include "aircraft_paths.h"
#include "doctest.h"

using namespace flightsim_aide;

TEST_CASE("folder of a Windows aircraft path") {
  CHECK(aircraftFolder("C:\\X-Plane 12\\Aircraft\\Laminar Research\\Cessna 172SP\\Cessna_172SP.acf") ==
        "C:\\X-Plane 12\\Aircraft\\Laminar Research\\Cessna 172SP");
}

TEST_CASE("folder of a POSIX aircraft path") {
  CHECK(aircraftFolder("/Users/pilot/X-Plane 12/Aircraft/Extra/Baron 58/Baron_58.acf") ==
        "/Users/pilot/X-Plane 12/Aircraft/Extra/Baron 58");
}

TEST_CASE("folder of a path with mixed separators") {
  CHECK(aircraftFolder("C:/X-Plane 12\\Aircraft/A/B.acf") == "C:/X-Plane 12\\Aircraft/A");
}

TEST_CASE("non-ASCII folder and file names are kept byte for byte") {
  const std::string folder = "/home/p\xC3\xA9re/Aircraft/Caf\xC3\xA9 \xE6\x97\xA5\xE6\x9C\xAC";
  const std::string acf = folder + "/Caf\xC3\xA9.acf";
  CHECK(aircraftFolder(acf) == folder);
  const auto c = checklistCandidates(acf);
  REQUIRE(c.size() == 2);
  CHECK(c[0] == folder + "/Caf\xC3\xA9_clist.txt");
  CHECK(c[1] == folder + "/clist.txt");
}

TEST_CASE("the named checklist is searched before clist.txt") {
  const auto c = checklistCandidates("C:\\Aircraft\\Foo\\Foo_747.acf");
  REQUIRE(c.size() == 2);
  CHECK(c[0] == "C:\\Aircraft\\Foo\\Foo_747_clist.txt");
  CHECK(c[1] == "C:\\Aircraft\\Foo\\clist.txt");
}

TEST_CASE("only the last extension is dropped from the acf name") {
  const auto c = checklistCandidates("/a/b/My.Plane.v2.acf");
  REQUIRE(c.size() == 2);
  CHECK(c[0] == "/a/b/My.Plane.v2_clist.txt");
}

TEST_CASE("trailing separators are tolerated") {
  CHECK(aircraftFolder("/a/b/") == "/a/b");
  CHECK(aircraftFolder("C:\\a\\b\\") == "C:\\a\\b");
  const auto c = checklistCandidates("/a/b/");
  REQUIRE(c.size() == 1);  // a folder has no acf name
  CHECK(c[0] == "/a/b/clist.txt");
  CHECK(aircraftFolder("/a/b//") == "/a/b");
}

TEST_CASE("a bare file name or an empty path gives nothing") {
  CHECK(aircraftFolder("").empty());
  CHECK(aircraftFolder("Cessna.acf").empty());
  CHECK(checklistCandidates("").empty());
  CHECK(checklistCandidates("Cessna.acf").empty());
}

TEST_CASE("the root folder keeps its separator") {
  CHECK(aircraftFolder("/plane.acf") == "/");
  const auto c = checklistCandidates("/plane.acf");
  REQUIRE(c.size() == 2);
  CHECK(c[1] == "/clist.txt");
  CHECK(aircraftFolder("C:\\plane.acf") == "C:\\");
}

TEST_CASE("a file without extension still names its checklist") {
  const auto c = checklistCandidates("/a/b/plane");
  REQUIRE(c.size() == 2);
  CHECK(c[0] == "/a/b/plane_clist.txt");
}
