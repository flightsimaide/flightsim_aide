#include "version.h"

#include <cstdint>
#include <cstdio>
#include <random>

namespace flightsim_aide {

const char* pluginVersion() { return "0.2.0"; }

const char* hostOsName() {
#if defined(_WIN32)
  return "windows";
#elif defined(__APPLE__)
  return "macos";
#else
  return "linux";
#endif
}

std::string makeRunId() {
  std::random_device device;
  std::mt19937_64 engine((static_cast<uint64_t>(device()) << 32) ^ device());
  char text[17];
  std::snprintf(text, sizeof text, "%016llx", static_cast<unsigned long long>(engine()));
  return text;
}

}  // namespace flightsim_aide
