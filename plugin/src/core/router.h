#pragma once

#include "cache.h"
#include "handlers.h"

namespace flightsim_aide {

/// Dispatches a plain HTTP request to the handlers (plugin/PROTOCOL.md
/// section 3). Exactly four paths exist: `/v1/hello`, `/v1/aircraft`,
/// `/v1/checklist` and the WebSocket `/v1/stream`. WebSocket upgrades on the
/// stream path never come here (the server hands them to the stream hub), so
/// a request for it that does arrive is a plain one and gets 400.
///
/// The path is compared as is: it is never decoded or normalised, and nothing
/// in the request selects a file. The only input beyond the request is the
/// cache snapshot.
Response route(const Request& request, const CacheData& cache, const ServerInfo& info);

}  // namespace flightsim_aide
