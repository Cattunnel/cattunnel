#pragma once

#include <functional>
#include <string>
#include <vector>

namespace cattunnel_helper {

/**
 * The tunnel's DNS servers, as trusttunnel_client 1.1.7 hands them to
 * `resolvectl` (vpn_os_tunnel_settings_defaults: the engine answers queries
 * to these addresses itself, through the tunnel).
 */
inline const std::vector<std::string> kTunnelDnsServers = {"46.243.231.30", "46.243.231.31"};

/** Where things live; the defaults are the real system. */
struct DnsPaths {
    std::string resolv_conf = "/etc/resolv.conf";
    // On disk, not in /run: after a crash and a reboot we still know what to put back.
    std::string backup = "/var/lib/cattunnel/resolv.conf.backup";
    // In /run on purpose: a reboot drops it and NetworkManager is itself again.
    std::string nm_drop_in = "/run/NetworkManager/conf.d/90-cattunnel-dns.conf";
    std::string systemctl = "/usr/bin/systemctl";
    std::string nmcli = "/usr/bin/nmcli";
};

/** Runs argv[0] (an absolute path) with a clean environment. @return the exit code, -1 if it didn't run. */
using CommandRunner = std::function<int(const std::vector<std::string>& argv)>;
int RunCommand(const std::vector<std::string>& argv);

/**
 * What trusttunnel_client 1.1.7 removes on a clean shutdown (teardown_routes,
 * net/src/os_tunnel_linux.cpp): its routing table 880 and the ip rules that
 * send traffic there. A CLI that dies without that (its helper killed, then
 * the CLI itself) leaves them behind - harmless once the TUN is gone (an
 * empty table falls through to main), but not ours to leave. Errors are
 * ignored: usually there's nothing to remove. [ip] is the absolute path.
 */
void CleanUpCliRouting(const CommandRunner& run = RunCommand, const std::string& ip = "/usr/sbin/ip");

/**
 * Points the system resolver at the tunnel for the length of a session.
 * The CLI does this itself only through systemd-resolved; without it
 * (Arch with NetworkManager, a plain resolv.conf) nothing would, and queries
 * would leave outside the tunnel.
 *
 * - systemd-resolved owns /etc/resolv.conf: nothing to do, the CLI sets it.
 * - NetworkManager: a runtime drop-in `dns=none` stops it from rewriting
 *   resolv.conf mid-session; we write ours. Undo: drop-in removed,
 *   `nmcli general reload conf,dns-rc` - NetworkManager writes its own again.
 * - Otherwise: resolv.conf is backed up, replaced and put back.
 *
 * The user's NetworkManager profiles are never touched.
 */
class SystemDns {
 public:
    explicit SystemDns(DnsPaths paths = {}, CommandRunner run = RunCommand);

    /** @return a line for the log saying what was done (or what failed). */
    std::string Apply(const std::vector<std::string>& servers);

    /**
     * Undoes Apply - also what an earlier, crashed helper left behind, so it
     * is called at startup too. @return a log line, or empty if there was nothing to undo.
     */
    std::string Restore();

 private:
    bool ResolvedOwnsResolvConf() const;
    bool IsActive(const std::string& unit) const;
    bool SaveBackup(std::string* error) const;
    bool WriteResolvConf(const std::vector<std::string>& servers, std::string* error) const;

    DnsPaths paths_;
    CommandRunner run_;
};

}  // namespace cattunnel_helper
