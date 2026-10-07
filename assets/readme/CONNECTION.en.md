# How the connection works

Step by step, from the engine to the server. Each step's settings are in the key settings (its section and the "?" next to it).

## 1. The engine

- The connection is built by the **TrustTunnel engine**, a native library inside the app. CatTunnel builds it with its own additions: censorship bypass techniques, a custom bypass string, size masking and clear failure reasons.
- The tunnel is an ordinary secure HTTPS connection (HTTP/2 over TLS, or HTTP/3 over QUIC) to the server. All your traffic goes inside it.

## 2. The handshake (TLS)

- A connection starts with the **ClientHello**, the first packet, which carries the server name (SNI) in plain text. That is what the provider's filter reads.
- **TLS fingerprint** - which app the handshake looks like. By default your browser, so the filter sees one fingerprint from your address. Don't change it needlessly.

## 3. Anti-DPI

- Changes only **how the ClientHello goes out**: the server gets the packet whole, the filter sees it cut or out of order. HTTP/2 only.
- **Basic** - the packet in two pieces with a pause.
- **1, 2, 3** - ByeDPI techniques: an "urgent" byte the server drops, and a piece with TTL 1 that is lost on the way and arrives again later.
- **Auto** - tries 1, 2, 3 in turn and remembers what worked for this server and network.
- **Custom string** - ByeDPI-style: parts `-s`, `-o`, `-d` with a position, e.g. `-o1+s -d3+s`. Syntax under "?" in "Censorship bypass".

## 4. Size masking

- The first frames of a connection get random padding, so the sizes of the tunnel's first requests never repeat. Part of HTTP/2; nothing to set up on the server.
- Turned on in "For experts"; off by default.
- **Turn off QUIC** (same place): apps inside the tunnel can't use UDP to port 443 - that's QUIC, used by YouTube and Chrome. They switch to plain TCP right away. Handy to compare speed and see whether QUIC gets in the way. Off by default.

## 5. Connecting and retries

- When the server doesn't answer, the app knows why: **no TCP** (address unreachable), **reset after the ClientHello** (blocked by name) or **silence after the ClientHello**.
- **Silence** looks like the filter "freezing" the address for a couple of minutes. Each new handshake extends it, so the engine waits a minute, Auto stops switching techniques, and Marsik skips his own checks and offers another server.
- After a reset the engine waits 5 seconds: a burst of handshakes looks suspicious in itself.

## 6. The server

- Nothing to set up on the server: all techniques work with a standard TrustTunnel server.
- The key (address, login, password) comes from a link or a subscription. A subscription can also set the bypass method, fingerprint, custom string, size masking and QUIC off.
