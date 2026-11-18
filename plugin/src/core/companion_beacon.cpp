#include "companion_beacon.h"

#include "json_writer.h"

namespace flightsim_aide {

std::string companionBeaconMessage(const std::string& simKind, const std::string& computerName, int port) {
  return "{\"fsaide\":1,\"sim\":" + jsonString(simKind) + ",\"name\":" + jsonString(computerName) +
         ",\"port\":" + std::to_string(port) + "}";
}

}  // namespace flightsim_aide
