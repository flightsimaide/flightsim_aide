#include "doctest.h"
#include "signal_name.h"

using namespace flightsim_aide;

TEST_CASE("a name without brackets has no index") {
  const auto n = parseSignalName("sim/flightmodel/failures/onground_any");
  REQUIRE(n.has_value());
  CHECK(n->base == "sim/flightmodel/failures/onground_any");
  CHECK(n->index == -1);
}

TEST_CASE("base[n] splits into base and index") {
  const auto n = parseSignalName("sim/cockpit2/engine/actuators/throttle_ratio[12]");
  REQUIRE(n.has_value());
  CHECK(n->base == "sim/cockpit2/engine/actuators/throttle_ratio");
  CHECK(n->index == 12);
  CHECK(parseSignalName("a[0]")->index == 0);
  CHECK(parseSignalName("a[007]")->index == 7);
  CHECK(parseSignalName("a[999999]")->index == 999999);
}

TEST_CASE("every malformed bracket form is refused") {
  for (const char* bad : {"a[", "a]", "a[]", "a[a]", "a[-1]", "a[+1]", "a[ 1]", "a[1 ]", "a[1]x", "a[1][2]", "[1]",
                          "a[[1]]", "a[1]]", "a]1[", "a[1234567]", "a[1.5]"}) {
    CHECK_FALSE(parseSignalName(bad).has_value());
  }
}

TEST_CASE("base[a..b] is a range of elements") {
  const auto n = parseSignalName("sim/flightmodel2/gear/on_ground[0..2]");
  REQUIRE(n.has_value());
  CHECK(n->base == "sim/flightmodel2/gear/on_ground");
  CHECK(n->index == 0);
  CHECK(n->last == 2);
  CHECK(parseSignalName("a[3..3]")->last == 3);
  CHECK(parseSignalName("a[0..127]")->last == 127);
  CHECK(parseSignalName("a[5]")->last == -1);  // a single element is not a range
  CHECK(parseSignalName("a")->last == -1);
}

TEST_CASE("a malformed or oversize range is refused") {
  for (const char* bad : {"a[1..]", "a[..2]", "a[1...2]", "a[1..2..3]", "a[2..1]", "a[0..128]", "a[a..2]", "a[1..b]",
                          "a[-1..2]", "a[1 ..2]", "a[1.. 2]", "a[1..2]x", "a[1..1234567]"}) {
    CHECK_FALSE(parseSignalName(bad).has_value());
  }
}
