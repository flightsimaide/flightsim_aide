#include "etag.h"

#include <cctype>

namespace flightsim_aide {

std::string makeEtag(int64_t mtimeMs, int64_t size) {
  return "\"" + std::to_string(mtimeMs) + "-" + std::to_string(size) + "\"";
}

namespace {

std::string trim(const std::string& s, size_t from, size_t to) {
  while (from < to && std::isspace(static_cast<unsigned char>(s[from]))) ++from;
  while (to > from && std::isspace(static_cast<unsigned char>(s[to - 1]))) --to;
  return s.substr(from, to - from);
}

}  // namespace

bool ifNoneMatchMatches(const std::string& header, const std::string& etag) {
  size_t start = 0;
  while (start <= header.size()) {
    size_t comma = header.find(',', start);
    if (comma == std::string::npos) comma = header.size();
    std::string token = trim(header, start, comma);
    start = comma + 1;
    if (token == "*") return true;
    if (token.size() >= 2 && token[0] == 'W' && token[1] == '/') token.erase(0, 2);
    if (token == etag) return true;
  }
  return false;
}

int64_t fileTimeToEpochMs(uint64_t fileTimeTicks) {
  constexpr int64_t kTicksPerMs = 10000;
  constexpr int64_t kEpochDiffMs = 11644473600000LL;  // 1601-01-01 to 1970-01-01
  return static_cast<int64_t>(fileTimeTicks / kTicksPerMs) - kEpochDiffMs;
}

}  // namespace flightsim_aide
