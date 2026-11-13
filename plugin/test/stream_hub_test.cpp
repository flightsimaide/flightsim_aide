#include <cmath>
#include <atomic>
#include <map>
#include <set>
#include <thread>
#include <tuple>

#include "doctest.h"
#include "stream_hub.h"

using namespace flightsim_aide;
using std::chrono::milliseconds;
using std::chrono::seconds;

namespace {

const char* kOnGround = "sim/flightmodel/failures/onground_any";
const char* kRunning = "sim/time/total_running_time_sec";

Instant ms(int64_t v) { return std::chrono::duration_cast<Instant>(milliseconds(v)); }

// A scripted sim. Records which thread called it, so a test can prove that
// only tick() ever does.
class FakeSource : public ValueSource {
 public:
  FakeSource() : owner(std::this_thread::get_id()) {}

  Resolution resolve(const std::string& base, int index) override {
    check();
    const std::string name = index < 0 ? base : base + "[" + std::to_string(index) + "]";
    ++resolveCount[name];
    Resolution r;
    if (index >= 0) {
      if (arrays.count(base) == 0) return r;  // unknown
      r.status = Resolution::Status::ok;
      r.handle = std::hash<std::string>()(name);
      byHandle[r.handle] = name;
      elements[r.handle] = {base, index};
      return r;
    }
    if (unsupported.count(base) != 0 || arrays.count(base) != 0) {
      r.status = Resolution::Status::unsupported;
    } else if (values.count(base) != 0) {
      r.status = Resolution::Status::ok;
      r.handle = std::hash<std::string>()(name);
      byHandle[r.handle] = name;
    }
    return r;
  }

  Resolution resolveRange(const std::string& base, int first, int last) override {
    check();
    Resolution r;
    if (arrays.count(base) == 0) return r;  // unknown
    r.status = Resolution::Status::ok;
    r.handle = std::hash<std::string>()(base + "[" + std::to_string(first) + ".." + std::to_string(last) + "]");
    ranges[r.handle] = {base, first, last};
    ++rangeResolves;
    return r;
  }

  void readRange(uint64_t handle, std::vector<double>& out) override {
    check();
    out.clear();
    ++rangeReads;
    const auto& [base, first, last] = ranges.at(handle);
    const auto& list = arrays.at(base);
    for (int i = first; i <= last && static_cast<size_t>(i) < list.size(); ++i) {
      out.push_back(list[static_cast<size_t>(i)]);
    }
  }

  double read(uint64_t handle) override {
    check();
    const std::string& name = byHandle.at(handle);
    ++readCount[name];
    const auto e = elements.find(handle);
    if (e != elements.end()) {
      const auto& list = arrays.at(e->second.first);
      const size_t i = static_cast<size_t>(e->second.second);
      return i < list.size() ? list[i] : std::nan("");
    }
    return values.at(name);
  }

  std::map<std::string, double> values{{kOnGround, 1}, {kRunning, 100.5}};
  std::map<std::string, std::vector<double>> arrays{{"arr/float", {0.25, 0.5}}, {"arr/int", {3, 0}}};
  std::map<uint64_t, std::pair<std::string, int>> elements;
  std::map<uint64_t, std::tuple<std::string, int, int>> ranges;
  int rangeResolves = 0;
  int rangeReads = 0;
  std::set<std::string> unsupported{"array/dataref"};
  std::map<std::string, int> resolveCount;
  std::map<std::string, int> readCount;
  std::map<uint64_t, std::string> byHandle;
  std::thread::id owner;
  std::atomic<int> wrongThread{0};

 private:
  void check() {
    if (std::this_thread::get_id() != owner) ++wrongThread;
  }
};

struct Rig {
  StreamHub hub;
  FakeSource source;
  int64_t generation = 12;
  Instant now{0};

