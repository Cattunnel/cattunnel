# cattunnel-helper (Linux)

The only part of CatTunnel for Linux that runs as root. The app (a normal
user process) asks it to start and stop the public `trusttunnel_client` CLI,
which needs root for the TUN device, routes and DNS (it runs `ip` and
`resolvectl` itself, so file capabilities on the CLI are not enough),
and points the system resolver at the tunnel when the CLI can't.

Kept small on purpose so it can be read in one sitting: no Flutter, no GTK,
C++17 + POSIX, the TOML parser is the only dependency.

Draft, 2026-09-28. Two ways to run it are still open (the second admin
decides, see ~/cattunnel_linux_plan.md, sections 3 and 13):

- **A. systemd service**: `cattunnel-helper.service` as root, socket
  `/run/cattunnel/helper.sock`, mode 0660, group `cattunnel`.
- **B. pkexec per session**: the app runs
  `pkexec /usr/lib/cattunnel/cattunnel-helper --socket <path> --uid <uid>`;
  socket in `$XDG_RUNTIME_DIR/cattunnel/` (0700 directory); the helper exits
  when the app's connection closes.

The protocol below is the same for both.

## Packaging (Arch)

`linux/packaging/build_release.sh <version> <build>` builds the app and
writes `build/arch/`: the app bundle, a `git archive` of the helper sources
and packaging files, and a PKGBUILD that compiles the helper from that
archive and fetches `trusttunnel_client` from the public release (sha256
from ENGINE_SHA256). Installed layout: app in `/opt/cattunnel`
(`/usr/bin/cattunnel`), helper and CLI in `/usr/lib/cattunnel/`,
`cattunnel-helper.service` (hardened; `systemd-analyze security`: 4.6 OK),
group `cattunnel` (sysusers), `com.cattunnel.app.desktop` with the
`tt://` handler. Enabling the service and joining the group are left to the
admin (the install message says how).

## Transport

- Unix stream socket. Every connection is checked with `SO_PEERCRED`: A
  accepts members of group `cattunnel`, B only the `--uid` it was started
  for. Anything else is closed without a reply.
- Newline-delimited JSON, one object per line (a field of the wrong type is
  treated as absent), at most 1200 KiB per line (a 1 MiB config, JSON-escaped); a line not finished within 5 s drops the connection
  (the config with the Russian lists is ~150 KiB).
- One *control* connection per app. *Relay* connections are separate (below).

## Control commands (app → helper)

| Request | Reply |
|---|---|
| `{"cmd":"hello","version":1}` | `{"ok":true,"version":1,"engine":"1.1.7"}` |
| `{"cmd":"start","config":"<toml>","log_level":"info"}` | `{"ok":true}` or `{"ok":false,"error":"..."}` - also when DNS can't be pointed at the tunnel (the CLI is stopped: fail closed) |
| `{"cmd":"stop"}` | `{"ok":true}` (Ctrl+C = SIGINT to the CLI, SIGTERM after 5 s) |
| `{"cmd":"state"}` | `{"state":"connected"}` |
| `{"cmd":"logs","max":500}` | `{"records":["2026-09-28T01:12:21.431 [info] ...", ...]}` |
| `{"cmd":"probe_tcp","ip":"1.2.3.4","port":443,"timeout_ms":5000}` | `{"outcome":"ok"}` (`ok` / `timeout` / `refused` / `failed`) |

Events (helper → app, on the control connection, unprompted):
`{"event":"state","state":"connecting"}` for every `raise_state: VPN_SS_*`
line of the CLI (parsed by `common/cli_output.h`, same as Windows).
`{"event":"failure","failure":"hello_no_answer"}` (`connect` /
`hello_reset` / `hello_no_answer`) for a `[failure=...]` tag of our engine
build, sent before the state change it explains; the official CLI never
writes one.

Events can arrive between a request and its reply; replies never carry an
`event` key, so the app sets events aside while it waits.

States: `disconnected`, `connecting`, `connected`, `waiting_recovery`,
`recovering`, `waiting_for_network` (= VpnManagerState).

## Diagnostics over the physical interface

While the tunnel is up, the app's diagnostics and latency tests must still
reach servers over the real network. The Dart side (`PhysicalNet`) opens
new connections to the same socket for this (not the control connection),
each handled in its own thread:

- `{"cmd":"probe","ip":"1.2.3.4","port":443,"timeout_ms":5000}` - a TCP
  connect; the helper answers `{"outcome":"ok"}` (`ok` / `timeout` /
  `refused` / `failed`) and closes.
- `{"cmd":"relay","ip":"1.2.3.4","port":443}` - the helper connects and then
  pipes raw bytes both ways (TLS runs end to end, from the app). **Nothing**
  is sent back on success: the app starts TLS on the socket right away, and
  any reply would be read as the server's first bytes. On failure the
  helper just closes the connection.

Connections are bound to the physical interface (`SO_BINDTODEVICE`, the
non-tun interface with the default route, `/proc/net/route`). Same idea as
the Windows `PhysicalNet` relay, without the token: `SO_PEERCRED` already
says who is asking. Numeric addresses only; the app resolves names before
the tunnel starts. At most 32 relay/probe connections at once (the unit
has `TasksMax=64`); more are closed right away.

