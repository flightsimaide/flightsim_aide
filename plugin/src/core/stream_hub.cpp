#include "stream_hub.h"

#include <algorithm>
#include <cmath>
#include <optional>

#include "signal_name.h"

namespace flightsim_aide {

namespace {

// What tick() decided for one command, applied later under the lock together
// with the snapshot, so a new subscription's first value is always there.
struct Effect {
  enum class Kind { ack, error, limiterSet, limiterRemove };
  Kind kind;
  StreamHub::ClientId client;
  int64_t id;
  int hz = 0;
  std::string code;
  std::string message;
};

}  // namespace

std::optional<StreamHub::ClientId> StreamHub::connect(Instant now) {
  std::lock_guard<std::mutex> lock(mutex_);
  const std::optional<ClientId> id = table_.addClient();
  if (!id) return std::nullopt;
  Client& c = clients_[*id];
  c.lastReceived = now;
  c.lastFrame = now;
  c.lastPing = now;
  return id;
}

void StreamHub::disconnect(ClientId client) {
  std::lock_guard<std::mutex> lock(mutex_);
  table_.removeClient(client);
  clients_.erase(client);
}

size_t StreamHub::clientCount() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return clients_.size();
}

std::set<std::string> StreamHub::requestedNames() const { return table_.requestedNames(); }

void StreamHub::queueFrame(Client& c, std::string frame) {
  if (c.outbox.size() >= kMaxQueuedFrames) {
    c.overflowed = true;  // the reader is stalled: the sender will close it
    return;
  }
  c.outbox.push_back(std::move(frame));
}

void StreamHub::onClientActivity(ClientId client, Instant now) {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto it = clients_.find(client);
  if (it != clients_.end()) it->second.lastReceived = now;
}

void StreamHub::onClientMessage(ClientId client, const std::string& text, Instant now) {
  std::lock_guard<std::mutex> lock(mutex_);
  const auto it = clients_.find(client);
  if (it == clients_.end()) return;
  Client& c = it->second;
  c.lastReceived = now;

  const ClientFrame f = parseClientFrame(text);
  switch (f.kind) {
    case FrameKind::ping:
      queueFrame(c, pongFrame());
      break;
    case FrameKind::set:
      queueFrame(c, errorFrame(f.id, "unsupported", "Writes are not supported."));
      break;
    case FrameKind::badRequest:
      queueFrame(c, errorFrame(f.id, "bad_request", f.message));
      break;
    case FrameKind::subscribe:
    case FrameKind::unsubscribe:
      if (commands_.size() >= kMaxQueuedCommands) {
        queueFrame(c, errorFrame(f.id, "limit", "Too many requests waiting."));
        break;
      }
      commands_.push_back(Command{client, f.kind, f.id.value_or(0), f.name, f.hz});
      break;
  }
}

