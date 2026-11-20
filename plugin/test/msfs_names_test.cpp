#include "doctest.h"
#include "msfs_names.h"

using namespace flightsim_aide;

TEST_CASE("an A-variable with an index and a unit") {
  const auto v = parseMsfsName("A:GENERAL ENG MASTER ALTERNATOR:1, bool");
  REQUIRE(v);
  CHECK(v->kind == MsfsVar::Kind::simVar);
  CHECK(v->datum == "GENERAL ENG MASTER ALTERNATOR:1");
  CHECK(v->unit == "bool");
}

TEST_CASE("an A-variable without a unit reads as a number") {
  const auto v = parseMsfsName("A:ELECTRICAL MASTER BATTERY");
  REQUIRE(v);
  CHECK(v->datum == "ELECTRICAL MASTER BATTERY");
  CHECK(v->unit == "number");
}

TEST_CASE("units with spaces are kept") {
  const auto v = parseMsfsName("A:AMBIENT TEMPERATURE,degrees celsius");
  REQUIRE(v);
  CHECK(v->unit == "degrees celsius");
}

TEST_CASE("an L-variable's datum keeps its L: prefix") {
  const auto v = parseMsfsName("L:ELECTRICAL_Switch_BATTERY_Bus_1");
  REQUIRE(v);
  CHECK(v->kind == MsfsVar::Kind::localVar);
  CHECK(v->datum == "L:ELECTRICAL_Switch_BATTERY_Bus_1");
  CHECK(v->unit == "number");
  CHECK(parseMsfsName("L:FUEL_Push_Pump_1, bool")->unit == "bool");
}

TEST_CASE("a Z-variable keeps its Z: prefix and reads like an L-variable") {
  const auto v = parseMsfsName("Z:SWS_EXIT_PassengerDoor_Handle, bool");
  REQUIRE(v);
  CHECK(v->kind == MsfsVar::Kind::zVar);
  CHECK(v->datum == "Z:SWS_EXIT_PassengerDoor_Handle");
  CHECK(v->unit == "bool");
  CHECK(parseMsfsName("z:Foo")->datum == "Z:Foo");
  CHECK(parseMsfsName("Z:Foo")->unit == "number");
  CHECK(parseMsfsName("Z:X")->key() != parseMsfsName("L:X")->key());
  CHECK(parseMsfsName("Z:X")->key() == parseMsfsName("z:x")->key());
  CHECK_FALSE(parseMsfsName("Z:"));
  CHECK_FALSE(parseMsfsName("Z:X:1"));
  CHECK_FALSE(parseMsfsName("Z:X,bool,number"));
}

TEST_CASE("a B-variable is an input event with no unit") {
  const auto v = parseMsfsName("B:ELECTRICAL_BATTERY_2");
  REQUIRE(v);
  CHECK(v->kind == MsfsVar::Kind::inputEvent);
  CHECK(v->datum == "ELECTRICAL_BATTERY_2");
  CHECK(v->unit.empty());
}

TEST_CASE("the prefix is case-insensitive and blanks around parts are ignored") {
  CHECK(parseMsfsName("l:Foo_Bar")->datum == "L:Foo_Bar");
  CHECK(parseMsfsName("a: PLANE ALTITUDE , feet ")->datum == "PLANE ALTITUDE");
  CHECK(parseMsfsName("a: PLANE ALTITUDE , feet ")->unit == "feet");
  CHECK(parseMsfsName("b: X ")->datum == "X");
}

TEST_CASE("names that differ only in case have one key") {
  CHECK(parseMsfsName("L:ELECTRICAL_Switch_BATTERY_Bus_1")->key() ==
        parseMsfsName("l:electrical_switch_battery_bus_1")->key());
  CHECK(parseMsfsName("L:X,bool")->key() != parseMsfsName("L:X,number")->key());
  CHECK(parseMsfsName("A:X")->key() != parseMsfsName("L:X")->key());
  CHECK(parseMsfsName("B:X")->key() != parseMsfsName("A:X")->key());
}

TEST_CASE("anything that is not one of the three forms is refused") {
  CHECK_FALSE(parseMsfsName(""));
  CHECK_FALSE(parseMsfsName("sim/flightmodel/position/elevation"));
  CHECK_FALSE(parseMsfsName("PLANE ALTITUDE"));
  CHECK_FALSE(parseMsfsName("X:FOO"));
  CHECK_FALSE(parseMsfsName("A:"));
  CHECK_FALSE(parseMsfsName("A: ,feet"));
  CHECK_FALSE(parseMsfsName("L:"));
}

TEST_CASE("malformed parts are refused") {
  CHECK_FALSE(parseMsfsName("A:X,feet,extra"));
  CHECK_FALSE(parseMsfsName("A:X,"));
  CHECK_FALSE(parseMsfsName("B:X,number"));
  CHECK_FALSE(parseMsfsName("B:X:1"));
  CHECK_FALSE(parseMsfsName("L:X:1"));
  CHECK_FALSE(parseMsfsName("A:X:a"));
  CHECK_FALSE(parseMsfsName("A:X:1:2"));
  CHECK_FALSE(parseMsfsName("A:X:"));
  CHECK_FALSE(parseMsfsName("A:X:1234"));
  CHECK_FALSE(parseMsfsName(std::string("A:X\x01") + "Y"));
}
