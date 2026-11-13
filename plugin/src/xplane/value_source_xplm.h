#pragma once

#include <string>
#include <vector>

#include "value_source.h"

namespace flightsim_aide {

/// The core's ValueSource over X-Plane datarefs. Called only from the flight
/// loop (through the hub's tick), never from a server thread.
///
/// Reads int, float and double datarefs, and one element of an int-array or a
/// float-array dataref (`name[index]`). A whole array and byte (string)
/// datarefs are `unsupported`; a range `name[a..b]` reads those elements in one
/// call and is cut short where the array ends; an index past the end reads NaN (`null` on the
/// wire), because an array's size can change with the aircraft.
class ValueSourceXplm : public ValueSource {
 public:
  Resolution resolve(const std::string& base, int index) override;
  Resolution resolveRange(const std::string& base, int first, int last) override;
  void readRange(uint64_t handle, std::vector<double>& out) override;
  double read(uint64_t handle) override;

 private:
  struct Entry {
    void* ref;
    int type;   // exactly one of xplmType_Int / Float / Double / IntArray / FloatArray
    int index;  // the element, for the array types (the first one of a range)
    int count = 1;  // the number of elements asked for by a range
  };
  std::vector<Entry> entries_;
};

}  // namespace flightsim_aide
