#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

fail() {
  echo
  echo "ERROR: $1"
  exit 1
}

command -v xcodebuild >/dev/null 2>&1 || fail "Install Xcode 26+ and open it once."
command -v node >/dev/null 2>&1 || fail "Install Node.js: brew install node"
command -v npm >/dev/null 2>&1 || fail "npm is missing; reinstall Node.js."
command -v pod >/dev/null 2>&1 || fail "Install CocoaPods: brew install cocoapods"

echo "== GreenChat Xcode preparation =="
xcodebuild -version
node --version
pod --version

echo
echo "[1/3] Installing locked npm dependencies..."
npm ci --ignore-scripts

echo
echo "[2/3] Restoring vendored CocoaPods sources..."
mkdir -p vendor
tar -C vendor -xzf vendor-archives/keychain-swift.tar.gz
tar -C vendor -xzf vendor-archives/ion-ios-filesystem.tar.gz

echo
echo "[3/3] Generating CocoaPods workspace..."
cd ios/App
pod install

test -s App.xcworkspace/contents.xcworkspacedata || fail "CocoaPods did not create the Xcode workspace."
test -d App.xcodeproj || fail "Xcode project is missing."

echo
echo "Opening App.xcworkspace..."
open App.xcworkspace
echo
echo "In Xcode choose scheme App and an iPhone Simulator, then press Run."
