// Copyright 2024 TrustTunnel contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

// Winsock before <windows.h>.
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <bcrypt.h>
#include <iphlpapi.h>

#include "physical_net.h"

#include <climits>
#include <cstring>
#include <memory>
#include <sstream>
#include <vector>

namespace vpn_plugin {

namespace {

constexpr int kRelayConnectTimeoutMs = 5000;
constexpr size_t kMaxHeader = 160;

void EnsureWinsock() {
    static const bool started = [] {
        WSADATA data;
        return WSAStartup(MAKEWORD(2, 2), &data) == 0;
    }();
    (void)started;
}

bool NameContains(const wchar_t* name, const wchar_t* part) {
    if (name == nullptr) return false;
    std::wstring haystack(name);
    std::wstring needle(part);
    for (auto& c : haystack) c = towlower(c);
    for (auto& c : needle) c = towlower(c);
    return haystack.find(needle) != std::wstring::npos;
}

/**
 * The adapter the traffic took before the tunnel: up, not loopback, not a
 * tunnel (Wintun / TrustTunnel), with a default gateway of [family] - which
 * also leaves out Hyper-V/WSL host adapters - and the lowest metric.
 * @return Interface index, 0 if none.
 */
ULONG PhysicalInterfaceIndex(int family) {
    ULONG size = 16 * 1024;
    std::vector<unsigned char> buffer;
    ULONG result = ERROR_BUFFER_OVERFLOW;
    for (int attempt = 0; attempt < 3 && result == ERROR_BUFFER_OVERFLOW; ++attempt) {
        buffer.resize(size);
        result = GetAdaptersAddresses(static_cast<ULONG>(family),
                                      GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_SKIP_ANYCAST |
                                              GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
                                      nullptr,
                                      reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &size);
    }
    if (result != NO_ERROR) return 0;

    ULONG best_index = 0;
    ULONG best_metric = ULONG_MAX;
    for (auto* a = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); a != nullptr; a = a->Next) {
        if (a->OperStatus != IfOperStatusUp) continue;
        if (a->IfType == IF_TYPE_SOFTWARE_LOOPBACK || a->IfType == IF_TYPE_PROP_VIRTUAL ||
            a->IfType == IF_TYPE_TUNNEL) {
            continue;
        }
        if (NameContains(a->Description, L"wintun") || NameContains(a->FriendlyName, L"trusttunnel") ||
            NameContains(a->Description, L"trusttunnel")) {
            continue;
        }
        bool has_gateway = false;
        for (auto* g = a->FirstGatewayAddress; g != nullptr; g = g->Next) {
            if (g->Address.lpSockaddr != nullptr && g->Address.lpSockaddr->sa_family == family) {
                has_gateway = true;
                break;
            }
        }
        if (!has_gateway) continue;

        ULONG index = family == AF_INET6 ? a->Ipv6IfIndex : a->IfIndex;
        ULONG metric = family == AF_INET6 ? a->Ipv6Metric : a->Ipv4Metric;
        if (index != 0 && metric < best_metric) {
            best_metric = metric;
            best_index = index;
        }
    }
    return best_index;
}

/** Pins [s] to the physical adapter. No-op if there's none. */
void PinToPhysical(SOCKET s, int family) {
    ULONG index = PhysicalInterfaceIndex(family);
    if (index == 0) return;
    if (family == AF_INET) {
        // IPv4 takes the index in network byte order, IPv6 in host order.
        DWORD value = htonl(index);
        setsockopt(s, IPPROTO_IP, IP_UNICAST_IF, reinterpret_cast<const char*>(&value), sizeof(value));
    } else {
        DWORD value = index;
        setsockopt(s, IPPROTO_IPV6, IPV6_UNICAST_IF, reinterpret_cast<const char*>(&value), sizeof(value));
    }
}

/**
 * Connects to a numeric [ip]:[port] over the physical adapter.
 * @param outcome "ok", "timeout", "refused" or "failed".
 * @return The connected (blocking) socket, or INVALID_SOCKET.
 */
SOCKET ConnectPhysical(const std::string& ip, int port, int timeout_ms, std::string* outcome) {
    EnsureWinsock();
    *outcome = "failed";

    addrinfo hints{};
    hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    addrinfo* info = nullptr;
    if (getaddrinfo(ip.c_str(), std::to_string(port).c_str(), &hints, &info) != 0 || info == nullptr) {
        return INVALID_SOCKET;
    }
    std::unique_ptr<addrinfo, decltype(&freeaddrinfo)> guard(info, freeaddrinfo);

    SOCKET s = socket(info->ai_family, SOCK_STREAM, IPPROTO_TCP);
    if (s == INVALID_SOCKET) return INVALID_SOCKET;
    PinToPhysical(s, info->ai_family);

    u_long non_blocking = 1;
    ioctlsocket(s, FIONBIO, &non_blocking);
    if (connect(s, info->ai_addr, static_cast<int>(info->ai_addrlen)) == SOCKET_ERROR &&
        WSAGetLastError() != WSAEWOULDBLOCK) {
        *outcome = WSAGetLastError() == WSAECONNREFUSED ? "refused" : "failed";
        closesocket(s);
        return INVALID_SOCKET;
    }

    fd_set writable, failed;
    FD_ZERO(&writable);
    FD_ZERO(&failed);
    FD_SET(s, &writable);
    FD_SET(s, &failed);
    timeval tv{timeout_ms / 1000, (timeout_ms % 1000) * 1000};
    int ready = select(0, nullptr, &writable, &failed, &tv);
    if (ready == 0) {
        *outcome = "timeout";
        closesocket(s);
        return INVALID_SOCKET;
    }
    int error = 0;
    int length = sizeof(error);
    getsockopt(s, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&error), &length);
    if (ready < 0 || FD_ISSET(s, &failed) || error != 0) {
        *outcome = error == WSAECONNREFUSED ? "refused" : error == WSAETIMEDOUT ? "timeout" : "failed";
        closesocket(s);
        return INVALID_SOCKET;
    }

