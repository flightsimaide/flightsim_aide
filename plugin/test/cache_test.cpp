#include <atomic>
#include <chrono>
#include <thread>
#include <vector>

#include "cache.h"
#include "doctest.h"

using namespace flightsim_aide;

namespace {
CacheData sample(int n) {
  CacheData d;
  d.icao = "A" + std::to_string(n);
  d.description = "Plane " + std::to_string(n);
  d.aircraftPath = "Aircraft/" + std::to_string(n) + ".acf";
  d.hasChecklist = true;
  d.checklistPath = "Aircraft/" + std::to_string(n) + "/clist.txt";
  d.checklistModified = 1000000 + n;
  d.checklistSize = static_cast<int64_t>(std::to_string(n).size());
  d.checklistText = std::to_string(n);
  return d;
}
}  // namespace

TEST_CASE("snapshot returns what update stored") {
  Cache c;
  c.update(sample(7));
  const CacheData s = c.snapshot();
  CHECK(s.icao == "A7");
  CHECK(s.description == "Plane 7");
  CHECK(s.aircraftPath == "Aircraft/7.acf");
  CHECK(s.hasChecklist);
  CHECK(s.checklistPath == "Aircraft/7/clist.txt");
  CHECK(s.checklistModified == 1000007);
  CHECK(s.checklistSize == 1);
  CHECK(s.checklistText == "7");
}

TEST_CASE("snapshot is a copy") {
  Cache c;
  c.update(sample(1));
  CacheData s = c.snapshot();
  s.icao = "changed";
  s.checklistText = "changed";
  CHECK(c.snapshot().icao == "A1");
  CHECK(c.snapshot().checklistText == "1");
}

TEST_CASE("an empty cache has generation 0 and no checklist") {
  Cache c;
  const CacheData s = c.snapshot();
  CHECK(s.generation == 0);
  CHECK_FALSE(s.hasChecklist);
}

TEST_CASE("generation is bumped separately from the data") {
  Cache c;
  c.update(sample(1));
  CHECK(c.snapshot().generation == 0);
  CHECK(c.bumpGeneration() == 1);
  CHECK(c.snapshot().generation == 1);
  c.update(sample(2));  // a file edit does not touch the generation
  CHECK(c.snapshot().generation == 1);
  CHECK(c.generation() == 1);
}

TEST_CASE("generation wraps at 2^31") {
  Cache c;
  c.setGeneration(2147483646);
  CHECK(c.bumpGeneration() == 2147483647);
  CHECK(c.bumpGeneration() == 0);
  CHECK(c.bumpGeneration() == 1);
}

TEST_CASE("concurrent readers while a writer updates 10000 times never see a torn snapshot") {
  Cache c;
  c.update(sample(0));
  std::atomic<bool> done{false};
  std::atomic<int> torn{0};
  std::vector<std::thread> readers;
  for (int i = 0; i < 4; ++i) {
    readers.emplace_back([&] {
      while (!done) {
        const CacheData s = c.snapshot();
        const int n = std::stoi(s.icao.substr(1));
        const CacheData want = sample(n);
        if (s.description != want.description || s.aircraftPath != want.aircraftPath ||
            s.checklistPath != want.checklistPath || s.checklistModified != want.checklistModified ||
            s.checklistSize != want.checklistSize || s.checklistText != want.checklistText) {
          ++torn;
        }
      }
    });
  }
  for (int n = 1; n <= 10000; ++n) c.update(sample(n));
  done = true;
  for (auto& t : readers) t.join();
  CHECK(torn == 0);
}

TEST_CASE("a refresh request returns at once when nothing serves refreshes") {
  Cache c;
  const auto start = std::chrono::steady_clock::now();
  CHECK_FALSE(c.requestRefresh(std::chrono::milliseconds(2000)));
  CHECK(std::chrono::steady_clock::now() - start < std::chrono::milliseconds(500));
}

TEST_CASE("a refresh request waits until the sim thread has served it") {
  Cache c;
  c.update(sample(1));
  c.enableRefreshRequests();
  std::atomic<bool> stop{false};
  std::thread sim([&] {
    while (!stop) {
      if (const int64_t ticket = c.pendingRefresh()) {
        c.update(sample(2));  // the "re-read" the sim thread does
        c.refreshServed(ticket);
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  });
  CHECK(c.requestRefresh(std::chrono::milliseconds(2000)));
  CHECK(c.snapshot().icao == "A2");
  stop = true;
  sim.join();
}

TEST_CASE("a refresh request that nobody serves gives up after the wait") {
  Cache c;
  c.enableRefreshRequests();
  const auto start = std::chrono::steady_clock::now();
  CHECK_FALSE(c.requestRefresh(std::chrono::milliseconds(60)));
  CHECK(std::chrono::steady_clock::now() - start >= std::chrono::milliseconds(50));
  CHECK(c.pendingRefresh() != 0);  // still there for the next frame
}

TEST_CASE("pendingRefresh is zero when nothing was asked") {
  Cache c;
  c.enableRefreshRequests();
  CHECK(c.pendingRefresh() == 0);
}
