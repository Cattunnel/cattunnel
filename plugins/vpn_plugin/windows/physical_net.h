// Copyright 2024 TrustTunnel contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

#pragma once

// No Winsock here: other plugin files include <windows.h> first, and
// <winsock2.h> after it doesn't compile. The listener is kept as the
// integer SOCKET is.
#include <atomic>
#include <cstdint>
#include <string>
#include <thread>

namespace vpn_plugin {

/**
 * Connections that must take the physical network even while the tunnel
 * holds the default route: the connection diagnostics ("is it the internet,
 * the server or the SNI?") and the server latency test. On Android the engine
 * leaves the app itself out of the tunnel; the Windows CLI can't, so these
 * sockets are pinned to the physical adapter with IP_UNICAST_IF (binding the
 * source address isn't enough - a full tunnel routes by destination).
 *
 * Dart can't set a socket option before connect, so the app talks to a small
 * relay on 127.0.0.1: it sends "<token> <ip> <port>\n", the relay opens the
 * pinned connection and pipes bytes both ways. TLS runs end to end over it.
 * The token keeps other local programs from using the relay to get around
 * the VPN.
 *
 * Not a way around the CLI's own firewall: with the kill switch on, Windows
 * Filtering Platform still drops what doesn't go through the tunnel.
 */
class PhysicalNet {
 public:
    PhysicalNet();
    ~PhysicalNet();

    PhysicalNet(const PhysicalNet&) = delete;
    PhysicalNet& operator=(const PhysicalNet&) = delete;

    /** Starts the relay on first use; 0 if it couldn't. */
    int RelayPort();

    const std::string& Token() const { return m_token; }

    /**
     * TCP connect to a numeric address over the physical adapter.
     * @return "ok", "timeout", "refused" or "failed".
     */
    static std::string ProbeTcp(const std::string& ip, int port, int timeout_ms);

 private:
    void AcceptLoop();

    std::string m_token;
    std::uintptr_t m_listener = ~std::uintptr_t{0};  // INVALID_SOCKET
    int m_port = 0;
    std::atomic<bool> m_stopping{false};
    std::thread m_accept_thread;
};

}  // namespace vpn_plugin
