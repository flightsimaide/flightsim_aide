#pragma once

#include <cstdint>
#include <deque>
#include <map>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "rate_limiter.h"
#include "stream_codec.h"
#include "subscriptions.h"
#include "value_source.h"

namespace flightsim_aide {

/// The stream protocol (plugin/PROTOCOL.md section 7) with no sockets and no
/// simulator. Three kinds of thread use it:
///
/// - **server threads** call [connect], [disconnect], [onClientMessage] and
///   [onClientActivity]. These only parse and queue; they never touch the sim.
/// - **the sim thread** calls [tick]. It is the only caller of [ValueSource].
/// - **the sender thread** calls [collectOutgoing] for each client. It reads
///   only the snapshot that [tick] published.
class StreamHub {
 public:
  using ClientId = SubscriptionTable::ClientId;

  /// A client that sent nothing for this long is pinged; for [kDeadAfter] it
  /// is closed.
  static constexpr std::chrono::seconds kPingAfter{5};
  static constexpr std::chrono::seconds kDeadAfter{15};
  /// A `hb` goes out when no `values` or `hb` frame did for this long.
  static constexpr std::chrono::seconds kHeartbeatAfter{1};
  /// Bounds against a stalled sim thread or a client that never reads.
  static constexpr size_t kMaxQueuedCommands = 1024;
  static constexpr size_t kMaxQueuedFrames = 1000;

  struct Outgoing {
    /// JSON text frames, in order.
    std::vector<std::string> frames;
    /// The server layer should send a WebSocket ping.
    bool sendPing = false;
    /// The server layer should close the connection (dead peer, overflow or
    /// unknown client) after sending [frames].
    bool close = false;
  };

  /// Registers a client; empty when four are already connected (the server
  /// answers the upgrade with 503).
  std::optional<ClientId> connect(Instant now);

  /// A client went away, from either side. Its subscriptions end.
  void disconnect(ClientId client);

  /// A text frame from a client. Frames that need no sim access (ping, bad
  /// requests, `set`) are answered at once; subscribe and unsubscribe wait for
  /// the next [tick].
  void onClientMessage(ClientId client, const std::string& text, Instant now);

  /// Any other sign of life (a WebSocket pong), so a quiet but alive client is
  /// not closed.
  void onClientActivity(ClientId client, Instant now);

  /// One sim-thread step: resolves newly requested names, answers `subscribed`
  /// or `error`, reads every name some client wants (and only those), and
  /// publishes the snapshot. [generation] is the current aircraft generation;
  /// [epochMs] stamps the `values` frames.
  void tick(ValueSource& source, int64_t generation, Instant now, int64_t epochMs);

  /// What to send to [client] now. Applies the per-subscription rate and the
  /// heartbeat.
  Outgoing collectOutgoing(ClientId client, Instant now);

  size_t clientCount() const;

  /// The names some client currently wants.
  std::set<std::string> requestedNames() const;

 private:
  struct Command {
    ClientId client;
    FrameKind kind;
    int64_t id;
    std::string name;
    int hz;
  };

  struct Client {
    Instant lastReceived{0};
    Instant lastFrame{0};  // last values or hb
    Instant lastPing{0};
    RateLimiter limiter;
    std::deque<std::string> outbox;
    bool generationDirty = false;
    bool overflowed = false;
  };

  struct Snapshot {
    std::map<std::string, double> values;
    std::map<std::string, std::vector<double>> lists;  // range names
    int64_t generation = 0;
    int64_t epochMs = 0;
  };

  void queueFrame(Client& c, std::string frame);

  mutable std::mutex mutex_;
  SubscriptionTable table_;
  std::map<ClientId, Client> clients_;
  std::vector<Command> commands_;
  Snapshot snapshot_;
  int64_t lastGeneration_ = -1;

  // Touched by the sim thread only (inside tick).
  struct Handle {
    uint64_t handle = 0;
    bool range = false;
  };
  std::map<std::string, Handle> handles_;
};

}  // namespace flightsim_aide
