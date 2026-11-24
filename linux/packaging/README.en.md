# CatTunnel for Linux: Arch and Debian packages

Русский: [README.md](README.md) (the Russian text is the main one; if the two differ, the Russian text is right)

For the administrator who installs, verifies or builds the package. The app runs as a normal user. Only two things run as root: the small helper `cattunnel-helper` (its protocol is in [HELPER.en.md](../../plugins/vpn_plugin/linux/HELPER.en.md)) and the console client `trusttunnel_client`, the [TrustTunnelClient](https://github.com/TrustTunnel/TrustTunnelClient) core at the version in the `ENGINE_VERSION` file (currently 1.3.0-rc.1) with CatTunnel patches, see [tools/engine_native/README.en.md](../../tools/engine_native/README.en.md). App source: [Cattunnel/cattunnel](https://github.com/Cattunnel/cattunnel).

## 1. Verify the signature

`build_release.sh` writes to `build/arch/`: `PKGBUILD`, `cattunnel.install`, `cattunnel-app-<version>-x86_64.tar.gz` (the prebuilt app), `cattunnel-helper-src-<version>.tar.gz` (helper sources and packaging files), `trusttunnel_client-v<engine>-cattunnel-linux-x86_64.tar.gz` (our engine build), plus `SHA256SUMS` and `SHA256SUMS.sig` for all of them. Finished packages (`.pkg.tar.zst`, `.deb`) are added to `SHA256SUMS` and re-signed with the same key when they sit in that folder (`makepkg_in_docker.sh` adds the Arch package and every `cattunnel_*_amd64.deb`).

```
# the Ed25519 public key (file linux/packaging/cattunnel-release.pub.pem), the same one that checks Android and Windows updates:
openssl pkeyutl -verify -pubin -inkey cattunnel-release.pub.pem -rawin -in SHA256SUMS \
    -sigfile <(base64 -d SHA256SUMS.sig)          # "Signature Verified Successfully"
sha256sum -c SHA256SUMS                            # all OK
```

Key fingerprint (sha256 of the DER): `d1c58a11338b4840ce26ff3a27796cfd600f768e4bd5092b92b948c32b38adbf`. To get it from the file: `openssl pkey -pubin -in cattunnel-release.pub.pem -outform DER | sha256sum`. Compare it with the release author over a different channel from the one the archive came through.

The engine hash in the `PKGBUILD` (the `sha256sums` line) is the hash of our own archive `trusttunnel_client-v<engine>-cattunnel-linux-x86_64.tar.gz`, not of the official TrustTunnel archive. The hashes of the official archives are in the `ENGINE_SHA256` file at the repository root; the Linux package is not built from them. `makepkg` checks the hash itself.

## 2. Install

Release files are named (see the [root README](../../README.en.md)): `cattunnel-linux.pkg.tar.zst` for Arch and `cattunnel-linux.deb` for Debian and Ubuntu.

Arch, the finished package:
```
sudo pacman -U cattunnel-linux.pkg.tar.zst
```
Arch, building from the same sources (compiles the helper with cmake, ninja and gcc, installs the package):
```
makepkg -si
```
Debian 13 and Ubuntu 24.04 or newer, amd64:
```
sudo apt install ./cattunnel-linux.deb
```
Then, in every case:
```
sudo usermod -aG cattunnel "$USER"          # access to the helper socket; log out and back in
sudo systemctl enable --now cattunnel-helper
```

The package does not enable the service or the group: that is the administrator's decision. On a package upgrade the helper is restarted right away if no VPN is up; if one is up, the package tells you to restart it after disconnecting (`sudo systemctl restart cattunnel-helper`).

Arch dependencies: `gtk3`, `gstreamer`, `gst-plugins-base-libs`, `gst-plugins-good`, `zenity`, `xdg-utils`, `iproute2`, `systemd`; to build also `cmake`, `ninja`, `gcc`. Optional: `networkmanager` (DNS when systemd-resolved is off) and `systemd-resolved`. Debian dependencies are the `Depends` field in `build_deb.sh`; `network-manager` is recommended.

## 3. What runs as root and what it can do

| | |
|---|---|
| `/usr/lib/cattunnel/cattunnel-helper` | about 1150 lines of C++17 in the helper's `.cpp` files; third-party headers nlohmann/json and toml++. Sources in `cattunnel-helper-src-*.tar.gz` (`src/plugins/vpn_plugin/linux/helper/`) |
| `/usr/lib/cattunnel/trusttunnel_client` | the TrustTunnel console client (Apache-2.0) with CatTunnel patches; the build is described in [tools/engine_native/README.en.md](../../tools/engine_native/README.en.md) |
| `cattunnel-helper.service` | `NoNewPrivileges`, `ProtectSystem=true`, `ProtectHome`, `PrivateTmp`, `DevicePolicy=closed` with only `/dev/net/tun`, a `CapabilityBoundingSet` of six capabilities (`CAP_NET_ADMIN CAP_NET_RAW CAP_CHOWN CAP_FOWNER CAP_DAC_OVERRIDE CAP_KILL`), `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK`, `MemoryDenyWriteExecute`, `TasksMax=64` |

The helper listens on `/run/cattunnel/helper.sock` (0660, group `cattunnel`) and checks every client with `SO_PEERCRED`: root and members of the group are accepted. What a client can ask for:

- **start**: the client config in TOML. The helper refuses it if a key is not on the allow-list of what the app writes, if a value is a file path, if the SOCKS listener is not on loopback, or if sizes exceed the limits. The accepted config is written to `/run/cattunnel/client.toml` (root, 0600) and the client is started by absolute path with a clean environment. One client at a time.
- **stop**, **state**, **logs** (the client's last records, no passwords at the info level).
- **probe** and **relay**: a TCP connection to a numeric address bound to the physical interface (`SO_BINDTODEVICE`). Used for diagnostics and latency tests outside the tunnel.

The helper accepts no arbitrary commands, paths or client arguments.

## 4. DNS

The client sets DNS only through `resolvectl`. Without systemd-resolved it skips that step and queries would leave outside the tunnel, so for the session the helper replaces `/etc/resolv.conf` itself (with NetworkManager active it first installs a temporary `dns=none` file) and puts the original back on disconnect. The original is kept in `/var/lib/cattunnel/resolv.conf.backup`; if the helper crashed, the next start restores DNS and removes routing rules the client left behind. Details and a diagram: [HELPER.en.md](../../plugins/vpn_plugin/linux/HELPER.en.md).

## 5. How the package is built

```text
 Flutter build (flutter build linux)          engine trusttunnel_client (ENGINE_BIN, our build)
        |                                        |  check: the binary contains "Anti-DPI mode"
        v                                        v
 cattunnel-app-<version>-x86_64.tar.gz    trusttunnel_client-v<engine>-cattunnel-linux-x86_64.tar.gz
        \                                       /
         \    git archive HEAD (helper sources, packaging files)
          \            |          cattunnel-helper-src-<version>.tar.gz
           v           v
        PKGBUILD from PKGBUILD.in (hashes filled in), cattunnel.install
                       |
                       v
        SHA256SUMS  --Ed25519 signature-->  SHA256SUMS.sig
                       |
        makepkg_in_docker.sh -> cattunnel-<version>-1-x86_64.pkg.tar.zst
        build_deb.sh         -> cattunnel_<version>_amd64.deb
```

Figure 1. What the scripts in `linux/packaging/` do and which files come out.

- `build_release.sh <version> <build-number> [--skip-flutter-build]`: the version is digits and dots only (it is also `pkgver`). The script refuses to run if the packaged paths are not committed: `git archive` takes `HEAD`, and the `PKGBUILD` names the commit the helper was built from. The path of the finished engine is set by `ENGINE_BIN`. The signing key comes from `UPDATE_SIGNING_KEY` (default `android/keystore/update-signing.pem`); without it `SHA256SUMS` stays unsigned and the script prints a warning.
- `build_deb.sh` runs after `build_release.sh`: it takes the app bundle and the engine archive from `build/arch/`, compiles the helper again from the committed sources and packs the `.deb` (`dpkg-deb`, needs `fakeroot`).
- `makepkg_in_docker.sh <ssh-host>` builds the Arch package in an `archlinux:latest` container on a Docker host, checks that the app bundle in the package is byte-identical to the archive, checks `pacman -U` and signs `SHA256SUMS` again.

The package also installs `com.cattunnel.app.desktop` (the `tt://` link handler), the `cattunnel.sysusers` rule for group `cattunnel`, the licenses (`LICENSE`, `NOTICE`, the client's license), and `HELPER.md` with this file in `/usr/share/doc/cattunnel/`.

## 6. Removal

`sudo pacman -R cattunnel` or removing the Debian package: the service is disabled first (`pre_remove` in `cattunnel.install`, `prerm` in the `.deb`). The scripts do not delete group `cattunnel` or the `/var/log/cattunnel/` directory with the client log.

## 7. What Linux does not have

- Updates inside the app: the app updates itself only on Android and Windows (the check is in `lib/feature/updates/domain/update_service.dart`). On Linux you update the package.
- Import "From a file (.toml)" takes only the server (`[endpoint]`) from the file; the rest comes from the app settings.

Per-program split tunnelling and a tray icon do exist on Linux; the [root README](../../README.en.md) describes them.
