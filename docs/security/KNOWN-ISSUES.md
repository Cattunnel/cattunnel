# CatTunnel Linux 1.4.5 (build 2013) — known issues (security audit in progress, 2026-09-29)

Pre-release for testing. Desktop security audit (skill security-audit, standard) is not finished: the items
below are candidates from hunters; independent verification is still pending. All will be fixed in the next build.
"Group" = members of `cattunnel` (on a single-user machine: only you and root).


> **2026-09-30:** items 1-7, DNS fail-open, helper restart on upgrade, log export dir and doc drift are fixed - see `linux.md` and `shared.md` (Russian). Later the same day: session ownership and relay/probe around another user's tunnel fixed too.
## Root helper (`cattunnel-helper`, socket /run/cattunnel/helper.sock)
1. **Crash on a wrong-typed JSON field** — reproduced in a sandbox (4/4). `{"cmd":1}` (or `port`/`max` as a
   string) -> uncaught nlohmann `type_error` -> SIGABRT; systemd restarts it. Who: a group member. Impact: DoS of
   the helper, crash skips clean teardown (the helper cleans DNS/rules on restart). Fix: type checks + try/catch.
2. **One idle peer stalls the helper** — reproduced. `ReadLine` blocks on the single poll loop while a peer
   withholds the newline; no replies/state events until it sends one. Who: a group member. Fix: non-blocking
   per-fd reads or SO_RCVTIMEO.
3. **Config allowlist bypass** — reproduced against `CheckConfig`. `[[listener.socks]]`/`[[listener]]`
   (array-of-tables), `address` as an array or missing, nested tables are accepted, so unreviewed keys and a
   non-loopback SOCKS address can reach the root CLI. Whether trusttunnel_client 1.1.7 honours those forms is
   unverified. Who: a group member. Fix: require exact node types, reject everything else.
4. **Unbounded on-disk log** — reproduced: /var/log/cattunnel/client.log grows without rotation (memory copy is
   bounded to 2 MiB). Fix: cap + one rotated file.
5. **Unbounded relay/probe threads** (needs validation) — one detached thread per connection, no cap; the unit
   sets no LimitNOFILE/TasksMax.
Checked clean: SO_PEERCRED + group auth, O_NOFOLLOW root files, fixed CLI path/clean env, DNS
(resolv.conf/NM drop-in) paths and restore, unit hardening, PKGBUILD pins.

## Shared code (all platforms, already in shipped versions)
6. **RU-list plausibility gaps** — reproduced with the production functions. The third-party lists (GitHub /
   jsDelivr, unsigned) are capped at 3% for IPv4 only: a poisoned IPv6 list can compile to `2000::/3` (all IPv6
   bypasses the tunnel); the domain list is filtered by a denylist, so arbitrary foreign domains
   (e.g. torproject.org, protonmail.com) can become "Russian" bypass rules. Needs a compromise of a list
   repository. Workaround: turn off "Russian services bypass". Fix: IPv6/aggregate caps, RU-TLD allowlist.
7. **Config encoder does not escape strings** (under review) — quotes/newlines in server fields are written raw
   into the engine TOML; on Linux the helper's allowlist limits the effect (see 3).

## Release process
8. **Package built in a Docker container on a LAN host** (`archlinux:latest`, then signed) — the signature
   vouches for what that host built. This build was made on our own trusted machine; if in doubt, rebuild from
   the same files with `makepkg -si` (PKGBUILD + sources, all sha256-pinned) — the root helper is compiled from
   `cattunnel-helper-src-1.4.5.tar.gz`, and you can read it.

Verify: `openssl pkeyutl -verify -pubin -inkey cattunnel-release.pub.pem -rawin -in SHA256SUMS -sigfile <(base64 -d SHA256SUMS.sig)`;
key fingerprint (sha256 of DER) `cec7226bb8218de67f02cf5992e3da7f54c3251d0ceade7e55c42cc7853a2f49` — confirm it with the owner by another channel.
