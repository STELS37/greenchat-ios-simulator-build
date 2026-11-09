# GreenChat iOS — Mac / Xcode

GreenChat's iOS app is a Capacitor + WKWebView application with a native Swift/UIKit shell. The bundled web interface is included in `mobile/ios/App/App/public`.

## One-command setup

Requirements: macOS, Xcode 26+, Node.js/npm, and CocoaPods.

If Node.js or CocoaPods is missing:

```bash
brew install node cocoapods
```

From the extracted repository root:

```bash
cd mobile
bash setup-mac.sh
```

The setup script:
1. Checks macOS, Xcode, Node.js and CocoaPods.
2. Verifies the complete bundled GreenChat web payload against its SHA-256 manifest and verifies that it matches `SOURCE_SHA.txt`.
3. Installs the locked npm dependency graph using `npm ci`.
4. Restores the two vendored CocoaPods source archives.
5. Runs `pod install`.
6. Verifies the generated Pods project, Xcode workspace and shared `App` scheme.
7. Opens `ios/App/App.xcworkspace` in Xcode.

**Open the workspace, not the containing folder.** Because GreenChat uses CocoaPods, the correct Xcode entry point is `mobile/ios/App/App.xcworkspace`.

## Build in Xcode

- Scheme: `App`
- Bundle identifier: `app.greenchat`
- Version: `1.0.0`
- Build: `1000079`
- Recommended simulator: iPhone with iOS 26
- Press Run (▶).

The native UIKit bottom bar uses Apple's system Liquid Glass on iOS 26. The web interface is rendered by WKWebView and includes iOS-specific glass styles.

## Build from Terminal

After setup, from `mobile`:

```bash
bash build-simulator.sh
```

This compiles an ARM64 iOS Simulator app without code signing and verifies its bundle ID and build number. The output is under `.derived-data/Build/Products/Release-iphonesimulator/`.

## Physical iPhone

Connect the iPhone, select it as the Xcode destination, and configure your Apple Development Team under Signing & Capabilities. Simulator builds do not require device provisioning.

## Architecture

MyVPN uses a native SwiftUI overlay on the upstream sing-box Apple client. GreenChat uses Capacitor + WKWebView. Both use the same deterministic Mac setup approach, but the native projects and dependency resolvers differ: GreenChat uses npm + CocoaPods and opens an Xcode workspace.
