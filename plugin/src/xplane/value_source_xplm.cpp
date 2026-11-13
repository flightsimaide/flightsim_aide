#include "value_source_xplm.h"

#include <limits>

#include "XPLMDataAccess.h"

namespace flightsim_aide {

Resolution ValueSourceXplm::resolve(const std::string& base, int index) {
  Resolution r;
  const XPLMDataRef ref = XPLMFindDataRef(base.c_str());
  if (ref == nullptr) return r;  // unknown
  const XPLMDataTypeID types = XPLMGetDataRefTypes(ref);
  int type = 0;
  if (index >= 0) {
    // name[i] names one element of an array.
    if ((types & xplmType_FloatArray) != 0) {
      type = xplmType_FloatArray;
    } else if ((types & xplmType_IntArray) != 0) {
      type = xplmType_IntArray;
    } else {
      return r;  // not an array: unknown
    }
  } else if ((types & xplmType_Double) != 0) {
    // A dataref that offers both a scalar and an array type is read as the scalar.
    type = xplmType_Double;
  } else if ((types & xplmType_Float) != 0) {
    type = xplmType_Float;
  } else if ((types & xplmType_Int) != 0) {
    type = xplmType_Int;
  }
  if (type == 0) {
    r.status = Resolution::Status::unsupported;  // a whole array or bytes
    return r;
  }
  entries_.push_back({ref, type, index, 1});
  r.status = Resolution::Status::ok;
  r.handle = entries_.size() - 1;
  return r;
}

Resolution ValueSourceXplm::resolveRange(const std::string& base, int first, int last) {
  Resolution r;
  const XPLMDataRef ref = XPLMFindDataRef(base.c_str());
  if (ref == nullptr) return r;  // unknown
  const XPLMDataTypeID types = XPLMGetDataRefTypes(ref);
  int type = 0;
  if ((types & xplmType_FloatArray) != 0) {
    type = xplmType_FloatArray;
  } else if ((types & xplmType_IntArray) != 0) {
    type = xplmType_IntArray;
  } else {
    return r;  // not an array: unknown
  }
  entries_.push_back({ref, type, first, last - first + 1});
  r.status = Resolution::Status::ok;
  r.handle = entries_.size() - 1;
  return r;
}

void ValueSourceXplm::readRange(uint64_t handle, std::vector<double>& out) {
  out.clear();
  if (handle >= entries_.size()) return;
  const Entry& e = entries_[static_cast<size_t>(handle)];
  const XPLMDataRef ref = static_cast<XPLMDataRef>(e.ref);
  const size_t count = static_cast<size_t>(e.count);
  // The SDK copies the elements that exist (none when the range starts past
  // the end) and returns how many it copied.
  if (e.type == xplmType_FloatArray) {
    std::vector<float> buffer(count);
    const int n = XPLMGetDatavf(ref, buffer.data(), e.index, e.count);
    for (int i = 0; i < n && static_cast<size_t>(i) < count; ++i) out.push_back(static_cast<double>(buffer[i]));
  } else if (e.type == xplmType_IntArray) {
    std::vector<int> buffer(count);
    const int n = XPLMGetDatavi(ref, buffer.data(), e.index, e.count);
    for (int i = 0; i < n && static_cast<size_t>(i) < count; ++i) out.push_back(static_cast<double>(buffer[i]));
  }
}

double ValueSourceXplm::read(uint64_t handle) {
  const double nan = std::numeric_limits<double>::quiet_NaN();
  if (handle >= entries_.size()) return nan;
  const Entry& e = entries_[static_cast<size_t>(handle)];
  const XPLMDataRef ref = static_cast<XPLMDataRef>(e.ref);
  switch (e.type) {
    case xplmType_Double:
      return XPLMGetDatad(ref);
    case xplmType_Float:
      return static_cast<double>(XPLMGetDataf(ref));
    case xplmType_Int:
      return static_cast<double>(XPLMGetDatai(ref));
    case xplmType_FloatArray: {
      float v = 0;
      return XPLMGetDatavf(ref, &v, e.index, 1) == 1 ? static_cast<double>(v) : nan;
    }
    case xplmType_IntArray: {
      int v = 0;
      return XPLMGetDatavi(ref, &v, e.index, 1) == 1 ? static_cast<double>(v) : nan;
    }
    default:
      return nan;
  }
}

}  // namespace flightsim_aide
