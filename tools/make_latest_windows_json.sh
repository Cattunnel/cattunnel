#!/usr/bin/env bash
# latest-windows.json for the Windows in-app update (UpdateService reads it
# next to latest.json). Same format as the phones' file; the installer is
# apks."windows-x64". Build = the --build-number the Windows app was built
# with (compared with its own), version = what the About screen shows.
#
#   tools/make_latest_windows_json.sh <base-url> <Setup.exe> <version> <build> <notes.txt> > latest-windows.json
#
# Sign it like latest.json (tools/sign_latest_json.sh sign latest-windows.json);
# upload the installer first, the .sig, then the json last.
set -euo pipefail

BASE=${1:?base url}
SETUP=${2:?setup exe}
VERSION=${3:?version}
BUILD=${4:?build number}
NOTES=${5:?notes file}
BASE=${BASE%/}
[[ $BASE == https://* ]] || { echo "base url must be https" >&2; exit 1; }
[[ $BUILD =~ ^[0-9]+$ ]] || { echo "build must be a number" >&2; exit 1; }

python3 - "$VERSION" "$BUILD" "$NOTES" "$BASE" "$SETUP" <<'PY'
import hashlib, json, os, sys
version, build, notes, base, setup = sys.argv[1:]
print(json.dumps({
    "version": version,
    "build": int(build),
    "notes": open(notes, encoding="utf-8").read().strip(),
    "apks": {"windows-x64": {
        "url": f"{base}/{os.path.basename(setup)}",
        "sha256": hashlib.sha256(open(setup, "rb").read()).hexdigest(),
    }},
}, ensure_ascii=False, indent=2))
PY
