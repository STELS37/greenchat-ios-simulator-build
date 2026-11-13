#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$ROOT/ios/App/App.xcworkspace"
DERIVED="$ROOT/.derived-data-device"
ARCHIVE="$ROOT/dist/GreenChat.xcarchive"
EXPORT="$ROOT/dist/app-store-connect"
DIST="$ROOT/dist"
BUNDLE_ID="${GREENCHAT_BUNDLE_ID:-app.greenchat}"
VERSION="${GREENCHAT_VERSION:-1.0.0}"
BUILD="${GREENCHAT_BUILD_NUMBER:-1000693}"
TEAM_ID="${APPLE_TEAM_ID:-}"

fail() { echo "GreenChat iOS IPA: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Run this on macOS."
command -v xcodebuild >/dev/null 2>&1 || fail "Xcode is required."
command -v xcrun >/dev/null 2>&1 || fail "Xcode Command Line Tools are required."
[[ -s "$WORKSPACE/contents.xcworkspacedata" ]] || fail "Run setup-mac.sh first."
[[ -d "$ROOT/ios/App/Pods/Pods.xcodeproj" ]] || fail "CocoaPods are missing; run setup-mac.sh."
[[ -n "$TEAM_ID" ]] || fail "Set APPLE_TEAM_ID to the 10-character Apple Developer Team ID shown in Xcode > Signing & Capabilities."

node "$ROOT/verify-ios-payload.cjs"

mkdir -p "$DIST"
rm -rf "$ARCHIVE" "$EXPORT"
PLIST="$DIST/ExportOptions.plist"
/usr/libexec/PlistBuddy -c 'Clear dict' "$PLIST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :destination string export' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :method string app-store-connect' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string automatic' "$PLIST"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "$PLIST"
/usr/libexec/PlistBuddy -c 'Add :uploadSymbols bool true' "$PLIST"

echo "==> Archiving GreenChat for physical iPhone"
set -o pipefail
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme App \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  archive 2>&1 | tee "$DIST/xcodebuild-archive.log"

[[ -d "$ARCHIVE" ]] || fail "Xcode archive was not created."

echo "==> Exporting the App Store Connect IPA"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates 2>&1 | tee "$DIST/xcodebuild-export.log"

IPA="$(find "$EXPORT" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
[[ -n "$IPA" && -s "$IPA" ]] || fail "App Store Connect IPA export failed."
cp "$IPA" "$DIST/GreenChat-$VERSION-$BUILD.ipa"
shasum -a 256 "$DIST/GreenChat-$VERSION-$BUILD.ipa" > "$DIST/GreenChat-$VERSION-$BUILD.ipa.sha256"

echo
echo "GreenChat iOS IPA: READY"
echo "IPA: $DIST/GreenChat-$VERSION-$BUILD.ipa"
echo "SHA-256: $DIST/GreenChat-$VERSION-$BUILD.ipa.sha256"
echo "Next: upload this IPA to App Store Connect, then distribute it through TestFlight."
