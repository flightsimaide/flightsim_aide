#include "address_filter.h"

#include <cstddef>

namespace flightsim_aide {

namespace {

struct Range {
  uint32_t base;
  int bits;
};

constexpr uint32_t ip(uint32_t a, uint32_t b, uint32_t c, uint32_t d) {
  return (a << 24) | (b << 16) | (c << 8) | d;
}

// The one table both the function and the ACL string are built from.
constexpr Range kRanges[] = {
    {ip(10, 0, 0, 0), 8},
    {ip(172, 16, 0, 0), 12},
    {ip(192, 168, 0, 0), 16},
    {ip(169, 254, 0, 0), 16},
    {ip(127, 0, 0, 0), 8},
};

uint32_t maskOf(int bits) { return bits == 0 ? 0u : 0xFFFFFFFFu << (32 - bits); }

}  // namespace

std::optional<uint32_t> parseIpv4(const std::string& text) {
  uint32_t result = 0;
  size_t i = 0;
  for (int octet = 0; octet < 4; ++octet) {
    if (i >= text.size()) return std::nullopt;
    const size_t start = i;
    uint32_t value = 0;
    while (i < text.size() && text[i] >= '0' && text[i] <= '9') {
      value = value * 10 + static_cast<uint32_t>(text[i] - '0');
      if (value > 255) return std::nullopt;
      ++i;
    }
    const size_t digits = i - start;
    if (digits == 0 || (digits > 1 && text[start] == '0')) return std::nullopt;
    result = (result << 8) | value;
    if (octet < 3) {
      if (i >= text.size() || text[i] != '.') return std::nullopt;
      ++i;
    }
  }
  if (i != text.size()) return std::nullopt;
  return result;
}

bool isAllowed(uint32_t ipv4) {
  for (const Range& r : kRanges) {
    if ((ipv4 & maskOf(r.bits)) == r.base) return true;
  }
  return false;
}

bool isAllowed(const std::string& ipv4) {
  const std::optional<uint32_t> parsed = parseIpv4(ipv4);
  return parsed.has_value() && isAllowed(*parsed);
}

std::string accessControlList() {
  std::string acl = "-0.0.0.0/0";
  for (const Range& r : kRanges) {
    acl += ",+" + std::to_string(r.base >> 24) + "." + std::to_string((r.base >> 16) & 255) + "." +
           std::to_string((r.base >> 8) & 255) + "." + std::to_string(r.base & 255) + "/" +
           std::to_string(r.bits);
  }
  return acl;
}

}  // namespace flightsim_aide
