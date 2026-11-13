#include "json_parser.h"

#include <cstdlib>

namespace flightsim_aide {

const JsonValue* JsonValue::find(const std::string& key) const {
  for (auto it = members.rbegin(); it != members.rend(); ++it) {
    if (it->first == key) return &it->second;
  }
  return nullptr;
}

namespace {

constexpr int kMaxDepth = 32;

class Parser {
 public:
  explicit Parser(const std::string& s) : s_(s) {}

  bool parse(JsonValue& out, std::string& error) {
    skipSpace();
    if (!value(out, 0)) {
      error = error_;
      return false;
    }
    skipSpace();
    if (pos_ != s_.size()) {
      error = "Unexpected text after the frame.";
      return false;
    }
    return true;
  }

 private:
  const std::string& s_;
  size_t pos_ = 0;
  std::string error_ = "Frame is not valid JSON.";

  bool fail(const char* message) {
    error_ = message;
    return false;
  }

  void skipSpace() {
    while (pos_ < s_.size() &&
           (s_[pos_] == ' ' || s_[pos_] == '\t' || s_[pos_] == '\n' || s_[pos_] == '\r')) {
      ++pos_;
    }
  }

  bool literal(const char* word) {
    size_t n = 0;
    while (word[n] != '\0') ++n;
    if (s_.compare(pos_, n, word) != 0) return false;
    pos_ += n;
    return true;
  }

  bool value(JsonValue& out, int depth) {
    if (depth > kMaxDepth) return fail("Frame is nested too deeply.");
    if (pos_ >= s_.size()) return false;
    const char c = s_[pos_];
    if (c == '{') return object(out, depth);
    if (c == '[') return array(out, depth);
    if (c == '"') {
      out.kind = JsonValue::Kind::string;
      return string(out.text);
    }
    if (c == 't') {
      out.kind = JsonValue::Kind::boolean;
      out.boolean = true;
      return literal("true");
    }
    if (c == 'f') {
      out.kind = JsonValue::Kind::boolean;
      return literal("false");
    }
    if (c == 'n') {
      out.kind = JsonValue::Kind::null;
      return literal("null");
    }
    if (c == '-' || (c >= '0' && c <= '9')) return number(out);
    return false;
  }

