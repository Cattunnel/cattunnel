#!/usr/bin/env bash
# Builds the TrustTunnel Android engine with CatTunnel's patches
# (0001-per-app-split.patch: excluded_apps / included_apps) without the
# upstream native build, which needs AdGuard's private Conan remote:
#
#   1. the official AAR of ENGINE_VERSION (Gradle cache, or GitHub Packages)
#   2. upstream Kotlin sources of the same tag + our patch
#   3. only the patched files are compiled, against the original classes.jar
#   4. their classes replace the originals in classes.jar; the native .so
#      files and everything else stay byte-for-byte the same
#   5. the result goes to android/engine-maven as <ver>-cattunnel.<n>
#
#   tools/engine_patch/build.sh
set -euo pipefail

# zip isn't always installed; python is.
zipdir() { python3 -c '
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            z.write(path, os.path.relpath(path, src))
' "$1" "$2"; }

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT/ENGINE_VERSION")
PATCH_LEVEL=$(tr -d "[:space:]" < "$HERE/PATCH_LEVEL")
OUT_VERSION="$VERSION-cattunnel.$PATCH_LEVEL"
GROUP_PATH=com/adguard/trusttunnel
ARTIFACT=trusttunnel-client-android
SOURCES=(VpnService.kt VpnServiceConfig.kt)
SRC_DIR=platform/android/lib/src/main/java/$GROUP_PATH

CACHE=~/.gradle/caches/modules-2/files-2.1/com.adguard.trusttunnel/$ARTIFACT/$VERSION
AAR=$(ls "$CACHE"/*/"$ARTIFACT-$VERSION.aar" 2>/dev/null | head -1 || true)
POM=$(ls "$CACHE"/*/"$ARTIFACT-$VERSION.pom" 2>/dev/null | head -1 || true)
if [[ ! -f $AAR || ! -f $POM ]]; then
    # Not in the Gradle cache (the app only resolves the patched version):
    # fetch the official one from GitHub Packages with gh's token
    # (read:packages, as tools/update_engine.sh needs).
    echo "Downloading the official $ARTIFACT $VERSION..."
    DL="$HERE/build/original"
    mkdir -p "$DL"
    BASE_URL="https://maven.pkg.github.com/TrustTunnel/TrustTunnelClient/$GROUP_PATH/$ARTIFACT/$VERSION/$ARTIFACT-$VERSION"
    for ext in aar pom; do
        curl -fsSL -u "_:$(gh auth token)" -o "$DL/$ARTIFACT-$VERSION.$ext" "$BASE_URL.$ext"
    done
    AAR="$DL/$ARTIFACT-$VERSION.aar"
    POM="$DL/$ARTIFACT-$VERSION.pom"
fi

WORK="$HERE/build"
rm -rf "$WORK/upstream" "$WORK/patched-src" "$WORK/aar" "$WORK/out" "$WORK/classes"
mkdir -p "$WORK/upstream/$SRC_DIR" "$WORK/patched-src/$GROUP_PATH" "$WORK/aar" "$WORK/out"

echo "Upstream sources v$VERSION..."
for f in "${SOURCES[@]}"; do
    gh api "repos/TrustTunnel/TrustTunnelClient/contents/$SRC_DIR/$f?ref=v$VERSION" --jq .content \
        | base64 -d > "$WORK/upstream/$SRC_DIR/$f"
done
for p in "$HERE"/0*.patch; do
    patch -d "$WORK/upstream" -p1 --no-backup-if-mismatch < "$p"
done
cp "$WORK/upstream/$SRC_DIR/"*.kt "$WORK/patched-src/$GROUP_PATH/"

(cd "$WORK/aar" && unzip -q "$AAR")

# NATIVE_JNI=<dir with <abi>/libtrusttunnel_android.so>: our own native
# build (tools/engine_native, patch 0001-anti-dpi-desync) replaces the
# official .so of each ABI it has; the other ABIs stay official.
if [[ -n ${NATIVE_JNI:-} ]]; then
    for so in "$NATIVE_JNI"/*/libtrusttunnel_android.so; do
        abi=$(basename "$(dirname "$so")")
        [[ -f $WORK/aar/jni/$abi/libtrusttunnel_android.so ]] || { echo "Unknown ABI $abi in $NATIVE_JNI" >&2; exit 1; }
        cp "$so" "$WORK/aar/jni/$abi/libtrusttunnel_android.so"
        echo "Native $abi: own build"
    done
fi

echo "Compiling the patched classes..."
"$ROOT/android/gradlew" -q -p "$HERE" compileReleaseKotlin -PoriginalClassesJar="$WORK/aar/classes.jar"
COMPILED="$HERE/build/tmp/kotlin-classes/release"
[[ -f $COMPILED/$GROUP_PATH/VpnService.class ]] || { echo "No compiled classes in $COMPILED" >&2; exit 1; }

echo "Splicing into classes.jar..."
mkdir -p "$WORK/classes"
rm -rf "$WORK/classes"/*
(cd "$WORK/classes" && unzip -q "$WORK/aar/classes.jar")
# Every class compiled from the patched files replaces its original; the
# originals of those files that no longer exist are removed too.
for f in "${SOURCES[@]}"; do
    base=${f%.kt}
    case $base in
        VpnServiceConfig) patterns=(VpnServiceConfig Tun Listener Endpoint) ;;
        *) patterns=("$base") ;;
    esac
    for n in "${patterns[@]}"; do
        rm -f "$WORK/classes/$GROUP_PATH/$n.class" "$WORK/classes/$GROUP_PATH/$n\$"*.class
    done
done
cp "$COMPILED/$GROUP_PATH/"*.class "$WORK/classes/$GROUP_PATH/"
rm -f "$WORK/aar/classes.jar"
zipdir "$WORK/classes" "$WORK/aar/classes.jar"

DEST="$ROOT/android/engine-maven/$GROUP_PATH/$ARTIFACT/$OUT_VERSION"
mkdir -p "$DEST"
rm -f "$DEST/$ARTIFACT-$OUT_VERSION.aar"
zipdir "$WORK/aar" "$DEST/$ARTIFACT-$OUT_VERSION.aar"
sed "s#<version>$VERSION</version>#<version>$OUT_VERSION</version>#" "$POM" > "$DEST/$ARTIFACT-$OUT_VERSION.pom"
grep -q "<version>$OUT_VERSION</version>" "$DEST/$ARTIFACT-$OUT_VERSION.pom" || { echo "pom version not replaced" >&2; exit 1; }

echo "Built $OUT_VERSION: $DEST"
sha256sum "$DEST/$ARTIFACT-$OUT_VERSION.aar"
