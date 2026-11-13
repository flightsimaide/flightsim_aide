#include "loop_timer.h"

#include <algorithm>

namespace flightsim_aide {

std::optional<LoopStats> LoopTimer::record(int64_t durationNs, int64_t nowMs) {
  if (!open_) {
    open_ = true;
    startMs_ = nowMs;
  }
  ++calls_;
  totalNs_ += durationNs;
  worstNs_ = std::max(worstNs_, durationNs);
  if (nowMs - startMs_ < windowMs_) return std::nullopt;

  LoopStats stats;
  stats.calls = calls_;
  stats.avgUs = static_cast<double>(totalNs_) / static_cast<double>(calls_) / 1000.0;
  stats.worstUs = static_cast<double>(worstNs_) / 1000.0;
  open_ = false;
  calls_ = 0;
  totalNs_ = 0;
  worstNs_ = 0;
  return stats;
}

}  // namespace flightsim_aide
