// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OmniKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "OmniKit",
            targets: ["OmniKit"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "OmniKit",
            swiftSettings: [
                // Ensure strict-concurrency diagnostics even when the language mode changes.
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "OmniKitTests",
            dependencies: ["OmniKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
