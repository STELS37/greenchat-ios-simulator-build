# GreenChat iOS — Xcode on macOS

## Quick start

1. Download and extract this repository ZIP.
2. Open Terminal in the extracted repository folder.
3. Run:

```bash
bash mobile/prepare-xcode-mac.sh
```

The script installs the locked npm dependencies, restores the two vendored CocoaPods source archives, runs `pod install`, and opens `App.xcworkspace`.

If Node.js or CocoaPods is missing:

```bash
brew install node cocoapods
```

## Open the correct file

Open:

`mobile/ios/App/App.xcworkspace`

Do not open the `.xcworkspace` folder itself in Finder. Open the workspace bundle after the preparation script has completed. The script runs CocoaPods, which generates the workspace contents and Pods project.

## Xcode

- Scheme: `App`
- Bundle ID: `app.greenchat`
- Build: `1000079`
- Recommended simulator for system Liquid Glass: iPhone with iOS 26 Simulator
- Press Run (▶).

For a physical iPhone, configure your Apple Development Team in Signing & Capabilities.

## Included app architecture

GreenChat uses a Capacitor iOS shell with WKWebView and a bundled web payload. The native Swift project, plugins, assets, and bundled interface are included. The complete private frontend/backend development source is not part of this iOS builder repository.
