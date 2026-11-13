// The X-Plane shell: the only code that includes XPLM headers. It wires the
// XPLM-free core (server, cache, stream hub) to the simulator. Server threads
// never call XPLM; the flight loop (sim thread) is the only place that does.
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>

#include "XPLMPlugin.h"
#include "XPLMProcessing.h"
#include "XPLMUtilities.h"
#include "aircraft_info.h"
#include "cache.h"
#include "checklist_watcher.h"
#include "loop_timer.h"
#include "server_lifecycle.h"
#include "value_source_xplm.h"
#include "version.h"

#if IBM
#define XCL_API extern "C" __declspec(dllexport)
#else
#define XCL_API extern "C" __attribute__((visibility("default")))
#endif

namespace {

using flightsim_aide::Cache;
using flightsim_aide::CacheData;

// How often the aircraft/file housekeeping runs; the stream tick runs every frame.
constexpr int64_t kHousekeepingMs = 1000;

Cache gCache;
std::unique_ptr<flightsim_aide::ServerLifecycle> gServer;
std::unique_ptr<flightsim_aide::ChecklistWatcher> gWatcher;
flightsim_aide::ValueSourceXplm gSource;
flightsim_aide::LoopTimer gLoopTimer;  // one log line a minute: the cost of the flight loop
XPLMFlightLoopID gLoop = nullptr;
bool gDirty = true;
// A new aircraft was loaded: bump the generation once the cache holds its data.
bool gBumpPending = false;
int64_t gLastHousekeepingMs = 0;
// Picked once when X-Plane loads the plugin, so it changes with each X-Plane run.
std::string gRunId;

int64_t nowMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

void logLine(const std::string& s) { XPLMDebugString(("flightsim_aide: " + s + "\n").c_str()); }

// Rebuilds the aircraft part of the cache and rereads its checklist, then bumps
// the generation if an aircraft was loaded. The bump comes last so that a client
// that sees the new generation never gets the previous aircraft's data (the
// flight loop does not run while the sim loads, so the message arrives first).
void rebuildCache() {
  const flightsim_aide::AircraftInfo info = flightsim_aide::readAircraftInfo();
  CacheData data;
  data.icao = info.icao;
  data.description = info.description;
  data.aircraftPath = info.acfPath;
  data.checklistPath = flightsim_aide::findChecklistFile(info.acfPath);
  gCache.update(data);
  if (gWatcher) gWatcher->refresh();
  if (gBumpPending) {
    gBumpPending = false;
    gCache.bumpGeneration();
  }
  const CacheData now = gCache.snapshot();
  logLine("aircraft " + (now.icao.empty() ? std::string("(no ICAO)") : now.icao) + " \"" + now.description +
          "\" path " + now.aircraftPath + ", generation " + std::to_string(now.generation) + ", checklist " +
          (now.checklistPath.empty() ? std::string("none") : now.checklistPath) +
          (now.hasChecklist ? "" : " (not loaded)"));
}

float flightLoopBody(int64_t now) {
  // A client asked for the aircraft: look at the checklist file now.
  if (const int64_t ticket = gCache.pendingRefresh()) {
    if (gWatcher && gWatcher->refresh()) {
      logLine("checklist file changed on disk, reread on request (generation unchanged)");
    }
    gCache.refreshServed(ticket);
  }
  if (gDirty || now - gLastHousekeepingMs >= kHousekeepingMs) {
    gLastHousekeepingMs = now;
    if (gDirty) {
      gDirty = false;
      rebuildCache();
    } else if (gWatcher && gWatcher->poll()) {
      logLine("checklist file changed on disk, reread (generation unchanged)");
    }
  }
  if (gServer) gServer->tick(gSource);
  return -1.0f;  // every frame; the hub paces each subscription itself
}

float flightLoop(float, float, int, void*) {
  const auto start = std::chrono::steady_clock::now();
  const int64_t now = nowMs();
  const float next = flightLoopBody(now);
  const auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - start).count();
  if (const auto stats = gLoopTimer.record(ns, now)) {
    char line[160];
    std::snprintf(line, sizeof line, "flight loop: %lld calls, average %.1f us, worst %.1f us",
                  static_cast<long long>(stats->calls), stats->avgUs, stats->worstUs);
    logLine(line);
  }
  return next;
}

}  // namespace

XCL_API int XPluginStart(char* name, char* sig, char* desc) {
  // The version is in the name so Plugin Admin shows which build is installed.
  std::snprintf(name, 256, "FlightSim Aide %s", flightsim_aide::pluginVersion());
  std::strcpy(sig, "com.flightsimaide.companion");
  std::strcpy(desc, "Serves the aircraft's checklist and live values to the FlightSim Aide app on the local network.");
  XPLMEnableFeature("XPLM_USE_NATIVE_PATHS", 1);
  gRunId = flightsim_aide::makeRunId();

  gWatcher = std::make_unique<flightsim_aide::ChecklistWatcher>(gCache, nowMs);
  XPLMCreateFlightLoop_t fl = {};
  fl.structSize = sizeof(fl);
  fl.phase = xplm_FlightLoop_Phase_AfterFlightModel;
  fl.callbackFunc = flightLoop;
  gLoop = XPLMCreateFlightLoop(&fl);
  logLine(std::string("started, version ") + flightsim_aide::pluginVersion());
  return 1;
}

XCL_API void XPluginStop(void) {
  if (gLoop != nullptr) {
    XPLMDestroyFlightLoop(gLoop);
    gLoop = nullptr;
  }
  gServer.reset();
  gWatcher.reset();
  logLine("stopped");
}

XCL_API int XPluginEnable(void) {
  int major = 0;
  int xplm = 0;
  XPLMHostApplicationID host = 0;
  XPLMGetVersions(&major, &xplm, &host);

  flightsim_aide::ServerConfig config;
  config.simVersion = std::to_string(major);
  config.os = flightsim_aide::hostOsName();
  config.pluginVersion = flightsim_aide::pluginVersion();
  config.runId = gRunId;
  gCache.enableRefreshRequests();  // the flight loop serves them every frame
  gServer = std::make_unique<flightsim_aide::ServerLifecycle>(gCache, config);
  if (gServer->start()) {
    logLine("listening on port " + std::to_string(gServer->port()));
  } else {
    logLine(gServer->failureReason());
  }
  gDirty = true;
  if (gLoop != nullptr) XPLMScheduleFlightLoop(gLoop, -1.0f, 1);
  return 1;
}

XCL_API void XPluginDisable(void) {
  if (gLoop != nullptr) XPLMScheduleFlightLoop(gLoop, 0.0f, 0);  // stop calling
  if (gServer) {
    gServer->stop();
    gServer.reset();
    logLine("server stopped");
  }
}

XCL_API void XPluginReceiveMessage(XPLMPluginID, int msg, void* param) {
  const intptr_t plane = reinterpret_cast<intptr_t>(param);  // 0 is the user's aircraft
  if (plane != 0) return;
  if (msg == XPLM_MSG_PLANE_LOADED) {
    gBumpPending = true;
    gDirty = true;
    logLine("user aircraft loaded, rebuilding the cache");
  } else if (msg == XPLM_MSG_LIVERY_LOADED) {
    // Not a new aircraft: rebuild, keep the generation (to confirm in the sim).
    gDirty = true;
    logLine("user livery loaded, generation unchanged");
  }
}