  bool object(JsonValue& out, int depth) {
    out.kind = JsonValue::Kind::object;
    ++pos_;  // {
    skipSpace();
    if (pos_ < s_.size() && s_[pos_] == '}') {
      ++pos_;
      return true;
    }
    while (true) {
      skipSpace();
      if (pos_ >= s_.size() || s_[pos_] != '"') return false;
      std::string key;
      if (!string(key)) return false;
      skipSpace();
      if (pos_ >= s_.size() || s_[pos_] != ':') return false;
      ++pos_;
      skipSpace();
      JsonValue v;
      if (!value(v, depth + 1)) return false;
      out.members.emplace_back(std::move(key), std::move(v));
      skipSpace();
      if (pos_ >= s_.size()) return false;
      if (s_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (s_[pos_] == '}') {
        ++pos_;
        return true;
      }
      return false;
    }
  }

  bool array(JsonValue& out, int depth) {
    out.kind = JsonValue::Kind::array;
    ++pos_;  // [
    skipSpace();
    if (pos_ < s_.size() && s_[pos_] == ']') {
      ++pos_;
      return true;
    }
    while (true) {
      skipSpace();
      JsonValue v;
      if (!value(v, depth + 1)) return false;
      out.members.emplace_back("", std::move(v));
      skipSpace();
      if (pos_ >= s_.size()) return false;
      if (s_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (s_[pos_] == ']') {
        ++pos_;
        return true;
      }
      return false;
    }
  }

  static int hexValue(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  }

  bool hex4(unsigned& out) {
    if (pos_ + 4 > s_.size()) return false;
    unsigned v = 0;
    for (int i = 0; i < 4; ++i) {
      const int h = hexValue(s_[pos_ + static_cast<size_t>(i)]);
      if (h < 0) return false;
      v = v * 16 + static_cast<unsigned>(h);
    }
    pos_ += 4;
    out = v;
    return true;
  }

  static void appendUtf8(std::string& out, unsigned cp) {
    if (cp < 0x80) {
      out += static_cast<char>(cp);
    } else if (cp < 0x800) {
      out += static_cast<char>(0xC0 | (cp >> 6));
      out += static_cast<char>(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
      out += static_cast<char>(0xE0 | (cp >> 12));
      out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
      out += static_cast<char>(0x80 | (cp & 0x3F));
    } else {
      out += static_cast<char>(0xF0 | (cp >> 18));
      out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
      out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
      out += static_cast<char>(0x80 | (cp & 0x3F));
    }
  }

  bool string(std::string& out) {
    ++pos_;  // opening quote
    while (pos_ < s_.size()) {
      const unsigned char c = static_cast<unsigned char>(s_[pos_]);
      if (c == '"') {
        ++pos_;
        return true;
      }
      if (c < 0x20) return false;  // raw control characters are not JSON
      if (c != '\\') {
        out += static_cast<char>(c);
        ++pos_;
        continue;
      }
      ++pos_;
      if (pos_ >= s_.size()) return false;
      const char e = s_[pos_++];
      switch (e) {
        case '"': out += '"'; break;
        case '\\': out += '\\'; break;
        case '/': out += '/'; break;
        case 'b': out += '\b'; break;
        case 'f': out += '\f'; break;
        case 'n': out += '\n'; break;
        case 'r': out += '\r'; break;
        case 't': out += '\t'; break;
        case 'u': {
          unsigned cp = 0;
          if (!hex4(cp)) return false;
          if (cp >= 0xD800 && cp <= 0xDBFF) {
            unsigned low = 0;
            if (pos_ + 2 > s_.size() || s_[pos_] != '\\' || s_[pos_ + 1] != 'u') return false;
            pos_ += 2;
            if (!hex4(low) || low < 0xDC00 || low > 0xDFFF) return false;
            cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
          } else if (cp >= 0xDC00 && cp <= 0xDFFF) {
            return false;
          }
          appendUtf8(out, cp);
          break;
        }
        default:
          return false;
      }
    }
    return false;
  }

  bool number(JsonValue& out) {
    out.kind = JsonValue::Kind::number;
    const size_t start = pos_;
    if (s_[pos_] == '-') ++pos_;
    if (pos_ >= s_.size()) return false;
    if (s_[pos_] == '0') {
      ++pos_;
    } else if (s_[pos_] >= '1' && s_[pos_] <= '9') {
      while (pos_ < s_.size() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
    } else {
      return false;
    }
    const size_t intEnd = pos_;
    bool plain = true;
    if (pos_ < s_.size() && s_[pos_] == '.') {
      plain = false;
      ++pos_;
      const size_t digits = pos_;
      while (pos_ < s_.size() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
      if (pos_ == digits) return false;
    }
    if (pos_ < s_.size() && (s_[pos_] == 'e' || s_[pos_] == 'E')) {
      plain = false;
      ++pos_;
      if (pos_ < s_.size() && (s_[pos_] == '+' || s_[pos_] == '-')) ++pos_;
      const size_t digits = pos_;
      while (pos_ < s_.size() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
      if (pos_ == digits) return false;
    }
    out.number = std::strtod(s_.substr(start, pos_ - start).c_str(), nullptr);
    out.isInteger = false;
    if (plain) {
      // Parse by hand so overflow is detected exactly.
      bool negative = s_[start] == '-';
      uint64_t v = 0;
      bool overflow = false;
      for (size_t i = start + (negative ? 1 : 0); i < intEnd; ++i) {
        const uint64_t d = static_cast<uint64_t>(s_[i] - '0');
        if (v > (static_cast<uint64_t>(INT64_MAX) - d) / 10) {
          overflow = true;
          break;
        }
        v = v * 10 + d;
      }
      if (!overflow) {
        out.isInteger = true;
        out.integer = negative ? -static_cast<int64_t>(v) : static_cast<int64_t>(v);
      }
    }
    return true;
  }
};

}  // namespace

bool parseJson(const std::string& text, JsonValue& out, std::string& error) {
  Parser parser(text);
  return parser.parse(out, error);
}

}  // namespace flightsim_aide
