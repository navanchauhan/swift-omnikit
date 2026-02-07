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
        .library(
            name: "OmniUICore",
            targets: ["OmniUICore"]
        ),
        .library(
            name: "OmniUI",
            targets: ["OmniUI"]
        ),
        .library(
            name: "OmniUINotcursesRenderer",
            targets: ["OmniUINotcursesRenderer"]
        ),
        .library(
            name: "OmniUITerminalRenderer",
            targets: ["OmniUITerminalRenderer"]
        ),
        .executable(
            name: "KitchenSink",
            targets: ["KitchenSink"]
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
        .target(
            name: "OmniUICore",
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "OmniUI",
            dependencies: ["OmniUICore"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "CNotcurses",
            path: "Sources/CNotcurses",
            publicHeadersPath: "include",
            cSettings: [
                // SwiftPM only accepts relative `headerSearchPath`, so use explicit `-I` flags.
                // Homebrew (Apple Silicon default prefix).
                .unsafeFlags(["-I/opt/homebrew/opt/notcurses/include"], .when(platforms: [.macOS])),
                // Homebrew (Intel default prefix).
                .unsafeFlags(["-I/usr/local/include"], .when(platforms: [.macOS])),
                // Common Linux include prefix for distro packages.
                .unsafeFlags(["-I/usr/include"], .when(platforms: [.linux])),
            ]
        ),
        .target(
            name: "OmniUINotcursesRenderer",
            dependencies: [
                "OmniUICore",
                .target(name: "CNotcurses", condition: .when(platforms: [.linux, .macOS])),
            ],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
                // Make notcurses headers visible to the Swift compiler when importing the Clang module.
                .unsafeFlags(["-Xcc", "-I/opt/homebrew/opt/notcurses/include"], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xcc", "-I/usr/local/include"], .when(platforms: [.macOS])),
                .unsafeFlags(["-Xcc", "-I/usr/include"], .when(platforms: [.linux])),
            ],
            linkerSettings: [
                .linkedLibrary("notcurses", .when(platforms: [.linux, .macOS])),
                .linkedLibrary("notcurses-core", .when(platforms: [.linux, .macOS])),
                .unsafeFlags(["-L/opt/homebrew/opt/notcurses/lib"], .when(platforms: [.macOS])),
                .unsafeFlags(["-L/usr/local/lib"], .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "OmniUITerminalRenderer",
            dependencies: ["OmniUICore"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "KitchenSink",
            dependencies: ["OmniUI", "OmniUINotcursesRenderer", "OmniUITerminalRenderer"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "OmniKitTests",
            dependencies: ["OmniKit"]
        ),
        .testTarget(
            name: "OmniUICoreTests",
            dependencies: ["OmniUICore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
