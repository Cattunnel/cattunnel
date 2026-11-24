Русский: [subscriptions.md](subscriptions.md) (the Russian text is the main one; if the two differ, the Russian text is right)

# Subscriptions

A subscription is an HTTPS address from which the app gets a list of servers. The app updates the server list and server settings from the subscription by itself. A subscription server is not part of this repository: any HTTPS server that returns a response in the format described below will do.

The built-in subscription of the TrustTunnel server (`[subscription]` in `vpn.toml`, JSON over HTTP Basic Auth) works differently, and the app does not read it. Everything on this page is about CatTunnel subscriptions: TrustTunnel has none.

## Response format

The response body is `tt://` links, one per line, in the same format as when exporting a single server ([DEEP_LINK.md](https://github.com/Cattunnel/cattunnel-server/blob/main/DEEP_LINK.md), including the extended CatTunnel tags).

```text
#mirrors https://sub1.example.com/s/<token> https://sub2.example.com/s/<token>
tt://?<payload of server 1>
tt://?<payload of server 2>
```

Figure 1. An example subscription response in plain form (before encryption).

- The `#mirrors` line is optional. It lists, separated by spaces, the mirrors of this subscription in polling order, `https://` only. It replaces the saved list, so the server can add, reorder and remove mirrors. Older app versions skip it.
- Other lines that do not start with `tt://` are skipped.
- A response without a single `tt://` link counts as an error, not as a command to delete all servers.

## Encryption

The response may be encrypted with [age](https://age-encryption.org/v1) (X25519), in binary form or ASCII armor. The app decrypts it on the device. If there are no keys, the response is read as text.

- **Device key.** On first launch the app creates its own age key and never changes it. The private part never leaves the device: on Android it is stored encrypted with a key from the Android Keystore, on Windows through DPAPI, on Linux in a file with mode 0600. The public part (`age1…`) goes to the server in a request header, and the server encrypts the response to it. So a leaked subscription address is useless to another device.
- **Key in the subscription settings.** A private key `AGE-SECRET-KEY-1…` can be set on a subscription by hand. It is used as a fallback when the device key is not available.

The age library for Dart is in `packages/dage`. It fixes two incompatibilities with the age specification (the HKDF salt for the header MAC and the re-writing of grease stanzas). Without those fixes, subscriptions encrypted by the reference implementation did not open.

## Request

- `https://` only, no redirects are followed: the response carries logins and passwords.
- `GET` with the headers `User-Agent: CatTunnel/<version>`, `x-device-key` (the device public key), `x-hwid` (a random device identifier, not a secret), `x-device-os`, `x-device-model`, `x-ver-os`, `x-app-version`.
- Connecting to one mirror and receiving the response headers gets 7 s, reading the body 20 s. A response larger than 4 MB is discarded. On codes 408, 429 and 5xx the request to the mirror is repeated.
- Mirrors are polled in order until the first 200 response.

## One-time codes

Instead of a permanent address, a one-time code can be passed: as a link from a browser, a QR code or a picture from the gallery. The app sends `POST <base>/api/ct/exchange` with the JSON `{code, device_key, device_id, platform, model, os_version}` (the usual device headers go with the request) and gets `{subscription, mirrors}`: the permanent subscription address and mirrors, already bound to the device key. The code burns after the exchange. The reply gets 20 seconds.

## Update

```text
 mirror 1 --no answer--> mirror 2 --200--> response
   -> decrypt with the device key (age)
   -> tt:// links -> match by names within the subscription:
      add new ones, remove missing ones, leave the selected one
   -> write link values into the keys (except "Override subscription")
```

Figure 2. One subscription update cycle.

- Servers are matched by name within their own subscription: new ones are added, missing ones are removed. The currently selected server is not removed while it is selected.
- Before connecting, the app updates the subscription if it has not been updated for 24 hours. The connection waits for the update for at most 4 seconds, and after a failure such an attempt is not repeated for an hour. A manual update is possible at any time.
- Under the subscription you can see when it updated, through which mirror and how fast, and after a failure how many mirrors did not answer. A tap opens the list of attempts: the address without a path, the result (HTTP 200, an error code, timeout, no connection, TLS error, decryption failed) and the time. The subscription token is not recorded. The same list goes into the log export as `subscription_polls.log`.

## Server order

The servers of a subscription are shown in the order the subscription gave them. Own keys go in the order they were added. Favorite keys (the star) are always on top, under any sorting. Subscriptions and "Own keys" are collected into separate groups: the order of the groups and their names can be changed.

## The subscription outranks the key

On every update the subscription writes into its keys all the link values, switched-off switches included: the anti-DPI technique, the TLS profile, size masking, QUIC blocking, NineLives, IP rotation and the rest. If the tag is absent from the link, the app value stays.

To configure a key from a subscription your own way, turn on "Override subscription" in the "For experts" section (for IP rotation the app asks about it by itself when you edit). The subscription then leaves such a key alone. The key is marked "Key differs from the server", and the "Restore server settings" button returns the subscription values.

## Server name and TLS profile

A subscription can give a key its own server name for the SNI (tag `0x03`), additional names for parallel TLS connections (tag `0x52`, up to 8 names) and a TLS profile (tag `0x42`), and change them over time. The app simply uses what came in the last update. For this the server must accept all the names (`allowed_sni` in the [CatTunnel server](https://github.com/Cattunnel/cattunnel-server/blob/main/docs/features.en.md#several-server-names-sni-rotation)) with a certificate that covers them: otherwise the strict certificate check in the app will not let the connection through.
