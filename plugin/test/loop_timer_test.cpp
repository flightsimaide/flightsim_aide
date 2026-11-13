#include "doctest.h"
#include "loop_timer.h"

using namespace flightsim_aide;

TEST_CASE("loop timer: nothing is reported before the window has passed") {
  LoopTimer t(60000);
  CHECK_FALSE(t.record(100000, 0).has_value());
  CHECK_FALSE(t.record(200000, 59999).has_value());
}

TEST_CASE("loop timer: the window reports calls, average and worst in microseconds") {
  LoopTimer t(60000);
  t.record(100000, 0);        // 100 us
  t.record(300000, 30000);    // 300 us
  const auto stats = t.record(200000, 60000);  // 200 us, closes the window
  REQUIRE(stats.has_value());
  CHECK(stats->calls == 3);
  CHECK(stats->avgUs == doctest::Approx(200.0));
  CHECK(stats->worstUs == doctest::Approx(300.0));
}

TEST_CASE("loop timer: a new window starts after a report") {
  LoopTimer t(1000);
  t.record(5000000, 0);
  REQUIRE(t.record(1000, 1000).has_value());
  CHECK_FALSE(t.record(2000, 1500).has_value());
  const auto stats = t.record(4000, 2500);  // the window opened at 1500
  REQUIRE(stats.has_value());
  CHECK(stats->calls == 2);
  CHECK(stats->worstUs == doctest::Approx(4.0));  // the 5 ms call is not carried over
}
