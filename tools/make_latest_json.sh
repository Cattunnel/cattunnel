#!/usr/bin/env bash
# Write latest.json for the in-app update (lib/feature/updates) from the two
# release APKs. Version name and versionCode are read from the APKs, so the
# file can't disagree with what gets installed.
#
#   tools/make_latest_json.sh <base-url> <arm64.apk> <universal.apk> <notes.txt> > latest.json
#
# <base-url> is the download folder the APKs are uploaded to (https://…/downloads);
# the APK file names are kept. Upload the APKs first, latest.json last, so a
# phone never sees an offer for a file that isn't there yet.
set -euo pipefail

BASE=${1:?base url}
ARM64=${2:?arm64 apk}
UNIVERSAL=${3:?universal apk}
NOTES=${4:?notes file}
BASE=${BASE%/}
[[ $BASE == https://* ]] || { echo "base url must be https" >&2; exit 1; }

AAPT=$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
[[ -x $AAPT ]] || { echo "aapt not found (Android build-tools)" >&2; exit 1; }

badging() { "$AAPT" dump badging "$1" | sed -n 1p; }
field() { sed -E "s/.* $1='([^']*)'.*/\1/"; }

ARM64_CODE=$(badging "$ARM64" | field versionCode)
UNIVERSAL_CODE=$(badging "$UNIVERSAL" | field versionCode)
VERSION=$(badging "$ARM64" | field versionName)
[[ $ARM64_CODE == "$UNIVERSAL_CODE" ]] \
    || { echo "versionCode differs: arm64 $ARM64_CODE, universal $UNIVERSAL_CODE" >&2; exit 1; }

python3 - "$VERSION" "$ARM64_CODE" "$NOTES" "$BASE" "$ARM64" "$UNIVERSAL" <<'EOF'
import hashlib, json, os, sys
version, build, notes, base, arm64, universal = sys.argv[1:]
sha = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
apk = lambda p: {"url": f"{base}/{os.path.basename(p)}", "sha256": sha(p)}
print(json.dumps({
    "version": version,
    "build": int(build),
    "notes": open(notes, encoding="utf-8").read().strip(),
    "apks": {"arm64-v8a": apk(arm64), "universal": apk(universal)},
}, ensure_ascii=False, indent=2))
EOF
