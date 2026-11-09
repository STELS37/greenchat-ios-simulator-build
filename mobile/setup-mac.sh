#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

fail() {
  echo "GreenChat Mac setup: $*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Run this script on macOS."
command -v xcodebuild >/dev/null 2>&1 || fail "Install Xcode 26+ and open it once to finish first-run setup."
command -v xcrun >/dev/null 2>&1 || fail "Xcode Command Line Tools are not available."
command -v node >/dev/null 2>&1 || fail "Install Node.js: brew install node"
command -v npm >/dev/null 2>&1 || fail "npm is missing; reinstall Node.js."
command -v pod >/dev/null 2>&1 || fail "Install CocoaPods: brew install cocoapods"

XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
XCODE_MAJOR="${XCODE_VERSION%%.*}"
[[ "${XCODE_MAJOR:-0}" =~ ^[0-9]+$ ]] || fail "Cannot determine Xcode version."
[[ "$XCODE_MAJOR" -ge 26 ]] || fail "Xcode 26 or newer is required for the native iOS Liquid Glass tab bar (found $XCODE_VERSION)."

[[ -s "$ROOT/package-lock.json" ]] || fail "package-lock.json is missing."
[[ -s "$ROOT/ios/App/App.xcodeproj/project.pbxproj" ]] || fail "App.xcodeproj is missing."
[[ -s "$ROOT/ios/App/Podfile" ]] || fail "Podfile is missing."
[[ -s "$ROOT/vendor-archives/keychain-swift.tar.gz" ]] || fail "KeychainSwift vendor archive is missing."
[[ -s "$ROOT/vendor-archives/ion-ios-filesystem.tar.gz" ]] || fail "IONFilesystemLib vendor archive is missing."

echo "==> GreenChat iOS setup"
echo "Xcode: $XCODE_VERSION"
echo "Node:  $(node --version)"
echo "npm:   $(npm --version)"
echo "Pods:  $(pod --version)"

echo
echo "==> Verifying the exact bundled GreenChat web payload"
node "$ROOT/verify-ios-payload.cjs"

echo
echo "==> Installing locked npm dependencies"
npm ci --ignore-scripts

echo
echo "==> Restoring the local CocoaPods source archives"
mkdir -p "$ROOT/vendor"
rm -rf "$ROOT/vendor/keychain-swift" "$ROOT/vendor/ion-ios-filesystem"
tar -C "$ROOT/vendor" -xzf "$ROOT/vendor-archives/keychain-swift.tar.gz"
tar -C "$ROOT/vendor" -xzf "$ROOT/vendor-archives/ion-ios-filesystem.tar.gz"

[[ -f "$ROOT/vendor/keychain-swift/KeychainSwift.podspec" ]] || fail "KeychainSwift podspec was not restored."
[[ -f "$ROOT/vendor/ion-ios-filesystem/IONFilesystemLib.podspec" ]] || fail "IONFilesystemLib podspec was not restored."

echo
echo "==> Installing Capacitor and native CocoaPods"
cd "$ROOT/ios/App"
pod install

WORKSPACE="$ROOT/ios/App/App.xcworkspace"
[[ -s "$WORKSPACE/contents.xcworkspacedata" ]] || fail "App.xcworkspace manifest is missing after pod install."
[[ -d "$ROOT/ios/App/Pods/Pods.xcodeproj" ]] || fail "CocoaPods did not generate Pods.xcodeproj."

echo
echo "==> Validating Xcode workspace and shared App scheme"
XCODE_LIST="$(xcodebuild -list -workspace "$WORKSPACE" 2>&1)" || {
  printf '%s\n' "$XCODE_LIST"
  fail "Xcode could not read App.xcworkspace."
}
printf '%s\n' "$XCODE_LIST"
printf '%s\n' "$XCODE_LIST" | grep -Eq '^[[:space:]]+App[[:space:]]*$' || fail "Shared App scheme was not found."

echo
echo "==> Opening GreenChat in Xcode"
if [[ "${GREENCHAT_OPEN_XCODE:-1}" == "1" ]]; then
  open "$WORKSPACE"
fi

echo
echo "GreenChat iOS setup: READY"
echo "Open this workspace (not the bare project or containing folder):"
echo "  $WORKSPACE"
echo "Select scheme App and an iPhone Simulator, then press Run."
