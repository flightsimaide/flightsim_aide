#pragma once

#include <string>
#include <vector>

namespace flightsim_aide {

/// The aircraft key of Microsoft Flight Simulator, from the `ATC MODEL` value
/// the sim reports, used as the checklist file name (`<key>_clist.txt`).
///
/// A third-party aircraft reports a plain name (`PC12`). A default aircraft
/// reports a localisation key, `ATCCOM.AC_MODEL C152.0.text`, whose model is
/// the part in the middle (`C152`). The result is safe as a file name: any
/// character a Windows file name cannot hold becomes `_`, and trailing dots and
/// blanks are dropped. Empty when nothing usable is left.
std::string msfsAircraftKey(const std::string& atcModel);

/// The checklist files to look for in [folder], best first:
/// `<key>_clist.txt`, then `clist.txt` (the XChecklist names, as for
/// X-Plane). Pure string work: the caller checks which one exists. [folder]
/// gets a separator appended unless it ends with one; an empty [key] leaves
/// only `clist.txt`. Empty when [folder] is empty.
std::vector<std::string> checklistCandidatesIn(const std::string& folder, const std::string& key);

}  // namespace flightsim_aide