  void tick() { hub.tick(source, generation, now, 1761206400000 + now.count() / 1000000); }
  void advance(int64_t millis) { now += ms(millis); }
};

int count(const std::vector<std::string>& frames, const std::string& op) {
  int n = 0;
  for (const std::string& f : frames) {
    if (f.find("\"op\":\"" + op + "\"") != std::string::npos) ++n;
  }
  return n;
}

std::string sub(int id, const std::string& name, int hz) {
  return "{\"op\":\"subscribe\",\"id\":" + std::to_string(id) + ",\"name\":\"" + name +
         "\",\"hz\":" + std::to_string(hz) + "}";
}

// Plays the hub for [total] ms with the sim ticking and the sender collecting
// every 10 ms; returns every frame sent to [client].
std::vector<std::string> run(Rig& r, StreamHub::ClientId client, int total, int step = 10) {
  std::vector<std::string> out;
  for (int t = 0; t < total; t += step) {
    r.tick();
    const auto o = r.hub.collectOutgoing(client, r.now);
    out.insert(out.end(), o.frames.begin(), o.frames.end());
    r.advance(step);
  }
  return out;
}

}  // namespace

TEST_CASE("subscribe is answered at the next tick") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, kOnGround, 2), r.now);
  CHECK(r.hub.collectOutgoing(c, r.now).frames.empty());  // nothing before the tick
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 2);
  CHECK(frames[0] == "{\"op\":\"subscribed\",\"id\":1}");
  CHECK(frames[1].find("\"v\":{\"1\":1}") != std::string::npos);  // the first value follows at once
}

TEST_CASE("unknown name gets unknown_name") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(2, "no/such", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 1);
  CHECK(frames[0].find("\"id\":2") != std::string::npos);
  CHECK(frames[0].find("\"code\":\"unknown_name\"") != std::string::npos);
  CHECK(count(run(r, c, 3000), "values") == 0);
  CHECK(r.hub.requestedNames().empty());
}

TEST_CASE("array dataref gets unsupported") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(3, "array/dataref", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 1);
  CHECK(frames[0].find("\"code\":\"unsupported\"") != std::string::npos);
}

TEST_CASE("known name gets values at the requested rate (fake clock)") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, kOnGround, 2), r.now);
  const auto frames = run(r, c, 2000);
  CHECK(count(frames, "subscribed") == 1);
  CHECK(count(frames, "values") == 4);  // at 0, 500, 1000 and 1500 ms
  CHECK(frames[0] == "{\"op\":\"subscribed\",\"id\":1}");
}

TEST_CASE("values frames carry t, the id as a string and the value") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, kOnGround, 1), r.now);
  r.hub.onClientMessage(c, sub(2, kRunning, 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 3);
  CHECK(frames[2] == "{\"op\":\"values\",\"t\":1761206400000,\"v\":{\"1\":1,\"2\":100.5}}");
}

TEST_CASE("generation is delivered at subscribe and at every change") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, kGenerationSignal, 1), r.now);
  r.tick();
  auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 2);
  CHECK(frames[1].find("\"v\":{\"1\":12}") != std::string::npos);

  // 10 ms later, far before the 1 s period: the change goes out at once.
  r.advance(10);
  r.generation = 13;
  r.tick();
  frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 1);
  CHECK(frames[0].find("\"v\":{\"1\":13}") != std::string::npos);

  // No change: nothing more until the period is due.
  r.advance(10);
  r.tick();
  CHECK(r.hub.collectOutgoing(c, r.now).frames.empty());
  // The reserved name never reaches the sim.
  CHECK(r.source.resolveCount.count(kGenerationSignal) == 0);
}

TEST_CASE("unsubscribe stops values") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, kOnGround, 10), r.now);
  CHECK(count(run(r, c, 300), "values") > 0);
  r.hub.onClientMessage(c, "{\"op\":\"unsubscribe\",\"id\":1}", r.now);
  run(r, c, 20);  // lets the unsubscribe through
  CHECK(count(run(r, c, 3000), "values") == 0);
}

TEST_CASE("idle client gets hb about once a second") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  const auto frames = run(r, c, 3500);
  CHECK(count(frames, "hb") == 3);  // at 1000, 2000 and 3000 ms
  CHECK(count(frames, "values") == 0);
}

TEST_CASE("values frames count as activity for the heartbeat") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, kOnGround, 5), r.now);
  CHECK(count(run(r, c, 3000), "hb") == 0);
}

