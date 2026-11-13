#pragma once

#include <cstdint>
#include <string>

namespace flightsim_aide {

/// Fields of GET /v1/hello (plugin/PROTOCOL.md section 2).
struct HelloInfo {
  std::string simKind = "xplane";
  std::string simVersion;
  /// `windows`, `macos` or `linux`; left out of the answer when empty.
  std::string os;
  std::string pluginVersion;
  /// Random text picked when X-Plane starts; the app tells a restart from a dropped link by it.
  std::string runId;
  int port = 0;
};

/// Fields of GET /v1/aircraft (section 4). The three checklist fields are
/// written only when [hasChecklist] is true.
struct AircraftInfo {
  int64_t generation = 0;
  std::string icao;
  std::string description;
  std::string aircraftPath;
  bool hasChecklist = false;
  std::string checklistPath;
  int64_t checklistModified = 0;  // epoch milliseconds UTC
  int64_t checklistSize = 0;
};

/// A JSON string literal with quotes. Escapes `"`, `\` and C0 control
/// characters; bytes of 0x80 and above (UTF-8) pass through unchanged.
std::string jsonString(const std::string& s);

std::string helloJson(const HelloInfo& h);
std::string aircraftJson(const AircraftInfo& a);

/// `{"error":"<code>","message":"<text>"}`.
std::string errorJson(const std::string& code, const std::string& message);

}  // namespace flightsim_aide
