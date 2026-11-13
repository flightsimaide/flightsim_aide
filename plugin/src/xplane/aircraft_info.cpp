#include "aircraft_info.h"

#include "XPLMDataAccess.h"
#include "XPLMPlanes.h"
#include "aircraft_paths.h"
#include "file_info.h"

namespace flightsim_aide {

namespace {

std::string readByteArray(const char* name) {
  const XPLMDataRef ref = XPLMFindDataRef(name);
  if (ref == nullptr) return {};
  char buf[512] = {0};
  const int n = XPLMGetDatab(ref, buf, 0, sizeof(buf) - 1);
  if (n <= 0) return {};
  buf[n] = 0;
  return std::string(buf);  // stops at the first NUL, like the sim's own strings
}

}  // namespace

AircraftInfo readAircraftInfo() {
  char file[256] = {0};
  char path[1024] = {0};
  XPLMGetNthAircraftModel(0, file, path);
  AircraftInfo info;
  info.acfFile = file;
  info.acfPath = path;
  info.icao = readByteArray("sim/aircraft/view/acf_ICAO");
  info.description = readByteArray("sim/aircraft/view/acf_descrip");
  return info;
}

std::string findChecklistFile(const std::string& acfPath) {
  for (const std::string& candidate : checklistCandidates(acfPath)) {
    if (statFile(candidate)) return candidate;
  }
  return {};
}

}  // namespace flightsim_aide
