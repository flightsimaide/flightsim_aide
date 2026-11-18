#include "aircraft_tracker.h"

namespace flightsim_aide {

void AircraftTracker::enterLoading(int64_t nowMs, bool bump) {
  phase_ = Phase::loading;
  loadingSinceMs_ = nowMs;
  identityFresh_ = false;
  if (bump) pendingBump_ = true;
}

void AircraftTracker::onConnected(int64_t nowMs) {
  phase_ = Phase::loading;
  simRunning_ = true;
  loadedSeen_ = true;
  identityFresh_ = false;
  pendingBump_ = false;
  wantsIdentity_ = true;
  settleUntilMs_ = nowMs + kSettleMs;
  loadingSinceMs_ = nowMs;
  latest_ = Identity();
  published_ = Identity();
}

void AircraftTracker::onDisconnected() {
  phase_ = Phase::disconnected;
  simRunning_ = false;
}

void AircraftTracker::onSimStop(int64_t nowMs) {
  if (phase_ == Phase::disconnected) return;
  enterLoading(nowMs, true);
  simRunning_ = false;
  loadedSeen_ = false;
}

void AircraftTracker::onSimStart(int64_t nowMs) {
  if (phase_ == Phase::disconnected) return;
  simRunning_ = true;
  if (phase_ == Phase::loading) loadingSinceMs_ = nowMs;  // the timeout counts from the start
}

void AircraftTracker::onAircraftLoaded(const std::string& path, int64_t nowMs) {
  if (phase_ == Phase::disconnected) return;
  if (phase_ == Phase::ready) enterLoading(nowMs, true);
  latest_.path = path;
  loadedSeen_ = true;
  identityFresh_ = false;
  pendingBump_ = true;
  wantsIdentity_ = true;
  settleUntilMs_ = nowMs + kSettleMs;
}

void AircraftTracker::onIdentity(const std::string& model, const std::string& title, int64_t nowMs) {
  if (phase_ == Phase::disconnected) return;
  if (phase_ == Phase::ready) {
    if (model == published_.model && title == published_.title) return;
    // No load event, but the aircraft or its livery is not the one published.
    enterLoading(nowMs, true);
    loadedSeen_ = true;
    settleUntilMs_ = nowMs + kSettleMs;
  }
  latest_.model = model;
  latest_.title = title;
  if (loadedSeen_) identityFresh_ = true;
}

AircraftTracker::Update AircraftTracker::tick(int64_t nowMs) {
  Update update;
  if (phase_ != Phase::loading || !simRunning_) return update;
  const bool settled = loadedSeen_ && identityFresh_ && nowMs >= settleUntilMs_;
  const bool timedOut = nowMs - loadingSinceMs_ >= kLoadTimeoutMs && !latest_.model.empty();
  if (!settled && !timedOut) return update;
  phase_ = Phase::ready;
  published_ = latest_;
  update.ready = true;
  update.bump = pendingBump_;
  pendingBump_ = false;
  return update;
}

}  // namespace flightsim_aide