    u_long blocking = 0;
    ioctlsocket(s, FIONBIO, &blocking);
    *outcome = "ok";
    return s;
}

/** Copies bytes both ways until either side closes. Closes both. */
void Pipe(SOCKET a, SOCKET b) {
    char buffer[16 * 1024];
    for (;;) {
        fd_set readable;
        FD_ZERO(&readable);
        FD_SET(a, &readable);
        FD_SET(b, &readable);
        timeval tv{120, 0};
        if (select(0, &readable, nullptr, nullptr, &tv) <= 0) break;

        bool done = false;
        for (auto [from, to] : {std::pair{a, b}, std::pair{b, a}}) {
            if (!FD_ISSET(from, &readable)) continue;
            int n = recv(from, buffer, sizeof(buffer), 0);
            if (n <= 0) {
                done = true;
                break;
            }
            for (int sent = 0; sent < n;) {
                int m = send(to, buffer + sent, n - sent, 0);
                if (m <= 0) {
                    done = true;
                    break;
                }
                sent += m;
            }
            if (done) break;
        }
        if (done) break;
    }
    closesocket(a);
    closesocket(b);
}

/** Serves one relay client: header, pinned connect, pipe. */
void ServeClient(SOCKET client, std::string token) {
    std::string header;
    char c;
    while (header.size() < kMaxHeader && recv(client, &c, 1, 0) == 1 && c != '\n') header += c;

    std::istringstream fields(header);
    std::string got_token, ip;
    int port = 0;
    fields >> got_token >> ip >> port;
    if (got_token != token || ip.empty() || port <= 0 || port > 65535) {
        closesocket(client);
        return;
    }

    std::string outcome;
    SOCKET remote = ConnectPhysical(ip, port, kRelayConnectTimeoutMs, &outcome);
    if (remote == INVALID_SOCKET) {
        closesocket(client);
        return;
    }
    Pipe(client, remote);
}

std::string RandomToken() {
    unsigned char bytes[16];
    if (BCryptGenRandom(nullptr, bytes, sizeof(bytes), BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
        return {};
    }
    static const char* hex = "0123456789abcdef";
    std::string token;
    for (unsigned char b : bytes) {
        token += hex[b >> 4];
        token += hex[b & 15];
    }
    return token;
}

}  // namespace

PhysicalNet::PhysicalNet() : m_token(RandomToken()) {}

PhysicalNet::~PhysicalNet() {
    m_stopping = true;
    if (m_listener != INVALID_SOCKET) closesocket(static_cast<SOCKET>(m_listener));
    if (m_accept_thread.joinable()) m_accept_thread.join();
}

int PhysicalNet::RelayPort() {
    if (m_port != 0 || m_token.empty()) return m_port;
    EnsureWinsock();

    SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener == INVALID_SOCKET) return 0;
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    int length = sizeof(address);
    if (bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == SOCKET_ERROR ||
        listen(listener, 8) == SOCKET_ERROR ||
        getsockname(listener, reinterpret_cast<sockaddr*>(&address), &length) == SOCKET_ERROR) {
        closesocket(listener);
        return 0;
    }

    m_listener = static_cast<std::uintptr_t>(listener);
    m_port = ntohs(address.sin_port);
    m_accept_thread = std::thread(&PhysicalNet::AcceptLoop, this);
    return m_port;
}

void PhysicalNet::AcceptLoop() {
    while (!m_stopping) {
        SOCKET client = accept(static_cast<SOCKET>(m_listener), nullptr, nullptr);
        if (client == INVALID_SOCKET) {
            if (m_stopping) break;
            Sleep(100);
            continue;
        }
        std::thread(ServeClient, client, m_token).detach();
    }
}

std::string PhysicalNet::ProbeTcp(const std::string& ip, int port, int timeout_ms) {
    std::string outcome;
    SOCKET s = ConnectPhysical(ip, port, timeout_ms, &outcome);
    if (s != INVALID_SOCKET) closesocket(s);
    return outcome;
}

}  // namespace vpn_plugin
