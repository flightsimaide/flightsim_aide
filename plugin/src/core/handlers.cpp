#include "handlers.h"

#include <cstdio>

#include "etag.h"
#include "json_writer.h"
#include "version.h"

namespace flightsim_aide {

namespace {

constexpr const char* kJsonType = "application/json; charset=utf-8";

bool isHead(const Request& request) { return request.method == "HEAD"; }

// A JSON response; HEAD keeps the headers (with the GET Content-Length) and
// drops the body.
Response jsonResponse(const Request& request, int status, const std::string& body) {
  Response r;
  r.status = status;
  r.headers = {{"Content-Type", kJsonType},
               {"Cache-Control", "no-store"},
               {"Content-Length", std::to_string(body.size())}};
  if (!isHead(request)) r.body = body;
  return r;
}

}  // namespace

Response handleHello(const Request& request, const ServerInfo& info) {
  HelloInfo h;
  h.simKind = "xplane";
  h.simVersion = info.simVersion;
  h.os = info.os;
  h.pluginVersion = info.pluginVersion;
  h.runId = info.runId;
  h.port = info.port;
  return jsonResponse(request, 200, helloJson(h));
}

Response handleAircraft(const Request& request, const CacheData& cache) {
  AircraftInfo a;
  a.generation = cache.generation;
  a.icao = cache.icao;
  a.description = cache.description;
  a.aircraftPath = cache.aircraftPath;
  a.hasChecklist = cache.hasChecklist;
  a.checklistPath = cache.checklistPath;
  a.checklistModified = cache.checklistModified;
  a.checklistSize = cache.checklistSize;
  return jsonResponse(request, 200, aircraftJson(a));
}

Response handleChecklist(const Request& request, const CacheData& cache) {
  if (!cache.hasChecklist) {
    return jsonResponse(request, 404,
                        errorJson("no_checklist", "The loaded aircraft has no checklist file."));
  }
  if (cache.checklistSize > kMaxChecklistBytes) {
    return jsonResponse(request, 413,
                        errorJson("too_large", "The checklist file is larger than 2 MB."));
  }
  const std::string etag = makeEtag(cache.checklistModified, cache.checklistSize);
  Response r;
  if (ifNoneMatchMatches(request.header("If-None-Match"), etag)) {
    r.status = 304;
    r.headers = {{"ETag", etag}, {"Cache-Control", "no-store"}};
    return r;
  }
  r.status = 200;
  r.headers = {{"Content-Type", "text/plain"},
               {"ETag", etag},
               {"Last-Modified", httpDate(cache.checklistModified)},
               {"X-Aircraft-Generation", std::to_string(cache.generation)},
               {"Cache-Control", "no-store"},
               {"Content-Length", std::to_string(cache.checklistText.size())}};
  if (!isHead(request)) r.body = cache.checklistText;
  return r;
}

std::string httpDate(int64_t epochMs) {
  static const char* days[] = {"Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"};
  static const char* months[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
  int64_t secs = epochMs / 1000;
  if (epochMs % 1000 < 0) --secs;
  int64_t days_since = secs / 86400;
  int64_t rem = secs % 86400;
  if (rem < 0) {
    rem += 86400;
    --days_since;
  }
  // Civil-from-days (Howard Hinnant's algorithm).
  const int64_t z = days_since + 719468;
  const int64_t era = (z >= 0 ? z : z - 146096) / 146097;
  const int64_t doe = z - era * 146097;
  const int64_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  const int64_t y = yoe + era * 400;
  const int64_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const int64_t mp = (5 * doy + 2) / 153;
  const int64_t d = doy - (153 * mp + 2) / 5 + 1;
  const int64_t m = mp < 10 ? mp + 3 : mp - 9;
  const int64_t year = y + (m <= 2 ? 1 : 0);
  const int weekday = static_cast<int>(((days_since % 7) + 7) % 7);

  char buf[40];
  std::snprintf(buf, sizeof buf, "%s, %02d %s %04d %02d:%02d:%02d GMT", days[weekday],
                static_cast<int>(d), months[m - 1], static_cast<int>(year),
                static_cast<int>(rem / 3600), static_cast<int>(rem % 3600 / 60),
                static_cast<int>(rem % 60));
  return buf;
}

}  // namespace flightsim_aide
