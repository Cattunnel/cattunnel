#!/usr/bin/env bash
# Сборка ядра TrustTunnelClient v1.1.7 (Linux x86_64, clang + libstdc++) без
# закрытого conan-репозитория AdGuard, по рецепту FreeTunnel (~/freetunnel_notes.md).
set -euo pipefail
B=~/tt-build
export PATH=$B/conan/bin:$HOME/.cargo/bin:$PATH
export CONAN_HOME=$B/conan-home
export CC=clang CXX=clang++
cd $B
[ -d TrustTunnelClient ] || git clone -q --branch v1.1.7 https://github.com/TrustTunnel/TrustTunnelClient
cd TrustTunnelClient
echo "== $(date -u +%T) conan profile"
conan profile detect --force
sed -i 's/^compiler.libcxx=.*/compiler.libcxx=libstdc++11/' $CONAN_HOME/profiles/default
cat $CONAN_HOME/profiles/default
mkdir -p $CONAN_HOME && printf 'core.download:retry = 8\ncore.download:retry_wait = 30\n' > $CONAN_HOME/global.conf
echo "== $(date -u +%T) bootstrap"
python3 scripts/bootstrap_conan_deps.py
echo "== $(date -u +%T) re-export NativeLibsCommon 8.1.52 last (boringssl recipe)"
rm -rf $B/nlc && git clone -q https://github.com/AdguardTeam/NativeLibsCommon.git $B/nlc
git -C $B/nlc checkout -q v8.1.52 && (cd $B/nlc && ./scripts/export_conan.sh)
echo "== $(date -u +%T) configure"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DDISABLE_HTTP3=OFF
echo "== $(date -u +%T) build"
cmake --build build --target trusttunnel_client -j6
echo "== $(date -u +%T) DONE"; ls -la build/trusttunnel/trusttunnel_client
