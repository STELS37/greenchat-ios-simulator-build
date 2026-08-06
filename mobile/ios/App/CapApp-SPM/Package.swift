// swift-tools-version: 5.9
import PackageDescription

// DO NOT MODIFY THIS FILE - managed by Capacitor CLI commands
let package = Package(
    name: "CapApp-SPM",
    platforms: [.iOS(.v15)],
    products: [
        .library(
            name: "CapApp-SPM",
            targets: ["CapApp-SPM"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", exact: "8.4.1"),
        .package(name: "AparajitaCapacitorSecureStorage", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@aparajita/capacitor-secure-storage"),
        .package(name: "CapacitorApp", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@capacitor/app"),
        .package(name: "CapacitorBrowser", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@capacitor/browser"),
        .package(name: "CapacitorFilesystem", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@capacitor/filesystem"),
        .package(name: "CapacitorLocalNotifications", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@capacitor/local-notifications"),
        .package(name: "CapacitorPushNotifications", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@capacitor/push-notifications"),
        .package(name: "CapacitorShare", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@capacitor/share"),
        .package(name: "CapacitorSplashScreen", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@capacitor/splash-screen"),
        .package(name: "CapacitorStatusBar", path: "../../../../../../../srv/projects/green_chat/clients/mobile/node_modules/@capacitor/status-bar")
    ],
    targets: [
        .target(
            name: "CapApp-SPM",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm"),
                .product(name: "AparajitaCapacitorSecureStorage", package: "AparajitaCapacitorSecureStorage"),
                .product(name: "CapacitorApp", package: "CapacitorApp"),
                .product(name: "CapacitorBrowser", package: "CapacitorBrowser"),
                .product(name: "CapacitorFilesystem", package: "CapacitorFilesystem"),
                .product(name: "CapacitorLocalNotifications", package: "CapacitorLocalNotifications"),
                .product(name: "CapacitorPushNotifications", package: "CapacitorPushNotifications"),
                .product(name: "CapacitorShare", package: "CapacitorShare"),
                .product(name: "CapacitorSplashScreen", package: "CapacitorSplashScreen"),
                .product(name: "CapacitorStatusBar", package: "CapacitorStatusBar")
            ]
        )
    ]
)
