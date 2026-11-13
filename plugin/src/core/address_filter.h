#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace flightsim_aide {

/// Strict dotted-quad IPv4 parser: exactly four decimal octets 0 to 255, no
/// leading zeros, no spaces or other characters. Returns the address in host
/// byte order (a.b.c.d is a<<24 | b<<16 | c<<8 | d).
std::optional<uint32_t> parseIpv4(const std::string& text);

/// True for loopback and private-range sources only: 10/8, 172.16/12,
/// 192.168/16, 169.254/16 and 127/8 (plugin/PROTOCOL.md section 3).
bool isAllowed(uint32_t ipv4);

/// Text form of [isAllowed]; anything that is not a valid IPv4 is refused.
bool isAllowed(const std::string& ipv4);

/// The CivetWeb `access_control_list` for the same table: deny all, then allow
/// each range.
std::string accessControlList();

}  // namespace flightsim_aide
