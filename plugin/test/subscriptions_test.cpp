#include "doctest.h"
#include "subscriptions.h"

using namespace flightsim_aide;
using Result = SubscriptionTable::AddResult;

namespace {
Subscription sub(int64_t id, const std::string& name, int hz = 1) {
  Subscription s;
  s.id = id;
  s.name = name;
  s.hz = hz;
  return s;
}
}  // namespace

TEST_CASE("add and remove") {
  SubscriptionTable t;
  const auto c = t.addClient().value();
  CHECK(t.add(c, sub(1, "a/b", 2)) == Result::added);
  CHECK(t.add(c, sub(2, "c/d", 5)) == Result::added);
  CHECK(t.subscriptions(c).size() == 2);
  CHECK(t.remove(c, 1));
  CHECK(t.subscriptions(c).size() == 1);
  CHECK(t.subscriptions(c)[0].name == "c/d");
  CHECK(t.subscriptions(c)[0].hz == 5);
  CHECK_FALSE(t.remove(c, 1));  // unknown id is ignored
  CHECK_FALSE(t.remove(c, 99));
}

TEST_CASE("repeated id replaces") {
  SubscriptionTable t;
  const auto c = t.addClient().value();
  CHECK(t.add(c, sub(1, "a/b", 2)) == Result::added);
  CHECK(t.add(c, sub(1, "x/y", 9)) == Result::replaced);
  const auto subs = t.subscriptions(c);
  REQUIRE(subs.size() == 1);
  CHECK(subs[0].name == "x/y");
  CHECK(subs[0].hz == 9);
}

TEST_CASE("the 129th subscription gives limit") {
  SubscriptionTable t;
  const auto c = t.addClient().value();
  for (int i = 1; i <= 128; ++i) CHECK(t.add(c, sub(i, "n" + std::to_string(i))) == Result::added);
  CHECK(t.add(c, sub(129, "n129")) == Result::limit);
  CHECK(t.subscriptions(c).size() == 128);
  // Replacing an existing id is not over the limit.
  CHECK(t.add(c, sub(1, "other")) == Result::replaced);
  // Freeing one makes room.
  CHECK(t.remove(c, 5));
  CHECK(t.add(c, sub(129, "n129")) == Result::added);
}

TEST_CASE("the limit is per client") {
  SubscriptionTable t;
  const auto a = t.addClient().value();
  const auto b = t.addClient().value();
  for (int i = 1; i <= 128; ++i) t.add(a, sub(i, "n"));
  CHECK(t.add(b, sub(1, "n")) == Result::added);
}

TEST_CASE("fifth client is refused") {
  SubscriptionTable t;
  std::vector<SubscriptionTable::ClientId> ids;
  for (int i = 0; i < 4; ++i) ids.push_back(t.addClient().value());
  CHECK(t.clientCount() == 4);
  CHECK_FALSE(t.addClient().has_value());
  CHECK(t.clientCount() == 4);
  t.removeClient(ids[2]);
  CHECK(t.addClient().has_value());  // a closed client frees its slot
}

TEST_CASE("client ids are never reused") {
  SubscriptionTable t;
  const auto a = t.addClient().value();
  t.removeClient(a);
  CHECK(t.addClient().value() != a);
}

TEST_CASE("removing a client removes its names from the union") {
  SubscriptionTable t;
  const auto a = t.addClient().value();
  const auto b = t.addClient().value();
  t.add(a, sub(1, "only/a"));
  t.add(b, sub(1, "only/b"));
  CHECK(t.requestedNames() == std::set<std::string>{"only/a", "only/b"});
  t.removeClient(a);
  CHECK(t.requestedNames() == std::set<std::string>{"only/b"});
  t.removeClient(b);
  CHECK(t.requestedNames().empty());
}

TEST_CASE("union has each name once") {
  SubscriptionTable t;
  const auto a = t.addClient().value();
  const auto b = t.addClient().value();
  t.add(a, sub(1, "shared", 1));
  t.add(a, sub(2, "shared", 30));  // twice in one client
  t.add(b, sub(1, "shared", 5));
  t.add(b, sub(2, "other"));
  CHECK(t.requestedNames() == std::set<std::string>{"other", "shared"});
}

TEST_CASE("operations on an unknown client are harmless") {
  SubscriptionTable t;
  CHECK(t.add(42, sub(1, "a")) == Result::unknownClient);
  CHECK_FALSE(t.remove(42, 1));
  CHECK(t.subscriptions(42).empty());
  t.removeClient(42);
  CHECK(t.clientCount() == 0);
}
