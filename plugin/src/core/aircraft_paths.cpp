#include "aircraft_paths.h"

namespace flightsim_aide {

namespace {

bool isSeparator(char c) { return c == '/' || c == '\\'; }

// Position of the last separator, or npos.
size_t lastSeparator(const std::string& path) {
  for (size_t i = path.size(); i > 0; --i) {
    if (isSeparator(path[i - 1])) return i - 1;
  }
  return std::string::npos;
}

// A folder with its trailing separators removed, but a root ("/", "C:\") kept.
std::string trimmed(const std::string& folder) {
  std::string out = folder;
  while (out.size() > 1 && isSeparator(out.back())) {
    if (out.size() == 3 && out[1] == ':') break;  // "C:\"
    out.pop_back();
  }
  return out;
}

}  // namespace

std::string aircraftFolder(const std::string& acfPath) {
  const size_t cut = lastSeparator(acfPath);
  if (cut == std::string::npos) return std::string();
  // "/plane.acf" -> "/", "C:\plane.acf" -> "C:\"
  const std::string head = acfPath.substr(0, cut + 1);
  return trimmed(head);
}

std::vector<std::string> checklistCandidates(const std::string& acfPath) {
  std::vector<std::string> out;
  const size_t cut = lastSeparator(acfPath);
  if (cut == std::string::npos) return out;
  const std::string folder = aircraftFolder(acfPath);
  const char separator = acfPath[cut];
  const std::string prefix = isSeparator(folder.back()) ? folder : folder + separator;

  std::string name = acfPath.substr(cut + 1);
  const size_t dot = name.rfind('.');
  if (dot != std::string::npos && dot > 0) name.resize(dot);
  if (!name.empty()) out.push_back(prefix + name + "_clist.txt");
  out.push_back(prefix + "clist.txt");
  return out;
}

}  // namespace flightsim_aide
