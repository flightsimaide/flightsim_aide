#pragma once

#include "cache.h"
#include "http_types.h"

namespace flightsim_aide {

/// `GET /v1/hello` and `HEAD /v1/hello` (plugin/PROTOCOL.md section 2).
Response handleHello(const Request& request, const ServerInfo& info);

/// `GET /v1/aircraft` and `HEAD`.
Response handleAircraft(const Request& request, const CacheData& cache);

/// `GET /v1/checklist` and `HEAD`: 200, 304, 404 or 413.
Response handleChecklist(const Request& request, const CacheData& cache);

/// Files larger than this are refused with 413 (2 MB).
constexpr int64_t kMaxChecklistBytes = 2097152;

/// An HTTP date such as "Thu, 23 Oct 2025 08:00:00 GMT" from epoch ms.
std::string httpDate(int64_t epochMs);

}  // namespace flightsim_aide
