#pragma once

#include <cstdint>
#include <string>

namespace flightsim_aide {

/// Which aircraft Microsoft Flight Simulator has loaded, and whether its values
/// can be trusted yet (D-88). Pure: the shell feeds it what SimConnect says and
/// the time, and asks what to publish. No sim calls in here.
///
/// Measured on MSFS 2024: a load is `SimStop`, `FlightLoaded`, `SimStart` and
/// then, 2 to 3 seconds later, `AircraftLoaded`; `TITLE` and `ATC MODEL` are
/// already the new aircraft's by then, but the values read during the load are
/// wrong (altitude 53819.6, parking brake 0). So after a load trigger the
/// aircraft is **loading**: nothing is reported, until the sim is running again,
/// `AircraftLoaded` was seen, a fresh identity was read and a settle time passed.
class AircraftTracker {
 public:
  /// How long after `AircraftLoaded` values are still held back.
  static constexpr int64_t kSettleMs = 2000;
  /// Loading with the sim running this long counts as done anyway (an aircraft
  /// whose events never came).
  static constexpr int64_t kLoadTimeoutMs = 15000;

  enum class Phase { disconnected, loading, ready };

  struct Identity {
    /// The `ATC MODEL` value, as the sim gives it.
    std::string model;
    /// `TITLE`: the livery's name.
    std::string title;
    /// Path of the `aircraft.cfg`, from `AircraftLoaded`.
    std::string path;
    bool operator==(const Identity& o) const { return model == o.model && title == o.title && path == o.path; }
  };

  /// What [tick] found.
  struct Update {
    /// The aircraft became ready: publish [AircraftTracker::identity].
    bool ready = false;
    /// Raise the generation after publishing: a new aircraft was loaded (not
    /// just the first read after connecting).
    bool bump = false;
  };

  Phase phase() const { return phase_; }
  /// Values may be reported: the phase is ready.
  bool available() const { return phase_ == Phase::ready; }
  /// The aircraft last published, or the one being loaded before the first
  /// publication. Valid when the phase is ready.
  const Identity& identity() const { return published_; }
  /// Whether the shell should ask for the identity once more now (after a load
  /// trigger).
  bool wantsIdentity() const { return wantsIdentity_; }
  void identityRequested() { wantsIdentity_ = false; }

  /// SimConnect opened. The first read, after a short settle, is not a new
  /// aircraft (the generation stays).
  void onConnected(int64_t nowMs);
  /// SimConnect closed.
  void onDisconnected();

  void onSimStop(int64_t nowMs);
  void onSimStart(int64_t nowMs);
  void onAircraftLoaded(const std::string& path, int64_t nowMs);
  /// The newest `ATC MODEL` and `TITLE` (read every second and on request). In
  /// the ready phase a change is itself a load: a livery change has no event of
  /// its own that was measured.
  void onIdentity(const std::string& model, const std::string& title, int64_t nowMs);

  /// Call regularly (every sim-thread step).
  Update tick(int64_t nowMs);

 private:
  void enterLoading(int64_t nowMs, bool bump);

  Phase phase_ = Phase::disconnected;
  bool simRunning_ = false;
  bool loadedSeen_ = false;
  bool identityFresh_ = false;
  bool pendingBump_ = false;
  bool wantsIdentity_ = false;
  int64_t settleUntilMs_ = 0;
  int64_t loadingSinceMs_ = 0;
  Identity latest_;
  Identity published_;
};

}  // namespace flightsim_aide
