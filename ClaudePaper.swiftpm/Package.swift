// swift-tools-version: 5.9

// ClaudePaper — app iPad « papier intelligent » : Apple Pencil + Claude.
// Ce paquet est un App Playground : il s'ouvre directement dans Swift Playgrounds
// sur iPad (Fichiers → ClaudePaper.swiftpm) ou dans Xcode sur Mac.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "ClaudePaper",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "ClaudePaper",
            targets: ["AppModule"],
            bundleIdentifier: "com.claudepaper.app",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .pencil),
            accentColor: .presetColor(.indigo),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .outgoingNetworkConnections()
            ],
            appCategory: .education
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ],
    swiftLanguageVersions: [.v5]
)
