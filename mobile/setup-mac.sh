#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

fail() { echo "GreenChat Mac setup: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Run this on macOS."
command -v xcodebuild >/dev/null 2>&1 || fail "Install Xcode 26+ and complete its first-run setup."
command -v xcrun >/dev/null 2>&1 || fail "Xcode Command Line Tools are unavailable."
command -v node >/dev/null 2>&1 || fail "Install Node.js 20+ (for example: brew install node)."
command -v npm >/dev/null 2>&1 || fail "npm is missing."
command -v pod >/dev/null 2>&1 || fail "Install CocoaPods (for example: brew install cocoapods)."

XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
[[ "${XCODE_MAJOR:-0}" =~ ^[0-9]+$ ]] || fail "Cannot determine Xcode version."
[[ "$XCODE_MAJOR" -ge 26 ]] || fail "Xcode 26+ is required for the iOS 26 Liquid Glass tab bar (found $XCODE_VERSION)."
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[[ "$NODE_MAJOR" -ge 20 ]] || fail "Node.js 20+ is required (found $(node --version))."

[[ -s "$ROOT/package-lock.json" ]] || fail "package-lock.json is missing."
[[ -s "$ROOT/ios/App/App.xcodeproj/project.pbxproj" ]] || fail "App.xcodeproj is missing."
[[ -s "$ROOT/ios/App/Podfile" ]] || fail "Podfile is missing."
[[ -s "$ROOT/vendor-archives/keychain-swift.tar.gz" ]] || fail "KeychainSwift vendor archive is missing."
[[ -s "$ROOT/vendor-archives/ion-ios-filesystem.tar.gz" ]] || fail "IONFilesystemLib vendor archive is missing."

echo "==> GreenChat iOS deterministic Mac setup"
echo "Xcode: $XCODE_VERSION"
echo "Node:  $(node --version)"
echo "npm:   $(npm --version)"
echo "Pods:  $(pod --version)"

echo
echo "==> Preparing the exact current GreenChat web payload"
bash "$ROOT/prepare-ios-payload.sh"

echo
echo "==> Installing the locked npm dependency graph"
npm ci

echo
echo "==> Restoring pinned local CocoaPods sources"
mkdir -p "$ROOT/vendor"
rm -rf "$ROOT/vendor/keychain-swift" "$ROOT/vendor/ion-ios-filesystem"
tar -C "$ROOT/vendor" -xzf "$ROOT/vendor-archives/keychain-swift.tar.gz"
tar -C "$ROOT/vendor" -xzf "$ROOT/vendor-archives/ion-ios-filesystem.tar.gz"
[[ -s "$ROOT/vendor/keychain-swift/KeychainSwift.podspec" ]] || fail "KeychainSwift source archive did not restore correctly."
[[ -s "$ROOT/vendor/ion-ios-filesystem/IONFilesystemLib.podspec" ]] || fail "IONFilesystemLib source archive did not restore correctly."

echo
echo "==> Installing Capacitor native plugins with CocoaPods"
cd "$ROOT/ios/App"
pod install

WORKSPACE="$ROOT/ios/App/App.xcworkspace"
[[ -s "$WORKSPACE/contents.xcworkspacedata" ]] || fail "App.xcworkspace is missing."
[[ -d "$ROOT/ios/App/Pods/Pods.xcodeproj" ]] || fail "CocoaPods did not generate Pods.xcodeproj."

echo
echo "==> Verifying Xcode workspace and App scheme"
XCODE_LIST="$(xcodebuild -list -workspace "$WORKSPACE" 2>&1)" || {
  printf '%s\n' "$XCODE_LIST"
  fail "Xcode could not load App.xcworkspace."
}
printf '%s\n' "$XCODE_LIST"
printf '%s\n' "$XCODE_LIST" | grep -Eq '^[[:space:]]+App[[:space:]]*$' || fail "The App scheme is missing."

echo
echo "==> Opening the correct Xcode workspace"
if [[ "${GREENCHAT_OPEN_XCODE:-1}" == "1" ]]; then
  open "$WORKSPACE"
fi

echo
echo "GreenChat Mac setup: READY"
echo "Workspace: $WORKSPACE"
echo "Scheme: App"
echo "Bundle ID: app.greenchat"
echo "Build: 1000693"
echo "For a Simulator build run: bash build-simulator.sh"
echo "For a signed TestFlight IPA run: APPLE_TEAM_ID=YOURTEAMID bash build-ipa.sh"
