#include "doctest.h"
#include "etag.h"

using namespace flightsim_aide;

TEST_CASE("formats quoted mtime-size") {
  CHECK(makeEtag(1761206400123, 267) == "\"1761206400123-267\"");
}

TEST_CASE("matching single value") {
  CHECK(ifNoneMatchMatches("\"1761206400123-267\"", makeEtag(1761206400123, 267)));
}

TEST_CASE("matching in a list") {
  CHECK(ifNoneMatchMatches("\"1-1\", \"1761206400123-267\" ,\"2-2\"",
                           makeEtag(1761206400123, 267)));
}

TEST_CASE("weak prefix matches") {
  CHECK(ifNoneMatchMatches("W/\"1761206400123-267\"", makeEtag(1761206400123, 267)));
  CHECK(ifNoneMatchMatches("\"1-1\", W/\"1761206400123-267\"", makeEtag(1761206400123, 267)));
}

TEST_CASE("star matches") {
  CHECK(ifNoneMatchMatches("*", makeEtag(5, 5)));
  CHECK(ifNoneMatchMatches("  * ", makeEtag(5, 5)));
}

TEST_CASE("different size does not match") {
  CHECK_FALSE(ifNoneMatchMatches("\"1761206400123-268\"", makeEtag(1761206400123, 267)));
}

TEST_CASE("older mtime does not match") {
  CHECK_FALSE(ifNoneMatchMatches("\"1761206400124-267\"", makeEtag(1761206400123, 267)));
  CHECK_FALSE(ifNoneMatchMatches("\"1761206400122-267\"", makeEtag(1761206400123, 267)));
}

TEST_CASE("garbage header does not match and does not crash") {
  const std::string etag = makeEtag(1761206400123, 267);
  for (const char* h : {"", ",", ",,,", "garbage,,\"", "\"", "W/", "W/\"", "\"\"", "1761206400123-267",
                        "\"1761206400123-267", "1761206400123-267\"", "*x", "W/*"}) {
    CAPTURE(h);
    CHECK_FALSE(ifNoneMatchMatches(h, etag));
  }
  CHECK_FALSE(ifNoneMatchMatches(std::string(100000, '"'), etag));
}

TEST_CASE("FILETIME epoch conversion") {
  // 2025-10-23T08:00:00.123Z is 1761206400123 ms after 1970 and
  // 13405680000123 ms after 1601, so 134056800001230000 ticks of 100 ns.
  CHECK(fileTimeToEpochMs(134056800001230000ULL) == 1761206400123);
  CHECK(fileTimeToEpochMs(116444736000000000ULL) == 0);  // the Unix epoch
  CHECK(fileTimeToEpochMs(116444736000009999ULL) == 0);  // sub-millisecond ticks are dropped
  CHECK(fileTimeToEpochMs(116444736000010000ULL) == 1);
}