TEST_CASE("closing a client removes its subscriptions") {
  Rig r;
  const auto a = r.hub.connect(r.now).value();
  const auto b = r.hub.connect(r.now).value();
  r.hub.onClientMessage(a, sub(1, kOnGround, 5), r.now);
  r.hub.onClientMessage(b, sub(1, kRunning, 5), r.now);
  r.tick();
  CHECK(r.hub.requestedNames() == std::set<std::string>{kOnGround, kRunning});
  r.hub.disconnect(a);
  CHECK(r.hub.requestedNames() == std::set<std::string>{kRunning});
  CHECK(r.hub.clientCount() == 1);
  r.source.readCount.clear();
  r.advance(10);
  r.tick();
  CHECK(r.source.readCount.count(kOnGround) == 0);
  CHECK(r.hub.collectOutgoing(a, r.now).close);  // a closed client is unknown
}

TEST_CASE("names nobody subscribed to are never read") {
  Rig r;
  r.source.values["unused/name"] = 5;
  const auto c = r.hub.connect(r.now).value();
  run(r, c, 500);  // no subscriptions at all
  CHECK(r.source.readCount.empty());
  r.hub.onClientMessage(c, sub(1, kOnGround, 10), r.now);
  run(r, c, 500);
  CHECK(r.source.readCount.count(kOnGround) == 1);
  CHECK(r.source.readCount.count("unused/name") == 0);
  CHECK(r.source.resolveCount.count("unused/name") == 0);
  r.hub.onClientMessage(c, "{\"op\":\"unsubscribe\",\"id\":1}", r.now);
  run(r, c, 20);
  r.source.readCount.clear();
  run(r, c, 500);
  CHECK(r.source.readCount.empty());
}

TEST_CASE("ValueSource is only called from tick (the fake asserts the thread)") {
  Rig r;
  std::atomic<bool> stop{false};
  std::thread server([&] {
    int n = 0;
    while (!stop) {
      if (auto c = r.hub.connect(ms(n))) {
        r.hub.onClientMessage(*c, sub(1, kOnGround, 30), ms(n));
        r.hub.onClientMessage(*c, "{\"op\":\"ping\"}", ms(n));
        r.hub.onClientMessage(*c, "garbage", ms(n));
        r.hub.collectOutgoing(*c, ms(n));
        r.hub.disconnect(*c);
      }
      ++n;
    }
  });
  std::thread sender([&] {
    const auto c = r.hub.connect(ms(0));
    int n = 0;
    while (!stop) r.hub.collectOutgoing(c.value_or(0), ms(n++));
  });
  for (int i = 0; i < 2000; ++i) {
    r.advance(1);
    r.tick();
  }
  stop = true;
  server.join();
  sender.join();
  CHECK(r.source.wrongThread == 0);
  CHECK(r.source.resolveCount.size() >= 1);  // the sim thread did get calls
}

TEST_CASE("two clients get independent rates") {
  Rig r;
  const auto a = r.hub.connect(r.now).value();
  const auto b = r.hub.connect(r.now).value();
  r.hub.onClientMessage(a, sub(1, kOnGround, 2), r.now);
  r.hub.onClientMessage(b, sub(1, kOnGround, 10), r.now);
  std::vector<std::string> fa, fb;
  for (int t = 0; t < 2000; t += 10) {
    r.tick();
    const auto oa = r.hub.collectOutgoing(a, r.now).frames;
    const auto ob = r.hub.collectOutgoing(b, r.now).frames;
    fa.insert(fa.end(), oa.begin(), oa.end());
    fb.insert(fb.end(), ob.begin(), ob.end());
    r.advance(10);
  }
  CHECK(count(fa, "values") == 4);
  CHECK(count(fb, "values") == 20);
}

TEST_CASE("silent client is closed after 15 s") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.advance(4900);
  CHECK_FALSE(r.hub.collectOutgoing(c, r.now).sendPing);
  r.advance(100);  // 5 s
  CHECK(r.hub.collectOutgoing(c, r.now).sendPing);
  r.advance(1000);
  CHECK_FALSE(r.hub.collectOutgoing(c, r.now).sendPing);  // not again at once
  r.advance(8900);  // 14.9 s
  CHECK_FALSE(r.hub.collectOutgoing(c, r.now).close);
  r.advance(100);  // 15 s
  CHECK(r.hub.collectOutgoing(c, r.now).close);
}

