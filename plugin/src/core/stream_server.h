#pragma once

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "cache.h"
#include "http_types.h"
#include "stream_hub.h"

namespace flightsim_aide {

struct ServerConfig {
  /// Address to bind: "0.0.0.0" for the LAN (the plugin) or "127.0.0.1".
  std::string bindAddress = "0.0.0.0";
  /// 0 lets the OS pick a free port (tests); the plugin passes 18086..18093.
  int port = 0;
  /// Refuse sources outside the private ranges and loopback (section 3).
  bool lanOnly = true;
  /// Replaces the CivetWeb access list when non-empty (tests); the default is
  /// the table in address_filter.
  std::string accessControlList;
  /// Reported by /v1/hello as `sim.kind`: `xplane` (the plugin) or `msfs`.
  std::string simKind = "xplane";
  /// Reported by /v1/hello.
  std::string simVersion;
  /// Reported by /v1/hello as `os`; see hostOsName().
  std::string os;
  std::string pluginVersion;
  /// Reported by /v1/hello as `runId`: the same for the whole X-Plane run.
  std::string runId;
  /// CivetWeb worker threads: four stream clients plus four for plain HTTP.
  int workerThreads = 8;
  /// How often each client's writer looks for something to send.
  std::chrono::milliseconds senderInterval{10};
};

/// The HTTP and WebSocket server (plugin/PROTOCOL.md sections 3 to 7) on top
/// of CivetWeb. It owns the listening socket, CivetWeb's worker pool and one
/// writer thread per stream client (so a client that stops reading stalls only
/// itself). It never touches the simulator: the caller drives [tick] from the
/// sim thread, which is the only place a [ValueSource] is used.
class Server {
 public:
  /// Starts listening. Returns null and fills [error] when the port cannot be
  /// bound (the plugin then tries the next one).
  static std::unique_ptr<Server> start(const ServerConfig& config, Cache& cache, std::string* error);

  ~Server();
  Server(const Server&) = delete;
  Server& operator=(const Server&) = delete;

  /// The port actually bound.
  int port() const { return port_; }

  const ServerConfig& config() const { return config_; }

  /// One sim-thread step; see [StreamHub::tick].
  void tick(ValueSource& source);

  StreamHub& hub() { return hub_; }

  /// Closes every client, stops listening and joins all threads. Idempotent.
  void stop();

 private:
  Server(const ServerConfig& config, Cache& cache);

  struct Impl;
  std::unique_ptr<Impl> impl_;
  ServerConfig config_;
  Cache& cache_;
  StreamHub hub_;
  int port_ = 0;
};

/// Runs [Server::tick] on its own thread, standing in for the simulator's
/// flight loop in `core_test_server` and in tests.
class TickThread {
 public:
  TickThread(Server& server, ValueSource& source,
             std::chrono::milliseconds interval = std::chrono::milliseconds(20));
  ~TickThread();
  void stop();

 private:
  std::atomic<bool> stop_{false};
  std::mutex mutex_;
  std::condition_variable wake_;
  std::thread thread_;
};

}  // namespace flightsim_aide
