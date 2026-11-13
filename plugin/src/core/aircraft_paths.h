#pragma once

#include <string>
#include <vector>

namespace flightsim_aide {

/// The folder part of the path of an aircraft's `.acf` file, as X-Plane gives
/// it (UTF-8; `\` or `/` separators, also mixed). No trailing separator except
/// for a root folder. Empty when the path has no folder part.
std::string aircraftFolder(const std::string& acfPath);

/// The checklist files to look for, best first, using the XChecklist names:
/// `<folder>/<acf name>_clist.txt`, then `<folder>/clist.txt`. Pure string
/// work: the caller checks which one exists. The separator of the input is
/// reused. Empty when [acfPath] has no folder part.
std::vector<std::string> checklistCandidates(const std::string& acfPath);

}  // namespace flightsim_aide
