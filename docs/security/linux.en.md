Русский: [linux.md](linux.md) (the Russian text is the main one; if the two differ, the Russian text is right)

# Linux: security (fixes)

This page covers the findings of an internal audit of the desktop clients, made on the Linux 1.4.5 build: the list and the outcome are in [KNOWN-ISSUES.en.md](KNOWN-ISSUES.en.md). Every fix in the table is present in the 1.5.9.5 code. The helper's design and protocol: [plugins/vpn_plugin/linux/HELPER.en.md](../../plugins/vpn_plugin/linux/HELPER.en.md).

On Linux only a small helper, `cattunnel-helper` (sources in `plugins/vpn_plugin/linux/helper/`), and the client core it starts run as root. The app runs as a normal user and talks to the helper through the socket `/run/cattunnel/helper.sock`.

```text
 app (user)
        |  socket /run/cattunnel/helper.sock, group cattunnel
        v
 cattunnel-helper (root)
   |-- client check: SO_PEERCRED, group
   |-- config check: allowlist of keys and types (config_guard)
   |-- starts the trusttunnel_client core by a fixed path
   |-- replaces DNS for the session, restores it on stop
   '-- relay / probe: diagnostics outside the tunnel
```

Figure 1. What the helper does and where the checks stand.

| # | Problem | Fix | Where in the code |
|---|---------|-----|-------------------|
| 1 | A JSON field of the wrong type (`{"cmd":1}`) crashed the root helper (uncaught exception, SIGABRT) | `Str` and `Int`: a wrong type means "no such field", numbers are clamped to a range; request handling is wrapped in try/catch | `helper/main.cpp` |
| 2 | A "silent" client froze the helper's single loop (`ReadLine`) | `SO_RCVTIMEO` of 5 s on accepted sockets (lifted for relay and probe) | `helper/main.cpp`, `kReadTimeoutSeconds` |
| 3 | The config allowlist let through `[[listener.socks]]`, arrays instead of strings, nested tables | a schema with the type of every key; `[listener.socks]` only with a loopback address | `helper/config_guard.cpp`, test `CheckConfig.RefusesOtherShapesAndTypes` |
| 4 | The log `/var/log/cattunnel/client.log` grew without a limit | over 8 MiB the file is renamed to `client.log.1` (one rotation); the in memory copy is capped at 2 MiB | `helper/cli_runner.cpp` |
| 5 | relay and probe threads without a limit | at most 32 at once; the unit sets `TasksMax=64` and `LimitNOFILE=1024` | `helper/main.cpp`, `linux/packaging/cattunnel-helper.service` |
| 6 | A DNS error did not stop the connection (fail open) | on `start`, if `resolv.conf` was not replaced ("DNS NOT SET"), the core is stopped, DNS is rolled back and the app gets an error | `helper/main.cpp`, `helper/system_dns.cpp` |
| 7 | A package upgrade did not restart the helper | `post_upgrade`: `daemon-reload` and a restart if the VPN is not up right now; otherwise a hint | `linux/packaging/cattunnel.install` |
| 8 | Log export into a predictable directory `/tmp/cattunnel_linux_logs_<time>` | `g_dir_make_tmp`: a random name, mode 0700 | `plugins/vpn_plugin/linux/vpn_plugin.cc` |
| 9 | HELPER.md disagreed with the code | fixed: lines up to 1200 KiB, log mode 0600, limits, fail closed | `plugins/vpn_plugin/linux/HELPER.md` |
| 10 | No session "owner": any group member could stop someone else's tunnel, replace it with their own or read its log | the owner is the user who started the tunnel. `stop`, `logs` and `start` over a running tunnel are allowed only to the owner and root; when the owner changes, the in memory log is cleared | `helper/main.cpp`, `IsOwner` |
| 11 | relay and probe led to any address around someone else's tunnel | while a tunnel is up they are available only to the owner and root. Without a tunnel there is nothing to bypass, and diagnostics work as before | `helper/main.cpp` |

**Still open.** The session owner can use relay and probe to reach any address outside their own tunnel: this is how the diagnostics of Marsik (the app's cat helper) are designed, to check servers and reference addresses. The log on disk (`/var/log/cattunnel/client.log`, root, mode 0600) is shared by all sessions.
