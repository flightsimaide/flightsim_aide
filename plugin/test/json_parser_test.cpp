#include "doctest.h"
#include "json_parser.h"

using namespace flightsim_aide;

TEST_CASE("json parser reads objects, arrays, numbers and booleans") {
  JsonValue v;
  std::string error;
  REQUIRE(parseJson("{\"a\":[1,2.5,-3e2],\"b\":true,\"c\":false,\"d\":null,\"e\":\"x\"}", v, error));
  const JsonValue* a = v.find("a");
  REQUIRE(a != nullptr);
  REQUIRE(a->members.size() == 3);
  CHECK(a->members[0].second.isInteger);
  CHECK(a->members[0].second.integer == 1);
  CHECK(a->members[1].second.number == 2.5);
  CHECK_FALSE(a->members[1].second.isInteger);
  CHECK(a->members[2].second.number == -300.0);
  CHECK(v.find("b")->boolean);
  CHECK_FALSE(v.find("c")->boolean);
  CHECK(v.find("d")->kind == JsonValue::Kind::null);
  CHECK(v.find("e")->text == "x");
  CHECK(v.find("missing") == nullptr);
}

TEST_CASE("json parser rejects trailing text and the last duplicate key wins") {
  JsonValue v;
  std::string error;
  CHECK_FALSE(parseJson("{} x", v, error));
  CHECK_FALSE(error.empty());
  JsonValue w;
  REQUIRE(parseJson("{\"k\":1,\"k\":2}", w, error));
  CHECK(w.find("k")->integer == 2);
}
