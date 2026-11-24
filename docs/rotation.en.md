Русский: [rotation.md](rotation.md) (the Russian text is the main one; if the two differ, the Russian text is right)

# IP rotation

Since 1.5.9.5 one key can work through several servers in turn. The app connects to the first address, after a random time (the term) moves to the next one, then on around the circle. A long session is harder to tie to one address, and blocking one address does not cut the key off.

In TrustTunnel a key has one server and there is no rotation. Rotation works in the client and needs no setup on the servers, but it needs a key with the `CONNECT` transport over HTTP/2. It does not work with [NineLives](ninelives.en.md) or with HTTP/3, and the core switches CatTail off for a key with rotation (it logs that 1.5.9.5 has no per server CatTail settings for rotation).

## How a switch goes

```text
 the term on A is over (random, between "from" and "to")
        |
        v
 a new TLS connection to B: B has its own SNI names,
 B's certificate is checked against the name sent in the SNI
        |
        +-- B opened and accepted the first app connection
        |     new connections go through B, the old ones
        |     finish on A and close
        |
        +-- B refused: a foreign certificate, a wrong password
        |     B rests for 5-10 minutes, the key stays on A
        |
        +-- B did not answer
              one new connection to A to find out who is to blame:
                A answered -> B rests for 5-10 minutes,
                              the key stays on A
                A is silent -> the network is gone: pauses of 1, 4, 9,
                              16, 20 minutes, nobody rests
```

Figure 1. A switch from server A to server B and its three outcomes.

Until B accepts the first app connection (the first `CONNECT`), the pool of A is not closed: if B accepts TLS but denies access, the tunnel returns to A without a break. After a switch the old pool lives out an overlap window while new connections go through B only. The window is 10 % of the average of the term range (for 600 and 900 seconds that is 75 seconds). Without a range the window is chosen at random between 300 and 900 seconds. No more than two pools are open at once.

## Other rules

- **The current server went silent in the middle of a term** (it does not answer the keepalive): the core starts the switch to the next one at once, without waiting for the end of the term. The first TLS connection to the next server opens before the silent one closes. The silent server rests for 5-10 minutes.
- **All other servers of the key are resting:** the key stays on the current one and waits for the next term. There are no repeated handshakes in a row: frequent attempts to a blocked address are noticeable to a filter by themselves.
- **A certificate or password error on the current server** (not on the next one) turns the VPN off, as it would without rotation: a substituted certificate is no reason to keep working silently.
- **A resting server** is skipped when the next one is chosen, until the rest ends. Rest marks survive a new session of the same client.
- **The pause when the network is gone** grows as the square of the attempt number in minutes (1, 4, 9, 16), then stays at 20 minutes, each with a random spread of 15 %.
- Servers are not checked in advance: a server is judged only by real handshakes and by the keepalive inside the tunnel.

```text
 A ---term---> B ---term---> C ---term---> A ...
               |
               (B is resting: A ---term---> C)
```

Figure 2. The order of servers around the circle and skipping a resting one.

## Settings

The "IP rotation" tab in the key settings (the switch "Change server over time"):

| What | In the `tt://` link | In the core config |
|---|---|---|
| Addresses in turn, each with its own SNI names (`host:port sni1 sni2`), up to 16 | `0x53` | `[[endpoint.rotation]]`: `address`, `sni_pool` (up to 8 names) |
| Term on one address, from, seconds | `0x54` | `rotation_min_secs` |
| Term on one address, to, seconds | `0x55` | `rotation_max_secs` |
| Rotation on (local switch) | none | without rotation the list is not passed |

- An address in the form: IPv4, `[IPv6]` or a domain, optionally with a port. The core accepts numeric addresses (IPv4 and IPv6) in the list and skips the rest with a log entry, so it is better to put IPs in the list.
- Server A, the key's own address: if it is not in the list, it still goes first. If there are fewer than two different servers, rotation does not turn on.
- The term: 0 or from 60 to 86400 seconds, the minimum not above the maximum. If no term is set, the core takes the key's session lifetime (`session_lifetime_secs`). If that is not set either, the key leaves a server only when the server stops answering.
- Switched-off rotation keeps the list saved, but the core and the link do not get it.
- A wrong entry (port, name) is skipped, the others work.
- If the key comes from a subscription, editing the rotation requires turning on "Override subscription": the app asks about it by itself ([subscriptions.en.md](subscriptions.en.md)).

Usually the addresses and terms come from the subscription, like the other key values. A key with the "Override subscription" switch is left alone by the subscription.

## What the servers need

Each server in the list must accept the key's login and have a certificate for its own SNI names. The servers do not need to know about each other: the client does the whole switch.
