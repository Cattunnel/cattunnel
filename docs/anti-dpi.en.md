Русский: [anti-dpi.md](anti-dpi.md) (the Russian text is the main one; if the two differ, the Russian text is right)

# Anti-DPI in CatTunnel

The provider's filter (TSPU) reads the server name (SNI) in the first packet of a TLS connection, the ClientHello. Anti-DPI changes only how that packet goes out onto the network. The ClientHello itself stays one TLS record, so the server needs no changes.

It works with HTTP/2 (TCP) only. For HTTP/3 (QUIC) the setting has no effect.

The implementation lives in the native client core, a CatTunnel build of TrustTunnelClient (revision `b59debf4` in 1.5.9.5): the functions `desync_write` and `desync_plan_parse` in `net/src/tcp_socket.cpp`. TrustTunnel splits the packet in one way only: the first byte, a 25 ms pause, the rest. Everything else on this page is added by CatTunnel. The techniques are borrowed from [ByeDPI](https://github.com/hufrea/byedpi) (MIT, © 2024 hufrea).

Patches for the 1.3.0-rc.1 core are in [tools/engine_native/](../tools/engine_native/README.md) (the first anti-DPI version is `0001-anti-dpi-desync.patch`, the rest is in `rc1/`). The 1.5.9.5 changes on top of them are not published in this repository yet.

## Modes

The mode is chosen in the key settings, section "Censorship bypass", menu "Anti-DPI".

| Item | In the app database (`anti_dpi`, `anti_dpi_mode`) | What the core gets | What it does |
|---|---|---|---|
| Off | `false`, 0 | nothing | the packet goes out whole |
| Normal | `true`, 0 | `anti_dpi = true` | as in TrustTunnel: first byte, 25 ms pause, the rest |
| Auto | `true`, 4 | `anti_dpi_mode` 1, 2 or 3 | the app tries the techniques and remembers the one that works (see "Auto mode") |
| 1 | `true`, 1 | `anti_dpi_mode = 1` | `-o3 -d7` |
| 2 | `true`, 2 | `anti_dpi_mode = 2` | `-d7` |
| 3 | `true`, 3 | `anti_dpi_mode = 3` | `-o1+s -d3+s` |
| Custom string | `true`, 5 and `anti_dpi_desync` | `anti_dpi_desync = "…"` | see below |

In the core, modes 1 to 3 are ready-made strings, so they and the custom string run through the same code.

```text
 ClientHello, one TLS record:
 [ header ... | SNI: www.example.com | ... ]
        |
        +-- -d N  the part up to N goes out with TTL 1: it is lost at the
        |         first router, the OS sends it again later
        +-- -o N  the part up to N plus an "urgent" byte that the
        |         receiver's OS removes from the stream
        +-- -s N  a plain TCP split
 the filter sees the parts out of order and cannot assemble the name,
 the server receives the same record whole
```

Figure 1. Three ways to cut the ClientHello. The record stays whole, only the way it goes out changes.

## Custom string

Parts are separated by spaces and run in order, at most eight parts.

- `-s N`: a plain TCP split after byte N.
- `-o N`: a split with an urgent byte. The part up to N goes out through `send(MSG_OOB)` together with one extra byte, which the receiving OS kernel removes from the stream.
- `-d N`: the part up to byte N goes out with TTL (hop limit) 1. It is lost at the first router, then the OS sends it again with the normal TTL, so the filter sees the rest of the stream before the beginning.

N counts from the start of the TLS record. A negative N counts from its end. With the suffix `+s` or `+h` (the same thing for TLS) it counts from the start of the server name in the SNI. Numbers from -1500 to 1500 are valid. If the packet has no SNI and the string has positions with `+s`, mode 1 is used. Parts that do not fall strictly inside the record after the previous one are skipped.

Limits:

- `-r` (splitting into TLS records) is not accepted: the TrustTunnel server drops such a connection. The [CatTunnel server](https://github.com/Cattunnel/cattunnel-server) can join a ClientHello from several records, but the client does not use that.
- `-o` without a `-d` after it is not accepted. The TrustTunnel server, built on tokio, hangs in this case: reading stops at the urgent mark, tokio treats the socket as empty, and the rest is already in the queue, so no new event comes. The later resend of the TTL 1 part wakes the server. If the `-d` after an `-o` drops out when a particular packet is cut (its position did not fall inside the record), that `-o` goes out as a plain split.
- Other ByeDPI techniques (`-f` with a fake packet, `-q`, `-m` and others) are not supported. Zapret techniques that need raw packets (seqovl, badseq, badsum, md5sig, fake segments with the same seq) are not available to an app without root.

Examples: `-o1+s -d3+s` (mode 3), `-d7` (mode 2), `-o3 -d7` (mode 1), `-s1 -d3+s`.

Three sets of the same rules check the string: `DesyncString.validate` (the plugin, the key form, links), `desync_plan_parse` (the core), and tests on both sides (`plugins/vpn_plugin/test/desync_string_test.dart`, `net/test/test_desync_plan.cpp` in the core). The core rejects a key with a wrong string as a whole and does not connect silently without the bypass. It does not get that far: the form does not save such a string, and links and subscriptions drop a wrong one.

## Auto mode

Auto (4) is resolved by the app itself, the core gets one of the techniques 1 to 3. One connection attempt tries at most two techniques. The one that worked in this network today goes first, then the others, starting where the previous round stopped. If a technique does not fit, the app stops the tunnel, waits 1.5 s and starts the next one. Each technique gets 6 seconds.

The network is recognized by its gateway and DNS. What worked in a network is remembered until local midnight.

The app looks at the failure reason the core reports (see "Failures and the freeze"):

- `hello_reset` and `hello_no_answer` mean the path is being cut: the app moves to the next technique.
- `connect` (TCP was not established) or silence for more than 6 seconds: the round ends, the core keeps going with the same technique and keeps its own pauses.
- If the address is "frozen" (the last failure was `hello_no_answer` less than two minutes ago), a new start tries one technique only: one more handshake into a freeze only extends it.

## When the bypass turns on

Since 1.5.8.10 the automatic bypass is off by default. In "Settings → Launch and connection" there are two switches: "Automatic blocking bypass: subscription keys" and "Automatic blocking bypass: personal keys". The first is turned on by hand and lasts until the end of the day, the second stays on until it is turned off.

For a key without anti-DPI, an enabled switch means: the app connects normally first and tries the techniques only if the network cuts the path. If the key itself asks for anti-DPI or has "Override subscription" on, the key decides, not the switch.

## TLS profile

The TLS profile (key `tls_profile`, tag `0x42`) sets which ClientHello the client resembles: "Like the default browser" (the default), Chrome 157, Firefox 160 or "Like an Android app". Without an explicit choice the app detects the device's default browser once (Chrome or Firefox), remembers the choice and does not change it later. A button in the key form detects the browser again.

| Value the app writes | JA4 of the ClientHello |
|---|---|
| `chrome` | `t13d1517h2_8daaf6152771_cb7bf5808d99` |
| `chrome_canary` | the same as `chrome` |
| `firefox` | `t13d1517h2_8daaf6152771_3cbfd9057e0d` |
| `okhttp` | `t13d1613h2_46e7e9700bed_eca864cca44a` |

The core also knows `openssl` and `default`, but they look like no browser, and the app does not write them.

## Connection pool

App connections go through 2 to 4 TLS connections to the server. The next one opens when each existing one already carries 24 to 48 streams. Between new handshakes there is a pause of 2 to 6 s, at most three per minute. The main connection carries 70 to 95 % of new streams. In TrustTunnel the pool could open up to eight connections within seconds, and such a burst of handshakes can itself be a signal for a filter.

```text
 app connections (CONNECT streams)
   | | | | | | | |
   v v v v v v v v
 [TLS 1: 70-95 % of streams] [TLS 2] [TLS 3] [TLS 4]
   a new TLS opens when each carries 24-48 streams,
   2-6 s between handshakes, at most 3 per minute
```

Figure 2. The TLS connection pool of one key.

## TLS authorization key

Instead of a fixed prefix in `client_random` (32 bytes), each connection takes the first 16 bytes at random (a salt) and computes the second 16 from the authorization key, the salt and the SNI. To an observer the field still looks random. The key is set by the `client_random_auth_key` parameter (link tag `0x0F`, as in TrustTunnel 1.3), at least 16 bytes written in hexadecimal. The key is not supported on mips and mipsel routers: the core there is built with OpenSSL, and access is decided by login and password.

## Where the setting comes from

- The key form saves the string in normalized form (single spaces).
- A `tt://` link: tag `0x41` is the mode (1 to 4), `0x42` the TLS profile, `0x43` the custom string (UTF-8). Without the tag the app keeps the user's choice. Older app versions skip unknown tags.
- A subscription writes every link value into its keys on each update, switched-off ones included. It does not touch a key with the "Override subscription" switch ([subscriptions.en.md](subscriptions.en.md)).
- The problem report shows the mode, and for a custom string the string itself.

## Size masking (HTTP/2 padding)

The first frames of every HTTP/2 stream get the PADDED flag and random bytes within a per stream and per session budget (`traffic_shaper` and `select_padding_callback` in the core). The server needs no setup. Parameters, defaults and link tags: [padding.en.md](padding.en.md).

## Turn off QUIC

The parameter `block_quic = true` (in the key form "Turn off QUIC", section "For experts"; tag `0x45` in `tt://`, one byte) makes the core reject every UDP connection to port 443 except DNS queries (`Tunnel::finalize_connect_action` in `core/src/tunnel.cpp`, action `VPN_CA_REJECT`). After QUIC is refused, browsers and YouTube fall back to TCP inside the tunnel. The server needs no setup. The test `TunnelTest.BlockQuic` covers the behavior. A subscription can set this flag on a key like the other link values.

## Failures and the freeze

When no server address answered, the core determines the reason (`PingFailure` in `net/include/net/utils.h`) and appends it to the error text as a `[failure=…]` tag:

| Tag | What happened | Core pause before the next handshake |
|---|---|---|
| `connect` | TCP was not established (refused, unreachable, timeout) or QUIC failed | as in TrustTunnel |
| `hello_reset` | TCP is up, the ClientHello went out, the connection was reset or closed: an SNI block or a server refusal | 5 s (TrustTunnel retries after about 10 ms, and a burst of handshakes that close together can itself cause a freeze) |
| `hello_no_answer` | TCP is up, the ClientHello went out, no answer: this is how a filter "freezing" an address looks | 60 s (according to TSPU reports from summer 2026, every handshake during a freeze prolongs it) |

The classification lives in `ping.cpp` (whether the ClientHello went out, function `tcp_socket_hello_sent`), the pause in `handshake_pause` in `vpn_fsm.cpp`.

```text
 core: the handshake failed
   |
   +-- the ClientHello did not go out --> connect          pause as in TrustTunnel
   +-- it went out, connection reset ----> hello_reset      pause 5 s
   +-- it went out, no answer -----------> hello_no_answer  pause 60 s
   |
   v
 error text + [failure=...]  -> app (VpnScope, ConnectFailures)
```

Figure 3. How the core tells the failure reasons apart.

The tag reaches the app like this. On Android the core raises the `VPN_EVENT_PING_FAILED` event after every failed attempt (also during the first connection), the JNI layer (`lib.cpp`, `onPingFailed`) sends a `{"cattunnel_failure":"…"}` record through `onConnectionInfo`, and the plugin forwards it to a separate channel, `vpn_plugin_event_channel_failures`. On Linux the helper finds the tag in the CLI output (`cli_output.h`, `ParseFailure`) and sends a `failure` event. The official core writes no tags, so with it the stream is empty.

The app uses the reason in two places (`ConnectFailures`, `VpnScope`):

- Auto mode moves to the next technique, as described above.
- During a freeze the diagnostics of Marsik (the app's cat helper) make no TLS checks of their own to that address. They say "the address is frozen, waiting" at once and look for another working server: another server has another address, and one handshake there does no harm.

## Platform limits

- Before each next part the core waits for the previous one to be acknowledged (ACK), for at most 500 ms: that adds one round trip to connection setup. It waits on `TCP_INFO.tcpi_unacked == 0`. On Android the OS denies the app `SIOCOUTQNSD`, so "sent" is judged by `TCP_INFO.tcpi_notsent_bytes`.
- Windows: the urgent byte and TTL code is the same, but neither "sent" nor ACK is measured there, and pauses of 10 and 50 ms stand in for the wait.
- The own core with this patch exists since 1.4.6. Since 1.5.7 all platforms (all Android ABIs, Windows, Linux and routers) get the same TrustTunnelClient 1.3.0-rc.1 build with CatTunnel patches, so the custom string, failure reasons, pauses, padding and QUIC blocking work the same everywhere. In 1.5.9 the app and the router are built from one core revision (`82963908`), in 1.5.9.5 again from one (`b59debf4`, with [IP rotation](rotation.en.md)).
