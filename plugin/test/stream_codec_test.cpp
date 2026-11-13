#include <cmath>
#include <limits>
#include <random>

#include "doctest.h"
#include "stream_codec.h"

using namespace flightsim_aide;

namespace {
const char* kOnGround = "sim/flightmodel/failures/onground_any";

std::string subscribeText(const std::string& name, const std::string& hz, const std::string& id = "1") {
  return "{\"op\":\"subscribe\",\"id\":" + id + ",\"name\":\"" + name + "\",\"hz\":" + hz + "}";
}
}  // namespace

TEST_CASE("subscribe parses") {
  const ClientFrame f = parseClientFrame(subscribeText(kOnGround, "2"));
  CHECK(f.kind == FrameKind::subscribe);
  CHECK(f.id == 1);
  CHECK(f.name == kOnGround);
  CHECK(f.hz == 2);
  // Field order and whitespace do not matter.
  const ClientFrame g = parseClientFrame(
      " { \"hz\" : 60 , \"name\" : \"a/b\" , \"op\" : \"subscribe\" , \"id\" : 0 } ");
  CHECK(g.kind == FrameKind::subscribe);
  CHECK(g.id == 0);
  CHECK(g.hz == 60);
}

TEST_CASE("unsubscribe and ping parse") {
  const ClientFrame u = parseClientFrame("{\"op\":\"unsubscribe\",\"id\":5}");
  CHECK(u.kind == FrameKind::unsubscribe);
  CHECK(u.id == 5);
  CHECK(parseClientFrame("{\"op\":\"ping\"}").kind == FrameKind::ping);
  CHECK(parseClientFrame("{\"op\":\"unsubscribe\"}").kind == FrameKind::badRequest);
}

TEST_CASE("hz 0 and 61 give bad_request") {
  for (const char* hz : {"0", "61", "-1", "1.5", "\"2\"", "null", "1e0", "100000000000000000000"}) {
    CAPTURE(hz);
    const ClientFrame f = parseClientFrame(subscribeText(kOnGround, hz, "6"));
    CHECK(f.kind == FrameKind::badRequest);
    CHECK(f.id == 6);  // the id was readable, so the error can name it
  }
  CHECK(parseClientFrame(subscribeText(kOnGround, "1")).kind == FrameKind::subscribe);
  CHECK(parseClientFrame(subscribeText(kOnGround, "60")).kind == FrameKind::subscribe);
}

TEST_CASE("bad ids give bad_request") {
  for (const char* id : {"-1", "1.5", "\"1\"", "null", "true", "[1]"}) {
    CAPTURE(id);
    const ClientFrame f = parseClientFrame(subscribeText(kOnGround, "1", id));
    CHECK(f.kind == FrameKind::badRequest);
    CHECK_FALSE(f.id.has_value());
  }
  CHECK(parseClientFrame("{\"op\":\"subscribe\",\"name\":\"a\",\"hz\":1}").kind == FrameKind::badRequest);
}

TEST_CASE("name of 201 characters gives bad_request") {
  CHECK(parseClientFrame(subscribeText(std::string(200, 'a'), "1")).kind == FrameKind::subscribe);
  CHECK(parseClientFrame(subscribeText(std::string(201, 'a'), "1")).kind == FrameKind::badRequest);
  CHECK(parseClientFrame(subscribeText("", "1")).kind == FrameKind::badRequest);
  CHECK(parseClientFrame("{\"op\":\"subscribe\",\"id\":1,\"hz\":1}").kind == FrameKind::badRequest);
  CHECK(parseClientFrame("{\"op\":\"subscribe\",\"id\":1,\"name\":5,\"hz\":1}").kind ==
        FrameKind::badRequest);
}

TEST_CASE("control characters in a name give bad_request") {
  CHECK(parseClientFrame(subscribeText("a\\u0001b", "1")).kind == FrameKind::badRequest);
  CHECK(parseClientFrame(subscribeText("a\\nb", "1")).kind == FrameKind::badRequest);
  CHECK(parseClientFrame(subscribeText("a\\u007fb", "1")).kind == FrameKind::badRequest);
  CHECK(parseClientFrame(subscribeText("a b", "1")).kind == FrameKind::subscribe);
  // An escaped quote is an ordinary character.
  CHECK(parseClientFrame(subscribeText("a\\\"b", "1")).name == "a\"b");
}

TEST_CASE("frame over 4 KB gives bad_request") {
  std::string big = subscribeText(kOnGround, "1");
  big.insert(big.size() - 1, ",\"pad\":\"" + std::string(5000, 'x') + "\"");
  CHECK(big.size() > kMaxFrameBytes);
  CHECK(parseClientFrame(big).kind == FrameKind::badRequest);
  CHECK(parseClientFrame(std::string(5000, 'x')).kind == FrameKind::badRequest);
  std::string ok = subscribeText(kOnGround, "1");
  ok.insert(ok.size() - 1, ",\"pad\":\"" + std::string(3000, 'x') + "\"");
  CHECK(parseClientFrame(ok).kind == FrameKind::subscribe);
}

TEST_CASE("unknown op gives bad_request") {
  const ClientFrame f = parseClientFrame("{\"op\":\"frobnicate\",\"id\":8}");
  CHECK(f.kind == FrameKind::badRequest);
  CHECK(f.id == 8);
  CHECK(parseClientFrame("{\"op\":5}").kind == FrameKind::badRequest);
  CHECK(parseClientFrame("{}").kind == FrameKind::badRequest);
}

