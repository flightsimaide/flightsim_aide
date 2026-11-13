#pragma once

#include <optional>
#include <string>

namespace flightsim_aide {

/// A signal name split into the dataref name and an optional array index
/// (plugin/PROTOCOL.md section 9).
struct SignalName {
  std::string base;
  /// -1 when the name has no brackets; otherwise the zero-based element, or
  /// the first element of a range.
  int index = -1;
  /// -1 unless the name is a range `base[a..b]`; then the last element (>=
  /// [index]).
  int last = -1;

  bool isRange() const { return last >= 0; }
};

/// The most elements one range may cover (the subscription cap).
constexpr int kMaxRangeElements = 128;

/// Splits `base`, `base[n]` or the range `base[a..b]`. Each number is 1 to 6
/// decimal digits, `a <= b`, a range covers at most [kMaxRangeElements]
/// elements, and nothing else may follow the `]`. Any other use of `[` or `]` (also in the base) gives
/// no value. A name with no brackets always parses.
std::optional<SignalName> parseSignalName(const std::string& name);

}  // namespace flightsim_aide
