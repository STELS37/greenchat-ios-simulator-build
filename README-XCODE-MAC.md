# GreenChat iOS — Mac / Xcode / TestFlight

The native iPhone app is a Capacitor + WKWebView application with a UIKit shell. The iOS navigation bar is a native `UITabBar`; iOS 26 renders it with Apple's system Liquid Glass material. The app content remains behind the floating tab bar, and the iOS-specific stylesheet adds translucent glass surfaces and motion to the shared messenger UI.

## One-command Mac preparation

Requirements: macOS, Xcode 26+, Node.js 20+, npm and CocoaPods.

If Node.js or CocoaPods is missing:

```bash
brew install node cocoapods
```

From the extracted repository:

```bash
cd mobile
bash setup-mac.sh
```

This prepares the complete Xcode project in the same deterministic style as MyVPN:

1. Checks Xcode, Node.js and CocoaPods.
2. Downloads the exact current GreenChat Android release 1.0.0-beta.10 / build 1000693 and verifies its pinned SHA-256.
3. Extracts all 233 web-app files from the release APK, including the main JavaScript/CSS, all lazy-loaded chunks, Capacitor native bridge, update bridge, startup recovery loader and iOS Liquid Glass stylesheet.
4. Generates a per-file SHA-256 manifest and verifies every asset and entrypoint.
5. Installs the locked npm dependencies using `npm ci`.
6. Restores the two local CocoaPods sources and runs `pod install`.
7. Verifies the generated Pods project, Xcode workspace and shared `App` scheme.
8. Opens the correct Xcode workspace.

The APK is cached under `mobile/.cache`; rerunning setup does not download it again unless the checksum no longer matches.

**Open `mobile/ios/App/App.xcworkspace`, not the bare `.xcodeproj` and not the containing folder.** GreenChat uses CocoaPods, so the workspace is the correct Xcode entry point.

## Xcode settings

- Scheme: `App`
- Bundle identifier: `app.greenchat`
- Marketing version: `1.0.0`
- Build number: `1000693`
- Minimum iOS deployment target: `15.0`
- Recommended visual test target: iOS 26 simulator or iPhone
- Native Liquid Glass: iOS 26 system `UITabBar`, with a graceful pre-iOS-26 fallback

Select an iPhone simulator and press Run.

## Build and test in Terminal

Simulator build:

```bash
bash build-simulator.sh
```

The script uses the Mac's native simulator architecture (Apple Silicon or Intel), verifies the web payload, and builds without signing.

## Create a signed TestFlight IPA

1. Open the project in Xcode and sign in to the Apple Developer account.
2. In **Signing & Capabilities**, select the GreenChat app target and your Apple Developer Team. Keep automatic signing enabled.
3. Copy the 10-character Team ID from Xcode.
4. From `mobile`, run:

```bash
APPLE_TEAM_ID=YOURTEAMID bash build-ipa.sh
```

The script archives the physical iPhone target, exports an App Store Connect IPA and writes a SHA-256 file into `mobile/dist`.

Upload `GreenChat-1.0.0-1000693.ipa` to App Store Connect using Xcode Organizer or Transporter. After Apple processes the build, add it to an internal or external TestFlight group. A signed IPA can be created locally, but App Store Connect upload and distribution require the developer account's signing and access credentials on the Mac.

## Architecture

MyVPN uses a native SwiftUI overlay over the sing-box Apple client. GreenChat uses Capacitor + WKWebView and CocoaPods. The Mac setup approach is intentionally the same: pinned inputs, repeatable preparation, integrity checks, a verified Xcode entry point and separate simulator / signed archive build commands.
