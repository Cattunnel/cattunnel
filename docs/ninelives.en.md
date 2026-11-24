Русский: [ninelives.md](ninelives.md) (the Russian text is the main one; if the two differ, the Russian text is right)

# NineLives

NineLives is the second CatTunnel transport, next to the plain `CONNECT`. It needs a [CatTunnel server](https://github.com/Cattunnel/cattunnel-server) with NineLives enabled, or another server that supports it. It is turned on in the key settings, section "For experts", with the switch "NineLives transport", or by a subscription.

NineLives is not compatible with XHTTP from Xray: it has its own frame layout, its own body encryption and its own session recovery. It does not accept Xray links or configurations. The word `xhttp` in setting keys is left over from the working name. The protocol on the wire: [protocols.md](protocols.md) and the server documents [xhttp-protocol.md](https://github.com/Cattunnel/cattunnel-server/blob/main/docs/xhttp-protocol.md) and [ninelives.md](https://github.com/Cattunnel/cattunnel-server/blob/main/docs/ninelives.md).

## How it works

```text
 app                                          server
   GET  /path/SID   <---- data to the device ----
   POST /path/SID   ----- data to the server ---->
   frames with byte numbers and acknowledgements,
   body encrypted with AES-128-GCM (if there is a server key)

 on a break:
   a new GET/POST pair with the same SID and proof of token ownership
   -> the server resends what was not acknowledged (waits up to 60 s)
```

Figure 1. A NineLives session and its continuation after a break.

- One app connection does not use a `CONNECT` stream. It uses a pair of HTTP/2 requests to one path: a `GET` whose response carries data to the device, and a `POST` whose body carries data to the server. The data is split into frames with byte numbers and acknowledgements. Many sessions share one TLS connection, and the TLS connection comes from the same pool as for `CONNECT` ([anti-dpi.en.md](anti-dpi.en.md#connection-pool)).
- **Body encryption.** If the key holds the server's public key, the client starts with a handshake: a one-time X25519 key, the server's reply with its own one-time key and an Ed25519 signature, then HKDF-SHA256 derives a separate AES-128-GCM key for each direction from the shared secret. The client checks the signature against the server's public key, so a middlebox with a forged certificate cannot read the body. A failure of the signature, the key exchange or decryption never moves the session to a plain body. Without the server key (or with the "NineLives encryption" switch off) the body is protected by TLS only.
- **Continuation after a break.** The server gives the session a token. If the connection breaks, the client opens a new pair of requests with the same session identifier and proves it owns the token (an HMAC over a fresh server challenge). The server resends the unacknowledged data. By default a session waits for continuation for 60 seconds (the server setting `xhttp_resume_timeout`).
- **Memory.** The server keeps NineLives buffers within a shared memory budget. If there is no room, a new session is refused with 503, and running ones are not evicted.

## Key settings

| Setting | Core key | `tt://` tag |
|---|---|---|
| NineLives transport instead of CONNECT | `xhttp_enable` | `0x4F` |
| Path prefix (empty means `/api/v2/`) | `xhttp_path` | `0x50` |
| Server public key, Ed25519, base64, 44 characters | `xhttp_server_key` | `0x51` |
| NineLives encryption (local switch) | the key is passed to the core only if the switch is on | none |

The path must start with `/`. The server key usually comes from the subscription. The encryption switch is stored on the device only: with the switch off the key stays saved, but the core does not get it. If body encryption is on in the core settings (`xhttp_body_encryption = true`), it needs a valid 32 byte server key, otherwise the core refuses the settings.

## Compatibility with other features

- **IP rotation** works only with `CONNECT` over HTTP/2. While NineLives is on, the key stays on its own address ([rotation.en.md](rotation.en.md)).
- **CatTail** (the noise disguise, the "Disguise" key setting) also works only with `CONNECT`. With NineLives on, the connection stays quiet, as in the plain mode.
- The router edition cannot configure NineLives yet.

## Status

NineLives appeared in 1.5.9 together with session continuation for up to 60 seconds. The traffic shape (frame sizes and rhythm compared with a browser) is still being refined, so the protocol may change in later versions.
