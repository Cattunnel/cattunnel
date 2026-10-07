#!/usr/bin/env bash
# Switch every platform to another TrustTunnel engine version.
#
#   tools/update_engine.sh 1.1.8
#
# Writes ENGINE_VERSION (read by Gradle for the Android AAR, and later by
# CMake for the desktop CLI client) and ENGINE_SHA256 (hashes of the desktop
# CLI archives from the public GitHub release; the desktop build refuses an
# archive whose hash differs). Checks first that the version exists both as
# a GitHub release and as the Android package. Needs `gh` logged in with
# read:packages. Then: rebuild, test, commit both files.
set -euo pipefail

REPO=TrustTunnel/TrustTunnelClient
ANDROID_PACKAGE=com.adguard.trusttunnel.trusttunnel-client-android
DESKTOP_TARGETS=(windows-x86_64.zip linux-x86_64.tar.gz linux-aarch64.tar.gz)

VERSION=${1:?usage: tools/update_engine.sh <version>, e.g. 1.1.8}
VERSION=${VERSION#v}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "Checking release v$VERSION of $REPO..."
gh api "repos/$REPO/releases/tags/v$VERSION" --jq '.tag_name' >/dev/null \
    || { echo "No GitHub release v$VERSION" >&2; exit 1; }

echo "Checking the Android package $VERSION..."
gh api "orgs/TrustTunnel/packages/maven/$ANDROID_PACKAGE/versions" --paginate --jq '.[].name' \
    | grep -qxF "$VERSION" \
    || { echo "No Android package $VERSION (GitHub Packages) - not released for Android yet" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

{
    echo "# sha256 of the desktop CLI archives of engine $VERSION (tools/update_engine.sh)"
    for target in "${DESKTOP_TARGETS[@]}"; do
        file="trusttunnel_client-v$VERSION-$target"
        echo "Downloading $file..." >&2
        gh release download "v$VERSION" -R "$REPO" -p "$file" -D "$TMP" >&2
        (cd "$TMP" && sha256sum "$file")
    done
} > "$TMP/ENGINE_SHA256"

echo "$VERSION" > "$ROOT/ENGINE_VERSION"
mv "$TMP/ENGINE_SHA256" "$ROOT/ENGINE_SHA256"

echo "Engine set to $VERSION:"
cat "$ROOT/ENGINE_SHA256"

echo
echo "Android uses this engine with CatTunnel patches: now run tools/engine_patch/build.sh"
echo "(if a patch no longer applies, update tools/engine_patch/0*.patch for the new sources)."
