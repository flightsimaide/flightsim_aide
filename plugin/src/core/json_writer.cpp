#include "json_writer.h"

#include "version.h"

namespace flightsim_aide {

std::string jsonString(const std::string& s) {
  static const char* hex = "0123456789abcdef";
  std::string out = "\"";
  for (const char ch : s) {
    const unsigned char c = static_cast<unsigned char>(ch);
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      case '\b': out += "\\b"; break;
      case '\f': out += "\\f"; break;
      default:
        if (c < 0x20) {
          out += "\\u00";
          out += hex[c >> 4];
          out += hex[c & 0xf];
        } else {
          out += ch;
        }
    }
  }
  out += '"';
  return out;
}

std::string helloJson(const HelloInfo& h) {
  return "{\"protocolVersion\":" + std::to_string(kProtocolVersion) +
         ",\"sim\":{\"kind\":" + jsonString(h.simKind) +
         ",\"version\":" + jsonString(h.simVersion) +
         "}" + (h.os.empty() ? std::string() : ",\"os\":" + jsonString(h.os)) +
         ",\"pluginVersion\":" + jsonString(h.pluginVersion) +
         ",\"runId\":" + jsonString(h.runId) +
         ",\"port\":" + std::to_string(h.port) + ",\"streamPath\":\"/v1/stream\"}";
}

std::string aircraftJson(const AircraftInfo& a) {
  std::string out = "{\"protocolVersion\":" + std::to_string(kProtocolVersion) +
                    ",\"generation\":" + std::to_string(a.generation) +
                    ",\"icao\":" + jsonString(a.icao) +
                    ",\"description\":" + jsonString(a.description) +
                    ",\"aircraftPath\":" + jsonString(a.aircraftPath);
  if (a.hasChecklist) {
    out += ",\"checklistPath\":" + jsonString(a.checklistPath) +
           ",\"checklistModified\":" + std::to_string(a.checklistModified) +
           ",\"checklistSize\":" + std::to_string(a.checklistSize);
  }
  return out + "}";
}

std::string errorJson(const std::string& code, const std::string& message) {
  return "{\"error\":" + jsonString(code) + ",\"message\":" + jsonString(message) + "}";
}

}  // namespace flightsim_aide
