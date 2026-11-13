#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "cache.h"
#include "stream_server.h"

namespace flightsim_aide {

/// How a server is started on one port: [Server::start] in the plugin, a fake
/// in tests.
using BindFn = std::function<std::unique_ptr<Server>(const ServerConfig&, Cache&, std::string*)>;

/// Owns the server across the plugin's enable/disable cycles. It walks the
/// fixed port range (18086 to 18093, D-38) and never asks the OS for a
/// port, so the app's probe range always covers the plugin.
class ServerLifecycle {
 public:
  /// The ports tried in order, 18086 to 18093.
  static std::vector<int> defaultPorts();

  /// [bind] defaults to [Server::start]; [ports] to [defaultPorts]. The port in
  /// [config] is overwritten by each attempt.
  ServerLifecycle(Cache& cache, ServerConfig config, BindFn bind = nullptr, std::vector<int> ports = {});
  ~ServerLifecycle();

  /// Binds the first free port. True when a server is running (also when it
  /// already was). On failure nothing is served and [failureReason] says why.
  bool start();

  /// Closes stream clients, stops the server and joins its threads. Idempotent.
  void stop();

  bool running() const { return server_ != nullptr; }

  /// The bound port, or 0 when not running.
  int port() const { return server_ ? server_->port() : 0; }

  /// A line for Log.txt after a failed [start]; empty otherwise.
  const std::string& failureReason() const { return failureReason_; }

  /// The running server, or null. For tools that tick it themselves.
  Server* server() const { return server_.get(); }

  /// Forwards to [Server::tick]; does nothing when not running. Sim thread only.
  void tick(ValueSource& source);

 private:
  Cache& cache_;
  ServerConfig config_;
  BindFn bind_;
  std::vector<int> ports_;
  std::unique_ptr<Server> server_;
  std::string failureReason_;
};

}  // namespace flightsim_aide
