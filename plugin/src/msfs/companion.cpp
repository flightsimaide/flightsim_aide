// The Microsoft Flight Simulator companion: an external program, because MSFS
// has no plug-in interface that can listen on a port (D-87). The sim starts it
// through an EXE.xml entry that the Setup program writes, with `--run`.
//
// It wires the sim-neutral core (server, cache, stream hub) to SimConnect. One
// thread, the main loop, is the only one that calls SimConnect and the only one
// that calls the hub's tick, as SimConnect is not thread safe.
//
//   --run               serve while the simulator runs; stop when it ends
//   --serve-only <s>    serve for <s> seconds without the simulator (the Setup
//                       uses it to trigger the firewall prompt and test the network)
//   --checklists <dir>  the folder with the checklists (default: ..\checklists)
//   --no-parent-watch   do not stop when the process that started this one ends
//
// With no option it shows a message and exits: it is not meant to be started by
// hand.
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <tlhelp32.h>

#include <SimConnect.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <limits>
#include <memory>
#include <string>

#include "aircraft_key.h"
#include "aircraft_tracker.h"
#include "beacon_sender.h"
#include "cache.h"
#include "checklist_watcher.h"
#include "file_info.h"
#include "server_lifecycle.h"
#include "simconnect_source.h"
#include "version.h"

using namespace flightsim_aide;

namespace {

// ---------------------------------------------------------------- small helpers

int64_t nowMs() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

std::string toUtf8(const std::wstring& w) {
  if (w.empty()) return std::string();
  const int n = WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), nullptr, 0, nullptr, nullptr);
  std::string s(static_cast<size_t>(n), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.data(), static_cast<int>(w.size()), &s[0], n, nullptr, nullptr);
  return s;
}

std::wstring fromUtf8(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), &w[0], n);
  return w;
}

std::wstring exePath() {
  wchar_t buf[MAX_PATH * 4];
  const DWORD n = GetModuleFileNameW(nullptr, buf, static_cast<DWORD>(sizeof buf / sizeof buf[0]));
  return std::wstring(buf, n);
}

std::wstring parentFolder(const std::wstring& path) {
  const size_t i = path.find_last_of(L"\\/");
  return i == std::wstring::npos ? std::wstring() : path.substr(0, i);
}

// ---------------------------------------------------------------- the log

std::wstring g_logPath;

void openLog() {
  wchar_t base[MAX_PATH];
  const DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", base, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return;
  const std::wstring folder = std::wstring(base, n) + L"\\FlightSimAide";
  CreateDirectoryW(folder.c_str(), nullptr);
  g_logPath = folder + L"\\msfs-companion.log";
  // A log that has grown large starts again.
  WIN32_FILE_ATTRIBUTE_DATA data;
  if (GetFileAttributesExW(g_logPath.c_str(), GetFileExInfoStandard, &data) && data.nFileSizeLow > 512 * 1024) {
    DeleteFileW(g_logPath.c_str());
  }
}

void logLine(const std::string& text) {
  if (g_logPath.empty()) return;
  SYSTEMTIME t;
  GetLocalTime(&t);
  char stamp[40];
  std::snprintf(stamp, sizeof stamp, "%04d-%02d-%02d %02d:%02d:%02d  ", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute,
                t.wSecond);
  std::ofstream f(g_logPath.c_str(), std::ios::app | std::ios::binary);
  if (f) f << stamp << text << "\r\n";
}

// ---------------------------------------------------------------- the parent process

// The sim can exit without a SimConnect quit and without stopping its add-ons
// (D-87), so the process that started this one is watched.
HANDLE g_parent = nullptr;

void watchParent() {
  HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snap == INVALID_HANDLE_VALUE) return;
  PROCESSENTRY32W e;
  e.dwSize = sizeof e;
  DWORD parentId = 0;
  const DWORD me = GetCurrentProcessId();
  for (BOOL ok = Process32FirstW(snap, &e); ok; ok = Process32NextW(snap, &e)) {
    if (e.th32ProcessID == me) parentId = e.th32ParentProcessID;
  }
  std::wstring parentName = L"(not running)";
  if (parentId != 0) {
    for (BOOL ok = Process32FirstW(snap, &e); ok; ok = Process32NextW(snap, &e)) {
      if (e.th32ProcessID == parentId) parentName = e.szExeFile;
    }
  }
  CloseHandle(snap);
  if (parentId != 0) g_parent = OpenProcess(SYNCHRONIZE, FALSE, parentId);
  logLine("parent process " + std::to_string(parentId) + " " + toUtf8(parentName) +
          (g_parent != nullptr ? "" : " (cannot be watched)"));
}

