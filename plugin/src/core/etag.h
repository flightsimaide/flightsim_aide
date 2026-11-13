#pragma once

#include <cstdint>
#include <string>

namespace flightsim_aide {

/// The checklist ETag: `"<mtime>-<size>"` with the quotes, mtime in epoch
/// milliseconds UTC (plugin/PROTOCOL.md section 5).
std::string makeEtag(int64_t mtimeMs, int64_t size);

/// True when an `If-None-Match` header value matches [etag]. The value may be
/// a comma-separated list, hold weak `W/"..."` entries or be `*`; matching is
/// exact equality of the quoted value. Anything else never matches.
bool ifNoneMatchMatches(const std::string& header, const std::string& etag);

/// Converts a Windows FILETIME (100 ns ticks since 1601-01-01 UTC) to epoch
/// milliseconds. Sub-millisecond ticks are dropped. The read of the file time
/// itself is platform code in the shell.
int64_t fileTimeToEpochMs(uint64_t fileTimeTicks);

}  // namespace flightsim_aide
