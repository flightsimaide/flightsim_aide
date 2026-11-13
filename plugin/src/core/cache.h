#pragma once

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>

namespace flightsim_aide {

/// Everything the HTTP handlers need about the current aircraft. A value type:
/// handlers work on a copy, so they never touch a lock.
struct CacheData {
  int64_t generation = 0;
  std::string icao;
  std::string description;
  std::string aircraftPath;
  bool hasChecklist = false;
  std::string checklistPath;
  int64_t checklistModified = 0;  // epoch milliseconds UTC
  int64_t checklistSize = 0;
  std::string checklistText;  // raw bytes of the file
};

/// The shared aircraft/checklist state. The sim thread writes, server threads
/// read, all under one mutex. The generation is its own counter: [update]
/// replaces the data but never touches it, and [bumpGeneration] never touches
/// the data, so a file edit does not look like an aircraft load.
class Cache {
 public:
  /// Generation values are 0 .. 2^31-1 and wrap back to 0.
  static constexpr int64_t kGenerationModulus = 2147483648LL;

  /// Replaces the aircraft and checklist data. [data.generation] is ignored.
  void update(const CacheData& data);

  /// A consistent copy of the data and the generation.
  CacheData snapshot() const;

  /// Increments the generation (wrapping) and returns the new value.
  int64_t bumpGeneration();

  int64_t generation() const;

  /// For tests and for starting from a known value.
  void setGeneration(int64_t generation);

  // ---- Asking the sim thread to re-check the checklist file
  //
  // The file watcher runs on the sim thread only and looks at the file every
  // few seconds. A request for the aircraft must not report a stale size or
  // time, so the server thread asks for an immediate re-check and waits a
  // short while for it. Without a sim thread that serves requests (the test
  // server) nothing waits.

  /// The sim thread's owner declares that it calls [pendingRefresh] every frame.
  void enableRefreshRequests();

  /// Server thread: asks for a re-check and waits up to [wait] for the sim
  /// thread to finish it. False when it was not served in time or when
  /// refresh requests are not enabled.
  bool requestRefresh(std::chrono::milliseconds wait);

  /// Sim thread: the newest ticket asked for and not yet served, or 0.
  int64_t pendingRefresh() const;

  /// Sim thread: the re-check for [ticket] (and every earlier one) is done.
  void refreshServed(int64_t ticket);

 private:
  mutable std::mutex mutex_;
  std::condition_variable refreshed_;
  CacheData data_;
  bool refreshEnabled_ = false;
  int64_t refreshAsked_ = 0;
  int64_t refreshDone_ = 0;
};

}  // namespace flightsim_aide
