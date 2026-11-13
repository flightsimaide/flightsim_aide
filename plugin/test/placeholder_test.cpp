#include "doctest.h"
#include "version.h"

TEST_CASE("the test runner runs") { CHECK(flightsim_aide::kProtocolVersion == 1); }
