#include <cctype>

#include "doctest.h"
#include "version.h"

using namespace flightsim_aide;

TEST_CASE("run id: 16 lowercase hex characters") {
  const std::string id = makeRunId();
  CHECK(id.size() == 16);
  for (const char c : id) CHECK((std::isdigit(static_cast<unsigned char>(c)) || (c >= 'a' && c <= 'f')));
}

TEST_CASE("run id: two runs get different ids") {
  CHECK(makeRunId() != makeRunId());
}
