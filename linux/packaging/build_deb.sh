#!/usr/bin/env bash
# The Debian package (Debian 13 / Ubuntu 24.04+, amd64), same layout as the Arch
# one: /opt/cattunnel (app), /usr/lib/cattunnel/{cattunnel-helper,trusttunnel_client},
# the systemd unit, the cattunnel group. Run after build_release.sh (it takes the
# app bundle and the engine archive from build/arch/); the helper is compiled here
# from the committed sources.
#
#   linux/packaging/build_deb.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$ROOT/build/arch
cd "$OUT"
VERSION=$(sed -n 's/^pkgver=//p' PKGBUILD)
ENGINE_ARCHIVE=$(ls trusttunnel_client-v*-cattunnel-linux-x86_64.tar.gz)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

tar -C "$W" -xzf "cattunnel-helper-src-$VERSION.tar.gz"
cmake -S "$W/src/plugins/vpn_plugin/linux/helper" -B "$W/helper" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DHELPER_TESTS=OFF >/dev/null
cmake --build "$W/helper" >/dev/null
tar -C "$W" -xzf "$ENGINE_ARCHIVE"
tar -C "$W" -xzf "cattunnel-app-$VERSION-x86_64.tar.gz"

P=$W/pkg; S=$W/src/linux/packaging
install -d "$P/opt/cattunnel" "$P/usr/bin" "$P/DEBIAN"
cp -a "$W/bundle/." "$P/opt/cattunnel/"
ln -s /opt/cattunnel/cattunnel "$P/usr/bin/cattunnel"
install -Dm755 "$W/helper/cattunnel-helper" "$P/usr/lib/cattunnel/cattunnel-helper"
install -Dm755 "$W/${ENGINE_ARCHIVE%.tar.gz}/trusttunnel_client" "$P/usr/lib/cattunnel/trusttunnel_client"
install -Dm644 "$S/cattunnel-helper.service" "$P/usr/lib/systemd/system/cattunnel-helper.service"
install -Dm644 "$S/cattunnel.sysusers" "$P/usr/lib/sysusers.d/cattunnel.conf"
install -Dm644 "$S/com.cattunnel.app.desktop" "$P/usr/share/applications/com.cattunnel.app.desktop"
install -Dm644 "$W/src/assets/icon/icon_square.png" "$P/usr/share/icons/hicolor/1024x1024/apps/com.cattunnel.app.png"
install -Dm644 "$W/src/plugins/vpn_plugin/linux/HELPER.md" "$P/usr/share/doc/cattunnel/HELPER.md"
install -Dm644 "$S/README.md" "$P/usr/share/doc/cattunnel/README.md"
install -Dm644 "$W/src/LICENSE" "$P/usr/share/doc/cattunnel/copyright"
install -Dm644 "$W/${ENGINE_ARCHIVE%.tar.gz}/LICENSE" "$P/usr/share/doc/cattunnel/LICENSE.trusttunnel_client"
install -Dm644 "$W/src/tools/engine_native/0001-anti-dpi-desync.patch" \
    "$P/usr/share/doc/cattunnel/engine-0001-anti-dpi-desync.patch"

cat > "$P/DEBIAN/control" <<CTRL
Package: cattunnel
Version: $VERSION
Architecture: amd64
Maintainer: CatTunnel <339258084+Cattunnel@users.noreply.github.com>
Section: net
Priority: optional
Depends: libgtk-3-0t64 | libgtk-3-0, libgstreamer1.0-0, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good, zenity, xdg-utils, iproute2, systemd
Recommends: network-manager
Installed-Size: $(du -sk "$P" | cut -f1)
Homepage: https://github.com/Cattunnel/cattunnel
Description: CatTunnel - VPN client for TrustTunnel servers
 The app runs as the user; the root part is cattunnel-helper (systemd),
 which runs trusttunnel_client (TrustTunnelClient with CatTunnel's anti-DPI
 patch) and points DNS at the tunnel. See /usr/share/doc/cattunnel/HELPER.md.
CTRL

# Same steps as cattunnel.install (Arch), in Debian's maintainer scripts.
cat > "$P/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
    systemd-sysusers /usr/lib/sysusers.d/cattunnel.conf >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [ -n "$2" ] && systemctl is-active --quiet cattunnel-helper; then
        # Upgrade: the new root part takes effect after a restart - not while a VPN is up.
        if pgrep -f /usr/lib/cattunnel/trusttunnel_client >/dev/null 2>&1; then
            echo "CatTunnel: the VPN is on - restart the helper after disconnecting: sudo systemctl restart cattunnel-helper"
        else
            systemctl restart cattunnel-helper || true
        fi
    elif [ -z "$2" ]; then
        echo "CatTunnel: two steps, once:"
        echo "  1. sudo usermod -aG cattunnel \"\$USER\"   (then log out and back in)"
        echo "  2. sudo systemctl enable --now cattunnel-helper"
        echo "  Details: /usr/share/doc/cattunnel/HELPER.md"
    fi
fi
exit 0
POST
cat > "$P/DEBIAN/prerm" <<'PRERM'
#!/bin/sh
set -e
if [ "$1" = remove ]; then
    systemctl disable --now cattunnel-helper >/dev/null 2>&1 || true
fi
exit 0
PRERM
chmod 755 "$P/DEBIAN/postinst" "$P/DEBIAN/prerm"

DEB="cattunnel_${VERSION}_amd64.deb"
fakeroot dpkg-deb --build --root-owner-group -Zxz "$P" "$OUT/$DEB" >/dev/null
echo "$OUT/$DEB"
dpkg-deb -I "$OUT/$DEB" | sed -n '1,4p'