TEST_CASE("a client that answers its ping is not closed") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.advance(10000);
  r.hub.onClientActivity(c, r.now);  // a WebSocket pong
  r.advance(14000);                  // 24 s after connect, 14 s after the pong
  CHECK_FALSE(r.hub.collectOutgoing(c, r.now).close);
  r.advance(1000);
  CHECK(r.hub.collectOutgoing(c, r.now).close);
}

TEST_CASE("any message counts as a sign of life") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.advance(14000);
  r.hub.onClientMessage(c, "{\"op\":\"ping\"}", r.now);
  r.advance(14000);
  CHECK_FALSE(r.hub.collectOutgoing(c, r.now).close);
}

TEST_CASE("fifth client is refused and a closed one frees its slot") {
  Rig r;
  std::vector<StreamHub::ClientId> ids;
  for (int i = 0; i < 4; ++i) ids.push_back(r.hub.connect(r.now).value());
  CHECK_FALSE(r.hub.connect(r.now).has_value());
  r.hub.disconnect(ids[1]);
  CHECK(r.hub.connect(r.now).has_value());
}

TEST_CASE("ping, bad requests and set are answered without a tick") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, "{\"op\":\"ping\"}", r.now);
  r.hub.onClientMessage(c, "this is not json", r.now);
  r.hub.onClientMessage(c, sub(4, kOnGround, 61), r.now);
  r.hub.onClientMessage(c, "{\"op\":\"set\",\"id\":7,\"name\":\"a\",\"value\":0}", r.now);
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 4);
  CHECK(frames[0] == "{\"op\":\"pong\"}");
  CHECK(frames[1].find("\"code\":\"bad_request\"") != std::string::npos);
  CHECK(frames[1].find("\"id\"") == std::string::npos);
  CHECK(frames[2].find("\"id\":4") != std::string::npos);
  CHECK(frames[2].find("\"code\":\"bad_request\"") != std::string::npos);
  CHECK(frames[3].find("\"id\":7") != std::string::npos);
  CHECK(frames[3].find("\"code\":\"unsupported\"") != std::string::npos);
}

TEST_CASE("the 129th subscription is over the limit") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  for (int i = 1; i <= 129; ++i) r.hub.onClientMessage(c, sub(i, kOnGround, 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  CHECK(count(frames, "subscribed") == 128);
  CHECK(count(frames, "error") == 1);
  bool found = false;
  for (const auto& f : frames) {
    if (f.find("\"code\":\"limit\"") != std::string::npos) {
      found = f.find("\"id\":129") != std::string::npos;
    }
  }
  CHECK(found);
  // Replacing an existing id does not count against the limit.
  r.hub.onClientMessage(c, sub(1, kOnGround, 2), r.now);
  r.advance(10);
  r.tick();
  CHECK(count(r.hub.collectOutgoing(c, r.now).frames, "error") == 0);
}

TEST_CASE("a repeated id replaces the subscription") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, kOnGround, 1), r.now);
  r.tick();
  r.hub.collectOutgoing(c, r.now);
  r.advance(10);
  r.hub.onClientMessage(c, sub(1, kRunning, 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  CHECK(r.hub.requestedNames() == std::set<std::string>{kRunning});
  REQUIRE(frames.size() == 2);
  CHECK(frames[1].find("\"v\":{\"1\":100.5}") != std::string::npos);
}

TEST_CASE("a client that never reads is closed instead of growing without bound") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  for (int i = 0; i < 1500; ++i) r.hub.onClientMessage(c, "{\"op\":\"ping\"}", r.now);
  CHECK(r.hub.collectOutgoing(c, r.now).close);
}

TEST_CASE("a non-finite value is sent as null") {
  Rig r;
  r.source.values["bad/value"] = std::nan("");
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, "bad/value", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 2);
  CHECK(frames[1].find("\"v\":{\"1\":null}") != std::string::npos);
}

