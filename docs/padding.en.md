Русский: [padding.md](padding.md) (the Russian text is the main one; if the two differ, the Russian text is right)

# Size masking (HTTP/2 padding)

The lengths of the first TLS records after the handshake are visible to an observer without decryption. For a tunnel they form a recognizable pattern: the first `CONNECT` request, the server's reply, the first data. Size masking adds random bytes to the first frames of every HTTP/2 stream, so this pattern changes from stream to stream.

TrustTunnel has no such feature: its client core adds no padding. This is a CatTunnel difference, and it works in the client only.

## How it works

```text
 CONNECT stream: frame 1   frame 2   frame 3   frame 4   frame 5 ...
 padding:        +17 B     +4 B      +52 B     none      none
                 \_ the first 2-4 frames (random), while the budget lasts _/
 on the wire: TLS record length = frame + padding
```

Figure 1. Padding of the first frames of one stream. The numbers in the example are random.

The mechanism is standard: the PADDED flag of HEADERS and DATA frames (RFC 9113, section 6.1). The receiver must accept and discard the added bytes, so the server needs no setup: it works with the [CatTunnel server](https://github.com/Cattunnel/cattunnel-server) and with a plain TrustTunnel server. It applies to HTTP/2 (TCP) only. For HTTP/3 (QUIC) the setting has no effect.

The core's traffic shaper makes the decision (`traffic_shaper` in `net/src/traffic_shaper.cpp`, the callback `select_padding_callback` in `net/src/http2.cpp`):

1. For every new stream (one app connection is one `CONNECT` stream) the core picks a random number of frames between the "minimum" and the "maximum".
2. Each of these first frames gets a random number of bytes within the set limits. The pad length byte counts in that number.
3. The padding is limited by the free room in the frame, the per stream budget and the budget of the whole HTTP/2 session. When the budget is spent, frames go out without padding.

```text
 new stream -> target = random(min frames .. max frames)
 frame ready -> padded frames < target ?
                  yes: pad = random(min bytes .. max bytes)
                       pad = min(pad, room in the frame,
                                 stream budget left,
                                 session budget left)
                       send the frame with padding, frame counter + 1
                  no:  send the frame as is
```

Figure 2. The decision for each frame.

Every stream starts the same way, so the first stream of a session does not differ in shape from the twentieth. The size of an HTTP/2 frame equals the size of the TLS record, so the padding changes the record length on the wire byte for byte.

Padding reduces the difference in the distribution of record lengths, but it does not make the tunnel indistinguishable from a browser: the order of records and their rhythm stay their own.

## Settings

The switch "Size masking (HTTP/2)" is in the key settings, section "For experts". It is off by default. Turning it on sets a maximum of 4 frames per stream; the other values are available in the same place.

| Setting | Core key | `tt://` tag | App default |
|---|---|---|---|
| Frames per stream, maximum | `h2_padding_frames` (0 turns it off, up to 64) | `0x44` | 0, 4 when turned on |
| Frames per stream, minimum | `h2_padding_frames_min` (up to 64) | `0x46` | 2 |
| Count frames for every stream | `h2_padding_per_stream` | `0x47` | yes |
| Padding per frame, from bytes | `h2_padding_min_bytes` (up to 256) | `0x48` | 1 |
| Padding per frame, up to bytes | `h2_padding_max_bytes` (up to 256) | `0x49` | 64 |
| Per stream budget, bytes | `h2_padding_stream_bytes` | `0x4A` | 2048 |
| Per session budget, bytes | `h2_padding_session_bytes` | `0x4B` | 4096 |

If "count for every stream" is off, the core pads only the first frames of the whole session, not of each stream.

The core caps the budgets at 1048576. While the masking is on, the app writes all seven values into the core settings, and they replace the core defaults. If a value is missing from the core settings, the core uses its own: a minimum of 2 frames, per stream, from 1 to 64 bytes per frame, 2048 bytes per stream and 4096 per session.

A subscription can set all these values on a key (the tags above). Without a tag the app value stays. A key with the "Override subscription" switch is left alone by the subscription ([subscriptions.en.md](subscriptions.en.md)).

The router edition passes only `h2_padding_frames` to the core, and the other values come from the core defaults there.

## What else shapes the traffic

- The core adds to the `CONNECT` request the headers a browser sends with a navigation request (`accept`, `accept-encoding`, `accept-language`, `sec-ch-ua*`, `sec-fetch-*`, `upgrade-insecure-requests`, `priority`). TrustTunnel sends only `user-agent` and `proxy-authorization`. Thanks to HPACK compression the first request of a session is large and the next ones are small, as in a browser (the function `put_browser_headers`). The `user-agent` is not a browser string but the platform and the app name.
- The CatTunnel server answers `CONNECT` with the headers of an ordinary web server (`date`, `server`, `cache-control` and two random identifiers of random length), not with an empty reply of the same size every time.
- The connection pool spreads streams over 2 to 4 TLS connections and opens them with pauses: [anti-dpi.en.md](anti-dpi.en.md#connection-pool).
