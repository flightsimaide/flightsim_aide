#pragma once

#include <atomic>
#include <string>
#include <thread>

namespace flightsim_aide {

/// Sends the companion beacon (core/companion_beacon.h) once a second on every
/// IPv4 adapter that is up, from its own thread. It touches no simulator.
class BeaconSender {
 public:
  BeaconSender() = default;
  ~BeaconSender();
  BeaconSender(const BeaconSender&) = delete;
  BeaconSender& operator=(const BeaconSender&) = delete;

  /// Starts sending `simKind` on behalf of the companion that listens on [port].
  void start(const std::string& simKind, int port);
  void stop();

 private:
  void run(std::string simKind, int port);

  std::atomic<bool> stop_{false};
  std::thread thread_;
};

/// The name of this computer (DNS host name), UTF-8; empty when unknown.
std::string computerName();

}  // namespace flightsim_aide
