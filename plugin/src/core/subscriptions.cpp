#include "subscriptions.h"

namespace flightsim_aide {

std::optional<SubscriptionTable::ClientId> SubscriptionTable::addClient() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (clients_.size() >= kMaxClients) return std::nullopt;
  const ClientId id = nextId_++;
  clients_[id];
  return id;
}

void SubscriptionTable::removeClient(ClientId client) {
  std::lock_guard<std::mutex> lock(mutex_);
  clients_.erase(client);
}

size_t SubscriptionTable::clientCount() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return clients_.size();
}

SubscriptionTable::AddResult SubscriptionTable::add(ClientId client, const Subscription& subscription) {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto it = clients_.find(client);
  if (it == clients_.end()) return AddResult::unknownClient;
  auto& subs = it->second;
  const auto existing = subs.find(subscription.id);
  if (existing != subs.end()) {
    existing->second = subscription;
    return AddResult::replaced;
  }
  if (subs.size() >= kMaxSubscriptionsPerClient) return AddResult::limit;
  subs.emplace(subscription.id, subscription);
  return AddResult::added;
}

bool SubscriptionTable::remove(ClientId client, int64_t id) {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto it = clients_.find(client);
  if (it == clients_.end()) return false;
  return it->second.erase(id) > 0;
}

std::vector<Subscription> SubscriptionTable::subscriptions(ClientId client) const {
  std::lock_guard<std::mutex> lock(mutex_);
  std::vector<Subscription> out;
  const auto it = clients_.find(client);
  if (it == clients_.end()) return out;
  for (const auto& entry : it->second) out.push_back(entry.second);
  return out;
}

std::set<std::string> SubscriptionTable::requestedNames() const {
  std::lock_guard<std::mutex> lock(mutex_);
  std::set<std::string> names;
  for (const auto& client : clients_) {
    for (const auto& entry : client.second) names.insert(entry.second.name);
  }
  return names;
}

}  // namespace flightsim_aide
