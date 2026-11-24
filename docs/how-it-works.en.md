Русский: [how-it-works.md](how-it-works.md) (the Russian text is the main one; if the two differ, the Russian text is right)

# How CatTunnel works

```text
 apps on the device
        |
        v
 system VPN (tun) ---- Russian networks and domains ----> direct
        |
        v
 TrustTunnelClient core (CatTunnel build)
        |  2-4 HTTP/2 TLS connections (a pool), each
        |  app connection = one CONNECT stream
        v
 CatTunnel / TrustTunnel server ---> internet
```

Figure 1. The path of an app connection through CatTunnel.

CatTunnel is built on [TrustTunnel](https://github.com/TrustTunnel/TrustTunnel) and its client. The default transport is the same: HTTP/2 CONNECT over TLS. What is added on top is described below and in separate documents.

## 1. Marsik diagnostics

If the VPN has not connected within 10 seconds, Marsik (the app's cat helper) checks the connection step by step.

```text
 core verdict -> network -> TCP to server -> TLS and SNI -> access (keys, subscription)
 the first failed step is the answer to "what is broken"
```

Figure 2. The diagnostic steps.

0. **What the core said.** If in the last attempt the core itself saw that the path to the server is being cut (a frozen address, a cut after a fixed number of bytes, a silent session), that is the answer. Probes from the app would add more handshakes to the same name, and a burst of them is what starts a freeze.
1. **Network.** The system's word: on Android, the network check done by Android itself. Where there is none, the step stays "not checked", and the app sends no packets to other people's hosts.
2. **Server.** TCP to the server, telling a timeout from a refusal.
3. **TLS and SNI.** A handshake with the server's SNI and ALPN `h2` and `http/1.1`. The TrustTunnel server silently drops a foreign SNI, so "answered" counts only on a TLS alert. A cut yields one verdict, "the secure connection is being cut". The device clock is judged by the validity period of the server's own certificate.
4. **Access.** A real `CONNECT` with the login, only to a server whose certificate was verified (replies 403, 404, 405 and 407 mean the keys did not fit). If the keys fit, the subscription is checked: 404 means the access has ended. The subscription is checked at most once in 5 minutes.

The diagnostics run right during the connection: on Android the core leaves the app itself out of the tunnel, and on Windows and Linux the probes are pinned to the physical adapter.

## 2. Strict server certificate check

- If the config has no certificate, the core verifies the server against the system store. On Android that store includes **certificates installed by hand**, among them the Russian Ministry of Digital Development root. Its holder could forge the server certificate and decrypt the tunnel together with the login and password.
- So for a server without its own certificate CatTunnel substitutes the **system root certificates without "Russian Trusted Root/Sub CA"** (`endpoint_ca_resolver.dart`). Russian certificates are filtered out by name and by the SHA-256 fingerprint of the key.
- A server with its own certificate (PEM) is verified against that certificate only.
- The check can be turned off (the switch "trust user certificates") only after **three confirmations**. If the check gets in the way of connecting, Marsik says so.

More on protection: [security/shared.en.md](security/shared.en.md).

## 3. Subscriptions

- The response body is `tt://` links, one per line. The response can be encrypted with age, to the device key or to an `AGE-SECRET-KEY-1…` key from the subscription settings.
- Servers are matched by name within their own subscription: new ones are added, missing ones are removed, **the selected server is never removed**.
- An empty response with no link at all counts as an error and does not erase servers.
- **The subscription outranks the key:** on update it writes every link value into its keys, switched-off ones included. A key with the "Override subscription" switch is left alone. Such a key is marked "Key differs from the server", and "Restore server settings" returns the server values.
- Subscription mirrors are tried in order. Under the subscription you can see when it updated, through which address and how fast. The list of attempts (address without a path, result, time) goes into the log export as `subscription_polls.log`, the subscription token is not recorded.
- The update before connecting waits at most 4 seconds and is not repeated for an hour after a failure.
- The age library for Dart is in the project (`packages/dage`). It fixes **two incompatibilities** with the age standard (the HKDF salt for the header MAC and re-writing of "grease" stanzas without distortion).
- Response format, request headers, one-time codes and update rules: [subscriptions.en.md](subscriptions.en.md).

## 4. "Russian services bypass the VPN": routes and speed

- **Android routes** (traffic that never enters the tunnel): only the large networks of the built-in list, /22 and wider. On **Android 13 and newer** they are given to the system as exclusions (`excludeRoute`, Android engine patch 0004), and all networks of the built-in list go this way. On Android 12 and older the system gets "the whole internet minus these networks": every separate block costs about ten routes, and neighbors cannot be merged because foreign addresses lie between them. Android handles thousands of routes in one call badly, so in that case only the large blocks are used.
- **Core exclusions**: everything else, that is the small networks of the built-in list, its domains (`*.ru`, `*.рф` and others) and the auto lists (Russian networks from runetfreedom/geoip and ipverse/rir-ip, domains from hydraponique/roscomvpn-geosite). The core searches a sorted list, so size does not matter to it.
- **The VPN server address** is always subtracted from the lists.
- **Fast start.** The auto lists download in parallel 30 seconds after connecting, at most once in 20 hours. They are merged in a separate isolate and saved ready to use (`ru_lists/compiled.v1`). On connect the file is only read, the server address is cut out precisely, and downloaded rules are not parsed one by one. For auto split only package names are requested. The log shows the line `Connect prepared in N ms`.
- Downloaded lists pass a plausibility check: [security/shared.en.md](security/shared.en.md).

## 5. Anti-DPI and the own core

- The app runs on **its own build of the TrustTunnelClient 1.3.0-rc.1 core** (all Android ABIs, Windows, Linux, routers) with CatTunnel patches. In 1.5.9.5 the app and the router are built from one core revision (`b59debf4`). What is added: anti-DPI techniques, HTTP/2 size masking, failure reasons, a pool of 2 to 4 TLS connections with pauses between handshakes, TLS profiles, IP rotation and the NineLives transport. The server needs no setup for anti-DPI: the ClientHello stays one TLS record, only the way it is cut into TCP segments changes.
- The techniques come from [ByeDPI](https://github.com/hufrea/byedpi) (MIT): an "urgent" byte that the receiver's kernel removes from the stream, and a part with TTL 1 that is lost at the first router and later resent by the system. A lone "urgent" byte hangs the tokio based TrustTunnel server, so it always comes paired with a TTL 1 part.
- Custom techniques and strings, Auto mode, TLS profiles, failure reasons and core pauses before a retry: [anti-dpi.en.md](anti-dpi.en.md). Size masking: [padding.en.md](padding.en.md). IP rotation: [rotation.en.md](rotation.en.md). NineLives: [ninelives.en.md](ninelives.en.md). Wire protocols: [protocols.md](protocols.md).

## 6. Ping from the connection

While the core chooses a server address, it measures the connection time to each candidate. When an address is chosen, the core raises the `VPN_EVENT_ENDPOINT_PING` event with the time of the chosen one. There is no separate probe for this number. The Android adapter turns the event into a `{"cattunnel_ping_ms":N}` record (0 to 60000), and the app shows the number next to the key.

```text
 core:    ping every candidate -> pick the best -> time of the pick
 core:    VPN_EVENT_ENDPOINT_PING {ms} ------------------> Android adapter
 adapter: {"cattunnel_ping_ms": N} --------------------> app
```

Figure 3. The path of the ping number from the core to the screen.
