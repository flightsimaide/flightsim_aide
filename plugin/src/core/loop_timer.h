#pragma once

#include <cstdint>
#include <optional>

namespace flightsim_aide {

/// What one reporting window of flight-loop calls looked like.
struct LoopStats {
  int64_t calls = 0;
  double avgUs = 0;
  double worstUs = 0;
};

/// Collects the duration of each flight-loop call and hands back the average
/// and the worst of a window (a minute in the plugin, for the performance
/// check AC-24). Sim thread only; the clock is passed in.
class LoopTimer {
 public:
  explicit LoopTimer(int64_t windowMs = 60000) : windowMs_(windowMs) {}

  /// Adds one call of [durationNs]. Returns the window's stats when
  /// [nowMs] is [windowMs] or more after the window's first call, and starts
  /// the next window.
  std::optional<LoopStats> record(int64_t durationNs, int64_t nowMs);

 private:
  int64_t windowMs_;
  bool open_ = false;
  int64_t startMs_ = 0;
  int64_t calls_ = 0;
  int64_t totalNs_ = 0;
  int64_t worstNs_ = 0;
};

}  // namespace flightsim_aide
