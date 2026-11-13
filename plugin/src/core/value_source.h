#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace flightsim_aide {

/// The outcome of looking a signal name up.
struct Resolution {
  enum class Status {
    ok,
    /// The sim has no such name (`unknown_name`).
    unknown,
    /// The sim has it but not as one readable number (`unsupported`).
    unsupported,
  };
  Status status = Status::unknown;
  /// Opaque to the core; valid when [status] is ok.
  uint64_t handle = 0;
};

/// What the shell implements over the simulator (the X-Plane SDK in the plugin, a script
/// in tests). The core calls it **only from [StreamHub::tick]**, which the
/// shell runs on the sim thread, because simulator APIs are not thread safe.
class ValueSource {
 public:
  virtual ~ValueSource() = default;

  /// Looks a name up: the dataref name [base] and, for an array element, its
  /// zero-based [index] (-1 for the name alone). Deterministic: the same name
  /// always gives the same answer. A name that is not an array with an index
  /// is `unknown`; an array with no index is `unsupported`. An index past the
  /// end of the array is `ok` and reads NaN (it goes out as `null`).
  virtual Resolution resolve(const std::string& base, int index) = 0;

  /// Looks up the range `base[first..last]` of an array dataref. Same rules as
  /// [resolve]; a range that reaches past the end of the array is `ok` and is
  /// cut short when read. The default knows no arrays.
  virtual Resolution resolveRange(const std::string& base, int first, int last) {
    (void)base;
    (void)first;
    (void)last;
    return Resolution();
  }

  /// Fills [out] with the elements of a resolved range that exist now: fewer
  /// than asked when the array ends inside the range, none when it ends
  /// before it. Non-finite values are allowed and go out as `null`.
  virtual void readRange(uint64_t handle, std::vector<double>& out) {
    (void)handle;
    out.clear();
  }

  /// The current value of a resolved name. Non-finite values are allowed and
  /// go out as `null`.
  virtual double read(uint64_t handle) = 0;
};

/// The reserved signal that carries the aircraft generation. The hub serves it
/// itself, so a ValueSource never sees it.
constexpr const char* kGenerationSignal = "flightsim_aide/aircraft_generation";

}  // namespace flightsim_aide
