// swift-tools-version:5.9
import PackageDescription

// Claw Copy intentionally has zero third-party dependencies.
// Do not add package dependencies: scripts/check-security.sh fails the build if any appear.
let package = Package(
    name: "ClawCopy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClawCopy", targets: ["ClawCopy"]),
    ],
    targets: [
        // Pure, platform-independent logic. Foundation only, fully unit tested.
        .target(name: "ClawCopyCore"),
        // The macOS app: AppKit + Accessibility glue around ClawCopyCore.
        .executableTarget(name: "ClawCopy", dependencies: ["ClawCopyCore"]),
        .testTarget(name: "ClawCopyCoreTests", dependencies: ["ClawCopyCore"]),
    ]
)
