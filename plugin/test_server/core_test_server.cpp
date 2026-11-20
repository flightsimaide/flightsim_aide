// core_test_server: the plugin core on its own, with scripted data and no
// simulator. Used by the contract runner, by device tests (3.12, 3.13) and as
// a stand-in for X-Plane when developing the app.
//
//   core_test_server [--port N] [--bind ADDR] [--scenario default|no_checklist|oversize]
//                    [--synthetic HZ] [--fixtures DIR] [--exit-on-stdin-close]
//
// Prints "PORT=<n>" once it is listening, then runs until Ctrl+C. Test
// harnesses pass --exit-on-stdin-close so that closing the pipe stops it.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <thread>
#include <utility>
#include <vector>

#include "json_parser.h"
#include "server_lifecycle.h"
#include "stream_server.h"
#include "version.h"

using namespace flightsim_aide;

namespace {

constexpr const char* kSeqSignal = "synthetic/seq";

std::string readFile(const std::string& path, bool* ok) {
  std::ifstream in(path, std::ios::binary);
  *ok = static_cast<bool>(in);
  return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

// Serves the signals of stream_values.json; with --synthetic also a counter
// that grows by one at every read (every sim tick).
class ScriptedSource : public ValueSource {
 public:
  std::map<std::string, double> signals;
  std::map<std::string, std::vector<double>> arrays;
  std::set<std::string> unsupported;
  bool synthetic = false;

  Resolution resolve(const std::string& base, int index) override {
    Resolution r;
    if (index >= 0) {
      if (arrays.count(base) == 0) return r;  // unknown
    } else if (unsupported.count(base) != 0 || arrays.count(base) != 0) {
      r.status = Resolution::Status::unsupported;
      return r;
    } else if (!((synthetic && base == kSeqSignal) || signals.count(base) != 0)) {
      return r;
    }
    r.status = Resolution::Status::ok;
    names_.push_back({base, index});
    r.handle = names_.size() - 1;
    return r;
  }

  Resolution resolveRange(const std::string& base, int first, int last) override {
    Resolution r;
    if (arrays.count(base) == 0) return r;  // unknown
    r.status = Resolution::Status::ok;
    ranges_.push_back({base, first, last});
    r.handle = ranges_.size() - 1;
    return r;
  }

  void readRange(uint64_t handle, std::vector<double>& out) override {
    out.clear();
    const auto& [base, first, last] = ranges_.at(static_cast<size_t>(handle));
    const auto& list = arrays.at(base);
    for (int i = first; i <= last && static_cast<size_t>(i) < list.size(); ++i) {
      out.push_back(list[static_cast<size_t>(i)]);
    }
  }

  double read(uint64_t handle) override {
    const auto& n = names_.at(static_cast<size_t>(handle));
    if (n.second >= 0) {
      const auto& list = arrays.at(n.first);
      const size_t i = static_cast<size_t>(n.second);
      return i < list.size() ? list[i] : std::numeric_limits<double>::quiet_NaN();
    }
    if (n.first == kSeqSignal) return static_cast<double>(++counter_);
    return signals.at(n.first);
  }

 private:
  std::vector<std::pair<std::string, int>> names_;
  std::vector<std::tuple<std::string, int, int>> ranges_;
  int64_t counter_ = 0;
};

}  // namespace

int main(int argc, char** argv) {
  int port = 0;
  std::string bind = "0.0.0.0";
  std::string scenario = "default";
  std::string fixtures = FIXTURE_DIR;
  int syntheticHz = 0;
  bool exitOnStdinClose = false;
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    const bool hasValue = i + 1 < argc;
    if (a == "--port" && hasValue) {
      port = std::atoi(argv[++i]);
    } else if (a == "--bind" && hasValue) {
      bind = argv[++i];
    } else if (a == "--scenario" && hasValue) {
      scenario = argv[++i];
    } else if (a == "--fixtures" && hasValue) {
      fixtures = argv[++i];
    } else if (a == "--exit-on-stdin-close") {
      exitOnStdinClose = true;
    } else if (a == "--synthetic" && hasValue) {
      syntheticHz = std::atoi(argv[++i]);
    } else {
      std::cerr << "usage: core_test_server [--port N] [--bind ADDR] "
                   "[--scenario default|no_checklist|oversize] [--synthetic HZ] [--fixtures DIR]\n";
      return 2;
    }
  }
  if (scenario != "default" && scenario != "no_checklist" && scenario != "oversize") {
    std::cerr << "unknown scenario " << scenario << "\n";
    return 2;
  }

  bool ok = false;
  const std::string valuesText = readFile(fixtures + "/stream_values.json", &ok);
  JsonValue values;
  std::string error;
  if (!ok || !parseJson(valuesText, values, error)) {
    std::cerr << "cannot read " << fixtures << "/stream_values.json\n";
    return 1;
  }
  ScriptedSource source;
  source.synthetic = syntheticHz > 0;
  if (const JsonValue* signals = values.find("signals")) {
    for (const auto& m : signals->members) source.signals[m.first] = m.second.number;
  }
  if (const JsonValue* arrays = values.find("arrays")) {
    for (const auto& m : arrays->members) {
      for (const auto& e : m.second.members) source.arrays[m.first].push_back(e.second.number);
    }
  }
  if (const JsonValue* unsupported = values.find("unsupported")) {
    for (const auto& m : unsupported->members) source.unsupported.insert(m.second.text);
  }

  Cache cache;
  CacheData d;
  d.icao = "C172";
  d.description = "Cessna Skyhawk 172SP";
  d.aircraftPath = "Aircraft/Laminar Research/Cessna 172SP/Cessna_172SP.acf";
  if (scenario != "no_checklist") {
    d.hasChecklist = true;
    d.checklistPath = "Aircraft/Laminar Research/Cessna 172SP/clist.txt";
    d.checklistModified = 1761206400123;
    if (scenario == "oversize") {
      d.checklistSize = 3 * 1024 * 1024;  // like the shell, an oversize file is not read
    } else {
      d.checklistText = readFile(fixtures + "/checklist_sample.txt", &ok);
      if (!ok) {
        std::cerr << "cannot read " << fixtures << "/checklist_sample.txt\n";
        return 1;
      }
      d.checklistSize = static_cast<int64_t>(d.checklistText.size());
    }
  }
  cache.update(d);
  const auto gen = source.signals.find(kGenerationSignal);
  cache.setGeneration(gen != source.signals.end() ? static_cast<int64_t>(gen->second) : 12);

  ServerConfig config;
  config.bindAddress = bind;
  config.port = port;
  config.simVersion = "core_test_server";
  config.os = flightsim_aide::hostOsName();
  config.pluginVersion = "0.3.0";
  config.runId = flightsim_aide::makeRunId();
  // Same start path as the plugin shell. An explicit --port is the only port
  // tried; without one the OS picks (tests, device runs).
  ServerLifecycle lifecycle(cache, config, nullptr, {port});
  if (!lifecycle.start()) {
    std::cerr << lifecycle.failureReason() << "\n";
    return 1;
  }
  Server* server = lifecycle.server();
  // One sim tick per requested frame in synthetic mode, so every frame carries
  // the next sequence number.
  TickThread ticker(*server, source,
                    std::chrono::milliseconds(syntheticHz > 0 ? 1000 / syntheticHz : 20));

  std::cout << "PORT=" << server->port() << std::endl;
  if (exitOnStdinClose) {
    std::string line;
    while (std::getline(std::cin, line)) {
    }
    return 0;
  }
  while (true) std::this_thread::sleep_for(std::chrono::seconds(1));
}