void StreamHub::tick(ValueSource& source, int64_t generation, Instant now, int64_t epochMs) {
  std::vector<Command> commands;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    commands.swap(commands_);
  }

  // 1. Decide, in order. Only this thread talks to the ValueSource.
  std::vector<Effect> effects;
  for (const Command& cmd : commands) {
    if (cmd.kind == FrameKind::unsubscribe) {
      if (table_.remove(cmd.client, cmd.id)) {
        effects.push_back({Effect::Kind::limiterRemove, cmd.client, cmd.id});
      }
      continue;
    }

    Resolution::Status status = Resolution::Status::ok;
    if (cmd.name != kGenerationSignal && handles_.count(cmd.name) == 0) {
      const std::optional<SignalName> parsed = parseSignalName(cmd.name);
      Resolution r;
      if (parsed && parsed->isRange()) {
        r = source.resolveRange(parsed->base, parsed->index, parsed->last);
      } else if (parsed) {
        r = source.resolve(parsed->base, parsed->index);
      }
      status = r.status;
      if (status == Resolution::Status::ok) handles_[cmd.name] = Handle{r.handle, parsed->isRange()};
    }
    if (status == Resolution::Status::unknown) {
      effects.push_back({Effect::Kind::error, cmd.client, cmd.id, 0, "unknown_name",
                         "No such signal."});
      continue;
    }
    if (status == Resolution::Status::unsupported) {
      effects.push_back({Effect::Kind::error, cmd.client, cmd.id, 0, "unsupported",
                         "Not a single number."});
      continue;
    }

    Subscription s;
    s.id = cmd.id;
    s.name = cmd.name;
    s.hz = cmd.hz;
    switch (table_.add(cmd.client, s)) {
      case SubscriptionTable::AddResult::limit:
        effects.push_back({Effect::Kind::error, cmd.client, cmd.id, 0, "limit",
                           "At most 128 subscriptions."});
        break;
      case SubscriptionTable::AddResult::unknownClient:
        break;  // it left while the command waited
      case SubscriptionTable::AddResult::replaced:
        effects.push_back({Effect::Kind::limiterRemove, cmd.client, cmd.id});
        [[fallthrough]];
      case SubscriptionTable::AddResult::added:
        effects.push_back({Effect::Kind::ack, cmd.client, cmd.id});
        effects.push_back({Effect::Kind::limiterSet, cmd.client, cmd.id, cmd.hz});
        break;
    }
  }

  // 2. Read exactly the names somebody wants.
  const std::set<std::string> wanted = table_.requestedNames();
  for (auto it = handles_.begin(); it != handles_.end();) {
    it = wanted.count(it->first) == 0 ? handles_.erase(it) : std::next(it);
  }
  Snapshot snapshot;
  snapshot.generation = generation;
  snapshot.epochMs = epochMs;
  for (const std::string& name : wanted) {
    if (name == kGenerationSignal) continue;
    const auto h = handles_.find(name);
    if (h == handles_.end()) continue;
    if (h->second.range) {
      source.readRange(h->second.handle, snapshot.lists[name]);
    } else {
      snapshot.values[name] = source.read(h->second.handle);
    }
  }

  // 3. Apply and publish together.
  std::lock_guard<std::mutex> lock(mutex_);
  for (const Effect& e : effects) {
    const auto it = clients_.find(e.client);
    if (it == clients_.end()) continue;
    Client& c = it->second;
    switch (e.kind) {
      case Effect::Kind::ack:
        queueFrame(c, subscribedFrame(e.id));
        break;
      case Effect::Kind::error:
        queueFrame(c, errorFrame(e.id, e.code, e.message));
        break;
      case Effect::Kind::limiterSet:
        c.limiter.set(e.id, e.hz, now);
        break;
      case Effect::Kind::limiterRemove:
        c.limiter.remove(e.id);
        break;
    }
  }
  snapshot_ = std::move(snapshot);
  if (generation != lastGeneration_) {
    lastGeneration_ = generation;
    for (auto& entry : clients_) entry.second.generationDirty = true;
  }
}

StreamHub::Outgoing StreamHub::collectOutgoing(ClientId client, Instant now) {
  Outgoing out;
  std::lock_guard<std::mutex> lock(mutex_);
  const auto it = clients_.find(client);
  if (it == clients_.end()) {
    out.close = true;
    return out;
  }
  Client& c = it->second;

  while (!c.outbox.empty()) {
    out.frames.push_back(std::move(c.outbox.front()));
    c.outbox.pop_front();
  }

  std::vector<int64_t> due = c.limiter.due(now);
  const std::vector<Subscription> subs = table_.subscriptions(client);
  if (c.generationDirty) {
    c.generationDirty = false;
    for (const Subscription& s : subs) {
      if (s.name == kGenerationSignal) due.push_back(s.id);  // a change goes out at once
    }
  }

  std::map<int64_t, std::string> nameById;
  for (const Subscription& s : subs) nameById[s.id] = s.name;
  std::set<int64_t> seen;
  std::vector<SignalValue> values;
  for (const int64_t id : due) {
    if (!seen.insert(id).second) continue;
    const auto n = nameById.find(id);
    if (n == nameById.end()) continue;  // unsubscribed meanwhile
    if (n->second == kGenerationSignal) {
      values.emplace_back(id, static_cast<double>(snapshot_.generation));
      continue;
    }
    const auto l = snapshot_.lists.find(n->second);
    if (l != snapshot_.lists.end()) {
      values.emplace_back(id, l->second);
      continue;
    }
    const auto v = snapshot_.values.find(n->second);
    if (v != snapshot_.values.end()) values.emplace_back(id, v->second);
  }
  std::sort(values.begin(), values.end(),
            [](const SignalValue& a, const SignalValue& b) { return a.id < b.id; });

  if (!values.empty()) {
    out.frames.push_back(valuesFrame(snapshot_.epochMs, values));
    c.lastFrame = now;
  } else if (now - c.lastFrame >= kHeartbeatAfter) {
    out.frames.push_back(heartbeatFrame());
    c.lastFrame = now;
  }

  const Instant quiet = now - c.lastReceived;
  if (quiet >= kDeadAfter || c.overflowed) out.close = true;
  if (quiet >= kPingAfter && now - c.lastPing >= kPingAfter) {
    out.sendPing = true;
    c.lastPing = now;
  }
  return out;
}

}  // namespace flightsim_aide
