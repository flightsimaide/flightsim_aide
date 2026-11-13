#include <chrono>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>

#include "cache.h"
#include "checklist_watcher.h"
#include "doctest.h"
#include "file_info.h"

using namespace flightsim_aide;
namespace fs = std::filesystem;

namespace {

// A temp folder removed at the end of each test case.
struct TempDir {
  fs::path path;
  TempDir() {
    static int n = 0;
    path = fs::temp_directory_path() /
           ("flightsim_aide_test_" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) +
            "_" + std::to_string(n++));
    fs::create_directories(path);
  }
  ~TempDir() {
    std::error_code ec;
    fs::remove_all(path, ec);
  }
  std::string file(const std::string& name) const { return (path / name).string(); }
};

void writeFile(const std::string& path, const std::string& bytes) {
  std::ofstream out(fs::u8path(path), std::ios::binary | std::ios::trunc);
  out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

void setAge(const std::string& path, std::chrono::hours age) {
  fs::last_write_time(fs::u8path(path), fs::file_time_type::clock::now() - age);
}

struct FakeClock {
  int64_t nowMs = 0;
  ClockFn fn() {
    return [this] { return nowMs; };
  }
};

}  // namespace

TEST_CASE("reads the whole file") {
  TempDir dir;
  const std::string bytes = "sw_checklist:Before start\nitem:a\n";
  writeFile(dir.file("clist.txt"), bytes);
  const FileRead r = readWholeFile(dir.file("clist.txt"));
  CHECK(r.status == ReadStatus::ok);
  CHECK(r.bytes == bytes);
  CHECK(r.size == static_cast<int64_t>(bytes.size()));
  CHECK(r.modifiedMs > 0);
}

TEST_CASE("file above 2 MB is rejected") {
  TempDir dir;
  writeFile(dir.file("big.txt"), std::string(kMaxChecklistBytes + 1, 'x'));
  const FileRead r = readWholeFile(dir.file("big.txt"));
  CHECK(r.status == ReadStatus::tooLarge);
  CHECK(r.bytes.empty());
  CHECK(r.size == kMaxChecklistBytes + 1);

  writeFile(dir.file("edge.txt"), std::string(kMaxChecklistBytes, 'x'));
  CHECK(readWholeFile(dir.file("edge.txt")).status == ReadStatus::ok);
}

TEST_CASE("mtime has millisecond resolution") {
  TempDir dir;
  const auto before = std::chrono::duration_cast<std::chrono::milliseconds>(
                          std::chrono::system_clock::now().time_since_epoch())
                          .count();
  bool sawSubSecond = false;
  for (int i = 0; i < 8; ++i) {
    const std::string p = dir.file("f" + std::to_string(i) + ".txt");
    writeFile(p, "x");
    const auto st = statFile(p);
    REQUIRE(st.has_value());
    // epoch milliseconds, near the wall clock
    CHECK(st->modifiedMs >= before - 5000);
    CHECK(st->modifiedMs <= before + 60000);
    if (st->modifiedMs % 1000 != 0) sawSubSecond = true;
    std::this_thread::sleep_for(std::chrono::milliseconds(7));
  }
  CHECK(sawSubSecond);
}

TEST_CASE("missing file gives none") {
  TempDir dir;
  CHECK_FALSE(statFile(dir.file("nope.txt")).has_value());
  CHECK(readWholeFile(dir.file("nope.txt")).status == ReadStatus::missing);
}

TEST_CASE("CR-only file is read byte for byte") {
  TempDir dir;
  const std::string bytes = "sw_checklist:A\ritem:b\r\xC3\xA9\r";
  writeFile(dir.file("cr.txt"), bytes);
  CHECK(readWholeFile(dir.file("cr.txt")).bytes == bytes);
}

TEST_CASE("non-ASCII path can be read") {
  TempDir dir;
  const std::string name = dir.file("caf\xC3\xA9_clist.txt");
  writeFile(name, "ok");
  const FileRead r = readWholeFile(name);
  CHECK(r.status == ReadStatus::ok);
  CHECK(r.bytes == "ok");
}

namespace {
CacheData cacheWithFile(const std::string& path) {
  CacheData d;
  d.icao = "C172";
  d.hasChecklist = true;
  d.checklistPath = path;
  return d;
}
}  // namespace

