#include "stream_codec.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <memory>

#include "json_parser.h"
#include "signal_name.h"
#include "json_writer.h"

namespace flightsim_aide {

namespace {

ClientFrame bad(std::optional<int64_t> id, const char* message) {
  ClientFrame f;
  f.kind = FrameKind::badRequest;
  f.id = id;
  f.message = message;
  return f;
}

}  // namespace

ClientFrame parseClientFrame(const std::string& text) {
  if (text.size() > kMaxFrameBytes) return bad(std::nullopt, "Frame is larger than 4 KB.");

  JsonValue root;
  std::string error;
  if (!parseJson(text, root, error)) return bad(std::nullopt, "Frame is not valid JSON.");
  if (root.kind != JsonValue::Kind::object) return bad(std::nullopt, "Frame must be a JSON object.");

  std::optional<int64_t> id;
  const JsonValue* idValue = root.find("id");
  if (idValue != nullptr && idValue->kind == JsonValue::Kind::number && idValue->isInteger &&
      idValue->integer >= 0) {
    id = idValue->integer;
  }

  const JsonValue* op = root.find("op");
  if (op == nullptr || op->kind != JsonValue::Kind::string) return bad(id, "Frame needs an op.");

  ClientFrame f;
  f.id = id;
  if (op->text == "ping") {
    f.kind = FrameKind::ping;
    return f;
  }
  if (op->text == "set") {
    f.kind = FrameKind::set;
    return f;
  }
  if (op->text == "unsubscribe") {
    if (!id) return bad(id, "unsubscribe needs an id.");
    f.kind = FrameKind::unsubscribe;
    return f;
  }
  if (op->text != "subscribe") return bad(id, "Unknown op.");

  if (!id) return bad(id, "subscribe needs an id of 0 or more.");
  const JsonValue* name = root.find("name");
  if (name == nullptr || name->kind != JsonValue::Kind::string || name->text.empty() ||
      name->text.size() > kMaxNameBytes) {
    return bad(id, "subscribe needs a name of 1 to 200 characters.");
  }
  for (const char ch : name->text) {
    const unsigned char c = static_cast<unsigned char>(ch);
    if (c < 0x20 || c == 0x7f) return bad(id, "The name has a control character.");
  }
  if (!parseSignalName(name->text)) return bad(id, "The name has a malformed index.");
  const JsonValue* hz = root.find("hz");
  if (hz == nullptr || hz->kind != JsonValue::Kind::number || !hz->isInteger || hz->integer < kMinHz ||
      hz->integer > kMaxHz) {
    return bad(id, "hz must be an integer from 1 to 60.");
  }
  f.kind = FrameKind::subscribe;
  f.name = name->text;
  f.hz = static_cast<int>(hz->integer);
  return f;
}

std::string jsonNumber(double value) {
  if (!std::isfinite(value)) return "null";
  if (value == std::trunc(value) && std::fabs(value) < 9007199254740992.0) {
    return std::to_string(static_cast<long long>(value));
  }
  char buf[40];
  for (int precision = 1; precision <= 17; ++precision) {
    std::snprintf(buf, sizeof buf, "%.*g", precision, value);
    if (std::strtod(buf, nullptr) == value) break;
  }
  std::string out = buf;
  for (char& c : out) {
    if (c == ',') c = '.';  // a locale with a decimal comma
  }
  return out;
}

std::string subscribedFrame(int64_t id) {
  return "{\"op\":\"subscribed\",\"id\":" + std::to_string(id) + "}";
}

std::string errorFrame(const std::optional<int64_t>& id, const std::string& code,
                       const std::string& message) {
  std::string out = "{\"op\":\"error\"";
  if (id) out += ",\"id\":" + std::to_string(*id);
  out += ",\"code\":" + jsonString(code);
  if (!message.empty()) out += ",\"message\":" + jsonString(message);
  return out + "}";
}

std::string valuesFrame(int64_t epochMs, const std::vector<SignalValue>& values) {
  std::string out = "{\"op\":\"values\",\"t\":" + std::to_string(epochMs) + ",\"v\":{";
  bool first = true;
  for (const SignalValue& v : values) {
    if (!first) out += ',';
    first = false;
    out += "\"" + std::to_string(v.id) + "\":";
    if (!v.isList) {
      out += jsonNumber(v.value);
      continue;
    }
    out += '[';
    for (size_t i = 0; i < v.list.size(); ++i) {
      if (i > 0) out += ',';
      out += jsonNumber(v.list[i]);
    }
    out += ']';
  }
  return out + "}}";
}

std::string heartbeatFrame() { return "{\"op\":\"hb\"}"; }

std::string pongFrame() { return "{\"op\":\"pong\"}"; }

}  // namespace flightsim_aide
