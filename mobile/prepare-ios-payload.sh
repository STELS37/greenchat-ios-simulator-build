#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="$ROOT/.cache"
APK="$CACHE/greenchat-android-reference-1000693.apk"
STAGING="$CACHE/ios-public-staging"
PUBLIC="$ROOT/ios/App/App/public"

APK_URL="https://greenchat.globalsystem.cc/v1/client/updates/artifact/google-universal-1000693.apk"
APK_SHA256="d6b84254c2fd0351ad0398e9c75d92740a53e8312b8e26d35173184eabd97316"

fail() { echo "GreenChat iOS payload: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl is required."
command -v shasum >/dev/null 2>&1 || fail "shasum is required."
command -v unzip >/dev/null 2>&1 || fail "unzip is required."
command -v python3 >/dev/null 2>&1 || fail "python3 is required."

mkdir -p "$CACHE"
if [[ ! -s "$APK" ]] || [[ "$(shasum -a 256 "$APK" | awk '{print $1}')" != "$APK_SHA256" ]]; then
  echo "==> Downloading the pinned GreenChat 1.0.0-beta.10 build 1000693"
  rm -f "$APK.part"
  curl --fail --location --retry 3 --retry-all-errors --connect-timeout 20 --output "$APK.part" "$APK_URL"
  ACTUAL="$(shasum -a 256 "$APK.part" | awk '{print $1}')"
  [[ "$ACTUAL" == "$APK_SHA256" ]] || fail "APK SHA-256 mismatch: $ACTUAL"
  mv "$APK.part" "$APK"
fi

ACTUAL="$(shasum -a 256 "$APK" | awk '{print $1}')"
[[ "$ACTUAL" == "$APK_SHA256" ]] || fail "cached APK SHA-256 mismatch."

echo "==> Extracting the complete, pinned Capacitor web application"
rm -rf "$STAGING"
mkdir -p "$STAGING"
unzip -q "$APK" 'assets/public/*' -d "$STAGING"
SOURCE_PUBLIC="$STAGING/assets/public"
[[ -s "$SOURCE_PUBLIC/index.html" ]] || fail "APK has no assets/public/index.html"
[[ -s "$SOURCE_PUBLIC/gc-bridge.js" ]] || fail "APK has no native Capacitor bridge"
[[ -s "$SOURCE_PUBLIC/gc-preboot.js" ]] || fail "APK has no startup recovery loader"
[[ -s "$SOURCE_PUBLIC/gc-store-update.js" ]] || fail "APK has no native update bridge"
[[ -s "$SOURCE_PUBLIC/gc-ios-liquid-glass.css" ]] || fail "APK has no iOS Liquid Glass stylesheet"

ENTRY_JS="$(sed -nE 's/.*name="gc-app-entry" content="([^"]+)".*/\1/p' "$SOURCE_PUBLIC/index.html" | head -n 1)"
ENTRY_CSS="$(sed -nE 's/.*id="gc-app-style" rel="stylesheet" href="([^"]+)".*/\1/p' "$SOURCE_PUBLIC/index.html" | head -n 1)"
ENTRY_JS="${ENTRY_JS#/}"
ENTRY_CSS="${ENTRY_CSS#/}"
[[ -n "$ENTRY_JS" && -s "$SOURCE_PUBLIC/$ENTRY_JS" ]] || fail "main JavaScript entrypoint is missing: $ENTRY_JS"
[[ -n "$ENTRY_CSS" && -s "$SOURCE_PUBLIC/$ENTRY_CSS" ]] || fail "main stylesheet is missing: $ENTRY_CSS"

SOURCE_SHA="$(tr -d '\r\n' < "$ROOT/SOURCE_SHA.txt")"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "SOURCE_SHA.txt must contain a full Git commit SHA."

echo "==> Generating the SHA-256 manifest for the extracted iOS payload"
python3 - "$SOURCE_PUBLIC" "$SOURCE_SHA" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
source_sha = sys.argv[2]
files = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or path.name == ".gc-build-profile.json":
        continue
    data = path.read_bytes()
    files.append({
        "path": path.relative_to(root).as_posix(),
        "sha256": hashlib.sha256(data).hexdigest(),
        "size": len(data),
    })

manifest = {
    "algorithm": "sha256",
    "build_id": source_sha,
    "distribution_channel": "development",
    "files": files,
    "profile": "ios-development",
    "schema": 1,
}
canonical = json.dumps(files, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
manifest["payload_sha256"] = hashlib.sha256(canonical).hexdigest()
(root / ".gc-build-profile.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
print(f"Verified source: {source_sha}")
print(f"Payload files: {len(files)}")
print(f"Payload bytes: {sum(item['size'] for item in files)}")
PY

echo "==> Installing the complete payload into the Xcode project"
mkdir -p "$(dirname "$PUBLIC")"
rm -rf "$PUBLIC"
mv "$SOURCE_PUBLIC" "$PUBLIC"
rm -rf "$STAGING"

node "$ROOT/verify-ios-payload.cjs"
echo "GreenChat iOS payload: READY (APK SHA-256 $APK_SHA256)"
