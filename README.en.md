# CatTunnel

[Русская версия](README.md)

CatTunnel is a VPN client for Android, Windows and Linux. It connects to servers over the TrustTunnel protocol (TLS with HTTP/2 or HTTP/3) and to the [CatTunnel server](https://github.com/Cattunnel/cattunnel-server) using the NineLives transport. The project provides no servers or subscriptions: you need your own server or one from an administrator.

<p>
  <a href="../../releases/latest"><img src="https://img.shields.io/github/v/release/Cattunnel/cattunnel?include_prereleases&label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="License"></a>
  <img src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white" alt="Android 8.0+">
  <img src="https://img.shields.io/badge/Windows-x64-0078D6?logo=windows&logoColor=white" alt="Windows x64">
  <img src="https://img.shields.io/badge/Linux-Arch%20%7C%20Debian-FCC624?logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/Flutter-3.38.3-02569B?logo=flutter" alt="Flutter 3.38.3">
</p>

<p>
  <a href="../../releases/latest"><b>Download</b></a> ·
  <a href="assets/readme/README.en.md">User guide</a> ·
  <a href="docs/how-it-works.md">How it works</a> (in Russian)
</p>

## CatTunnel repositories

| Repository | What it is |
|---|---|
| [Cattunnel/cattunnel](https://github.com/Cattunnel/cattunnel) | App for Android, Windows and Linux (this repository) |
| [Cattunnel/cattunnel-router](https://github.com/Cattunnel/cattunnel-router) | Router edition for OpenWrt, Keenetic and ASUS Merlin |
| [Cattunnel/cattunnel-server](https://github.com/Cattunnel/cattunnel-server) | Server: a fork of the TrustTunnel endpoint with the NineLives transport |

The app is based on the open-source [TrustTunnel Flutter Client](https://github.com/TrustTunnel/TrustTunnelFlutterClient) (Apache-2.0). CatTunnel adds its own build of the network core, subscriptions encrypted with age, step-by-step connection diagnostics, strict certificate checking and a Russian interface. The app includes a helper cat, Marsik, who explains what went wrong.

> The account was created separately from the author, and this is deliberate: the project was developed privately from September 2026 and became public in October without any link to the developer's identity. For the same reason the development history before publication was not carried over, and the repository starts from already finished code. All CatTunnel builds are published only in the Releases section of this repository; files from other sites have nothing to do with the project.

## Features

### Connection and servers

- Servers can be added manually, by a `tt://` link, by QR code or from a subscription. A new link for the same account (same domain, login and key) updates the server, for example "port 8443 → 9443", and keeps the name and routing instead of creating a duplicate.
- Kill switch, auto-connect, and an Android quick settings tile: it turns the VPN on without opening the app, including on Samsung, which resets the VPN permission after every stop.
- Switching to another server of the same subscription if the selected one fails to connect for 2 minutes, and trying to switch back later. Can be turned off in settings.
- A running VPN does not reconnect when the app is opened again; changing the server makes one connection, not two.
- Server check and sorting by latency, MTU setting.
- "Russian exit" keys for people abroad: only Russian sites and apps go through the server, everything else goes directly.
- Traffic statistics on Android, Windows and Linux: charts for 24 hours to 90 days by server, hour and day of week, a heat map, a monthly limit. Counted on the device only.

### Subscriptions

- A subscription updates the server list and its settings by itself. `https://` only, no redirects, with fallback addresses (mirrors) in case the first one is blocked.
- **Device key.** The app creates its own age key (X25519) and does not change it; the private part stays on the device, the public part is sent to the server, and the response is encrypted to it. A leaked subscription address is useless on another device. Both the binary age format and ASCII armor are supported.
- **The subscription outranks the key.** On every update the subscription writes all values of the link into its keys, including disabled ones. Your own key settings are turned on with the "Above subscription" switch, and the "Restore server values" button brings back the server ones.
- Under a subscription you can see how the last poll went: through which address and how long it took, or how many addresses did not answer and why. The subscription token is not recorded.
- Subscription exchange by QR code, import with a scanner or from an image ("From gallery"), one-time codes from the browser.

Format, request headers and update rules: [docs/subscriptions.md](docs/subscriptions.md) (in Russian).

### DPI resistance

- **Anti-DPI.** The own build of the TrustTunnelClient core sends the ClientHello using techniques from [ByeDPI](https://github.com/hufrea/byedpi): an "urgent" byte, a piece with TTL 1, a split inside the server name. Methods 1-3, a custom string in ByeDPI syntax and an "Auto" mode: first a normal connection, then the methods in turn; the method that worked for a server and network is remembered until the end of the day. Automatic bypass is off by default: for keys from subscriptions it is turned on until the end of the day, for personal keys it stays on; if the subscription sets bypass for its keys, the subscription decides. Details: [docs/anti-dpi.md](docs/anti-dpi.md) (in Russian).
- **"Networks" list** ("Settings → Networks"): networks where a normal connection is cut today and the app turns bypass on. A network is marked only if a bypass method worked afterwards. The same screen has "Check network": a check of your own subscription servers on button press.
- **TLS fingerprint** for each server: by default the same as the device's browser, with a choice of Chrome 150, Chrome 156, Firefox, Safari and the Android app.
- **Size masking (HTTP/2 padding).** The first frames of each stream get random bytes within a per-stream and per-session budget; the server needs no configuration. Details: [docs/padding.md](docs/padding.md) (in Russian).
- **Connection pool.** App connections go through 2-4 TLS connections to the server, and new ones are opened with a 2-6 s pause rather than all at once.
- **Server name and profile from the subscription.** A subscription can give a key its own server name (SNI) and TLS profile and change them; the app takes the values from the last update.
- **NineLives** ("For experts", needs the [CatTunnel server](https://github.com/Cattunnel/cattunnel-server) or another one that supports it): a pair of GET and POST requests instead of CONNECT, its own body encryption inside TLS using the server key, session resumption after a break for up to 60 seconds. Not compatible with XHTTP from Xray. Details: [docs/ninelives.md](docs/ninelives.md) (in Russian).
- **QUIC blocking** inside the tunnel: browsers fall back to TCP.
- Clear failure reasons and gentle retries if a filter has temporarily "frozen" the server address.

### Split tunneling

- Sites, IP addresses, networks and apps bypass the VPN; your own list is editable.
- **Apps on Windows and Linux** (since 1.5.6, no driver): connections of the selected programs either bypass the VPN or go only through the VPN. The core finds the socket owner (Windows: `GetExtendedTcpTable`/`GetExtendedUdpTable`, Linux: `NETLINK_SOCK_DIAG`).
  *DNS is not split everywhere.* On Windows and on Linux with systemd-resolved, names for programs are resolved by the system, so requests of an excluded program go through the tunnel's DNS: there is no leak to the provider, but the site address is chosen for the server's country, and without the tunnel the excluded program is left without DNS. To make DNS bypass the tunnel too, turn on the program's own DNS ("Secure DNS" in Chrome or DoH in Firefox). On Linux without systemd-resolved the program asks for DNS itself, and its requests bypass the tunnel together with the rest of its traffic, as on Android.
- Russian networks and domains are pulled in automatically (runetfreedom, ipverse, hydraponique) and refreshed once a day.
- "Auto" mode: Russian, Chinese and Uzbek services and the phone manufacturer's apps bypass the VPN; the Russian ones always, the others can be put back into the tunnel.
- **Yandex Browser always stays in the VPN**, even though it is Russian: for many people it is the main browser, and otherwise almost all of their traffic would bypass the tunnel. Yandex sites still go directly under the domain rules.
- Downloaded lists are checked for plausibility: a rule such as `0.0.0.0/0` ("everything bypasses the VPN") is dropped, and on a suspicious download the previous copy is kept. The address of the VPN server itself is always subtracted from the lists.

### Diagnostics: the cat Marsik

- If a connection hangs for 10 seconds, Marsik checks the network, server availability, the secure connection, keys and subscription, says in one line what is wrong and offers one action. Checks go only to your own servers.
- If the system did not allow creating a VPN, it says so directly.
- "Report a problem": a report for the administrator without passwords, keys and hardware addresses; on Windows and Linux it is saved to "Downloads" and copied to the clipboard.
- Marsik can be petted: compliments, a counter, easter eggs, purring and sometimes poems.

### Security and privacy

- **Strict server certificate check** (on by default on Android, Windows and Linux): only the system root certificates, without "Russian Trusted Root/Sub CA" (by name and by key fingerprint) and without manually installed ones. It can be turned off only after three confirmations.
- A server link or file from another person does not turn on "Russian exit" by itself; invisible characters and text-direction control characters in server names are removed; subscription, update and list responses are limited in size.
- Device and leak checks, a panic button (erase app data), disguise as "Calculator", app lock, screenshot protection for screens with keys.
- No analytics or ads, ML Kit telemetry is disabled; data does not go into cloud backups; passwords, keys and subscription addresses are not written to the log.

More: [docs/security/](docs/security/) (in Russian).

### Desktop

- **Linux:** Arch and Debian packages; the app runs as a user, and root rights belong only to a helper with a command allowlist and a hardened systemd unit.
- **Windows:** installer and updates from within the app; a tray icon, the close button hides the window to the tray.
- **Tray icon on Linux** written in Dart over D-Bus (StatusNotifierItem), with no new system libraries: KDE, XFCE, Cinnamon, MATE, Ubuntu.

### Appearance and updates

- Five home screen styles, chosen by swiping previews: "Cozy", "Minimalism", "Y2K", "Aero" and "City pop". On tablets the app rotates. Dark theme, a "What's new" window, first-run tutorial, Russian and English interface.
- Android and Windows update from within the app: `latest.json` is signed with Ed25519, files are checked by SHA-256, and the update address is set only at build time.

## Installation

Files are in the [releases](../../releases/latest).

| File | Platform | Note |
| :--- | :--- | :--- |
| `cattunnel-arm64.apk` | Android 8.0+, `arm64-v8a` | Main build |
| `cattunnel-universal.apk` | Android 8.0+, `arm64-v8a` + `armeabi-v7a` | For old 32-bit devices |
| `cattunnel-windows-setup.exe` | Windows 10/11 x64 | Installer |
| `cattunnel-linux.deb` | Debian, Ubuntu | `sudo apt install ./cattunnel-linux.deb` |
| `cattunnel-linux.pkg.tar.zst` | Arch Linux | `sudo pacman -U …`; a `PKGBUILD` for building from source is next to it |

**Windows:** the installer is not signed with a developer certificate, so SmartScreen may show "Windows protected your PC": "More info" → "Run anyway". For the same reason some antivirus products with heuristics occasionally flag the installer (VirusTotal results are in the description of each release). The file's authenticity is checked with `SHA256SUMS` (see below). Updates then arrive from within the app.

**Linux:** the app runs as an ordinary user; root rights are needed only by a small helper `cattunnel-helper` (systemd, access through the `cattunnel` group), see [plugins/vpn_plugin/linux/HELPER.md](plugins/vpn_plugin/linux/HELPER.md) and [linux/packaging/README.md](linux/packaging/README.md).

**Routers** (OpenWrt, Keenetic, ASUS Merlin): a separate repository, [cattunnel-router](https://github.com/Cattunnel/cattunnel-router).

### Verifying authenticity

The release files are listed in `SHA256SUMS`, signed with an Ed25519 key. Public key: [`linux/packaging/cattunnel-release.pub.pem`](linux/packaging/cattunnel-release.pub.pem).

```bash
openssl pkeyutl -verify -pubin -inkey cattunnel-release.pub.pem -rawin \
  -in SHA256SUMS -sigfile <(base64 -d SHA256SUMS.sig)
sha256sum -c SHA256SUMS --ignore-missing
```

Android app signing certificate: `CN=CatTunnel`, SHA-256 `42:6C:CE:9A:C6:62:B2:D1:41:01:E2:7F:0C:B6:7E:0C:AA:23:13:7B:CC:29:1C:6D:6A:06:EF:11:62:99:AF:B7`.

## Setup

1. Add a server: "Add server", then a `tt://` link, a QR code (the "From gallery" button reads a QR from an image) or manual entry. The server prints the `tt://` link with its export command (`trusttunnel_endpoint … -c <user> -a <address>`, see the [server README](https://github.com/Cattunnel/cattunnel-server#export-a-client-configuration)).
2. Or add a subscription: "Add server" → "Subscription", an `https://` address or a one-time code from the administrator. The subscription creates the servers by itself and keeps them updated.
3. Press "Connect". If it does not connect within 10 seconds, Marsik shows the reason.

Anti-DPI and the TLS fingerprint are in the server settings, section "Bypass blocking"; size masking, QUIC blocking, keepalive and NineLives are in the "For experts" section. Keys from a subscription are overwritten by the subscription on every update unless the "Above subscription" switch is on. Detailed guide: [assets/readme/README.en.md](assets/readme/README.en.md); how the connection works: [assets/readme/CONNECTION.ru.md](assets/readme/CONNECTION.ru.md) (in Russian).

## Building from source

**Requirements:** Flutter **3.38.3** (the version is pinned in `pubspec.yaml`), JDK 17, Android SDK (platform 36), NDK `29.0.14206865`, a GitHub token with the `read:packages` scope: the TrustTunnel Android engine is downloaded from GitHub Packages.

```bash
export GPR_KEY=<token with read:packages>
make init          # dependencies and code generation
flutter test
```

**Android**

```bash
# Main build (arm64)
flutter build apk --release --split-per-abi --target-platform android-arm64

# Universal (arm64 + armv7), with the same versionCode as arm64
flutter build apk --release --target-platform android-arm,android-arm64 --build-number=<versionCode arm64>

# In-app updates: the latest.json address and the key it is signed with
flutter build apk ... \
  --dart-define=UPDATE_URL=https://github.com/Cattunnel/cattunnel/releases/latest/download/latest.json \
  --dart-define=UPDATE_PUBKEY=$(openssl pkey -pubin -in linux/packaging/cattunnel-release.pub.pem -outform DER | tail -c 32 | base64)

# Your own application id (fork, parallel install)
ORG_GRADLE_PROJECT_appId=org.example.myvpn flutter build apk ...
```

The release signature is taken from `android/key.properties` and `android/keystore/` (both paths are in `.gitignore`). Without them the build is signed with a debug key, and such an APK will not install over the official one.

**Windows and Linux:** the installer is in [`windows/installer/`](windows/installer/), the Arch and Debian packages in [`linux/packaging/`](linux/packaging/README.md).

**Network core:** an own build of TrustTunnelClient with CatTunnel patches, scripts and patches in [`tools/engine_native/`](tools/engine_native/README.md), Android engine patches in [`tools/engine_patch/`](tools/engine_patch/). The patches in these folders describe core 1.3.0-rc.1 with anti-DPI, failure reasons, the first version of size masking, QUIC blocking and per-program split. In 1.5.9 the app on all platforms and the router are built from one core revision (`82963908`); its changes on top of these patches (connection pool, NineLives, padding shaper, browser-like `CONNECT` headers) have not been published to this folder yet.

<details>
<summary>Build notes</summary>

- `--split-per-abi` adds 2000 to the `versionCode` for arm64, so the number is passed explicitly for the universal build.
- x86/x86_64 libraries are excluded from the APK: the app will not start on x86 emulators.
- `tools/update_engine.sh <version>` changes the core version for all platforms at once.
- `latest.json` for a release: `tools/make_latest_json.sh https://github.com/Cattunnel/cattunnel/releases/download/v<version> <arm64.apk> <universal.apk> notes.txt`, signing: `tools/sign_latest_json.sh`.
- Changes from the original TrustTunnel Flutter Client are brought over one by one (cherry-pick): the history of this repository starts anew, and there is no common ancestor with upstream.

</details>

## Documentation

| File | What it covers |
|---|---|
| [docs/how-it-works.md](docs/how-it-works.md) (in Russian) | Diagnostics, certificate check, subscriptions, routes, the own core |
| [docs/subscriptions.md](docs/subscriptions.md) (in Russian) | Subscription format, age encryption, device key, mirrors, polling, one-time codes |
| [docs/anti-dpi.md](docs/anti-dpi.md) (in Russian) | Anti-DPI modes, custom string, connection pool, TLS authorization key, failure reasons |
| [docs/padding.md](docs/padding.md) (in Russian) | HTTP/2 size masking: parameters, budgets, link tags |
| [docs/ninelives.md](docs/ninelives.md) (in Russian) | The NineLives transport on the client side |
| [docs/security/](docs/security/) (in Russian) | Known security limitations, the Linux helper |
| [assets/readme/README.en.md](assets/readme/README.en.md) | User guide (also inside the app) |

## Structure

```text
lib/                      the app (Flutter)
  feature/companion/      Marsik
  feature/vpn/domain/     diagnostics, anti-DPI "Auto", TLS fingerprint
  feature/security/       device and leak checks, panic button
  feature/subscriptions/  subscriptions, QR, import
plugins/vpn_plugin/       bindings to TrustTunnelClient (Pigeon); linux/helper: privileged helper
packages/dage/            age library with compatibility fixes
tools/engine_native/      build of the own core and the anti-DPI patch
tools/engine_patch/       Android engine patches
android/ ios/ macos/ windows/ linux/   platform parts, installer and packages
docs/                     design, subscriptions, anti-DPI, padding, NineLives, security
test/                     tests (flutter test)
```

## Security

If you found a vulnerability, please do not post it in Issues; report it through [GitHub Security Advisories](../../security/advisories/new).

## License

CatTunnel is distributed under the [Apache-2.0](LICENSE) license, like the original TrustTunnel Flutter Client © Adguard Software Ltd. Third-party code and materials keep their own licenses: see [NOTICE](NOTICE) and `assets/licenses/` (also shown on the licenses page in the app). The exception: Marsik's poems are protected by copyright and are not distributed under Apache-2.0 (details in NOTICE).

"TrustTunnel" and "AdGuard" are trademarks of their owners. CatTunnel is not affiliated with them and only works over the TrustTunnel protocol.
