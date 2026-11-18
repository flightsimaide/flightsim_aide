#include "companion_beacon.h"
#include "doctest.h"
#include "test_util.h"

using namespace flightsim_aide;

TEST_CASE("the beacon message matches the golden file shared with the app") {
  CHECK(companionBeaconMessage("msfs", "FLIGHT-PC", 18086) == readFixture("companion_beacon_msfs.json"));
}

TEST_CASE("a computer name is escaped like any JSON string") {
  CHECK(companionBeaconMessage("msfs", "A\"B", 18087) == "{\"fsaide\":1,\"sim\":\"msfs\",\"name\":\"A\\\"B\",\"port\":18087}");
}

TEST_CASE("the group and port are the documented ones") {
  CHECK(std::string(kCompanionBeaconGroup) == "239.255.18.86");
  CHECK(kCompanionBeaconPort == 18094);
}