TEST_CASE("size change with the same mtime is detected") {
  TempDir dir;
  const std::string p = dir.file("clist.txt");
  writeFile(p, "aaaa");
  Cache cache;
  FakeClock clock;
  ChecklistWatcher w(cache, clock.fn());
  cache.update(cacheWithFile(p));
  CHECK(w.refresh());
  CHECK(cache.snapshot().checklistText == "aaaa");

  // A longer file; then make the cached mtime equal the file's, so only the
  // size differs.
  writeFile(p, "aaaaaa");
  const auto st = statFile(p);
  REQUIRE(st.has_value());
  CacheData forced = cache.snapshot();
  forced.checklistModified = st->modifiedMs;
  cache.update(forced);

  clock.nowMs += 3000;
  CHECK(w.poll());
  CHECK(cache.snapshot().checklistText == "aaaaaa");
}

TEST_CASE("older mtime is detected") {
  TempDir dir;
  const std::string p = dir.file("clist.txt");
  writeFile(p, "new");
  Cache cache;
  FakeClock clock;
  ChecklistWatcher w(cache, clock.fn());
  cache.update(cacheWithFile(p));
  w.refresh();
  CHECK(cache.snapshot().checklistText == "new");

  // Restore an older copy of the same size.
  writeFile(p, "old");
  setAge(p, std::chrono::hours(48));
  clock.nowMs += 3000;
  CHECK(w.poll());
  CHECK(cache.snapshot().checklistText == "old");
}

TEST_CASE("restat only every 3 s (fake clock)") {
  TempDir dir;
  const std::string p = dir.file("clist.txt");
  writeFile(p, "one");
  Cache cache;
  FakeClock clock;
  ChecklistWatcher w(cache, clock.fn());
  cache.update(cacheWithFile(p));
  CHECK(w.refresh());

  writeFile(p, "twotwo");
  setAge(p, std::chrono::hours(1));
  clock.nowMs += 2999;
  CHECK_FALSE(w.poll());
  CHECK(cache.snapshot().checklistText == "one");
  clock.nowMs += 1;
  CHECK(w.poll());
  CHECK(cache.snapshot().checklistText == "twotwo");

  // No change, no update.
  clock.nowMs += 3000;
  CHECK_FALSE(w.poll());
}

TEST_CASE("change updates the cache and leaves the generation alone") {
  TempDir dir;
  const std::string p = dir.file("clist.txt");
  writeFile(p, "v1");
  Cache cache;
  cache.setGeneration(41);
  FakeClock clock;
  ChecklistWatcher w(cache, clock.fn());
  cache.update(cacheWithFile(p));
  w.refresh();

  writeFile(p, "version2");
  setAge(p, std::chrono::hours(1));
  clock.nowMs += 3000;
  REQUIRE(w.poll());
  const CacheData s = cache.snapshot();
  CHECK(s.generation == 41);
  CHECK(s.checklistText == "version2");
  CHECK(s.checklistSize == 8);
  CHECK(s.icao == "C172");  // other fields survive
  CHECK(s.hasChecklist);
}

TEST_CASE("a deleted file clears the checklist, a returning one restores it") {
  TempDir dir;
  const std::string p = dir.file("clist.txt");
  writeFile(p, "v1");
  Cache cache;
  FakeClock clock;
  ChecklistWatcher w(cache, clock.fn());
  cache.update(cacheWithFile(p));
  w.refresh();

  fs::remove(fs::u8path(p));
  clock.nowMs += 3000;
  CHECK(w.poll());
  CHECK_FALSE(cache.snapshot().hasChecklist);
  clock.nowMs += 3000;
  CHECK_FALSE(w.poll());  // still gone, nothing new

  writeFile(p, "back");
  clock.nowMs += 3000;
  CHECK(w.poll());
  CHECK(cache.snapshot().hasChecklist);
  CHECK(cache.snapshot().checklistText == "back");
}

TEST_CASE("an oversize file is treated as no checklist") {
  TempDir dir;
  const std::string p = dir.file("clist.txt");
  writeFile(p, std::string(kMaxChecklistBytes + 1, 'x'));
  Cache cache;
  FakeClock clock;
  ChecklistWatcher w(cache, clock.fn());
  cache.update(cacheWithFile(p));
  w.refresh();
  const CacheData s = cache.snapshot();
  CHECK(s.hasChecklist);  // handlers answer 413 from the size
  CHECK(s.checklistSize == kMaxChecklistBytes + 1);
  CHECK(s.checklistText.empty());
}
