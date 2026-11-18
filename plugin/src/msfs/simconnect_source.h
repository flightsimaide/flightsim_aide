#pragma once

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <SimConnect.h>

#include <cstdint>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "msfs_names.h"
#include "value_source.h"

namespace flightsim_aide {

/// The [ValueSource] over SimConnect: the only code that turns the names of a
/// checklist (`A:...`, `L:...`, `B:...`, see msfs_names.h) into requests to
/// Microsoft Flight Simulator. SimConnect is not thread safe, so everything
/// here, including the dispatch callbacks, runs on the one thread that also
/// calls StreamHub::tick (the companion's main loop).
///
/// SimConnect answers by message, and the core wants an answer to
/// [resolve] at once. So [resolve] sends the request and runs the dispatch
/// loop (the [pump] it is given) until the sim answered or a short time passed:
///
/// - an A-variable (or a bad unit) the sim refuses sends exception 7
///   `NAME_UNRECOGNIZED` for the definition: `unknown_name` (D-86);
/// - a B-variable is looked up in the sim's list of input events for the
///   loaded aircraft; a name that is not on the list is `unknown_name`;
/// - an L-variable that does not exist reads 0 and cannot be told apart from
///   one that does (accepted in D-86), so it is always accepted;
/// - no answer in time is accepted; if the sim refuses later the value is
///   reported as missing (`null`) from then on.
///
/// While the aircraft is not [setAvailable] every value is missing, because
/// what the sim returns during a load is wrong (D-88).
class SimConnectSource : public ValueSource {
 public:
  using ClockFn = std::function<int64_t()>;

  /// [sc] is an open SimConnect handle. [pump] reads and dispatches the
  /// messages that are waiting (it ends up calling the `on...` functions below).
  SimConnectSource(HANDLE sc, std::function<void()> pump, ClockFn clock);

  Resolution resolve(const std::string& base, int index) override;
  double read(uint64_t handle) override;

  /// Hides every value (false) or shows them again (true): the requests are
  /// sent again so that fresh values arrive.
  void setAvailable(bool available);
  bool available() const { return available_; }

  /// Asks the sim for the list of input events of the loaded aircraft. Call it
  /// after the aircraft is ready; B-variables are looked up when it arrives.
  void requestInputEventList();

  /// Reads the B-variables that are due. Call it every step.
  void poll(int64_t nowMs);

  // The dispatch callbacks.
  void onSimObjectData(const SIMCONNECT_RECV_SIMOBJECT_DATA* data);
  void onException(const SIMCONNECT_RECV_EXCEPTION* exception);
  void onInputEventList(const SIMCONNECT_RECV_ENUMERATE_INPUT_EVENTS* list);
  void onInputEventValue(const SIMCONNECT_RECV_GET_INPUT_EVENT* value);

  /// How many names are being read.
  size_t entryCount() const { return entries_.size(); }

 private:
  struct Entry {
    MsfsVar var;
    DWORD id = 0;               // the definition id and the request id
    bool failed = false;        // the sim refused it
    bool answered = false;      // the sim said anything about it (data or an exception)
    bool seen = false;          // [value] is current
    double value = 0;
    // B-variables:
    bool hashKnown = false;
    UINT64 hash = 0;
    int failures = 0;
    int64_t nextDueMs = 0;
  };

  enum class Sent { define, request, getInputEvent };
  struct SentInfo {
    size_t entry;
    Sent what;
  };

  void send(Entry& e);
  void noteSent(size_t entry, Sent what);
  void lookUpInputEvents();
  void waitFor(const std::function<bool()>& done, int64_t maxMs);

  HANDLE sc_;
  std::function<void()> pump_;
  ClockFn clock_;
  bool available_ = false;
  std::vector<Entry> entries_;
  std::map<std::string, size_t> byKey_;
  std::map<DWORD, SentInfo> sent_;  // packet id -> what it was
  // The sim's input events of the loaded aircraft, by lower-case name.
  struct InputEvent {
    UINT64 hash;
    bool isNumber;
  };
  std::map<std::string, InputEvent> inputEvents_;
  bool inputEventsFresh_ = false;
  bool inputEventsPending_ = false;
  bool inputEventsBuilding_ = false;
  // After a wait ran out with no answer at all, the next waits are short until
  // the sim answers something (it may be on a menu with no aircraft).
  bool sluggish_ = false;
};

}  // namespace flightsim_aide
