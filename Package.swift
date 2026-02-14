// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

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
            name: "SwiftUI",
            targets: ["OmniSwiftUI"]
        ),
        .library(
            name: "SwiftData",
            targets: ["OmniSwiftData"]
        ),
        .library(
            name: "OmniKit",
            targets: ["OmniKit"]
        ),
        .library(
            name: "OmniHTTP",
            targets: ["OmniHTTP"]
        ),
        .library(
            name: "OmniHTTPNIO",
            targets: ["OmniHTTPNIO"]
        ),
        .library(
            name: "OmniAICore",
            targets: ["OmniAICore"]
        ),
        .library(
            name: "OmniAILLMClient",
            targets: ["OmniAILLMClient"]
        ),
        .library(
            name: "OmniAIAgent",
            targets: ["OmniAIAgent"]
        ),
        .library(
            name: "OmniAIAttractor",
            targets: ["OmniAIAttractor"]
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
        .executable(
            name: "iGopherBrowserTUI",
            targets: ["iGopherBrowserTUI"]
        ),
    ],
    dependencies: [
        // Cross-platform networking + streaming.
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.0.0"),
        // For Swift macro stubs (SwiftData compatibility).
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "OmniSwiftUI",
            dependencies: ["OmniUI", "SwiftUIMacros"],
            path: "Sources/SwiftUI",
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
                // iGopherBrowser's `BrowserView.body` is large enough to trip Swift's default solver timeout.
                .unsafeFlags(["-Xfrontend", "-solver-expression-time-threshold=300"]),
            ]
        ),
        .macro(
            name: "SwiftUIMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .macro(
            name: "SwiftDataMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "OmniSwiftData",
            dependencies: ["OmniUICore", "SwiftDataMacros"],
            path: "Sources/SwiftData",
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "SwiftUICompatibilityHarness",
            dependencies: ["OmniSwiftUI", "OmniSwiftData"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
                // Keep source compatibility with `import SwiftUI` / `import SwiftData`.
                .unsafeFlags(["-module-alias", "SwiftUI=OmniSwiftUI"]),
                .unsafeFlags(["-module-alias", "SwiftData=OmniSwiftData"]),
            ]
        ),
        .target(
            name: "OmniKit",
            swiftSettings: [
                // Ensure strict-concurrency diagnostics even when the language mode changes.
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "OmniHTTP",
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "OmniHTTPNIO",
            dependencies: [
                "OmniHTTP",
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(
                    name: "NIOTransportServices",
                    package: "swift-nio-transport-services",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS])
                ),
            ],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "OmniAICore",
            dependencies: ["OmniHTTP"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "OmniAILLMClient",
            path: "Sources/OmniAILLMClient",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=minimal"]),
            ]
        ),
        .target(
            name: "OmniAIAgent",
            dependencies: ["OmniAICore"],
            path: "Sources/OmniAIAgent",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=minimal"]),
            ]
        ),
        .target(
            name: "OmniAIAttractor",
            dependencies: ["OmniAICore", "OmniAIAgent"],
            path: "Sources/OmniAIAttractor",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=minimal"]),
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
        // iGopherBrowser dependency shims (compile-only on non-Apple platforms).
        .target(
            name: "TelemetryDeck",
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "QuickLook",
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "AppIntents",
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        // Minimal Gopher client + helpers (enough for iGopherBrowser).
        .target(
            name: "SwiftGopherClient",
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "GopherHelpers",
            dependencies: ["SwiftGopherClient"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        // Builds iGopherBrowser views (from `references/`) against our SwiftUI/SwiftData shims.
        .target(
            name: "iGopherBrowserViews",
            dependencies: [
                "OmniSwiftUI",
                "OmniSwiftData",
                "SwiftGopherClient",
                "GopherHelpers",
                "TelemetryDeck",
                "QuickLook",
                "AppIntents",
            ],
            path: ".",
            sources: [
                "references/iGopherBrowser/iGopherBrowser/Bookmark.swift",
                "references/iGopherBrowser/iGopherBrowser/BookmarksView.swift",
                "references/iGopherBrowser/iGopherBrowser/BrowserView.swift",
                "references/iGopherBrowser/iGopherBrowser/CRTEffect.swift",
                "references/iGopherBrowser/iGopherBrowser/ContentView.swift",
                "references/iGopherBrowser/iGopherBrowser/FileView.swift",
                "references/iGopherBrowser/iGopherBrowser/Helpers.swift",
                "references/iGopherBrowser/iGopherBrowser/History.swift",
                "references/iGopherBrowser/iGopherBrowser/LiquidGlass.swift",
                "references/iGopherBrowser/iGopherBrowser/SearchInputView.swift",
                "references/iGopherBrowser/iGopherBrowser/SidebarView.swift",
                "references/iGopherBrowser/iGopherBrowser/WhatsNew.swift",
                "Sources/iGopherBrowserCompat/iGopherBrowserCompat.swift",
            ],
            swiftSettings: [
                // iGopherBrowser is upstream SwiftUI code. Compile it in Swift 5 mode to avoid
                // Swift 6's stricter `sending` diagnostics without patching the reference sources.
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=minimal"]),
                // BrowserView's body is large enough to trip the default solver timeout.
                .unsafeFlags(["-Xfrontend", "-solver-expression-time-threshold=300"]),
                // Upstream sources import `SwiftUI` / `SwiftData`; map those names to our shim modules.
                .unsafeFlags(["-module-alias", "SwiftUI=OmniSwiftUI"]),
                .unsafeFlags(["-module-alias", "SwiftData=OmniSwiftData"]),
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
        .executableTarget(
            name: "iGopherBrowserTUI",
            dependencies: ["iGopherBrowserViews", "OmniUINotcursesRenderer", "OmniUITerminalRenderer"],
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
            name: "OmniHTTPTests",
            dependencies: ["OmniHTTP"]
        ),
        .testTarget(
            name: "OmniAICoreTests",
            dependencies: ["OmniAICore"]
        ),
        .testTarget(
            name: "OmniAILLMClientTests",
            dependencies: ["OmniAILLMClient"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=minimal"]),
            ]
        ),
        .testTarget(
            name: "OmniAIAgentTests",
            dependencies: ["OmniAIAgent", "OmniAICore"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=minimal"]),
            ]
        ),
        .testTarget(
            name: "OmniAIAttractorTests",
            dependencies: ["OmniAIAttractor", "OmniAICore", "OmniAIAgent"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=minimal"]),
            ]
        ),
        .testTarget(
            name: "OmniUICoreTests",
            dependencies: ["OmniUICore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
