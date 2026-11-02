# How the connection works

Step by step, from the engine to the server. The settings of each step are in the key's settings (a section and a "?" button on it).

## 1. The engine

- The connection is built by the **TrustTunnel engine**, a native library inside the app. In CatTunnel it is built with our changes: censorship bypass techniques, a custom bypass string, size masking, keepalive and clear failure reasons.
- The tunnel is an ordinary secure HTTPS connection (HTTP/2 over TLS or HTTP/3 over QUIC) to the server. All your traffic goes inside it.
- The key (address, login, password) comes from a link or a subscription. The subscription is offered at several addresses: if the first one is blocked, the app tries the next, and each gets at most 7 seconds to connect.
- The app has its own device key: the private part stays on the phone, the subscription server gets the public part and encrypts its reply to it. A leaked subscription link will not help another device.

## 2. The handshake (TLS)

- The connection starts with the **ClientHello**, the first packet, which carries the server name (SNI) in plain text. This is what the provider's filter reads.
- The **TLS fingerprint** says which app this handshake looks like. The options: "like the default browser" (the default; when no browser is found, one is picked at random), "like Chrome", "like Firefox", "like Safari" and "like an Android app". Do not change it needlessly: a change during a block can extend the address "freeze".

## 3. Anti-DPI

- It changes only **how the ClientHello goes onto the network**: the packet stays whole for the server, while the filter sees it cut or out of order. HTTP/2 only.
- **Basic**: the packet in two pieces with a pause.
- **1, 2, 3**: ByeDPI techniques. They are an "urgent" byte the server drops, and a piece with TTL 1 that is lost on the way and then arrives again.
- **Auto** tries techniques 1, 2, 3 in turn, but not all at once: two per attempt, and the next attempt starts where the previous one stopped, so three handshakes with one name never go back to back. Each technique gets up to 6 seconds, with a 1.5 second pause between them.
- **Custom string**: as in ByeDPI, parts `-s`, `-o`, `-d` with a position, for example `-o1+s -d3+s`. The syntax is in the "?" of the "Censorship bypass" section.

## 4. Networks

- The app remembers a particular network, not a kind of network: it is recognized by its gateway and DNS, so the home Wi-Fi and the university count as two networks.
- If the plain connection fails in a network and the bypass helped, that is remembered: for 7 days on Wi-Fi; on a mobile network for 1 day during the first 3 days, then as on Wi-Fi. After that the app tries the plain connection again.
- What is remembered is in "Settings → Networks": a network can be renamed or forgotten there, and a tap shows which technique worked for each key and when. A key whose subscription asks for the bypass itself does not mark the network.

## 5. Size masking

- The first frames of a connection get random bytes added, so the sizes of the tunnel's first requests do not repeat. It is part of the HTTP/2 standard, and the server needs no setup.
- It is turned on under "For experts" and is off by default. When it is on, 2 to 4 of the first frames of every stream are padded, and the junk in a frame takes 1 to 64 bytes. A stream gets at most 2048 bytes of junk and the whole session at most 4096. The limits can be changed in the same place.
- **Turn off QUIC** (same place): apps inside the tunnel cannot use UDP to port 443, which is QUIC, what YouTube and Chrome run on. They fall back to plain TCP at once. It helps compare speed and see whether QUIC gets in the way. Off by default.
- **Keepalive** (same place): an idle tunnel is sometimes closed, and a mobile network can quietly freeze a connection. Keepalive sends a signal on an idle session. Off by default; when on, the signal goes after a random number of seconds from 60 to 240.

## 6. Connecting and retries

- If the server did not answer, the app knows why: **no TCP** (the address is unreachable), **reset after the ClientHello** (a block by name) or **silence after the ClientHello**.
- **Silence** looks like the filter "freezing" the address for a couple of minutes, and every new handshake extends it. So after silence the engine waits a minute, and the app treats the address as frozen for two minutes: meanwhile Auto does not rotate techniques, and Marsik does not knock with his own checks and offers another server.
- After a reset the engine waits 5 seconds: a burst of handshakes in a row looks suspicious by itself.
- **Switching to another server.** If the chosen server does not connect for 2 minutes while the internet works, the app moves to the next server of the same subscription (it leaves reserve keys and "Russian exit" alone) and tries to come back after 30 minutes. It can be turned off in "Settings → Launch and connection".
- **Marsik** checks the network, the server, TLS, the keys and the subscription only on your own servers and never goes to other sites. He keeps the result for a server for 2 minutes and does not check it again before that.

## 7. The server

- Nothing needs to be set up on the server: all the techniques work with a standard TrustTunnel server.
- A subscription can set the bypass technique, the fingerprint, the custom string, size masking and QUIC off by itself, and then the app takes them from there.