bool parentGone() { return g_parent != nullptr && WaitForSingleObject(g_parent, 0) == WAIT_OBJECT_0; }

// ---------------------------------------------------------------- the companion

struct Options {
  bool run = false;
  int serveOnlySeconds = 0;
  bool parentWatch = true;
  std::wstring checklists;
};

// SimConnect event ids and request ids of main (the names' ids are in simconnect_source.cpp).
enum EventId : DWORD { EV_SIMSTART = 1, EV_SIMSTOP, EV_AIRCRAFT_LOADED };
enum { DEF_IDENTITY = 10, REQ_IDENTITY_PERIODIC = 11, REQ_IDENTITY_ONCE = 12 };

class Companion {
 public:
  explicit Companion(Options options) : options_(std::move(options)) {}

  int run();

 private:
  bool startServer();
  bool tryConnect();
  void onConnected();
  void dispatchAll();
  void dispatch(SIMCONNECT_RECV* r);
  void publish();
  std::string findChecklist(const std::string& key) const;

  Options options_;
  Cache cache_;
  ChecklistWatcher watcher_{cache_, nowMs};
  std::unique_ptr<ServerLifecycle> server_;
  BeaconSender beacon_;
  std::string runId_ = makeRunId();

  HANDLE sc_ = nullptr;
  std::unique_ptr<SimConnectSource> source_;
  AircraftTracker tracker_;
  std::string simVersion_;
  int dispatched_ = 0;
  int dispatchFailures_ = 0;
  bool quit_ = false;
  int64_t lastConnectTryMs_ = -100000;
  int64_t lastHousekeepingMs_ = 0;
};

std::string Companion::findChecklist(const std::string& key) const {
  const std::string folder = toUtf8(options_.checklists);
  for (const std::string& candidate : checklistCandidatesIn(folder, key)) {
    if (statFile(candidate)) return candidate;
  }
  return std::string();
}

bool Companion::startServer() {
  ServerConfig config;
  config.simKind = "msfs";
  config.simVersion = simVersion_;
  config.os = hostOsName();
  config.pluginVersion = pluginVersion();
  config.runId = runId_;
  server_ = std::make_unique<ServerLifecycle>(cache_, config);
  if (!server_->start()) {
    logLine(server_->failureReason());
    return false;
  }
  logLine("listening on port " + std::to_string(server_->port()));
  beacon_.start("msfs", server_->port());
  return true;
}

// Answers nothing: used before SimConnect is open, so a subscription is `unknown_name`
// until the simulator is there (the app subscribes again at the next generation).
class NullSource : public ValueSource {
 public:
  Resolution resolve(const std::string&, int) override { return Resolution(); }
  double read(uint64_t) override { return std::numeric_limits<double>::quiet_NaN(); }
};

// What the app sees before a flight is loaded.
void publishNoAircraft(Cache& cache) {
  flightsim_aide::CacheData data;
  data.description = "No aircraft loaded";
  data.aircraftPath = "msfs/none";
  cache.update(data);
}

void Companion::publish() {
  const AircraftTracker::Identity& id = tracker_.identity();
  const std::string key = msfsAircraftKey(id.model);
  flightsim_aide::CacheData data;
  data.icao = key;
  data.description = id.title.empty() ? id.model : id.title;
  // Opaque to the app, which only uses it to tell aircraft apart; the checklist
  // depends on the key alone, so two liveries share one entry.
  data.aircraftPath = "msfs/" + (key.empty() ? std::string("unknown") : key);
  data.checklistPath = findChecklist(key);
  cache_.update(data);
  watcher_.refresh();
}

bool Companion::tryConnect() {
  HANDLE h = nullptr;
  if (FAILED(SimConnect_Open(&h, "FlightSim Aide", nullptr, 0, nullptr, 0))) return false;
  sc_ = h;
  return true;
}

