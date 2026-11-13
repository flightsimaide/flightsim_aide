#include "server_lifecycle.h"

namespace flightsim_aide {

std::vector<int> ServerLifecycle::defaultPorts() {
  std::vector<int> ports;
  for (int p = 18086; p <= 18093; ++p) ports.push_back(p);
  return ports;
}

ServerLifecycle::ServerLifecycle(Cache& cache, ServerConfig config, BindFn bind, std::vector<int> ports)
    : cache_(cache),
      config_(std::move(config)),
      bind_(bind ? std::move(bind) : BindFn(&Server::start)),
      ports_(ports.empty() ? defaultPorts() : std::move(ports)) {}

ServerLifecycle::~ServerLifecycle() { stop(); }

bool ServerLifecycle::start() {
  if (server_ != nullptr) return true;
  failureReason_.clear();
  std::string lastError;
  for (const int port : ports_) {
    ServerConfig attempt = config_;
    attempt.port = port;
    std::string error;
    std::unique_ptr<Server> server = bind_(attempt, cache_, &error);
    if (server != nullptr) {
      server_ = std::move(server);
      return true;
    }
    lastError = error;
  }
  failureReason_ = "No port from " + std::to_string(ports_.front()) + " to " + std::to_string(ports_.back()) +
                   " could be bound; the companion server is off.";
  if (!lastError.empty()) failureReason_ += " Last error: " + lastError;
  return false;
}

void ServerLifecycle::stop() {
  if (server_ == nullptr) return;
  server_->stop();
  server_.reset();
}

void ServerLifecycle::tick(ValueSource& source) {
  if (server_ != nullptr) server_->tick(source);
}

}  // namespace flightsim_aide
