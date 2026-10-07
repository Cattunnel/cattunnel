# CatTunnel

An Android VPN client for the **TrustTunnel** protocol - a fork of the open-source TrustTunnel client (Apache-2.0 license). Mascot and helper: **Marsik** the cat.

## Quick start

1. Get a subscription from your VPN administrator (e.g. in the bot: `/config` → Android → "Subscription"). It comes with a link and an encryption key.
2. "Add server" → "Subscription" → paste the link and the key. Or scan a subscription QR code (see below).
3. Pick a server and tap "Connect" - or the big button with Marsik if the "Cozy" style is on.

## Servers and subscriptions

- **Ways to add a server:** manually, with a `tt://` link, by QR code, or via a subscription.
- **A subscription** is an address the app fetches your server list from. Only `https://` addresses are accepted; redirects to other addresses are refused.
- **Subscription encryption (age).** If the subscription has an `AGE-SECRET-KEY-1…` key, the server's reply is decrypted right on the phone - anyone intercepting the link on the way sees only ciphertext. Both the binary and the text ("armor") age formats are supported.
- **Auto-refresh:** once a day before connecting (waits at most 4 seconds; after a failure, no retry for an hour). Refresh manually with the button next to the subscription.
- If a subscription returns an empty list, servers are **not deleted** - that's almost always a server-side error.
- **Backup subscription addresses.** Together with the server list the server sends several addresses the subscription can be downloaded from. If the first one is unreachable (e.g. blocked by your operator), the app tries the next one by itself.
- **Share a subscription:** "⋮" menu of the subscription → "Share via QR". The code is full access to your servers: show it only to your own devices and people you trust.
- **Import by QR:** "Add server" → QR code. The scanner recognizes both servers and subscriptions; you always confirm before anything is saved.
- **Server export** (QR and link) and these screens are protected from screenshots and screen recording.

## Connecting

- **Quick Settings tile.** Turns the VPN on and off. If the VPN was turned off manually, the tile opens the app, which connects to the last server right away.
- **Auto-connect on launch**, **Kill switch** (blocks traffic if the tunnel drops), **Russian services directly** (banks, government services etc. bypass the VPN; the list is editable), MTU, server check timeout - in "Settings → Launch and connection".
- **A single notification** "CatTunnel - connected to …" instead of two.
- **Anti-DPI** and the other bypass settings are in the server settings, section "Censorship bypass" (each section has a "?" with an explanation). Methods: Basic, 1, 2, 3 (ByeDPI techniques), Auto (tries 1 → 2 → 3 and remembers what worked for the server and network) and a ByeDPI-style Custom string. The TLS fingerprint is there too; size masking and "Turn off QUIC" (UDP to port 443 is refused, browsers go over TCP inside the tunnel) are under "For experts". A subscription can pick all of this itself. Step by step: "Settings → How the connection works".
- For reliability, enable "Always-on VPN" and "Block connections without VPN" for CatTunnel in Android settings.

## Split tunneling

The "Routing" tab - the "Split tunneling" window opens by itself:
- **Sites and IPs** - domains and addresses that go directly, around the VPN. Turn on "Russian services" and the Russian networks come automatically from open lists (runetfreedom, ipverse, hydraponique), refreshed about once a day.
- **Apps** - all through the VPN; the selected ones around it; or only the selected ones through it. "Auto: Russian and Chinese apps bypass the VPN" (on by default) - banks, government services, marketplaces, VK, Yandex, Chinese services and the phone maker's apps go directly; recomputed on every connect. The exception is **Yandex Browser**: it always stays in the VPN, because for many people it is the main browser (Yandex sites still go directly by domain).
- Changes apply on the next connect.
- **vivo, OPPO, realme, OnePlus, iQOO phones (BBK).** With "Russian services" on, their firmware may say "VPN not connected" or "no internet" although everything works: Android doesn't mark a VPN with a long route list as validated. Marsik says so once himself, then an "i" button appears next to "Connected".

## Updates

