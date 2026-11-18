#include "simconnect_source.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <limits>

namespace flightsim_aide {

namespace {

// Ids are the companion's own: 1 to 99 belong to main (identity, events), the
// names start here. One id is both the definition and the request of a name.
constexpr DWORD kFirstId = 100;
constexpr DWORD kEnumerateRequest = 90;
constexpr size_t kMaxEntries = 2048;
constexpr size_t kMaxSentRemembered = 4096;

constexpr int64_t kResolveWaitMs = 400;
constexpr int64_t kSluggishWaitMs = 40;
constexpr int64_t kInputListWaitMs = 800;
constexpr int64_t kInputEventPeriodMs = 250;

std::string lower(std::string s) {
  for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  return s;
}

constexpr double kMissing = std::numeric_limits<double>::quiet_NaN();

}  // namespace

SimConnectSource::SimConnectSource(HANDLE sc, std::function<void()> pump, ClockFn clock)
    : sc_(sc), pump_(std::move(pump)), clock_(std::move(clock)) {}

void SimConnectSource::waitFor(const std::function<bool()>& done, int64_t maxMs) {
  const int64_t start = clock_();
  for (;;) {
    pump_();
    if (done() || clock_() - start >= maxMs) return;
    Sleep(2);
  }
}

void SimConnectSource::noteSent(size_t entry, Sent what) {
  DWORD id = 0;
  if (FAILED(SimConnect_GetLastSentPacketID(sc_, &id))) return;
  if (sent_.size() >= kMaxSentRemembered) {
    // Packet ids only grow: forget the older half.
    auto middle = sent_.begin();
    std::advance(middle, static_cast<std::ptrdiff_t>(sent_.size() / 2));
    sent_.erase(sent_.begin(), middle);
  }
  sent_[id] = SentInfo{entry, what};
}

void SimConnectSource::send(Entry& e) {
  const size_t index = static_cast<size_t>(&e - entries_.data());
  if (e.var.kind == MsfsVar::Kind::inputEvent) return;  // read by polling
  if (e.id == 0) {
    e.id = kFirstId + static_cast<DWORD>(index);
    SimConnect_AddToDataDefinition(sc_, e.id, e.var.datum.c_str(), e.var.unit.c_str(), SIMCONNECT_DATATYPE_FLOAT64);
    noteSent(index, Sent::define);
  }
  SimConnect_RequestDataOnSimObject(sc_, e.id, e.id, SIMCONNECT_OBJECT_ID_USER, SIMCONNECT_PERIOD_SIM_FRAME,
                                    SIMCONNECT_DATA_REQUEST_FLAG_CHANGED);
  noteSent(index, Sent::request);
}

Resolution SimConnectSource::resolve(const std::string& base, int index) {
  Resolution r;  // unknown
  if (index >= 0) return r;
  const std::optional<MsfsVar> var = parseMsfsName(base);
  if (!var) return r;

  const std::string key = var->key();
  const auto known = byKey_.find(key);
  if (known != byKey_.end()) {
    const Entry& e = entries_[known->second];
    if (e.failed) return r;
    r.status = Resolution::Status::ok;
    r.handle = known->second;
    return r;
  }
  if (entries_.size() >= kMaxEntries) return r;

  const size_t slot = entries_.size();
  entries_.emplace_back();
  entries_[slot].var = *var;
  // The id stays 0 until send() defines it.

  if (var->kind == MsfsVar::Kind::inputEvent) {
    if (!inputEventsFresh_) {
      if (!inputEventsPending_) requestInputEventList();
      waitFor([this] { return inputEventsFresh_; }, kInputListWaitMs);
    }
    if (inputEventsFresh_) {
      const auto it = inputEvents_.find(lower(var->datum));
      if (it == inputEvents_.end()) {
        entries_[slot].failed = true;  // not kept in byKey_: another aircraft may have it
        return r;
      }
      if (!it->second.isNumber) {
        entries_[slot].failed = true;
        r.status = Resolution::Status::unsupported;
        return r;
      }
      entries_[slot].hashKnown = true;
      entries_[slot].hash = it->second.hash;
    }
    byKey_[key] = slot;
    r.status = Resolution::Status::ok;
    r.handle = slot;
    return r;
  }

  send(entries_[slot]);
  byKey_[key] = slot;
  waitFor([this, slot] { return entries_[slot].answered || entries_[slot].failed; },
          sluggish_ ? kSluggishWaitMs : kResolveWaitMs);
  if (entries_[slot].failed) return r;
  sluggish_ = !entries_[slot].answered;
  r.status = Resolution::Status::ok;
  r.handle = slot;
  return r;
}

double SimConnectSource::read(uint64_t handle) {
  if (!available_ || handle >= entries_.size()) return kMissing;
  const Entry& e = entries_[static_cast<size_t>(handle)];
  if (e.failed || !e.seen) return kMissing;
  return e.value;
}

void SimConnectSource::setAvailable(bool available) {
  available_ = available;
  for (Entry& e : entries_) {
    e.seen = false;
    if (!available || e.failed) continue;
    e.nextDueMs = 0;
    if (e.var.kind != MsfsVar::Kind::inputEvent) send(e);  // a fresh first value
  }
}

void SimConnectSource::requestInputEventList() {
  inputEventsFresh_ = false;
  inputEventsPending_ = true;
  inputEventsBuilding_ = false;
  for (Entry& e : entries_) {
    if (e.var.kind == MsfsVar::Kind::inputEvent) {
      e.hashKnown = false;
      e.seen = false;
    }
  }
  SimConnect_EnumerateInputEvents(sc_, kEnumerateRequest);
}

void SimConnectSource::lookUpInputEvents() {
  for (Entry& e : entries_) {
    if (e.var.kind != MsfsVar::Kind::inputEvent) continue;
    const auto it = inputEvents_.find(lower(e.var.datum));
    e.hashKnown = it != inputEvents_.end() && it->second.isNumber;
    e.failed = it != inputEvents_.end() ? !it->second.isNumber : false;
    if (e.hashKnown) e.hash = it->second.hash;
    e.failures = 0;
    e.nextDueMs = 0;
    e.seen = false;
  }
}

void SimConnectSource::poll(int64_t nowMs) {
  if (!available_ || !inputEventsFresh_) return;
  for (size_t i = 0; i < entries_.size(); ++i) {
    Entry& e = entries_[i];
    if (e.var.kind != MsfsVar::Kind::inputEvent || !e.hashKnown || e.failed || nowMs < e.nextDueMs) continue;
    SimConnect_GetInputEvent(sc_, kFirstId + static_cast<DWORD>(i), e.hash);
    noteSent(i, Sent::getInputEvent);
    e.nextDueMs = nowMs + kInputEventPeriodMs;
  }
}

void SimConnectSource::onSimObjectData(const SIMCONNECT_RECV_SIMOBJECT_DATA* data) {
  if (data->dwRequestID < kFirstId) return;
  const size_t index = data->dwRequestID - kFirstId;
  if (index >= entries_.size()) return;
  Entry& e = entries_[index];
  e.answered = true;
  if (!available_ || data->dwDefineCount != 1) return;
  e.value = *reinterpret_cast<const double*>(&data->dwData);
  e.seen = true;
}

void SimConnectSource::onException(const SIMCONNECT_RECV_EXCEPTION* exception) {
  const auto it = sent_.find(exception->dwSendID);
  if (it == sent_.end() || it->second.entry >= entries_.size()) return;
  Entry& e = entries_[it->second.entry];
  e.answered = true;
  switch (it->second.what) {
    case Sent::define:
      e.failed = true;  // NAME_UNRECOGNIZED: no such variable, or a wrong unit
      break;
    case Sent::request:
      break;  // follows a refused definition
    case Sent::getInputEvent: {
      // The event is not readable now (another aircraft, or a load): ask less often.
      e.seen = false;
      e.failures = std::min(e.failures + 1, 4);
      e.nextDueMs = clock_() + std::min<int64_t>(5000, 500LL << e.failures);
      break;
    }
  }
}

void SimConnectSource::onInputEventList(const SIMCONNECT_RECV_ENUMERATE_INPUT_EVENTS* list) {
  if (!inputEventsBuilding_) {
    inputEvents_.clear();
    inputEventsBuilding_ = true;
  }
  for (DWORD i = 0; i < list->dwArraySize; ++i) {
    const SIMCONNECT_INPUT_EVENT_DESCRIPTOR& d = (&list->rgData[0])[i];
    inputEvents_[lower(d.Name)] = InputEvent{d.Hash, d.eType == SIMCONNECT_INPUT_EVENT_TYPE_DOUBLE};
  }
  if (list->dwEntryNumber + 1 >= list->dwOutOf) {
    inputEventsFresh_ = true;
    inputEventsPending_ = false;
    inputEventsBuilding_ = false;
    lookUpInputEvents();
  }
}

void SimConnectSource::onInputEventValue(const SIMCONNECT_RECV_GET_INPUT_EVENT* value) {
  if (value->dwRequestID < kFirstId) return;
  const size_t index = value->dwRequestID - kFirstId;
  if (index >= entries_.size()) return;
  Entry& e = entries_[index];
  e.answered = true;
  if (!available_ || value->eType != SIMCONNECT_INPUT_EVENT_TYPE_DOUBLE) return;
  e.value = *reinterpret_cast<const double*>(&value->Value);
  e.seen = true;
  e.failures = 0;
}

}  // namespace flightsim_aide
