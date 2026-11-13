#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

#include "address_filter.h"
#include "doctest.h"

using namespace flightsim_aide;

namespace {

// Evaluates a CivetWeb access_control_list string the way CivetWeb does: the
// entries are checked in order and the last one that matches decides.
bool aclAllows(const std::string& acl, uint32_t ip) {
  bool allowed = true;
  std::stringstream ss(acl);
  std::string entry;
  while (std::getline(ss, entry, ',')) {
    const bool plus = entry[0] == '+';
    const std::string rest = entry.substr(1);
    const size_t slash = rest.find('/');
    const uint32_t base = parseIpv4(rest.substr(0, slash)).value();
    const int bits = std::stoi(rest.substr(slash + 1));
    const uint32_t mask = bits == 0 ? 0 : 0xFFFFFFFFu << (32 - bits);
    if ((ip & mask) == (base & mask)) allowed = plus;
  }
  return allowed;
}

uint32_t ip(int a, int b, int c, int d) {
  return (static_cast<uint32_t>(a) << 24) | (static_cast<uint32_t>(b) << 16) |
         (static_cast<uint32_t>(c) << 8) | static_cast<uint32_t>(d);
}

}  // namespace

TEST_CASE("allows each private range edge") {
  for (const char* a : {"10.0.0.0", "10.255.255.255", "172.16.0.0", "172.31.255.255", "192.168.0.0",
                        "192.168.255.255", "169.254.0.0", "169.254.255.255", "127.0.0.0",
                        "127.255.255.255", "127.0.0.1", "192.168.1.10"}) {
    CAPTURE(a);
    CHECK(isAllowed(a));
  }
}

TEST_CASE("refuses 172.15.255.255 and 172.32.0.0") {
  CHECK_FALSE(isAllowed("172.15.255.255"));
  CHECK_FALSE(isAllowed("172.32.0.0"));
  CHECK_FALSE(isAllowed("9.255.255.255"));
  CHECK_FALSE(isAllowed("11.0.0.0"));
  CHECK_FALSE(isAllowed("192.167.255.255"));
  CHECK_FALSE(isAllowed("192.169.0.0"));
  CHECK_FALSE(isAllowed("169.253.255.255"));
  CHECK_FALSE(isAllowed("169.255.0.0"));
  CHECK_FALSE(isAllowed("126.255.255.255"));
  CHECK_FALSE(isAllowed("128.0.0.0"));
}

TEST_CASE("refuses public addresses") {
  for (const char* a : {"8.8.8.8", "1.1.1.1", "93.184.216.34", "100.64.0.1", "203.0.113.5"}) {
    CAPTURE(a);
    CHECK_FALSE(isAllowed(a));
  }
}

TEST_CASE("refuses 0.0.0.0 and broadcast") {
  CHECK_FALSE(isAllowed("0.0.0.0"));
  CHECK_FALSE(isAllowed("255.255.255.255"));
}

TEST_CASE("acl string and function agree for 200 sampled addresses") {
  const std::string acl = accessControlList();
  uint32_t x = 12345;
  std::vector<uint32_t> samples = {ip(10, 0, 0, 0),      ip(172, 15, 255, 255), ip(172, 16, 0, 0),
                                   ip(172, 31, 255, 255), ip(172, 32, 0, 0),     ip(192, 168, 1, 1),
                                   ip(169, 254, 1, 1),   ip(127, 0, 0, 1),      ip(0, 0, 0, 0),
                                   ip(255, 255, 255, 255)};
  while (samples.size() < 200) {
    x = x * 1664525u + 1013904223u;
    // Half the samples are random, half are steered into the private ranges.
    samples.push_back(samples.size() % 2 ? x : (x & 0x00FFFFFFu) | ((x >> 24) % 2 ? ip(10, 0, 0, 0) : ip(172, 16, 0, 0)));
  }
  for (const uint32_t s : samples) {
    CAPTURE(s);
    CHECK(aclAllows(acl, s) == isAllowed(s));
  }
}

TEST_CASE("garbage input is refused") {
  for (const char* a : {"", "garbage", "10.0.0", "10.0.0.0.1", "10.0.0.256", "10.0.0.-1", "10..0.1", "10.0.0.1 ",
                        " 10.0.0.1", "10.0.0.1/8", "010.0.0.1", "::1", "10.0.0.a", "+10.0.0.1",
                        "192.168.0.1\n", "1e1.0.0.1"}) {
    CAPTURE(a);
    CHECK_FALSE(isAllowed(a));
    CHECK_FALSE(parseIpv4(a).has_value());
  }
}