TEST_CASE("malformed json gives bad_request without an id") {
  for (const char* t : {"", "not json", "[1,2]", "42", "\"op\"", "{\"op\":\"ping\"} x", "{\"op\":\"ping\"",
                        "{\"op\":\"ping\",}", "{'op':'ping'}", "{\"op\":\"ping\"}{}", "nul", "{\"a\":01}"}) {
    CAPTURE(t);
    const ClientFrame f = parseClientFrame(t);
    CHECK(f.kind == FrameKind::badRequest);
    CHECK_FALSE(f.id.has_value());
    CHECK_FALSE(f.message.empty());
  }
}

TEST_CASE("set gives unsupported") {
  const ClientFrame f = parseClientFrame("{\"op\":\"set\",\"id\":7,\"name\":\"a\",\"value\":0}");
  CHECK(f.kind == FrameKind::set);
  CHECK(f.id == 7);
}

TEST_CASE("deeply nested json is rejected, not crashed on") {
  CHECK(parseClientFrame(std::string(3000, '[')).kind == FrameKind::badRequest);
  std::string nested = "{\"op\":\"ping\",\"x\":";
  for (int i = 0; i < 2000; ++i) nested += "[";
  CHECK(parseClientFrame(nested).kind == FrameKind::badRequest);
}

TEST_CASE("server frames") {
  CHECK(subscribedFrame(1) == "{\"op\":\"subscribed\",\"id\":1}");
  CHECK(errorFrame(2, "unknown_name") == "{\"op\":\"error\",\"id\":2,\"code\":\"unknown_name\"}");
  CHECK(errorFrame(std::nullopt, "bad_request", "Frame is not JSON.") ==
        "{\"op\":\"error\",\"code\":\"bad_request\",\"message\":\"Frame is not JSON.\"}");
  CHECK(heartbeatFrame() == "{\"op\":\"hb\"}");
  CHECK(pongFrame() == "{\"op\":\"pong\"}");
}

TEST_CASE("values frame equals the golden byte for byte") {
  const std::string golden = "{\"op\":\"values\",\"t\":1761206400123,\"v\":{\"1\":1,\"2\":0.5,\"3\":null,\"10\":12}}";
  CHECK(valuesFrame(1761206400123, {{1, 1.0}, {2, 0.5}, {3, std::nan("")}, {10, 12.0}}) == golden);
}

TEST_CASE("integer prints as integer") {
  CHECK(jsonNumber(1.0) == "1");
  CHECK(jsonNumber(0.0) == "0");
  CHECK(jsonNumber(-0.0) == "0");
  CHECK(jsonNumber(-7.0) == "-7");
  CHECK(jsonNumber(2147483647.0) == "2147483647");
  CHECK(jsonNumber(100.5) == "100.5");
  CHECK(jsonNumber(1e15) == "1000000000000000");
}

TEST_CASE("fractions print in the shortest round-trip form") {
  for (const double v : {0.1, 0.5, 1.0 / 3.0, 3.14159265358979, 1e-7, 123456.789, -0.000123, 5e-324,
                         1.7976931348623157e308, 1e20, 0.30000000000000004}) {
    CAPTURE(v);
    const std::string s = jsonNumber(v);
    CHECK(std::strtod(s.c_str(), nullptr) == v);  // not stod: it throws on denormals with glibc
    CHECK(s.find(',') == std::string::npos);
    CHECK(s.find("inf") == std::string::npos);
  }
  CHECK(jsonNumber(0.1) == "0.1");
  CHECK(jsonNumber(1.0 / 3.0) == "0.3333333333333333");
}

TEST_CASE("non-finite prints null") {
  CHECK(jsonNumber(std::nan("")) == "null");
  CHECK(jsonNumber(std::numeric_limits<double>::infinity()) == "null");
  CHECK(jsonNumber(-std::numeric_limits<double>::infinity()) == "null");
}

TEST_CASE("1000 seeded random frames never throw") {
  std::mt19937 rng(12345);
  const std::string seeds[] = {subscribeText(kOnGround, "2"), "{\"op\":\"unsubscribe\",\"id\":1}",
                               "{\"op\":\"ping\"}", "{\"op\":\"set\",\"id\":1,\"name\":\"a\",\"value\":0}"};
  for (int i = 0; i < 1000; ++i) {
    std::string t;
    if (i % 2 == 0) {
      const size_t n = rng() % 200;
      for (size_t k = 0; k < n; ++k) t.push_back(static_cast<char>(rng() % 256));
    } else {
      t = seeds[rng() % 4];
      const int edits = 1 + static_cast<int>(rng() % 5);
      for (int e = 0; e < edits && !t.empty(); ++e) {
        const size_t pos = rng() % t.size();
        switch (rng() % 3) {
          case 0: t[pos] = static_cast<char>(rng() % 256); break;
          case 1: t.erase(pos, 1 + rng() % 3); break;
          default: t.insert(pos, 1, "{}[]\":,\\"[rng() % 8]); break;
        }
      }
    }
    CHECK_NOTHROW(parseClientFrame(t));
  }
}
