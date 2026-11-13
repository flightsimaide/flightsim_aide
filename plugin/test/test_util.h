#pragma once

#include <fstream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <string>

// Reads a golden file from testing/fixtures/protocol byte for byte.
inline std::string readFixture(const std::string& name) {
  std::ifstream in(std::string(FIXTURE_DIR) + "/" + name, std::ios::binary);
  if (!in) throw std::runtime_error("missing fixture " + name);
  return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}
