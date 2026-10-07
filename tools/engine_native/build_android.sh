#!/usr/bin/env bash
# Android native core (libtrusttunnel_android.so) with 0001-anti-dpi-desync,
# for tools/engine_patch/build.sh (NATIVE_JNI=...). Needs what build_linux.sh
# needs (conan, ~/tt-build/conan-home) plus NDK 29.0.14206865, JDK 17,
# `rustup target add aarch64-linux-android armv7-linux-androideabi
# x86_64-linux-android i686-linux-android` and `cargo install cargo-ndk`.
#
#   TT_ABIS=arm64-v8a,armeabi-v7a,x86,x86_64 tools/engine_native/build_android.sh
set -euo pipefail
B=~/tt-build
export PATH=$B/conan/bin:$HOME/.cargo/bin:$HOME/development/jdk-17/bin:$PATH
export CONAN_HOME=$B/conan-home JAVA_HOME=$HOME/development/jdk-17
export ANDROID_HOME=$HOME/Android/Sdk ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/29.0.14206865
export TT_ABIS=${TT_ABIS:-arm64-v8a}
cd $B/TrustTunnelClient/platform/android
printf 'sdk.dir=%s\ncmake.dir=/usr\n' "$ANDROID_HOME" > local.properties
# Upstream builds every ABI; TT_ABIS narrows it (one ABI ~25 min cold).
grep -q TT_ABIS lib/build.gradle.kts || sed -i \
  's/^        minSdk = 26$/        minSdk = 26\n        ndk { abiFilters += (System.getenv("TT_ABIS") ?: "arm64-v8a").split(",") }/' \
  lib/build.gradle.kts
./gradlew --no-daemon assembleRelease
OUT=$B/jni; rm -rf "$OUT"; mkdir -p "$OUT"
cp -r lib/build/intermediates/stripped_native_libs/release/stripReleaseDebugSymbols/out/lib/* "$OUT/"
ls -la "$OUT"/*/libtrusttunnel_android.so
echo "Next: NATIVE_JNI=$OUT tools/engine_patch/build.sh"
