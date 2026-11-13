#include <cmath>

#include "doctest.h"
#include "rate_limiter.h"

using namespace flightsim_aide;
using std::chrono::milliseconds;
using std::chrono::seconds;

namespace {
Instant ms(int64_t v) { return std::chrono::duration_cast<Instant>(milliseconds(v)); }
}  // namespace

TEST_CASE("2 Hz is due every 500 ms") {
  RateLimiter r;
  r.set(1, 2, ms(0));
  CHECK(r.due(ms(0)) == std::vector<int64_t>{1});  // the first frame is immediate
  CHECK(r.due(ms(1)).empty());
  CHECK(r.due(ms(499)).empty());
  CHECK(r.due(ms(500)) == std::vector<int64_t>{1});
  CHECK(r.due(ms(999)).empty());
  CHECK(r.due(ms(1000)) == std::vector<int64_t>{1});
}

TEST_CASE("60 Hz is due every 16.7 ms on average over 10 s") {
  RateLimiter r;
  r.set(1, 60, ms(0));
  int count = 0;
  for (int t = 0; t < 10000; ++t) count += static_cast<int>(r.due(ms(t)).size());
  CHECK(count >= 599);
  CHECK(count <= 601);
}

TEST_CASE("late sender gets one frame, not a burst") {
  RateLimiter r;
  r.set(1, 10, ms(0));
  CHECK(r.due(ms(0)).size() == 1);
  CHECK(r.due(ms(1050)).size() == 1);  // ten periods late: still one
  CHECK(r.due(ms(1051)).empty());
  CHECK(r.due(ms(1099)).empty());
  CHECK(r.due(ms(1100)).size() == 1);  // back on the original grid
}

TEST_CASE("a faster tick does not produce extra frames") {
  RateLimiter r;
  r.set(1, 1, ms(0));
  int count = 0;
  for (int t = 0; t < 3000; ++t) count += static_cast<int>(r.due(ms(t)).size());
  CHECK(count == 3);  // at 0, 1000 and 2000 ms
}

TEST_CASE("no drift over 1000 periods") {
  RateLimiter r;
  r.set(1, 3, ms(0));
  const double period = 1000.0 / 3.0;
  int k = 0;
  for (int t = 0; t <= 334000; ++t) {
    if (!r.due(ms(t)).empty()) {
      // The k-th frame goes out within one tick of its place on the grid.
      CHECK(std::fabs(t - k * period) < 1.0 + 1e-6);
      ++k;
    }
  }
  CHECK(k >= 1001);
}

TEST_CASE("hz change takes effect on the next period") {
  RateLimiter r;
  r.set(1, 1, ms(0));
  CHECK(r.due(ms(0)).size() == 1);
  r.set(1, 10, ms(500));  // only the rate changes; the running period completes
  CHECK(r.due(ms(999)).empty());
  CHECK(r.due(ms(1000)).size() == 1);
  CHECK(r.due(ms(1099)).empty());
  CHECK(r.due(ms(1100)).size() == 1);  // now at 10 Hz
}

TEST_CASE("two subscriptions have independent rates and come back ascending") {
  RateLimiter r;
  r.set(7, 1, ms(0));
  r.set(3, 2, ms(0));
  CHECK(r.due(ms(0)) == std::vector<int64_t>{3, 7});
  CHECK(r.due(ms(500)) == std::vector<int64_t>{3});
  CHECK(r.due(ms(1000)) == std::vector<int64_t>{3, 7});
}

TEST_CASE("removed subscriptions are never due") {
  RateLimiter r;
  r.set(1, 60, ms(0));
  r.remove(1);
  CHECK(r.empty());
  CHECK(r.due(ms(5000)).empty());
  r.remove(99);  // unknown id is ignored
}
