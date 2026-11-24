# cattunnel-helper (Linux)

Русский: [HELPER.md](HELPER.md) (the Russian text is the main one; if the two differ, the Russian text is right)

The only part of CatTunnel for Linux that runs as root. The app runs as a normal user and asks the helper to start and stop the console client `trusttunnel_client` (as in [TrustTunnelClient](https://github.com/TrustTunnel/TrustTunnelClient), with CatTunnel patches). The client needs root for the TUN device, routes and DNS: it runs `ip` and `resolvectl` itself, so file capabilities on the binary are not enough. When the client cannot point the system resolver at the tunnel, the helper does it.

The helper is small: C++17 and POSIX, no Flutter or GTK. The only third-party parts, in `helper/third_party/`, are the nlohmann/json and toml++ headers.

## How it runs

- **A. systemd service.** `cattunnel-helper --system` (unit `cattunnel-helper.service`). Socket `/run/cattunnel/helper.sock`, mode 0660, group `cattunnel`. This is how the Arch and Debian packages work.
- **B. One user's session.** `cattunnel-helper --socket <path> --uid <uid>`. The socket is created 0600 and handed to that uid; the helper exits when the app closes its control connection. The app does not start this mode itself: it connects to the socket in `CATTUNNEL_HELPER_SOCKET` or, if unset, to `/run/cattunnel/helper.sock`. Mode B is for tests and manual runs.

The protocol is the same in both modes.

```text
 app (user)                      cattunnel-helper (root)           trusttunnel_client (root)
 ----------                      -----------------------           -------------------------
 {"cmd":"start","config":...} -> SO_PEERCRED check
                                 config allow-list check
                                 write /run/cattunnel/client.toml
                                 run: -c client.toml -l info   ->  brings up TUN, routes
                                 DNS: resolv.conf / NetworkManager
 {"ok":true}                  <-
 {"event":"state",...}        <- parse client output          <-   log lines
 {"cmd":"stop"}               -> SIGINT to the client, DNS back
```

Figure 1. The path of the `start` command from the app to the client.

## Packages

How the packages are built and installed is described in [linux/packaging/README.en.md](../../../linux/packaging/README.en.md). For the helper one thing matters: the package compiles it from source (`cmake`, `ninja`, `gcc`) and ships `trusttunnel_client` as a prebuilt binary whose hash is written into the `PKGBUILD`. Installed layout: the app in `/opt/cattunnel` (link `/usr/bin/cattunnel`), the helper and the client in `/usr/lib/cattunnel/`. The package does not enable the service or the group: the administrator runs `sudo usermod -aG cattunnel "$USER"` and `sudo systemctl enable --now cattunnel-helper`.

## Transport

- Unix stream socket. Every connection is checked with `SO_PEERCRED`. In mode A root and members of group `cattunnel` are accepted; in mode B only the `--uid` the helper was started for. Anything else is closed without a reply.
- Newline-delimited JSON, one object per line. A field of the wrong type is treated as absent. A line is at most 1200 KiB (a config of up to 1 MiB, JSON-escaped). A line not finished within 5 seconds drops the connection.
- One control connection per app. A second one gets `{"ok":false,"error":"busy"}`. `probe` and `relay` connections are separate (below).

## Control commands (app to helper)

| Request | Reply |
|---|---|
| `{"cmd":"hello","version":1}` | `{"ok":true,"version":1,"engine":"1.3.0-rc.1"}` (the engine version comes from the `ENGINE_VERSION` file at build time) |
| `{"cmd":"start","config":"<toml>","log_level":"info"}` | `{"ok":true}` or `{"ok":false,"error":"..."}`. Also an error when DNS could not be pointed at the tunnel: the client is stopped instead of running with a leak |
| `{"cmd":"stop"}` | `{"ok":true}` (SIGINT to the client, SIGTERM after 5 seconds, SIGKILL 2 seconds later) |
| `{"cmd":"state"}` | `{"state":"connected"}` |
| `{"cmd":"logs","max":500}` | `{"records":["2026-09-28T01:12:21.431 [info] ...", ...]}` (`max` from 0 to 5000) |
| `{"cmd":"probe_tcp","ip":"203.0.113.10","port":443,"timeout_ms":5000}` | `{"outcome":"ok"}` (`ok`, `timeout`, `refused` or `failed`) |

`log_level` accepts `debug` and `trace`; any other value becomes `info`.

Events (helper to app, on the control connection, unprompted):

- `{"event":"state","state":"connecting"}` for every client line `raise_state: VPN_SS_*`. The lines are parsed by `plugins/vpn_plugin/common/cli_output.h`, the same code as on Windows.
- `{"event":"failure","failure":"hello_no_answer"}` (`connect`, `hello_reset` or `hello_no_answer`) for a `[failure=...]` tag in the output of our engine. It is sent before the state change it explains. A TrustTunnel client without CatTunnel patches never writes this tag.
- `{"event":"diagnostic","diagnostic":"symptom=cut_after_bytes proto=h2 up=8200 ..."}` for a `NETDIAG ` line of our engine: what the last session to the server ended with. The app passes it to the diagnostics dialog.

Events can arrive between a request and its reply. Replies never carry an `event` key, so the app sets events aside while it waits.

States: `disconnected`, `connecting`, `connected`, `waiting_recovery`, `recovering`, `waiting_for_network` (the `VpnManagerState`).

## Diagnostics over the physical interface

While the tunnel is up, the app's checks and latency tests must still reach servers over the real network. The Dart side (`PhysicalNet`) opens new connections to the same socket for this, not the control connection. Each one is served in its own thread:

- `{"cmd":"probe","ip":"203.0.113.10","port":443,"timeout_ms":5000}`: the helper makes a TCP connection, answers `{"outcome":"ok"}` (or `timeout`, `refused`, `failed`) and closes. `timeout_ms` is limited to 100-10000.
- `{"cmd":"relay","ip":"203.0.113.10","port":443}`: the helper connects and then pipes bytes both ways (TLS runs end to end, from the app to the server). **Nothing** is sent back on success: the app starts TLS on the socket right away, and any reply would be read as the server's first bytes. On failure the helper just closes the connection. A connection with no data for 120 seconds is closed.

Connections are bound to the physical interface (`SO_BINDTODEVICE`): the non-TUN interface with the default route and the lowest metric in `/proc/net/route`. Only numeric addresses are accepted; the app resolves names before the tunnel starts. At most 32 `relay` and `probe` connections run at once (the unit has `TasksMax=64`); more are closed right away. While a tunnel is up, such connections are accepted from the session owner and root only.

The control connection's `probe_tcp` makes the same connection but blocks the helper's loop, so the app does not use it.

## What the helper refuses

Root must not do the app's bidding blindly.

- **Another user's session.** The owner of a tunnel is the uid that started it. `stop`, `logs` and `start` while the tunnel runs get "another user's session" for anyone but the owner and root. `state` and `hello` answer everyone. When the owner changes, the in-memory log is cleared.

The config is TOML that the client, as root, will act on. The helper parses it and rejects the start unless all of these hold:

- every key is on the allow-list of what the app's encoder writes (`lib/domain/configuration_codec.dart`) and has the expected type:
  - top level: `loglevel`, `vpn_mode`, `killswitch_enabled`, `post_quantum_group_enabled`, `exclusions`;
  - `[endpoint]`: `hostname`, `addresses`, `has_ipv6`, `username`, `password`, `client_random`, `client_random_auth_key`, `custom_sni`, `skip_verification`, `certificate` (inline PEM), `upstream_protocol`, `upstream_fallback_protocol`, `anti_dpi`, `anti_dpi_mode`, `anti_dpi_desync`, `tls_profile`, `h2_padding_frames`, `block_quic`, `dns_upstreams`, `name`;
  - `[endpoint]`, expert settings: `h2_padding_frames_min`, `h2_padding_per_stream`, `h2_padding_min_bytes`, `h2_padding_max_bytes`, `h2_padding_stream_bytes`, `h2_padding_session_bytes`, `keepalive_interval_secs`, `keepalive_signal`, `session_lifetime_secs`, `xhttp_enable`, `xhttp_path`;
  - `[listener.tun]`: `included_routes`, `excluded_routes`, `mtu_size`, `excluded_apps`, `included_apps`;
  - `[listener.socks]`: `address`, `username`, `password`;
- the numbers of the expert settings are within the engine's limits: padding frames 0-64, padding bytes 0-256, padding budgets up to 1048576, `keepalive_interval_secs` up to 3600, `session_lifetime_secs` up to 86400; `keepalive_signal` is `check` or `ping`; `xhttp_path` starts with `/`, is at most 256 characters, with no spaces or control characters;
- the `[listener.socks]` address is loopback only (`127.0.0.1:`, `[::1]:` or `localhost:`), otherwise root would open a proxy to the whole network;
- **no key names a file** (log file, certificate paths, anything not in the list above). A pinned certificate goes inline as PEM; the log goes to the helper's own file;
- sizes are sane: the config is at most 1 MiB, lists have at most 50 000 items.

The helper writes the accepted config to `/run/cattunnel/client.toml` (root, 0600) and starts `/usr/lib/cattunnel/trusttunnel_client -c /run/cattunnel/client.toml -l <level>`. The path is absolute, there is no `PATH` lookup, and the environment is clean (`PATH=/usr/sbin:/usr/bin:/sbin:/bin`, `LANG=C.UTF-8`). One client at a time: `start` while it runs is `stop` plus `start`.

The client binary is verified by hash when the package is built and installed root-owned, mode 0755.

## DNS without systemd-resolved

The client sets DNS only through `resolvectl` and just logs a warning if that fails, so without systemd-resolved queries would leave outside the tunnel. For the other setups the helper (`helper/system_dns.cpp`) points the resolver, for the session, at two service addresses that the engine answers itself through the tunnel (the `kTunnelDnsServers` list in `helper/system_dns.h`, the same addresses the client gives `resolvectl`).

- `/etc/resolv.conf` links to `/run/systemd/resolve/...` and resolved is active: the helper does nothing, the client handles DNS.
- NetworkManager is active (the Arch default): the helper writes a runtime file `/run/NetworkManager/conf.d/90-cattunnel-dns.conf` with `dns=none`, runs `nmcli general reload conf` and writes its own `resolv.conf`. On disconnect it puts the original back, removes the file and runs `nmcli general reload conf,dns-rc`.
- Otherwise: back up, replace, put back.

```text
 start                                   stop / client exited / helper crashed
   |                                                   |
   v                                                   v
 resolved owns resolv.conf? --yes--> nothing           Restore():
   | no                                                 reads /var/lib/cattunnel/resolv.conf.backup
   v                                                    puts back the link or the file
 SaveBackup()  (keeps an existing copy)                 removes the NetworkManager drop-in
   v                                                    nmcli general reload conf,dns-rc
 NetworkManager active? --yes--> drop-in dns=none + reload conf
   v
 write resolv.conf with the tunnel addresses  (failure: "DNS NOT SET", the client is stopped)
```

Figure 2. How the helper replaces and restores DNS.

The original is saved to `/var/lib/cattunnel/resolv.conf.backup` (on disk, so a crash plus a reboot does not lose it) and is never overwritten while it exists. At startup the helper restores leftovers and also cleans up routing table 880 and the `ip rule` entries that the client creates and may have failed to remove. The file in `/run` disappears on reboot, so a reboot alone gives NetworkManager its DNS back. NetworkManager profiles are never modified. Every step is a `=== CatTunnel: DNS ... ===` record in the log.

## Logs

The helper keeps the last ~2 MiB of client output in memory (records in the app's log format, `ToRecord` in `common/cli_output.h`) and writes them to `/var/log/cattunnel/client.log` (root-only file, the mode follows from `umask 0077`). Once the file is over 8 MiB it becomes `client.log.1`: one rotated file is kept. The app reads the records with `logs`.

## The app's side (vpn_plugin.cc, helper_client.cc)

The Linux plugin implements the Pigeon `IVpnManager` (GObject bindings in `platform_api.g.*`, generated from `pigeons/platform_api.dart`) on top of `HelperClient`.

- `start` and `stop` run in order on one background thread; the UI never waits for the helper. States come from the helper's events and go to Dart on the main loop (`vpn_plugin_event_channel`, as on Windows). `diagnostic` events use a separate channel, `vpn_plugin_event_channel_diagnostics`.
- On launch the plugin asks the helper for its state, so a tunnel left up by an earlier session shows as connected. Closing the window stops the VPN, as on Windows.
- If the helper is missing, not running or refuses the config, the state goes back to disconnected and the reason is logged with `g_warning` and put into the exported log (up to 100 records), so "Report a problem" shows it.
- `exportLogs` writes the app's own errors and the helper's last 5000 records to a temp file (records separated by 0x1E) in a new 0700 directory. `clearLogs` clears only the app's records: the engine log belongs to root and the helper bounds its size.
- Socket: `/run/cattunnel/helper.sock` or `$CATTUNNEL_HELPER_SOCKET`.

## Tests

`helper/CMakeLists.txt` builds two sets. `helper_tests` covers the config allow-list, starting the client, DNS and parsing the client output. `helper_client_tests` covers the client side of the protocol against a fake helper and against the real `cattunnel-helper` in mode B with a fake client (no root needed).