The control connection's `probe_tcp` does the same connect but blocks the
helper's loop, so the app doesn't use it.

## What the helper refuses (root must not do the app's bidding blindly)

- **Another user's session.** The uid that started the tunnel owns it:
  `stop`, `logs`, and `start` while it runs are refused ("another user's
  session") for anyone but the owner and root; `state`/`hello` still answer.
  While a tunnel is up, `relay`/`probe` connections are accepted from the
  owner and root only. A new owner starts with an empty in-memory log.

The config is TOML that the CLI, as root, will act on. The helper parses it
and rejects the start unless:

- every key is on the allow-list of what the app's encoder writes
  (`lib/domain/configuration_codec.dart`): top level `loglevel`, `vpn_mode`,
  `killswitch_enabled`, `post_quantum_group_enabled`, `exclusions`;
  `[endpoint]` `hostname`, `addresses`, `has_ipv6`, `username`, `password`,
  `custom_sni`, `client_random`, `skip_verification`, `certificate` (inline
  PEM), `upstream_protocol`, `upstream_fallback_protocol`, `anti_dpi`,
  `dns_upstreams`; `[listener.tun]` `included_routes`, `excluded_routes`,
  `mtu_size`, `excluded_apps`, `included_apps`; `[listener.socks]`
  `address`, `username`, `password`;
- a `[listener.socks]` address is on loopback only (`127.0.0.1` / `[::1]`) -
  otherwise root would open a proxy to the whole LAN;
- **no key names a file** (logfile, certificate *paths*, anything ending in
  `_path`/`_file`); a pinned certificate goes inline as PEM, the log goes to
  the helper's own file;
- sizes are sane (config ≤ 1 MiB, ≤ 50 000 exclusions).

The helper writes the accepted config to `/run/cattunnel/client.toml`
(root, 0600) and starts `/usr/lib/cattunnel/trusttunnel_client -c
/run/cattunnel/client.toml`: absolute paths only, no `PATH` lookup, a clean
environment. One CLI at a time; `start` while running = `stop` + `start`.

The CLI binary itself is verified at package build time (sha256 pinned in
ENGINE_SHA256, like the Windows build) and installed root-owned 0755.

## DNS without systemd-resolved

The CLI sets DNS only through `resolvectl` and just logs a warning if that
fails, so without systemd-resolved queries would leave outside the tunnel.
The helper (`system_dns.cpp`) covers the other setups for each session,
pointing the resolver at the engine's addresses `46.243.231.30/31` (what
the CLI would give resolvectl):

- `/etc/resolv.conf` links to `/run/systemd/resolve/...` and resolved is
  active: nothing to do, the CLI handles it.
- NetworkManager active (Arch default): a runtime drop-in
  `/run/NetworkManager/conf.d/90-cattunnel-dns.conf` with `dns=none` +
  `nmcli general reload conf`, then our resolv.conf. On disconnect: the
  original back, drop-in removed, `nmcli general reload conf,dns-rc`.
- Otherwise: back up, replace, put back.

The original is saved to `/var/lib/cattunnel/resolv.conf.backup` (on disk:
a crash plus a reboot must not lose it) and never overwritten while it
exists; the helper restores leftovers at startup. The drop-in lives in
`/run`, so a reboot alone gives NetworkManager its DNS back. NetworkManager
profiles are never modified. Every step is a `=== CatTunnel: DNS ... ===`
record in the log.

## Logs

The helper keeps the last ~2 MiB of CLI output (records in the app's log
format, `common/cli_output.h` `ToRecord`) in memory and in
`/var/log/cattunnel/client.log` (root 0600; over 8 MiB it becomes
`client.log.1`, one rotated file). The app
reads them with `logs`; passwords never appear in CLI output at the `info`
level (checked on Windows).

## The app's side (vpn_plugin.cc, helper_client.cc)

The Linux plugin implements the Pigeon `IVpnManager` (GObject bindings in
`platform_api.g.*`, generated from `pigeons/platform_api.dart`) on top of
`HelperClient`:

- `start` / `stop` run on one background thread, in order; the UI never
  waits for the helper. States come from the helper's events and go to Dart
  on the main loop (`vpn_plugin_event_channel`, as on Windows).
- On launch the plugin asks the helper for its state, so a tunnel left up by
  an earlier session shows as connected. Closing the window stops the VPN,
  like on Windows.
- If the helper is missing, not running or refuses the config, the state
  goes back to disconnected and the reason is logged (`g_warning`) and put
  into the exported log, so "Report a problem" shows it.
- `exportLogs` writes our own errors plus the helper's last 5000 records to
  a temp file (records separated by 0x1E); `clearLogs` clears only ours -
  the engine log belongs to root and the helper bounds its size.
- Socket: `/run/cattunnel/helper.sock` (systemd service), or
  `$CATTUNNEL_HELPER_SOCKET` (tests, a per-session helper).

Tests: `helper/CMakeLists.txt` builds `helper_client_tests` - the client
against a fake helper and against the real `cattunnel-helper` in its
per-session mode with a fake CLI (no root needed).
