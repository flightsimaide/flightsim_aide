#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace flightsim_aide {

/// Limits from plugin/PROTOCOL.md section 7.
constexpr size_t kMaxFrameBytes = 4096;
constexpr size_t kMaxNameBytes = 200;
constexpr int kMinHz = 1;
constexpr int kMaxHz = 60;

/// What a client frame turned out to be.
enum class FrameKind {
  subscribe,
  unsubscribe,
  ping,
  /// A well-formed `set`: reserved, always answered `unsupported` in v1.
  set,
  /// Anything malformed, unknown or out of range.
  badRequest,
};

/// A parsed client frame. Parsing never throws: a frame that cannot be used
/// is [FrameKind::badRequest] with a short [message].
struct ClientFrame {
  FrameKind kind = FrameKind::badRequest;
  /// The frame's `id` when it had a readable one (integer, 0 or more), also on
  /// a bad request, so the error can name the offending subscription.
  std::optional<int64_t> id;
  std::string name;  // subscribe
  int hz = 0;        // subscribe
  std::string message;
};

ClientFrame parseClientFrame(const std::string& text);

/// A value in a `values` frame. Finite whole numbers print as integers,
/// other finite numbers in the shortest form that round-trips, anything else
/// as `null`.
///
/// A subscription to a range `name[a..b]` carries a list instead: `[1,1,0]`,
/// one number per element that exists (fewer than asked when the array ends
/// inside the range, `[]` when it ends before it).
struct SignalValue {
  SignalValue(int64_t id_, double value_) : id(id_), value(value_) {}
  SignalValue(int64_t id_, std::vector<double> list_) : id(id_), list(std::move(list_)), isList(true) {}

  int64_t id;
  double value = 0;
  std::vector<double> list;
  bool isList = false;
};

std::string subscribedFrame(int64_t id);

/// `{"op":"error","id":<id>,"code":"<code>"[,"message":"<message>"]}`; `id` is
/// left out when [id] is empty and `message` when it is empty.
std::string errorFrame(const std::optional<int64_t>& id, const std::string& code,
                       const std::string& message = "");

/// `{"op":"values","t":<epoch ms>,"v":{"<id>":<number>,...}}` in the given order.
std::string valuesFrame(int64_t epochMs, const std::vector<SignalValue>& values);

std::string heartbeatFrame();
std::string pongFrame();

/// A double as JSON text (see [SignalValue]).
std::string jsonNumber(double value);

}  // namespace flightsim_aide
