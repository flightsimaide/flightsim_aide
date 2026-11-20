#include "msfs_names.h"

#include <cctype>

namespace flightsim_aide {

namespace {

std::string trim(const std::string& s) {
  size_t a = 0;
  size_t b = s.size();
  while (a < b && (s[a] == ' ' || s[a] == '\t')) ++a;
  while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\t')) --b;
  return s.substr(a, b - a);
}

std::string lower(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

bool hasControl(const std::string& s) {
  for (const char c : s) {
    if (static_cast<unsigned char>(c) < 0x20) return true;
  }
  return false;
}

// "NAME" or "NAME:digits": at most one colon, and what follows it is a number.
bool validSimVarDatum(const std::string& datum) {
  const size_t colon = datum.find(':');
  if (colon == std::string::npos) return !datum.empty();
  if (colon == 0 || datum.find(':', colon + 1) != std::string::npos) return false;
  const std::string index = datum.substr(colon + 1);
  if (index.empty() || index.size() > 3) return false;
  for (const char c : index) {
    if (c < '0' || c > '9') return false;
  }
  return true;
}

}  // namespace

std::string MsfsVar::key() const {
  const char* prefix = kind == Kind::simVar ? "a:" : kind == Kind::inputEvent ? "b:" : "";
  // An L- or Z-variable's datum already starts with its own prefix.
  return std::string(prefix) + lower(datum) + "," + lower(unit);
}

std::optional<MsfsVar> parseMsfsName(const std::string& name) {
  if (name.size() < 3 || name[1] != ':' || hasControl(name)) return std::nullopt;
  const char tag = static_cast<char>(std::tolower(static_cast<unsigned char>(name[0])));
  if (tag != 'a' && tag != 'l' && tag != 'b' && tag != 'z') return std::nullopt;
  const std::string rest = name.substr(2);

  std::string head = rest;
  std::string unit;
  bool hasUnit = false;
  const size_t comma = rest.find(',');
  if (comma != std::string::npos) {
    if (rest.find(',', comma + 1) != std::string::npos) return std::nullopt;
    head = rest.substr(0, comma);
    unit = trim(rest.substr(comma + 1));
    hasUnit = true;
    if (unit.empty()) return std::nullopt;
  }
  head = trim(head);
  if (head.empty()) return std::nullopt;

  MsfsVar v;
  if (tag == 'b') {
    if (hasUnit || head.find(':') != std::string::npos) return std::nullopt;
    v.kind = MsfsVar::Kind::inputEvent;
    v.datum = head;
    return v;
  }
  if (tag == 'l' || tag == 'z') {
    if (head.find(':') != std::string::npos) return std::nullopt;
    v.kind = tag == 'l' ? MsfsVar::Kind::localVar : MsfsVar::Kind::zVar;
    v.datum = std::string(tag == 'l' ? "L:" : "Z:") + head;
    v.unit = hasUnit ? unit : "number";
    return v;
  }
  if (!validSimVarDatum(head)) return std::nullopt;
  v.kind = MsfsVar::Kind::simVar;
  v.datum = head;
  v.unit = hasUnit ? unit : "number";
  return v;
}

}  // namespace flightsim_aide
