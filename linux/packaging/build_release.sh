#!/usr/bin/env bash
# Makes everything the Arch package needs, in build/arch/:
#   cattunnel-app-<ver>-x86_64.tar.gz     the Flutter bundle (flutter build linux)
#   cattunnel-helper-src-<ver>.tar.gz     git archive of HEAD: helper sources,
#                                         packaging files, licenses, icon
#   PKGBUILD, cattunnel.install           from PKGBUILD.in, hashes filled in
#   SHA256SUMS, SHA256SUMS.sig            all of the above, Ed25519-signed
# Then on Arch: cd build/arch && makepkg -si
#
#   linux/packaging/build_release.sh <version> <build-number> [--skip-flutter-build]
#   e.g. linux/packaging/build_release.sh 1.4.5 2013
# Version and build number as for the other platforms' releases (the About
# screen shows the version; pkgver is the same, so digits and dots only).
#
# The helper source tarball is a `git archive` of HEAD, so the packaged
# paths must be committed - otherwise what the PKGBUILD says it was built
# from would be a lie.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
FLUTTER=${FLUTTER:-$HOME/development/flutter-3.38.3/bin/flutter}  # pubspec pins Dart 3.10.1
OUT=$ROOT/build/arch

PACKAGED=(ENGINE_VERSION LICENSE NOTICE assets/icon/icon_square.png linux/packaging
          plugins/vpn_plugin/common plugins/vpn_plugin/linux/helper plugins/vpn_plugin/linux/HELPER.md
          tools/engine_native)

VERSION=${1:?usage: build_release.sh <version> <build-number> [--skip-flutter-build]}
BUILD=${2:?usage: build_release.sh <version> <build-number> [--skip-flutter-build]}
[[ $VERSION =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "version: digits and dots only (pkgver)" >&2; exit 1; }
[[ $BUILD =~ ^[0-9]+$ ]] || { echo "build number: digits only" >&2; exit 1; }
ENGINE=$(tr -d '[:space:]' < ENGINE_VERSION)
# Our own engine build (tools/engine_native/build_linux.sh: upstream tag +
# 0001-anti-dpi-desync.patch), not the upstream release binary.
ENGINE_BIN=${ENGINE_BIN:-$HOME/tt-build/TrustTunnelClient/build/trusttunnel/trusttunnel_client}
[[ -x $ENGINE_BIN ]] || { echo "No engine build at $ENGINE_BIN (tools/engine_native/build_linux.sh)" >&2; exit 1; }
grep -qa "Anti-DPI mode" "$ENGINE_BIN" || { echo "$ENGINE_BIN lacks the anti-DPI patch" >&2; exit 1; }
ENGINE_DIR="trusttunnel_client-v$ENGINE-cattunnel-linux-x86_64"
ENGINE_ARCHIVE="$ENGINE_DIR.tar.gz"

if ! git diff --quiet HEAD -- "${PACKAGED[@]}" || [[ -n $(git ls-files --others --exclude-standard -- "${PACKAGED[@]}") ]]; then
    echo "Commit the packaged paths first (${PACKAGED[*]})" >&2
    exit 1
fi
COMMIT=$(git rev-parse HEAD)

if [[ ${3:-} != --skip-flutter-build ]]; then
    "$FLUTTER" build linux --release --build-name="$VERSION" --build-number="$BUILD"
fi
BUNDLE=${CATTUNNEL_BUNDLE:-build/linux/x64/release/bundle}  # override: packaging tests
[[ -x $BUNDLE/cattunnel ]] || { echo "No $BUNDLE/cattunnel - run without --skip-flutter-build" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
APP="cattunnel-app-$VERSION-x86_64.tar.gz"
SRC="cattunnel-helper-src-$VERSION.tar.gz"
tar -C "$(dirname "$BUNDLE")" --owner=0 --group=0 -czf "$OUT/$APP" bundle
git archive --format=tar.gz --prefix=src/ -o "$OUT/$SRC" "$COMMIT" "${PACKAGED[@]}"
ENGINE_TMP=$(mktemp -d)
install -Dm755 "$ENGINE_BIN" "$ENGINE_TMP/$ENGINE_DIR/trusttunnel_client"
strip "$ENGINE_TMP/$ENGINE_DIR/trusttunnel_client"
install -m644 "$(dirname "$ENGINE_BIN")/../../LICENSE" "$ENGINE_TMP/$ENGINE_DIR/LICENSE"
tar -C "$ENGINE_TMP" --owner=0 --group=0 --mtime=@0 -czf "$OUT/$ENGINE_ARCHIVE" "$ENGINE_DIR"
rm -rf "$ENGINE_TMP"
ENGINE_HASH=$(sha256sum "$OUT/$ENGINE_ARCHIVE" | cut -d' ' -f1)

sed -e "s/@PKGVER@/$VERSION/" \
    -e "s/@ENGINE@/$ENGINE/" \
    -e "s/@COMMIT@/$COMMIT/" \
    -e "s/@APP_SHA256@/$(sha256sum "$OUT/$APP" | cut -d' ' -f1)/" \
    -e "s/@SRC_SHA256@/$(sha256sum "$OUT/$SRC" | cut -d' ' -f1)/" \
    -e "s/@ENGINE_SHA256@/$ENGINE_HASH/" \
    linux/packaging/PKGBUILD.in > "$OUT/PKGBUILD"
cp linux/packaging/cattunnel.install "$OUT/"
# Signed checksums: the same Ed25519 key as the phones' latest.json
# (tools/sign_latest_json.sh); the public half is linux/packaging/cattunnel-release.pub.pem.
(cd "$OUT" && sha256sum PKGBUILD cattunnel.install "$APP" "$SRC" "$ENGINE_ARCHIVE" > SHA256SUMS)
if [[ -e ${UPDATE_SIGNING_KEY:-android/keystore/update-signing.pem} ]]; then
    tools/sign_latest_json.sh sign "$OUT/SHA256SUMS"
    openssl pkeyutl -verify -pubin -inkey linux/packaging/cattunnel-release.pub.pem -rawin \
        -in "$OUT/SHA256SUMS" -sigfile <(base64 -d "$OUT/SHA256SUMS.sig") >/dev/null \
        || { echo "SHA256SUMS.sig doesn't verify with cattunnel-release.pub.pem" >&2; exit 1; }
else
    echo "WARNING: no signing key - SHA256SUMS left unsigned" >&2
fi
if command -v makepkg >/dev/null; then
    (cd "$OUT" && makepkg --printsrcinfo > .SRCINFO)
fi

echo "CatTunnel $VERSION (engine $ENGINE, commit ${COMMIT:0:12}) -> $OUT"
ls -l "$OUT"
