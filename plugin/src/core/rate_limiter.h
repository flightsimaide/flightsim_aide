#pragma once

#include <chrono>
#include <cstdint>
#include <map>
#include <vector>

namespace flightsim_aide {

/// A point on a monotonic clock that the caller supplies, so tests can use
/// fake time. Nanoseconds keep every rate from 1 to 60 Hz free of rounding
/// drift.
using Instant = std::chrono::nanoseconds;

/// Decides which subscriptions of one client are due (plugin/PROTOCOL.md
/// section 7, "Rate"). A subscription never produces frames faster than its
/// `hz`, and a sender that is late gets one due entry, not a burst: the next
/// due time stays on the original grid (computed from the previous due time,
/// not from `now`), so rates do not drift.
class RateLimiter {
 public:
  /// Starts a subscription that is due at once. Calling it again for a known
  /// id only changes the rate; the new period applies from the next one.
  void set(int64_t id, int hz, Instant now);

  void remove(int64_t id);

  bool empty() const { return entries_.empty(); }

  /// Ids whose period has elapsed, ascending. Each returned id is advanced to
  /// its next due time, which is always after [now].
  std::vector<int64_t> due(Instant now);

 private:
  struct Entry {
    Instant period;
    Instant nextDue;
  };
  std::map<int64_t, Entry> entries_;
};

}  // namespace flightsim_aide