void Companion::onConnected() {
  SimConnect_SubscribeToSystemEvent(sc_, EV_SIMSTART, "SimStart");
  SimConnect_SubscribeToSystemEvent(sc_, EV_SIMSTOP, "SimStop");
  SimConnect_SubscribeToSystemEvent(sc_, EV_AIRCRAFT_LOADED, "AircraftLoaded");
  SimConnect_AddToDataDefinition(sc_, DEF_IDENTITY, "ATC MODEL", nullptr, SIMCONNECT_DATATYPE_STRING256);
  SimConnect_AddToDataDefinition(sc_, DEF_IDENTITY, "TITLE", nullptr, SIMCONNECT_DATATYPE_STRING256);
  SimConnect_RequestDataOnSimObject(sc_, REQ_IDENTITY_PERIODIC, DEF_IDENTITY, SIMCONNECT_OBJECT_ID_USER,
                                    SIMCONNECT_PERIOD_SECOND);
  source_ = std::make_unique<SimConnectSource>(sc_, [this] { dispatchAll(); }, nowMs);
  tracker_.onConnected(nowMs());
  dispatchFailures_ = 0;
  logLine("connected to the simulator");
}

void Companion::dispatchAll() {
  for (int i = 0; i < 256; ++i) {
    dispatched_ = 0;
    if (FAILED(SimConnect_CallDispatch(sc_, [](SIMCONNECT_RECV* r, DWORD, void* self) {
                 static_cast<Companion*>(self)->dispatched_++;
                 static_cast<Companion*>(self)->dispatch(r);
               }, this))) {
      if (++dispatchFailures_ >= 30) quit_ = true;  // the connection is gone
      return;
    }
    dispatchFailures_ = 0;
    if (dispatched_ == 0) return;
  }
}

void Companion::dispatch(SIMCONNECT_RECV* r) {
  switch (r->dwID) {
    case SIMCONNECT_RECV_ID_OPEN: {
      const auto* o = reinterpret_cast<SIMCONNECT_RECV_OPEN*>(r);
      simVersion_ = std::to_string(o->dwApplicationVersionMajor) + "." + std::to_string(o->dwApplicationVersionMinor) +
                    "." + std::to_string(o->dwApplicationBuildMajor);
      logLine(std::string("SimConnect: ") + o->szApplicationName + " " + simVersion_);
      break;
    }
    case SIMCONNECT_RECV_ID_QUIT:
      logLine("the simulator closed the connection");
      quit_ = true;
      break;
    case SIMCONNECT_RECV_ID_EVENT: {
      const auto* e = reinterpret_cast<SIMCONNECT_RECV_EVENT*>(r);
      if (e->uEventID == EV_SIMSTOP) {
        logLine("SimStop");
        tracker_.onSimStop(nowMs());
      } else if (e->uEventID == EV_SIMSTART) {
        logLine("SimStart");
        tracker_.onSimStart(nowMs());
      }
      break;
    }
    case SIMCONNECT_RECV_ID_EVENT_FILENAME: {
      const auto* e = reinterpret_cast<SIMCONNECT_RECV_EVENT_FILENAME*>(r);
      if (e->uEventID == EV_AIRCRAFT_LOADED) {
        logLine(std::string("AircraftLoaded ") + e->szFileName);
        tracker_.onAircraftLoaded(e->szFileName, nowMs());
      }
      break;
    }
    case SIMCONNECT_RECV_ID_SIMOBJECT_DATA: {
      const auto* d = reinterpret_cast<SIMCONNECT_RECV_SIMOBJECT_DATA*>(r);
      if (d->dwRequestID == REQ_IDENTITY_PERIODIC || d->dwRequestID == REQ_IDENTITY_ONCE) {
        const char* base = reinterpret_cast<const char*>(&d->dwData);
        const std::string model(base, strnlen(base, 256));
        const std::string title(base + 256, strnlen(base + 256, 256));
        tracker_.onIdentity(model, title, nowMs());
      } else if (source_) {
        source_->onSimObjectData(d);
      }
      break;
    }
    case SIMCONNECT_RECV_ID_EXCEPTION:
      if (source_) source_->onException(reinterpret_cast<SIMCONNECT_RECV_EXCEPTION*>(r));
      break;
    case SIMCONNECT_RECV_ID_ENUMERATE_INPUT_EVENTS:
      if (source_) source_->onInputEventList(reinterpret_cast<SIMCONNECT_RECV_ENUMERATE_INPUT_EVENTS*>(r));
      break;
    case SIMCONNECT_RECV_ID_GET_INPUT_EVENT:
      if (source_) source_->onInputEventValue(reinterpret_cast<SIMCONNECT_RECV_GET_INPUT_EVENT*>(r));
      break;
    default:
      break;
  }
}

