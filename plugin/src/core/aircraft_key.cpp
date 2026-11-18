#include "aircraft_key.h"

namespace flightsim_aide {

namespace {

const std::string kLocalisationPrefix = "ATCCOM.AC_MODEL ";
const std::string kLocalisationSuffix = ".text";

bool endsWith(const std::string& s, const std::string& tail) {
  return s.size() >= tail.size() && s.compare(s.size() - tail.size(), tail.size(), tail) == 0;
}

bool isIllegalInFileName(unsigned char c) {
  if (c < 0x20) return true;
  switch (c) {
    case '<':
    case '>':
    case ':':
    case '"':
    case '/':
    case '\\':
    case '|':
    case '?':
    case '*':
      return true;
    default:
      return false;
  }
}

}  // namespace

std::string msfsAircraftKey(const std::string& atcModel) {
  std::string model = atcModel;
  if (model.compare(0, kLocalisationPrefix.size(), kLocalisationPrefix) == 0 && endsWith(model, kLocalisationSuffix)) {
    model = model.substr(kLocalisationPrefix.size(), model.size() - kLocalisationPrefix.size() - kLocalisationSuffix.size());
    // "C152.0" -> "C152": a trailing ".<digits>" is the localisation index.
    const size_t dot = model.rfind('.');
    if (dot != std::string::npos && dot + 1 < model.size()) {
      bool digits = true;
      for (size_t i = dot + 1; i < model.size(); ++i) {
        if (model[i] < '0' || model[i] > '9') digits = false;
      }
      if (digits) model.resize(dot);
    }
  }
  std::string key;
  key.reserve(model.size());
  for (const char ch : model) key.push_back(isIllegalInFileName(static_cast<unsigned char>(ch)) ? '_' : ch);
  while (!key.empty() && (key.back() == '.' || key.back() == ' ')) key.pop_back();
  size_t first = 0;
  while (first < key.size() && key[first] == ' ') ++first;
  key.erase(0, first);
  // "." and ".." are folder names, not file names.
  if (key.find_first_not_of('.') == std::string::npos) return std::string();
  return key;
}

std::vector<std::string> checklistCandidatesIn(const std::string& folder, const std::string& key) {
  std::vector<std::string> out;
  if (folder.empty()) return out;
  const char last = folder.back();
  const std::string prefix = (last == '/' || last == '\\') ? folder : folder + "\\";
  if (!key.empty()) out.push_back(prefix + key + "_clist.txt");
  out.push_back(prefix + "clist.txt");
  return out;
}

}  // namespace flightsim_aide
