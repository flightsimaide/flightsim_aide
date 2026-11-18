#pragma once

#include <algorithm>
#include <cctype>
#include <string>
#include <utility>
#include <vector>

namespace flightsim_aide {

/// What the handlers need to know about a request. No file path is ever built
/// from any of it.
struct Request {
  std::string method;  // "GET", "HEAD", ...
  std::string path;    // the URI path; a query string, if present, is ignored
  std::vector<std::pair<std::string, std::string>> headers;

  /// Case-insensitive header lookup; empty when absent.
  std::string header(const std::string& name) const {
    for (const auto& h : headers) {
      if (iequals(h.first, name)) return h.second;
    }
    return "";
  }

  static bool iequals(const std::string& a, const std::string& b) {
    return a.size() == b.size() &&
           std::equal(a.begin(), a.end(), b.begin(), [](char x, char y) {
             return std::tolower(static_cast<unsigned char>(x)) ==
                    std::tolower(static_cast<unsigned char>(y));
           });
  }
};

/// A complete HTTP response. [headers] already holds Content-Length where the
/// protocol wants one; for HEAD the body is empty but Content-Length is that
/// of the GET body.
struct Response {
  int status = 200;
  std::vector<std::pair<std::string, std::string>> headers;
  std::string body;

  /// Case-insensitive header lookup; empty when absent.
  std::string header(const std::string& name) const {
    for (const auto& h : headers) {
      if (Request::iequals(h.first, name)) return h.second;
    }
    return "";
  }

  bool hasHeader(const std::string& name) const {
    for (const auto& h : headers) {
      if (Request::iequals(h.first, name)) return true;
    }
    return false;
  }
};

/// Facts about the running server that the handlers report.
struct ServerInfo {
  int port = 0;
  /// Reported as `sim.kind`: `xplane` or `msfs`.
  std::string simKind = "xplane";
  std::string simVersion;
  std::string os;
  std::string pluginVersion;
  std::string runId;
};

}  // namespace flightsim_aide
