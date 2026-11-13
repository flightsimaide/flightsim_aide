#include "cache.h"

namespace flightsim_aide {

void Cache::update(const CacheData& data) {
  std::lock_guard<std::mutex> lock(mutex_);
  const int64_t generation = data_.generation;
  data_ = data;
  data_.generation = generation;
}

CacheData Cache::snapshot() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return data_;
}

int64_t Cache::bumpGeneration() {
  std::lock_guard<std::mutex> lock(mutex_);
  data_.generation = (data_.generation + 1) % kGenerationModulus;
  return data_.generation;
}

int64_t Cache::generation() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return data_.generation;
}

void Cache::setGeneration(int64_t generation) {
  std::lock_guard<std::mutex> lock(mutex_);
  data_.generation = ((generation % kGenerationModulus) + kGenerationModulus) % kGenerationModulus;
}

void Cache::enableRefreshRequests() {
  std::lock_guard<std::mutex> lock(mutex_);
  refreshEnabled_ = true;
}

bool Cache::requestRefresh(std::chrono::milliseconds wait) {
  std::unique_lock<std::mutex> lock(mutex_);
  if (!refreshEnabled_) return false;
  const int64_t ticket = ++refreshAsked_;
  return refreshed_.wait_for(lock, wait, [&] { return refreshDone_ >= ticket; });
}

int64_t Cache::pendingRefresh() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return refreshAsked_ > refreshDone_ ? refreshAsked_ : 0;
}

void Cache::refreshServed(int64_t ticket) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (ticket > refreshDone_) refreshDone_ = ticket;
  }
  refreshed_.notify_all();
}

}  // namespace flightsim_aide
