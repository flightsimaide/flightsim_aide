#pragma once

#include <string>

namespace flightsim_aide {

/// What X-Plane says about the user's aircraft. Sim thread only (calls XPLM).
struct AircraftInfo {
  std::string icao;
  std::string description;
  /// File name of the `.acf`, as X-Plane reports it.
  std::string acfFile;
  /// Full path of the `.acf` (native, UTF-8).
  std::string acfPath;
};

AircraftInfo readAircraftInfo();

/// The checklist file for an aircraft: the first of `checklistCandidates`
/// that exists, or empty when there is none. The one place that decides where
/// a checklist lives (the extension point for open item 1).
std::string findChecklistFile(const std::string& acfPath);

}  // namespace flightsim_aide
