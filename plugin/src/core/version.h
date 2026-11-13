#pragma once

#include <string>

namespace flightsim_aide {

/// Wire protocol version reported by GET /v1/hello (plugin/PROTOCOL.md).
constexpr int kProtocolVersion = 1;

/// Plugin release reported by GET /v1/hello.
const char* pluginVersion();

/// The OS this build runs on: `windows`, `macos` or `linux`.
const char* hostOsName();

/// A random id for one X-Plane run: 16 lowercase hex characters. GET /v1/hello
/// sends it as `runId` so the app can tell a restart from a dropped link.
std::string makeRunId();

}  // namespace flightsim_aide
