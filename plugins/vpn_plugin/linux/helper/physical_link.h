#pragma once

#include <string>

namespace cattunnel_helper {

/**
 * The interface traffic took before the tunnel: a default route in
 * /proc/net/route whose interface isn't a TUN device (type 65534 in
 * /sys/class/net/<if>/type), lowest metric. Empty if none.
 */
std::string PhysicalInterface();

/**
 * TCP connect to a numeric [ip]:[port] pinned to [iface] (SO_BINDTODEVICE -
 * root only). An empty [iface] connects normally.
 * @param outcome "ok", "timeout", "refused" or "failed".
 * @return The connected blocking socket, or -1.
 */
int ConnectPinned(const std::string& ip, int port, int timeout_ms, const std::string& iface, std::string* outcome);

/** Copies bytes both ways until either side closes; closes both. */
void Pipe(int a, int b);

}  // namespace cattunnel_helper
