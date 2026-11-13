#include "signal_name.h"

namespace flightsim_aide {

std::optional<SignalName> parseSignalName(const std::string& name) {
  const size_t open = name.find('[');
  const size_t close = name.find(']');
  if (open == std::string::npos && close == std::string::npos) return SignalName{name, -1};
  // Exactly one pair, the `]` last, a non-empty base before the `[`.
  if (open == std::string::npos || close == std::string::npos || open == 0 || close != name.size() - 1 ||
      close < open || name.find('[', open + 1) != std::string::npos) {
    return std::nullopt;
  }
  const std::string inside = name.substr(open + 1, close - open - 1);
  const size_t dots = inside.find("..");
  const auto number = [](const std::string& text) -> int {
    if (text.size() < 1 || text.size() > 6) return -1;
    int value = 0;
    for (const char ch : text) {
      if (ch < '0' || ch > '9') return -1;
      value = value * 10 + (ch - '0');
    }
    return value;
  };
  if (dots == std::string::npos) {
    const int index = number(inside);
    if (index < 0) return std::nullopt;
    return SignalName{name.substr(0, open), index, -1};
  }
  const int first = number(inside.substr(0, dots));
  const int last = number(inside.substr(dots + 2));
  if (first < 0 || last < first || last - first + 1 > kMaxRangeElements) return std::nullopt;
  return SignalName{name.substr(0, open), first, last};
}

}  // namespace flightsim_aide
