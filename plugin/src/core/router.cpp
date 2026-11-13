#include "router.h"

#include "json_writer.h"

namespace flightsim_aide {

namespace {

Response errorResponse(int status, const std::string& code, const std::string& message) {
  Response r;
  r.status = status;
  const std::string body = errorJson(code, message);
  r.headers = {{"Content-Type", "application/json; charset=utf-8"},
               {"Cache-Control", "no-store"},
               {"Content-Length", std::to_string(body.size())}};
  r.body = body;
  return r;
}

}  // namespace

Response route(const Request& request, const CacheData& cache, const ServerInfo& info) {
  // The query string is ignored; the rest of the path is compared verbatim.
  const std::string path = request.path.substr(0, request.path.find('?'));

  enum class Target { hello, aircraft, checklist, stream, none };
  Target target = Target::none;
  if (path == "/v1/hello") {
    target = Target::hello;
  } else if (path == "/v1/aircraft") {
    target = Target::aircraft;
  } else if (path == "/v1/checklist") {
    target = Target::checklist;
  } else if (path == "/v1/stream") {
    target = Target::stream;
  }

  if (target == Target::none) {
    return errorResponse(404, "not_found", "No such path.");
  }
  if (request.method != "GET" && request.method != "HEAD") {
    Response r = errorResponse(405, "method_not_allowed", "Only GET and HEAD are allowed.");
    r.headers.push_back({"Allow", "GET, HEAD"});
    return r;
  }
  switch (target) {
    case Target::hello:
      return handleHello(request, info);
    case Target::aircraft:
      return handleAircraft(request, cache);
    case Target::checklist:
      return handleChecklist(request, cache);
    case Target::stream:
      return errorResponse(400, "upgrade_required", "This path needs a WebSocket upgrade.");
    case Target::none:
      break;
  }
  return errorResponse(404, "not_found", "No such path.");
}

}  // namespace flightsim_aide