TEST_CASE("array elements read their value, int and float") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, "arr/float[1]", 1), r.now);
  r.hub.onClientMessage(c, sub(2, "arr/int[0]", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  CHECK(count(frames, "subscribed") == 2);
  bool found = false;
  for (const auto& f : frames) {
    if (f.find("\"v\":{\"1\":0.5,\"2\":3}") != std::string::npos) found = true;
  }
  CHECK(found);
}

TEST_CASE("an index past the end is accepted and reads null") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(7, "arr/float[99]", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  CHECK(count(frames, "subscribed") == 1);
  CHECK(count(frames, "error") == 0);
  bool found = false;
  for (const auto& f : frames) {
    if (f.find("\"v\":{\"7\":null}") != std::string::npos) found = true;
  }
  CHECK(found);
}

TEST_CASE("the whole array is unsupported, an index on a scalar is unknown") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, "arr/float", 1), r.now);
  r.hub.onClientMessage(c, sub(2, std::string(kOnGround) + "[0]", 1), r.now);
  r.hub.onClientMessage(c, sub(3, "no/such[0]", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 3);
  CHECK(frames[0].find("\"code\":\"unsupported\"") != std::string::npos);
  CHECK(frames[1].find("\"code\":\"unknown_name\"") != std::string::npos);
  CHECK(frames[2].find("\"code\":\"unknown_name\"") != std::string::npos);
}

TEST_CASE("a malformed index is a bad request, before the sim is asked") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, "arr/float[a]", 1), r.now);
  r.hub.onClientMessage(c, sub(2, "arr/float[1][2]", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 2);
  CHECK(frames[0].find("\"code\":\"bad_request\"") != std::string::npos);
  CHECK(frames[1].find("\"code\":\"bad_request\"") != std::string::npos);
  CHECK(r.source.resolveCount.empty());
}

TEST_CASE("a range is one subscription and one list of values") {
  Rig r;
  r.source.arrays["arr/int"] = {1, 1, 1, 0, 0};
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(5, "arr/int[0..3]", 2), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  REQUIRE(frames.size() == 2);
  CHECK(frames[0] == "{\"op\":\"subscribed\",\"id\":5}");
  CHECK(frames[1].find("\"v\":{\"5\":[1,1,1,0]}") != std::string::npos);
  CHECK(r.source.rangeResolves == 1);
  CHECK(r.source.wrongThread == 0);
}

TEST_CASE("a range past the end of the array is cut short, and empty when it starts past the end") {
  Rig r;  // arr/float has two elements
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(1, "arr/float[0..4]", 1), r.now);
  r.hub.onClientMessage(c, sub(2, "arr/float[3..5]", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  CHECK(count(frames, "subscribed") == 2);
  bool found = false;
  for (const std::string& f : frames) {
    if (f.find("\"op\":\"values\"") == std::string::npos) continue;
    found = true;
    CHECK(f.find("\"1\":[0.25,0.5]") != std::string::npos);
    CHECK(f.find("\"2\":[]") != std::string::npos);
  }
  CHECK(found);
}

TEST_CASE("a range on a name that is not an array is unknown_name") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(3, std::string(kOnGround) + "[0..1]", 1), r.now);
  r.hub.onClientMessage(c, sub(4, "no/such[0..1]", 1), r.now);
  r.tick();
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  CHECK(count(frames, "error") == 2);
  CHECK(frames[0].find("\"code\":\"unknown_name\"") != std::string::npos);
}

TEST_CASE("a malformed range is bad_request and never reaches the sim") {
  Rig r;
  const auto c = r.hub.connect(r.now).value();
  r.hub.onClientMessage(c, sub(6, "arr/int[2..1]", 1), r.now);
  r.hub.onClientMessage(c, sub(7, "arr/int[0..128]", 1), r.now);
  const auto frames = r.hub.collectOutgoing(c, r.now).frames;
  CHECK(count(frames, "error") == 2);
  CHECK(frames[0].find("\"code\":\"bad_request\"") != std::string::npos);
  r.tick();
  CHECK(r.source.rangeResolves == 0);
}
