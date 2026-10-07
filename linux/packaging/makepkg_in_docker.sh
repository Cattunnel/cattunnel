#!/usr/bin/env bash
# Builds the Arch package from build/arch/ (build_release.sh) in an Arch
# container on a Docker host, checks it (bundle byte-identical, pacman -U),
# brings cattunnel-<ver>-1-x86_64.pkg.tar.zst back and re-signs SHA256SUMS.
#
#   linux/packaging/makepkg_in_docker.sh root@docker-host
#
# The host needs docker and an ssh key login; nothing of ours stays there
# except /root/archbuild (removed at the start of the next run).
set -euo pipefail

HOST=${1:?usage: makepkg_in_docker.sh <ssh-host with docker>}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$ROOT/build/arch
cd "$OUT"
VERSION=$(sed -n 's/^pkgver=//p' PKGBUILD)
APP="cattunnel-app-$VERSION-x86_64.tar.gz"
PKG="cattunnel-$VERSION-1-x86_64.pkg.tar.zst"

ssh "$HOST" 'rm -rf /root/archbuild && mkdir -p /root/archbuild'
scp -q PKGBUILD cattunnel.install "$APP" "cattunnel-helper-src-$VERSION.tar.gz" trusttunnel_client-v*-cattunnel-linux-x86_64.tar.gz "$HOST:/root/archbuild/"
ssh "$HOST" "docker run --rm -v /root/archbuild:/build archlinux:latest bash -ec '
    pacman -Syu --noconfirm --needed base-devel cmake ninja gtk3 gstreamer gst-plugins-base-libs \
        gst-plugins-good zenity xdg-utils iproute2 >/dev/null
    useradd -m builder && cp -r /build /home/builder/pkg && chown -R builder /home/builder/pkg
    cd /home/builder/pkg && runuser -u builder -- makepkg -f --noconfirm | tail -1
    cp $PKG /build/
    mkdir /x /y && tar -C /x -xf /build/$APP && tar -C /y -xf /build/$PKG
    diff -r /x/bundle /y/opt/cattunnel && echo \"app bundle byte-identical\"
    pacman -U --noconfirm /build/$PKG >/dev/null && echo \"pacman -U ok\"
'"
scp -q "$HOST:/root/archbuild/$PKG" .

sha256sum PKGBUILD cattunnel.install "$APP" "cattunnel-helper-src-$VERSION.tar.gz" "$PKG" trusttunnel_client-v*-cattunnel-linux-x86_64.tar.gz $(ls cattunnel_*_amd64.deb 2>/dev/null) > SHA256SUMS
cd "$ROOT"
tools/sign_latest_json.sh sign "$OUT/SHA256SUMS"
openssl pkeyutl -verify -pubin -inkey linux/packaging/cattunnel-release.pub.pem -rawin \
    -in "$OUT/SHA256SUMS" -sigfile <(base64 -d "$OUT/SHA256SUMS.sig") >/dev/null
echo "$PKG built, checked and signed -> $OUT"
