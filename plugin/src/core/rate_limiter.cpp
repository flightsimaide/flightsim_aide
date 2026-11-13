#include "rate_limiter.h"

namespace flightsim_aide {

void RateLimiter::set(int64_t id, int hz, Instant now) {
  const Instant period = Instant(1000000000LL / hz);
  const auto it = entries_.find(id);
  if (it != entries_.end()) {
    // The period already running ends at nextDue; the new one starts there.
    it->second.period = period;
    return;
  }
  entries_[id] = Entry{period, now};
}

void RateLimiter::remove(int64_t id) { entries_.erase(id); }

std::vector<int64_t> RateLimiter::due(Instant now) {
  std::vector<int64_t> out;
  for (auto& entry : entries_) {
    Entry& e = entry.second;
    if (e.nextDue > now) continue;
    out.push_back(entry.first);
    // Skip every period that was missed: one frame now, then back on the grid.
    const int64_t periodsBehind = (now - e.nextDue) / e.period;
    e.nextDue += e.period * (periodsBehind + 1);
  }
  return out;
}

}  // namespace flightsim_aide
