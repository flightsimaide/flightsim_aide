#pragma once

#include <cstdint>
#include <optional>
#include <string>

#include "handlers.h"  // kMaxChecklistBytes

namespace flightsim_aide {

struct FileStat {
  int64_t modifiedMs = 0;  // epoch milliseconds UTC
  int64_t size = 0;
};

enum class ReadStatus { ok, missing, tooLarge, error };

struct FileRead {
  ReadStatus status = ReadStatus::missing;
  int64_t modifiedMs = 0;
  int64_t size = 0;
  std::string bytes;  // empty unless status is ok
};

/// Size and modification time of a file ([path] is UTF-8), or none when it does
/// not exist. The time has millisecond resolution on every platform.
std::optional<FileStat> statFile(const std::string& path);

/// Reads the whole file byte for byte. A file above [maxBytes] is not read:
/// the status is tooLarge and [size] says how big it is.
FileRead readWholeFile(const std::string& path, int64_t maxBytes = kMaxChecklistBytes);

}  // namespace flightsim_aide