- **In the app, by itself.** Shortly after launch (at most once a day) CatTunnel checks for a new version and Marsik offers it: one button downloads and installs it. Check by hand: "Settings → About → Check for updates".
- The first time, Android asks you to let CatTunnel **install apps** - it's only needed for updates.
- **Google Play Protect** may suggest "scanning the app" because CatTunnel isn't on Google Play: tap "More details" → "Install without scanning".
- **An update can't be swapped:** the file is checked against its checksum, and Android installs an update only with the same signature as the installed app.

## Appearance

"Settings → Appearance":
- **"Cozy" style** - a big round button with Marsik on the main screen (asleep when the VPN is off, holding a shield when it's on), with the status, session time, ping and a server card below. Tap the card to open the server list with "Test all".
- **"Minimal" style** - the familiar server list with power buttons.
- **Theme:** same as the phone, light or dark.
- After an update the app shows "What's new" once and asks which main screen you like.

## Marsik

- **Diagnostics.** If connecting hangs for 10 seconds, Marsik checks step by step: is there internet → does the server answer → does the secure connection get through (and is the server name, SNI, being filtered) → does the server accept the keys and is the subscription alive. He tells you what's wrong and offers a server that works right now.
- **Petting.** The cat button on the main screen (in both styles): stroke him to fill the bar; a full bar earns a compliment. There's a pet counter, easter eggs and purring (off by default, toggled with the speaker icon).

## Cyber security

Section "Settings → Cyber security".

- **Phone check:** the Russian Ministry certificate and other manually installed certificates, screen lock, Private DNS, USB debugging, background restrictions, IPv6 leak. Each finding has a "Fix" button.
- **Leak check:** the address your traffic leaves from through the VPN vs your real address; DNS inside the VPN; IPv6 leak. "Check in the browser" opens ipleak.net, which shows DNS and WebRTC leaks in the browser.
- **Strict server certificate check** - **on** by default. The Russian Ministry of Digital Development certificate ("Russian Trusted Root CA") is installed manually, usually for banking. If the VPN trusted it, whoever holds it could forge the server certificate and decrypt the tunnel, login and password included. While the check is on, the VPN verifies the server against Android's system certificates only, without the Ministry one. Servers with their own certificate (PEM) are verified against it alone. Turn it off only if the VPN won't connect because of it or your provider asked you to install their certificate. Turning it off takes three confirmations.
- **Panic button** (optional): long-press Marsik on the servers screen → confirm → all servers, subscriptions, keys, settings and logs are wiped and the app closes. The only way back is re-importing the subscription.
- **Disguise** (optional): home-screen icon and name become "Calculator", and so do the notification and the tile. The VPN key icon in the status bar and the app name in Android settings stay the same - it protects from a quick glance, not from checking settings.
- **App lock** (optional): fingerprint, face or phone PIN on opening and after a minute in the background. Requires a screen lock on the phone.

## Data and privacy

- **Stored on the phone:** servers, logins and passwords, subscriptions and age keys, settings. All in the app's private storage.
- **Nothing goes into backups or phone-to-phone transfers** - on a new phone the subscription is restored in a minute.
- **The connection log** (where apps connected) is kept for the current session only and wiped on every VPN disconnect and app start.
- **Logs** contain no passwords, keys or subscription addresses. They're sent anywhere only when you tap "Share".
- **No analytics, no ads.** Google ML Kit telemetry (QR scanner) is disabled.
- **Addresses the app itself uses:** your servers and subscription address; `ya.ru` and `77.88.8.8` - diagnostics ("is there internet"); `1.1.1.1` (Cloudflare) - leak check; ipleak.net - only via the button; the download server - checking and downloading updates (its address is set at build time; the request carries nothing about you, it just fetches a file with the version number).

## Technical information

- **Version:** 1.5.0. **Android:** 8.0 and newer (minSdk 26, targetSdk 36).
- **"/S-Signed" in the version** (e.g. `1.4.0/S-Signed`) - a build signed and released **after the VirusTotal check**. First the same build with the plain version `1.4.0` is made and scanned on VirusTotal, then the signed one is built from the same code with a link to that report. The link is in "Settings → About". The report covers the "twin" without the suffix and the link: a link can't point at the file it's inside of (it changes the file's hash).
- **Builds:** `arm64` (main, nearly all phones) and universal `arm64 + armv7` (if the main one won't install).
- **Protocol:** TrustTunnel - HTTP/2 over TLS (the protocol also supports QUIC). Native engine: TrustTunnelClient 1.3.0-beta.1, built by us with CatTunnel patches (see "How it differs from TrustTunnel").
- **The app is excluded from its own tunnel** - that's how the engine works; this is why diagnostics and checks work even while connecting.
- **Server link:** `tt://?…` - base64url of a set of TLV fields (address, host name, login, password, SNI, certificate, DNS and more; format: DEEP_LINK.md of the TrustTunnel project).
- **Subscription body:** `tt://` links, one per line; with a key - encrypted with age (X25519).
- **Subscription QR link:** `cattunnel://subscription?url=…&key=…&name=…`.
- **Server certificate verification:** the server's own certificate (PEM) → only that; otherwise Android's system root certificates without "Russian Trusted Root/Sub CA"; user-installed ones only if the strict check is turned off.
- **Permissions:** internet, VPN, notifications, camera (QR scanner), biometrics (app lock), background work (VPN service), installing apps (CatTunnel updates only).
- **Licenses:** Apache-2.0 (TrustTunnel). Purring sound - CC0 (freesound.org, recording 496275).

## How it differs from TrustTunnel

Everything below was added in this fork; the original TrustTunnel client doesn't have it. Format: what it does → how it works → where in the code.

### Subscriptions
- **Server-list subscriptions** → the reply body is `tt://` links one per line, parsed by the same decoder as a single link; servers are matched by name within their subscription (new ones added, missing ones removed, the selected server is never removed; duplicate names in one reply - the first wins) → `lib/data/domain/subscription_sync_service.dart`, `subscription_datasource_impl.dart`, DB migrations v5/v6.
- **Subscription safeguards** → `https://` only, no redirects; an empty reply counts as an error and doesn't wipe servers; the pre-connect auto-refresh waits at most 4 s and isn't retried for an hour after a failure (so 404s don't pile up for the server's fail2ban) → same files and `servers_card.dart`.
- **age encryption** → the reply is decrypted with an X25519 key on the phone; binary and armor formats accepted. Two interoperability bugs with standard age were fixed in the `dage` package (the HKDF salt of the header MAC and the "grease" stanza format); the package is vendored → `packages/dage`, `lib/common/utils/age_armor.dart`.
- **Servers grouped by subscription**, manual refresh, **subscription QR** (`cattunnel://subscription?url&key&name`) and importing it with the scanner → `subscription_servers_group.dart`, `subscription_share_link.dart`, `qr_scan_screen.dart`.

### Connecting
- **Quick Settings tile** → with a saved config it connects without opening the app (the config the native service keeps for Always-On); otherwise it opens the app with a per-process secret and the app connects to the last server; "is it on" is decided by our own service, not any VPN → `CatTunnelQsTileService.kt`, `CatTunnelActivity.kt`, `auto_connect_on_launch_settings_scope.dart`.
- **A single notification** → the app posts its notification under the id and channel of the native service's mandatory one, and Android replaces it in place → `vpn_connection_notifier.dart`.
- **Kill switch, auto-connect and Russian services directly are available on phones** (the original screen was macOS-only), an editable rule list, MTU, check timeout.

### Updates and engine
- **Engine patches (Android)** → the engine's Kotlin part is rebuilt with patches (the native part is our own build with the anti-DPI patch, `tools/engine_native`): `0001` - per-app split (`excluded_apps` / `included_apps`); `0002` - the config reaches the service in memory, not in an Intent (with the Russian lists it exceeds 1 MB, the Binder limit); `0003` - if the app asks to start a VPN that is already running, the engine tells it the real state, so a working VPN isn't shown as broken; `0004` - on Android 13+ the Russian networks are excluded with `excludeRoute` (a few dozen routes instead of hundreds); `0005` - "Disconnect" always closes the service, even if the connection hung; `0006` - if the system refused the VPN interface (e.g. `Cannot set address`) or the start failed otherwise, the engine reports "disconnected" to the app instead of staying silent → `tools/engine_patch`.
- **In-app updates** → `latest.json` from the download server (address only via `--dart-define=UPDATE_URL`, not in the source; without it the feature is off); `build` (versionCode) is compared → the APK for the phone's ABI goes to `cache/updates/` → sha256 checked natively → the system installer through an own FileProvider → `lib/feature/updates`, `UpdateChannel.kt`, `tools/make_latest_json.sh`.
- **One engine version for all platforms** → the `ENGINE_VERSION` file, updated with `tools/update_engine.sh <version>` (checks the version is out, writes desktop build hashes to `ENGINE_SHA256`).

### Appearance
- **Dark theme and styles** → all theme colors moved into a palette (`theme_palette.dart`: light is the original, dark is derived from the same accent `#3972AA`); style and theme live in `appearance_preferences.dart`; the "Cozy" main screen → `lib/feature/server/servers/widget/cozy/`; both styles connect through the shared `server_connection_actions.dart`. The "What's new" dialog with the style pick → `whats_new_dialog.dart`. Settings are grouped.

### Marsik
- **Stuck-connection diagnostics** → after 10 s: TCP to `ya.ru` / `77.88.8.8`; TCP to the server (timeout vs refused); TLS with the server's SNI and ALPN `h2`/`http/1.1` (a TrustTunnel server silently drops a foreign SNI or an unusable ALPN, so only a TLS alert counts as "answered"); if that dies - the same SNI to `ya.ru` with a control handshake (SNI block vs IP block); then a real `CONNECT` with the credentials (403/404/405/407 = keys rejected, anything else = accepted) - only to a server with a verified certificate; then the subscription (404 = access ended; at most once per 5 minutes). Works mid-connect because the native service excludes the app itself from the tunnel → `lib/feature/vpn/domain/connection_diagnostics.dart`, `connection_watchdog.dart`.
- **Petting, compliments, purring** (the sound doesn't take audio focus from music) → `lib/feature/companion`.

### Security
- **Strict server certificate check** → without a certificate in the config, the native engine verifies the server through Android's store, which includes manually installed certificates (the Russian Ministry one too); with a certificate in the config it uses only that. So for servers without their own certificate the app supplies the system roots minus "Russian Trusted" → `endpoint_ca_resolver.dart`, `SecurityChannel.kt`; the same rule for the app's own checks → `server_tls.dart`.
- **Logs** → the subscription address is printed as host only; the sanitizer strips `/api/ct/…` and `AGE-SECRET-KEY-1…` → `trust_tunnel_sensitive_data_sanitizer.dart`.
- **Backups** → cloud backups and phone-to-phone transfers are disabled → `AndroidManifest.xml`, `res/xml/data_extraction_rules.xml`.
- **Connection log** → in a folder excluded from backups, wiped on app start and on any VPN disconnect → `plugins/vpn_plugin/.../NativeVpnImpl.kt`.
- **ML Kit telemetry** → the upload transport is removed from the manifest; the library then deletes the events → `AndroidManifest.xml`.
- **Screenshot protection for screens with keys** (FLAG_SECURE) → `lib/widgets/secure_screen.dart`.
- **Phone check, leak check** → `lib/feature/security` + `SecurityChannel.kt`; the exit address comes from `CONNECT 1.1.1.1:80` through the server and `/cdn-cgi/trace` (the app itself bypasses the tunnel, so it can't see the exit address directly).
- **Panic button** → the system's app data wipe (`clearApplicationUserData`). **Disguise** → two `activity-alias` entries (the default one keeps the 1.2.0 name, so home-screen shortcuts survive the update). **App lock** → `local_auth` above the whole navigator so it covers dialogs too.

### Other
- **Russian language and a language switch**, **first-run tutorial**, **server export/import by link and QR**.
- **Size** → WebP images, x86/x86_64 dropped from the APK, separate arm64 and universal builds.

## If something doesn't work

1. Wait 10 seconds - Marsik will run diagnostics and give a hint.
2. Refresh the subscription manually.
3. Try another server.
4. Logs: "Settings → Logs" → "Share" - send them to your VPN administrator.