int Companion::run() {
  logLine(std::string("started, version ") + pluginVersion() + ", checklists " + toUtf8(options_.checklists));
  if (options_.parentWatch) watchParent();
  publishNoAircraft(cache_);
  if (!startServer()) return 3;

  const int64_t startedMs = nowMs();
  if (options_.serveOnlySeconds > 0) {
    // No simulator: serve the hello (and the beacon) so the network can be checked.
    while (nowMs() - startedMs < options_.serveOnlySeconds * 1000LL && !(options_.parentWatch && parentGone())) {
      Sleep(100);
    }
    beacon_.stop();
    server_->stop();
    logLine("serve-only run ended");
    return 0;
  }

  NullSource idle;
  while (!quit_) {
    if (options_.parentWatch && parentGone()) {
      logLine("the process that started this one (the simulator) ended; stopping");
      break;
    }
    const int64_t now = nowMs();
    if (sc_ == nullptr) {
      // Not connected yet: SimConnect appears some time after the simulator starts.
      if (now - lastConnectTryMs_ >= 2000) {
        lastConnectTryMs_ = now;
        if (tryConnect()) onConnected();
      }
      if (server_) server_->tick(idle);
      Sleep(20);
      continue;
    }

    dispatchAll();
    if (quit_) break;
    if (tracker_.wantsIdentity()) {
      tracker_.identityRequested();
      SimConnect_RequestDataOnSimObject(sc_, REQ_IDENTITY_ONCE, DEF_IDENTITY, SIMCONNECT_OBJECT_ID_USER,
                                        SIMCONNECT_PERIOD_ONCE);
    }
    const AircraftTracker::Update update = tracker_.tick(now);
    if (!tracker_.available()) {
      if (source_->available()) source_->setAvailable(false);
    }
    if (update.ready) {
      const AircraftTracker::Identity& id = tracker_.identity();
      publish();
      if (update.bump) cache_.bumpGeneration();
      source_->requestInputEventList();
      source_->setAvailable(true);
      logLine("aircraft " + id.model + " \"" + id.title + "\" key " + msfsAircraftKey(id.model) + ", generation " +
              std::to_string(cache_.generation()) + ", checklist " +
              (cache_.snapshot().checklistPath.empty() ? std::string("none") : cache_.snapshot().checklistPath));
    }
    source_->poll(now);
    if (now - lastHousekeepingMs_ >= 1000) {
      lastHousekeepingMs_ = now;
      if (watcher_.poll()) logLine("checklist file changed on disk, reread (generation unchanged)");
    }
    // A client asked for the aircraft: look at the checklist file now.
    if (const int64_t ticket = cache_.pendingRefresh()) {
      watcher_.refresh();
      cache_.refreshServed(ticket);
    }
    if (server_) server_->tick(*source_);
    Sleep(10);
  }

  beacon_.stop();
  if (server_) server_->stop();
  if (sc_ != nullptr) SimConnect_Close(sc_);
  logLine("stopped");
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  Options options;
  options.checklists = parentFolder(parentFolder(exePath())) + L"\\checklists";
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    if (a == "--run") {
      options.run = true;
    } else if (a == "--serve-only" && i + 1 < argc) {
      options.serveOnlySeconds = std::max(1, std::atoi(argv[++i]));
      options.run = true;
    } else if (a == "--checklists" && i + 1 < argc) {
      options.checklists = fromUtf8(argv[++i]);
    } else if (a == "--no-parent-watch") {
      options.parentWatch = false;
    }
  }
  if (!options.run) {
    MessageBoxW(nullptr,
                L"This is the FlightSim Aide program for Microsoft Flight Simulator.\n\n"
                L"It starts and stops with the simulator by itself. To install or remove it, use "
                L"FlightSimAide-MSFS-Setup.exe.",
                L"FlightSim Aide", MB_OK | MB_ICONINFORMATION);
    return 0;
  }
  openLog();
  Companion companion(std::move(options));
  return companion.run();
}
