# Native TrustTunnelClient engine: our own build and patches

Русский: [README.md](README.md) (the Russian text is the main one; if the two differ, the Russian text is right)

CatTunnel does not run on the official [TrustTunnelClient](https://github.com/TrustTunnel/TrustTunnelClient) core but on our own build of the same core with patches. Since 1.5.7 every platform gets one base version, 1.3.0-rc.1 (the `ENGINE_VERSION` file at the repository root, the hashes of the official desktop archives in `ENGINE_SHA256`, version change with `tools/update_engine.sh <version>`). The core of app 1.5.9.5 and of the router is built from one revision, `b59debf4` (`1.3.0-rc.1-57-gb59debf4`, that is 57 commits on top of rc.1). In this repository the revision is written down only in the text of [docs/anti-dpi.md](../../docs/anti-dpi.md); it is pinned by the script `engine/build_router.sh` in the [cattunnel-router](https://github.com/Cattunnel/cattunnel-router) repository (the variables `REV` and `VERSION`; the build aborts if the revision differs).

The patches in this folder describe core 1.3.0-rc.1. The changes of revision `b59debf4` on top of them (connection pool, NineLives, padding shaper, browser-like `CONNECT` headers, IP rotation) have not been published here yet. For what the core does at the protocol level, see [docs/](../../docs/).

The main change in this folder concerns how the first packet of a TLS connection (the ClientHello) goes onto the network. The packet stays one TLS record, so the server needs no change, but a provider's filter sees it cut up or out of order. The techniques are borrowed from [ByeDPI](https://github.com/hufrea/byedpi) (MIT, © 2024 hufrea); the modes and the custom string are described in [docs/anti-dpi.md](../../docs/anti-dpi.md).

## What is in the folder

| Path | Purpose |
|---|---|
| `rc1/0001-cattunnel-core.patch` | the main patch for 1.3.0-rc.1: anti-DPI (modes 1-3, custom string), failure reasons and pauses before a retry, HTTP/2 padding, QUIC blocking, a network monitor aware of policy routing |
| `rc1/0002-desktop-per-app-split.patch` | per-program split tunnelling on Windows and Linux (`excluded_apps`, `included_apps`) |
| `0001-anti-dpi-desync.patch` | an earlier form of the anti-DPI patch for a different core base: `build_linux.sh` takes tag v1.1.7, the header of `router/build_router.sh` names v1.3.0-beta.1. For 1.3.0-rc.1 use `rc1/` |
| `build_linux.sh` | the recipe for the dependencies and the client on Linux x86_64 (clang, libstdc++, conan) |
| `build_android.sh` | builds `libtrusttunnel_android.so`, which `tools/engine_patch/build.sh` puts into the AAR instead of the official one |
| `windows/build_rc1.cmd` | builds the Windows console client (MSVC) from tag v1.3.0-rc.1 with the `rc1/` patches |
| `router/` | the router build through zig (`build_router.sh`), zig patches, and the network monitor patch for a base without `rc1/` (`0002-network-monitor-policy-routing.patch`) |

## Building

On Windows the order is fixed in `windows/build_rc1.cmd`: clone tag `v1.3.0-rc.1`, run `git apply --index` for every `0*.patch` in the patch folder, build the dependencies with `scripts/bootstrap_conan_deps.py`, then `cmake` and `ninja` with target `trusttunnel_client`.

`build_linux.sh` does the following for Linux. It takes `conan` and `cargo` from the build directory, clones `TrustTunnelClient` at tag `v1.1.7` and does not apply patches to it itself. It builds the dependencies with `scripts/bootstrap_conan_deps.py` without AdGuard's private conan repository. Last, it re-exports NativeLibsCommon v8.1.52 (the boringssl recipe). Then `cmake` with `clang`, `libstdc++11` and `-DDISABLE_HTTP3=OFF`, and the target `trusttunnel_client`. The Linux package build takes a finished binary as input (`ENGINE_BIN`) and checks that it contains the string `Anti-DPI mode` (`linux/packaging/build_release.sh`).

Android needs everything Linux needs, plus NDK 29.0.14206865, JDK 17, the Rust targets for the four Android ABIs and `cargo-ndk`. `TT_ABIS` narrows the ABI list (default `arm64-v8a`). The script runs `assembleRelease` in a clean tree (`TT_SRC`), copies `libtrusttunnel_android.so` and prints the next command: `NATIVE_JNI=<directory> tools/engine_patch/build.sh`. A cold build of one ABI takes about 25 minutes (a comment in the script).

Routers need zig 0.17.0, conan 2.31.1, NativeLibsCommon v8.1.52 and DnsLibs v2.10.2 from source with the patches in `router/` (nested dependency builds do not recognise the zig wrapper). `router/build_router.sh [arch...]` accepts `x86_64`, `aarch64`, `armv7`, `mips`, `mipsel` (default `aarch64 mipsel armv7`), builds static musl binaries and checks that each contains the string `Anti-DPI mode`. The first build per architecture takes 30-40 minutes (a comment in the script), later ones minutes. The script in the router repository (`engine/build_router.sh`) already builds revision `b59debf4`.

```text
 TrustTunnelClient tag v1.3.0-rc.1
        |  git apply rc1/0001-cattunnel-core.patch, rc1/0002-desktop-per-app-split.patch
        v
 tree with CatTunnel patches
        |-- cmake + ninja (Windows, MSVC)      -> trusttunnel_client.exe
        |-- cmake + ninja (Linux, clang)       -> trusttunnel_client  -> Arch and Debian packages
        |-- gradle + cargo-ndk (build_android) -> libtrusttunnel_android.so -> AAR (tools/engine_patch)
        |-- zig + cmake (router/build_router)  -> static binaries for routers
```

Figure 1. Where the core for each platform comes from.

## Anti-DPI modes

The `anti_dpi_mode` key in the TOML (with `anti_dpi = true`, clamped to 0-3) reaches the TCP socket parameters and the pinger (`ping.cpp`, `locations_pinger`). The sending itself is done by `desync_write` in `net/src/tcp_socket.cpp`.

- Mode 0 repeats the original core: the first byte, a 25 ms pause, the rest.
- Mode 1 (`-o3 -d7` in ByeDPI syntax): an urgent byte after the third byte, then bytes 4 to 7 with TTL 1.
- Mode 2 (`-d7`): the first 7 bytes with TTL 1.
- Mode 3 (`-o1+s -d3+s`): an urgent byte and a TTL 1 piece inside the server name (SNI).

The `anti_dpi_desync` key takes a custom string of `-s<n>` (a plain TCP split), `-o<n>` (urgent data) and `-d<n>` (TTL 1); the position counts from the start of the record, from its end if negative, or from the server name with the suffix `+s`. A non-empty string replaces `anti_dpi_mode`. Not accepted: `-r` (a TLS record split: the server refuses it) and `-o` without a `-d` after it.

A TTL 1 piece dies on the first router, the operating system retransmits it with the normal TTL, and the filter sees the rest of the stream before the beginning.

```text
 ClientHello (one TLS record), mode 1
   [bytes 1-3] + 1 urgent byte   --send(MSG_OOB)-->
        wait for the previous piece to be acknowledged (up to 500 ms)
   [bytes 4-7]  --sent with TTL 1--> dies on the first router
        TTL set back to the previous value
   [the rest]   --normal send-->     the OS retransmits the lost piece with the normal TTL
```

Figure 2. The order in which the ClientHello is sent in mode 1.

A lone urgent byte without a TTL 1 piece after it is not allowed. According to a comment in `desync_write`, a TrustTunnel server on tokio reads up to the urgent mark, the short read is taken as an empty socket, and the rest of the ClientHello, already queued, wakes nobody. The parser rejects such a plan, and if the TTL 1 partner is dropped because of record bounds, the urgent piece goes out as a plain split. The retransmitted TTL 1 piece arrives later and wakes the server.

Other keys of the patch: `h2_padding_frames` (0-64: the first HTTP/2 frames of a session get random padding of up to 255 bytes, the PADDED mechanism of RFC 9113) and `block_quic` (below).

## Linux and Android specifics

The OS kernel may hold back a TTL 1 piece sent right after a packet with an urgent byte (TCP small queues, seen on a Galaxy S22) and send it only after the normal TTL is restored. The fix follows sing-box: before each next piece, wait for the acknowledgement (`TCP_INFO.tcpi_unacked == 0`, at most 500 ms). It works on Linux and Android. The TTL is then restored once the kernel reports an empty queue (up to 20 ms): on Linux through the `SIOCOUTQNSD` request, and on Android, where SELinux denies that request to apps, through the `tcpi_notsent_bytes` field. On Windows neither is measured, and fixed pauses of 10 and 50 ms stand in.

## Failure reasons and pauses

The core tells three reasons for a failed ping apart and writes them to the log as a `[failure=...]` tag: `connect` (no TCP connection, or QUIC failed), `hello_reset` (the ClientHello went out, the connection was reset) and `hello_no_answer` (the ClientHello went out, no answer: what a filter "freezing" the address looks like). Before the next handshake the core waits at least 60 seconds after `hello_no_answer` and 5 seconds after `hello_reset`; after `connect` there is no extra pause. The app reads the tag to tell the user what to do.

## QUIC blocking

The `block_quic = true` key in the TOML passes through `VpnUpstreamConfig` and `EndpointConnectionConfig` to `Tunnel::finalize_connect_action`, where UDP to port 443 gets `VPN_CA_REJECT`. After the refusal browsers fall back to TCP inside the tunnel. The behaviour is covered by the test `TunnelTest.BlockQuic` (`core/test/test_tunnel.cpp`).

## Per-program split tunnelling

The `rc1/0002` patch adds the keys `excluded_apps` and `included_apps` to `[listener.tun]` (executable names or full paths). Programs in `excluded_apps` go directly; with a non-empty `included_apps` only the listed programs go through the tunnel. `process_owner.cpp` finds the socket owner: on Windows through `GetExtendedTcpTable` and `GetExtendedUdpTable`, on Linux through `NETLINK_SOCK_DIAG` and `/proc/<pid>/fd`; no driver is needed.

## Network monitor on routers and Android

The NativeLibsCommon network monitor on Linux looked for the default route only in table `main`. With policy routing (Android, many routers) routes live in separate tables, and after any address or route event the client decided there was no network (`VPN_SS_WAITING_FOR_NETWORK`) and never left that state by itself. The patch makes `AutoNetworkMonitor` ask the OS kernel directly: a UDP socket `connect` to 8.8.8.8 (to `2001:4860:4860::8888` if that fails) and `getsockname`, with the rules taken into account. If a route exists, "no network" is not reported, and a reconnect happens only when the outgoing address changes. This fix is already inside `rc1/0001`; the separate `router/0002-network-monitor-policy-routing.patch` is for a base without `rc1/`.
