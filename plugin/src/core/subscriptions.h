#pragma once

#include <cstdint>
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace flightsim_aide {

struct Subscription {
  int64_t id = 0;
  std::string name;
  int hz = 1;
};

/// Who is connected and what each client asked for (plugin/PROTOCOL.md
/// section 7). Thread safe: connect and close arrive on server threads, the
/// sim thread reads [requestedNames].
class SubscriptionTable {
 public:
  using ClientId = uint64_t;

  static constexpr size_t kMaxClients = 4;
  static constexpr size_t kMaxSubscriptionsPerClient = 128;

  enum class AddResult { added, replaced, limit, unknownClient };

  /// Registers a client; empty when [kMaxClients] are already connected.
  std::optional<ClientId> addClient();

  /// Drops a client and every subscription it had. Unknown ids are ignored.
  void removeClient(ClientId client);

  size_t clientCount() const;

  /// Adds a subscription; a repeated id replaces the old one (and never counts
  /// against the limit). The 129th distinct id gives [AddResult::limit].
  AddResult add(ClientId client, const Subscription& subscription);

  /// Removes one subscription; an unknown id is ignored. Returns whether one
  /// was removed.
  bool remove(ClientId client, int64_t id);

  std::vector<Subscription> subscriptions(ClientId client) const;

  /// The union of the names of all clients, each once, sorted. Names nobody
  /// wants are never read from the sim.
  std::set<std::string> requestedNames() const;

 private:
  mutable std::mutex mutex_;
  ClientId nextId_ = 1;
  std::map<ClientId, std::map<int64_t, Subscription>> clients_;
};

}  // namespace flightsim_aide
