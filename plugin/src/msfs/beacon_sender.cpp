#include "beacon_sender.h"

#define NOMINMAX
// winsock2.h before windows.h
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <windows.h>

#include <chrono>
#include <vector>

#include "companion_beacon.h"

namespace flightsim_aide {

namespace {

// The IPv4 addresses (network order) of the adapters that are up, not loopback.
std::vector<in_addr> localAddresses() {
  std::vector<in_addr> out;
  ULONG size = 0;
  const ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
  GetAdaptersAddresses(AF_INET, flags, nullptr, nullptr, &size);
  if (size == 0) return out;
  std::vector<char> buffer(size);
  auto* list = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  if (GetAdaptersAddresses(AF_INET, flags, nullptr, list, &size) != NO_ERROR) return out;
  for (const IP_ADAPTER_ADDRESSES* a = list; a != nullptr; a = a->Next) {
    if (a->OperStatus != IfOperStatusUp || a->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    for (const IP_ADAPTER_UNICAST_ADDRESS* u = a->FirstUnicastAddress; u != nullptr; u = u->Next) {
      if (u->Address.lpSockaddr == nullptr || u->Address.lpSockaddr->sa_family != AF_INET) continue;
      const auto* sin = reinterpret_cast<const sockaddr_in*>(u->Address.lpSockaddr);
      const unsigned first = sin->sin_addr.S_un.S_un_b.s_b1;
      const unsigned second = sin->sin_addr.S_un.S_un_b.s_b2;
      if (first == 127 || (first == 169 && second == 254)) continue;  // loopback, link-local
      out.push_back(sin->sin_addr);
    }
  }
  return out;
}

}  // namespace

std::string computerName() {
  wchar_t name[256];
  DWORD n = 256;
  if (!GetComputerNameExW(ComputerNameDnsHostname, name, &n) || n == 0) return std::string();
  const int bytes = WideCharToMultiByte(CP_UTF8, 0, name, static_cast<int>(n), nullptr, 0, nullptr, nullptr);
  std::string out(static_cast<size_t>(bytes), '\0');
  WideCharToMultiByte(CP_UTF8, 0, name, static_cast<int>(n), &out[0], bytes, nullptr, nullptr);
  return out;
}

BeaconSender::~BeaconSender() { stop(); }

void BeaconSender::start(const std::string& simKind, int port) {
  if (thread_.joinable()) return;
  stop_ = false;
  thread_ = std::thread([this, simKind, port] { run(simKind, port); });
}

void BeaconSender::stop() {
  stop_ = true;
  if (thread_.joinable()) thread_.join();
}

void BeaconSender::run(std::string simKind, int port) {
  WSADATA wsa;
  if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return;
  const SOCKET sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (sock != INVALID_SOCKET) {
    const std::string message = companionBeaconMessage(simKind, computerName(), port);
    sockaddr_in to = {};
    to.sin_family = AF_INET;
    to.sin_port = htons(static_cast<u_short>(kCompanionBeaconPort));
    inet_pton(AF_INET, kCompanionBeaconGroup, &to.sin_addr);
    const DWORD ttl = 1;  // the local network only
    setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, reinterpret_cast<const char*>(&ttl), sizeof ttl);
    while (!stop_) {
      // One send per adapter, each from that adapter's address, as X-Plane does.
      for (const in_addr& local : localAddresses()) {
        setsockopt(sock, IPPROTO_IP, IP_MULTICAST_IF, reinterpret_cast<const char*>(&local), sizeof local);
        sendto(sock, message.data(), static_cast<int>(message.size()), 0, reinterpret_cast<const sockaddr*>(&to),
               sizeof to);
      }
      for (int i = 0; i < 10 && !stop_; ++i) std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    closesocket(sock);
  }
  WSACleanup();
}

}  // namespace flightsim_aide
