#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace flightsim_aide {

/// A parsed JSON value. Just enough for the stream's client frames and the
/// test server's fixture files.
struct JsonValue {
  enum class Kind { null, boolean, number, string, array, object };
  Kind kind = Kind::null;
  bool boolean = false;
  // number
  double number = 0;
  bool isInteger = false;  // no fraction or exponent, and it fits in int64
  int64_t integer = 0;
  // string
  std::string text;
  // array and object members (an array has empty keys)
  std::vector<std::pair<std::string, JsonValue>> members;

  /// The last member with this key (duplicates: the last wins), or null.
  const JsonValue* find(const std::string& key) const;
};

/// Parses strict JSON (nesting at most 32 deep). Never throws: false and a
/// short [error] on any failure, including trailing text.
bool parseJson(const std::string& text, JsonValue& out, std::string& error);

}  // namespace flightsim_aide
