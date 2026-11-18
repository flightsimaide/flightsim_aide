#pragma once

#include <string>

namespace flightsim_aide {

/// The announcement a companion without a beacon of its own sends so the app can
/// find it (`plugin/PROTOCOL.md` section 11). X-Plane has its own multicast
/// beacon and does not use this; Microsoft Flight Simulator has none.
///
/// UDP multicast to [kCompanionBeaconGroup]:[kCompanionBeaconPort], once a
/// second, on every network adapter. The text is one compact JSON object.
constexpr const char* kCompanionBeaconGroup = "239.255.18.86";
constexpr int kCompanionBeaconPort = 18094;

/// `{"fsaide":1,"sim":"msfs","name":"FLIGHT-PC","port":18086}`: [simKind] as in
/// the hello's `sim.kind`, [computerName] the name of this computer and [port]
/// the TCP port the companion listens on.
std::string companionBeaconMessage(const std::string& simKind, const std::string& computerName, int port);

}  // namespace flightsim_aide
