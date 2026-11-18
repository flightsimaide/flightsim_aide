#include "aircraft_key.h"
#include "doctest.h"

using namespace flightsim_aide;

TEST_CASE("a plain ATC MODEL is the key") {
  CHECK(msfsAircraftKey("PC12") == "PC12");
  CHECK(msfsAircraftKey("TBM930") == "TBM930");
}

TEST_CASE("a default aircraft's localisation key gives its model") {
  CHECK(msfsAircraftKey("ATCCOM.AC_MODEL C152.0.text") == "C152");
  CHECK(msfsAircraftKey("ATCCOM.AC_MODEL C185.0.text") == "C185");
  CHECK(msfsAircraftKey("ATCCOM.AC_MODEL DA62.0.text") == "DA62");
}

TEST_CASE("only the final index and the text suffix are removed") {
  CHECK(msfsAircraftKey("ATCCOM.AC_MODEL B737.800.0.text") == "B737.800");
  CHECK(msfsAircraftKey("ATCCOM.AC_MODEL C152.text") == "C152");
}

TEST_CASE("the prefix alone, without the suffix, is not a localisation key") {
  CHECK(msfsAircraftKey("ATCCOM.AC_MODEL C152") == "ATCCOM.AC_MODEL C152");
}

TEST_CASE("characters a file name cannot hold become underscores") {
  CHECK(msfsAircraftKey("A/B\\C:D*E?F\"G<H>I|J") == "A_B_C_D_E_F_G_H_I_J");
  CHECK(msfsAircraftKey(std::string("A\x01") + "B") == "A_B");
}

TEST_CASE("the key is never a folder name or empty padding") {
  CHECK(msfsAircraftKey("").empty());
  CHECK(msfsAircraftKey(".").empty());
  CHECK(msfsAircraftKey("..").empty());
  CHECK(msfsAircraftKey("   ").empty());
  CHECK(msfsAircraftKey("PC12. ") == "PC12");
  CHECK(msfsAircraftKey("../../x") == ".._.._x");
}

TEST_CASE("non-ASCII model names are kept byte for byte") {
  CHECK(msfsAircraftKey("Caf\xC3\xA9") == "Caf\xC3\xA9");
}

TEST_CASE("the named checklist is searched before clist.txt in a folder") {
  const auto c = checklistCandidatesIn("C:\\pkg\\checklists", "PC12");
  REQUIRE(c.size() == 2);
  CHECK(c[0] == "C:\\pkg\\checklists\\PC12_clist.txt");
  CHECK(c[1] == "C:\\pkg\\checklists\\clist.txt");
}

TEST_CASE("a folder with a trailing separator is not doubled") {
  const auto c = checklistCandidatesIn("C:\\pkg\\checklists\\", "PC12");
  CHECK(c[0] == "C:\\pkg\\checklists\\PC12_clist.txt");
  CHECK(checklistCandidatesIn("/x/", "A")[0] == "/x/A_clist.txt");
}

TEST_CASE("without a key only clist.txt is searched, without a folder nothing") {
  const auto c = checklistCandidatesIn("C:\\pkg", "");
  REQUIRE(c.size() == 1);
  CHECK(c[0] == "C:\\pkg\\clist.txt");
  CHECK(checklistCandidatesIn("", "PC12").empty());
}
