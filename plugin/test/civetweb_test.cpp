#include <string>
#include "civetweb.h"
#include "doctest.h"

TEST_CASE("civetweb is linked with websocket support") {
  CHECK(std::string(mg_version()) == "1.16");
  CHECK((mg_check_feature(MG_FEATURES_WEBSOCKET) & MG_FEATURES_WEBSOCKET) != 0);
  CHECK((mg_check_feature(MG_FEATURES_TLS) & MG_FEATURES_TLS) == 0);
  CHECK((mg_check_feature(MG_FEATURES_CGI) & MG_FEATURES_CGI) == 0);
  CHECK((mg_check_feature(MG_FEATURES_FILES) & MG_FEATURES_FILES) == 0);
}
