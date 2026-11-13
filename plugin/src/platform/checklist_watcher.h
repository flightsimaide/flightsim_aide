#pragma once

#include <cstdint>
#include <functional>

#include "cache.h"

namespace flightsim_aide {

using ClockFn = std::function<int64_t()>;  // monotonic milliseconds

/// Keeps the checklist part of the [Cache] in step with the file on disk. The
/// path comes from the cache (`checklistPath`). Runs on the sim thread only.
/// The generation is never touched: a file edit is not an aircraft load.
class ChecklistWatcher {
 public:
  static constexpr int64_t kIntervalMs = 3000;

  ChecklistWatcher(Cache& cache, ClockFn clock) : cache_(cache), clock_(std::move(clock)) {}

  /// Re-stats the file if the interval has passed and rereads it when its
  /// mtime or size differs from the cache. True when the cache was updated.
  bool poll();

  /// Stats and rereads now, whatever the clock says (after an aircraft
  /// change). True when the cache was updated.
  bool refresh();

 private:
  bool check(bool force);

  Cache& cache_;
  ClockFn clock_;
  bool started_ = false;
  int64_t lastCheckMs_ = 0;
};

}  // namespace flightsim_aide
