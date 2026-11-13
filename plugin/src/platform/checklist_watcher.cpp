#include "checklist_watcher.h"

#include "file_info.h"

namespace flightsim_aide {

bool ChecklistWatcher::poll() { return check(false); }

bool ChecklistWatcher::refresh() { return check(true); }

bool ChecklistWatcher::check(bool force) {
  const int64_t now = clock_();
  if (!force && started_ && now - lastCheckMs_ < kIntervalMs) return false;
  started_ = true;
  lastCheckMs_ = now;

  CacheData data = cache_.snapshot();
  if (data.checklistPath.empty()) return false;

  const std::optional<FileStat> st = statFile(data.checklistPath);
  if (!st) {
    if (!data.hasChecklist && data.checklistText.empty()) return false;
    data.hasChecklist = false;
    data.checklistModified = 0;
    data.checklistSize = 0;
    data.checklistText.clear();
    cache_.update(data);
    return true;
  }
  if (!force && data.hasChecklist && st->modifiedMs == data.checklistModified && st->size == data.checklistSize) {
    return false;
  }

  const FileRead read = readWholeFile(data.checklistPath);
  if (read.status == ReadStatus::missing || read.status == ReadStatus::error) return false;  // retry at the next poll
  data.hasChecklist = true;
  data.checklistModified = read.modifiedMs;
  data.checklistSize = read.size;
  data.checklistText = std::move(read.bytes);
  cache_.update(data);
  return true;
}

}  // namespace flightsim_aide
