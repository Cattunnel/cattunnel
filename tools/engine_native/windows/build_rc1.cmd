@echo off
rem TrustTunnelClient v1.3.0-rc.1 + CatTunnel commits (anti-DPI, block_quic, h2 padding, ping_failed, per-app split) for Windows (MSVC), CLI only.
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
set W=C:\dev\tt-win
set PY=%LOCALAPPDATA%\Programs\Python\Python313
set PATH=%W%\nasm-2.16.03;%PY%;%PY%\Scripts;%APPDATA%\Python\Python313\Scripts;%USERPROFILE%\.cargo\bin;%PATH%;C:\Program Files\Git\cmd;C:\Program Files\Git\usr\bin
set CONAN_HOME=%W%\conan-home
cd /d %W%
if not exist TTC-rc1 (
  git clone -q --branch v1.3.0-rc.1 https://github.com/TrustTunnel/TrustTunnelClient TTC-rc1 || exit /b 1
  cd TTC-rc1
  for %%f in (%W%\rc1-patches\0*.patch) do git -c user.name=build -c user.email=build@localhost apply --index "%%f" || exit /b 1
  sed -i "s/subprocess\.run(\[os\.path\.join(/subprocess.run([\"sh\", os.path.join(/g" scripts/bootstrap_conan_deps.py
  cd ..
)
cd /d %W%\TTC-rc1
if not exist %W%\bootstraprc1.done (
  echo == bootstrap & python scripts\bootstrap_conan_deps.py || exit /b 1
  echo done> %W%\bootstraprc1.done
)
conan remove "cxxopts/*" -c >nul 2>&1
echo == configure
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DDISABLE_HTTP3=OFF || exit /b 1
echo == build
cmake --build build --target trusttunnel_client || exit /b 1
echo == DONE
dir build\trusttunnel\trusttunnel_client.exe
