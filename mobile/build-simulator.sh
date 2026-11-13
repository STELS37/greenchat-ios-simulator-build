#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$ROOT/ios/App/App.xcworkspace"
DERIVED="$ROOT/.derived-data"
LOG="$ROOT/xcodebuild-simulator.log"

fail() { echo "GreenChat iOS Simulator build: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Run this script on macOS."
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is missing."
[[ -s "$WORKSPACE/contents.xcworkspacedata" ]] || fail "Run bash setup-mac.sh first."
[[ -d "$ROOT/ios/App/Pods/Pods.xcodeproj" ]] || fail "CocoaPods are missing; run setup-mac.sh."

node "$ROOT/verify-ios-payload.cjs"

echo "==> Building GreenChat for the current Mac's iOS Simulator architecture"
set -o pipefail
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme App \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  build 2>&1 | tee "$LOG"

APP="$(find "$DERIVED/Build/Products/Release-iphonesimulator" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "$APP" && -d "$APP" ]] || fail "Xcode did not produce an app bundle."

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
[[ "$BUNDLE_ID" == "app.greenchat" ]] || fail "Unexpected bundle ID: $BUNDLE_ID"
[[ "$BUILD" == "1000693" ]] || fail "Unexpected build number: $BUILD"

echo
echo "GreenChat Simulator build: PASS"
echo "App: $APP"
echo "Bundle ID: $BUNDLE_ID"
echo "Build: $BUILD"
echo "Run: open -a Simulator"
