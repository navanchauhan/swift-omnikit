// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let commonSwiftSettings: [SwiftSetting] = [
    .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
    .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
]

let swift6CommonSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
] + commonSwiftSettings

let imessageTargetDependencies: [Target.Dependency] = [
    "TheAgentIngress",
    "OmniAgentMesh",
    .product(name: "PhotonImessage", package: "swift-photon"),
]

#if os(macOS)
let zlibPkgConfig: String? = nil
let zlibProviders: [SystemPackageProvider]? = nil
let sqlitePkgConfig: String? = nil
let sqliteProviders: [SystemPackageProvider]? = nil
let adwaitaPkgConfig: String? = nil
let adwaitaProviders: [SystemPackageProvider]? = nil
#else
let zlibPkgConfig: String? = "zlib"
let zlibProviders: [SystemPackageProvider]? = [
    .apt(["zlib1g-dev"]),
    .brew(["zlib"]),
]
let sqlitePkgConfig: String? = "sqlite3"
let sqliteProviders: [SystemPackageProvider]? = [
    .apt(["libsqlite3-dev"]),
    .brew(["sqlite"]),
]
let adwaitaPkgConfig: String? = "libadwaita-1"
let adwaitaProviders: [SystemPackageProvider]? = [
    .apt(["libadwaita-1-dev", "libgtk-4-dev"]),
    .brew(["libadwaita", "gtk4"]),
]
#endif

let package = Package(
    name: "OmniKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
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
            name: "OmniAIAgent",
            targets: ["OmniAIAgent"]
        ),
        .library(
            name: "OmniAIAttractor",
            targets: ["OmniAIAttractor"]
        ),
        .library(
            name: "OmniACPModel",
            targets: ["OmniACPModel"]
        ),
        .library(
            name: "OmniACP",
            targets: ["OmniACP"]
        ),
        .library(
            name: "OmniMCP",
            targets: ["OmniMCP"]
        ),
        .library(
            name: "OmniAgentsSDK",
            targets: ["OmniAgentsSDK"]
        ),
        .library(
            name: "OmniAgentMesh",
            targets: ["OmniAgentMesh"]
        ),
        .library(
            name: "OmniSkills",
            targets: ["OmniSkills"]
        ),
        .library(
            name: "OmniUICore",
            targets: ["OmniUICore"]
        ),
        .library(
            name: "OmniSwiftUISymbolExtras",
            targets: ["OmniSwiftUISymbolExtras"]
        ),
        .library(
            name: "OmniUI",
            targets: ["OmniUI"]
        ),
        .library(
            name: "OmniUIAdwaita",
            targets: ["OmniUIAdwaita"]
        ),
        .library(
            name: "Sparkle",
            targets: ["Sparkle"]
        ),
        .library(
            name: "OmniUINotcursesRenderer",
            targets: ["OmniUINotcursesRenderer"]
        ),
        .library(
            name: "OmniUIAdwaitaRenderer",
            targets: ["OmniUIAdwaitaRenderer"]
        ),
        .library(
            name: "OmniExecution",
            targets: ["OmniExecution"]
        ),
        .library(
            name: "OmniVFS",
            targets: ["OmniVFS"]
        ),
        .executable(
            name: "KitchenSink",
            targets: ["KitchenSink"]
        ),
        .executable(
            name: "KitchenSinkAdwaita",
            targets: ["KitchenSinkAdwaita"]
        ),
        .executable(
            name: "OmniUIAdwaitaSmoke",
            targets: ["OmniUIAdwaitaSmoke"]
        ),
        .executable(
            name: "OmniUIAdwaitaSwiftUISmoke",
            targets: ["OmniUIAdwaitaSwiftUISmoke"]
        ),
        .executable(
            name: "AttractorCLI",
            targets: ["AttractorCLI"]
        ),
        .executable(
            name: "KitchenSinkAttractorRunner",
            targets: ["KitchenSinkAttractorRunner"]
        ),
        .executable(
            name: "OmniAICode",
            targets: ["OmniAICode"]
        ),
        .executable(
            name: "TheAgentWorker",
            targets: ["TheAgentWorkerCLI"]
        ),
        .executable(
            name: "TheAgentControlPlane",
            targets: ["TheAgentControlPlaneCLI"]
        ),
        .executable(
            name: "TheAgentSupervisor",
            targets: ["TheAgentSupervisor"]
        ),
        .library(
            name: "TheAgentWorkerKit",
            targets: ["TheAgentWorkerKit"]
        ),
        .library(
            name: "TheAgentControlPlaneKit",
            targets: ["TheAgentControlPlaneKit"]
        ),
        .library(
            name: "TheAgentIngress",
            targets: ["TheAgentIngress"]
        ),
        .library(
            name: "TheAgentTelegram",
            targets: ["TheAgentTelegram"]
        ),
        .library(
            name: "TheAgentImessage",
            targets: ["TheAgentImessage"]
        ),
        .library(
            name: "OmniAgentDeploy",
            targets: ["OmniAgentDeployKit"]
        ),
        .library(
            name: "OmniAgentDeliveryCore",
            targets: ["OmniAgentDeliveryCore"]
        ),
        .executable(
            name: "OmniAgentDeployCLI",
            targets: ["OmniAgentDeployCLI"]
        ),
    ],
    dependencies: [
        // Cross-platform networking + streaming.
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.0.0"),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.15.0"),
        .package(path: "External/swift-photon"),
        // For Swift macro stubs (SwiftData compatibility).
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"604.0.0"),
        // Swift-native testing DSL (`import Testing`, `@Test`, `#expect`).
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "6.2.0"),
        // Pure-Swift bash interpreter for in-process command execution.
        .package(url: "https://github.com/Cocoanetics/SwiftBash.git", branch: "main"),
        // Mail access for Jeff's email inbox and outbound drafts.
        .package(url: "https://github.com/Cocoanetics/SwiftMail.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .systemLibrary(
            name: "OmniCZlib",
            path: "Sources/CZlib",
            pkgConfig: zlibPkgConfig,
            providers: zlibProviders
        ),
        .systemLibrary(
            name: "CSQLite",
            pkgConfig: sqlitePkgConfig,
            providers: sqliteProviders
        ),
        .target(
            name: "CAdwaita",
            path: "Sources/CAdwaita",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/include/gtk-4.0", "-I/opt/homebrew/include/libadwaita-1", "-I/opt/homebrew/include/glib-2.0", "-I/opt/homebrew/lib/glib-2.0/include", "-I/opt/homebrew/include/pango-1.0", "-I/opt/homebrew/include/harfbuzz", "-I/opt/homebrew/include/cairo", "-I/opt/homebrew/include/gdk-pixbuf-2.0", "-I/opt/homebrew/include/graphene-1.0", "-I/opt/homebrew/lib/graphene-1.0/include"], .when(platforms: [.macOS])),
                .unsafeFlags(["-I/usr/include/gtk-4.0", "-I/usr/include/libadwaita-1", "-I/usr/include/glib-2.0", "-I/usr/lib/x86_64-linux-gnu/glib-2.0/include", "-I/usr/lib/aarch64-linux-gnu/glib-2.0/include", "-I/usr/include/pango-1.0", "-I/usr/include/harfbuzz", "-I/usr/include/cairo", "-I/usr/include/gdk-pixbuf-2.0", "-I/usr/include/graphene-1.0", "-I/usr/lib/x86_64-linux-gnu/graphene-1.0/include", "-I/usr/lib/aarch64-linux-gnu/graphene-1.0/include"], .when(platforms: [.linux])),
            ],
            linkerSettings: [
                .linkedLibrary("adwaita-1", .when(platforms: [.linux, .macOS])),
                .linkedLibrary("gtk-4", .when(platforms: [.linux, .macOS])),
                .linkedLibrary("glib-2.0", .when(platforms: [.linux, .macOS])),
                .linkedLibrary("gobject-2.0", .when(platforms: [.linux, .macOS])),
                .linkedLibrary("gio-2.0", .when(platforms: [.linux, .macOS])),
                .linkedLibrary("dl", .when(platforms: [.linux])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("WebKit", .when(platforms: [.macOS])),
                .unsafeFlags(["-L/opt/homebrew/lib"], .when(platforms: [.macOS])),
            ]
        ),
        .target(
            name: "OmniSwiftUI",
            dependencies: ["OmniUICore", "OmniUINotcursesRenderer", "SwiftUIMacros"],
            path: "Sources/SwiftUI",
            swiftSettings: commonSwiftSettings + [
                // Some larger SwiftUI view trees can trip the default solver timeout.
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
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "SwiftUICompatibilityHarness",
            dependencies: ["OmniSwiftUI", "OmniSwiftData", "OmniSwiftUISymbolExtras"],
            swiftSettings: commonSwiftSettings + [
                // Keep source compatibility with `import SwiftUI` / `import SwiftData`.
                .unsafeFlags(["-module-alias", "SwiftUI=OmniSwiftUI"]),
                .unsafeFlags(["-module-alias", "SwiftData=OmniSwiftData"]),
            ]
        ),
        .target(
            name: "OmniExecution",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniVFS",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniKit",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniHTTP",
            swiftSettings: commonSwiftSettings
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
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniAICore",
            dependencies: [
                "OmniHTTP",
                "OmniHTTPNIO",
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "WebSocketKit", package: "websocket-kit"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniAIAgent",
            dependencies: [
                "OmniAICore",
                "OmniMCP",
                "OmniExecution",
                "OmniSkills",
                "CSQLite",
                .product(name: "BashInterpreter", package: "SwiftBash"),
                .product(name: "BashCommandKit", package: "SwiftBash"),
            ],
            path: "Sources/OmniAIAgent",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniACPModel",
            path: "Sources/OmniACPModel",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "OmniACP",
            dependencies: ["OmniACPModel", "OmniHTTP", "OmniHTTPNIO", "OmniAICore"],
            path: "Sources/OmniACP",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "OmniMCP",
            dependencies: ["OmniAICore", "OmniHTTP"],
            path: "Sources/OmniMCP",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "OmniAIAttractor",
            dependencies: ["OmniAICore", "OmniAIAgent", "OmniACP"],
            path: "Sources/OmniAIAttractor",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniAgentsSDK",
            dependencies: ["OmniAICore", "OmniAgentMesh", "OmniMCP", "OmniSkills"],
            path: "Sources/OmniAgentsSDK",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "OmniAgentMesh",
            dependencies: [
                "CSQLite",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/OmniAgentMesh",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "OmniSkills",
            dependencies: [
                "OmniAgentMesh",
            ],
            path: "Sources/OmniSkills",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "OmniUICore",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniUI",
            dependencies: [
                "OmniUICore",
                .target(name: "OmniUINotcursesRenderer", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniSwiftUISymbolExtras",
            dependencies: [],
            path: "Sources/OmniSwiftUISymbolExtras",
            swiftSettings: commonSwiftSettings
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
            swiftSettings: commonSwiftSettings + [
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
            name: "OmniUIAdwaitaRenderer",
            dependencies: ["OmniUICore", "CAdwaita"],
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "OmniUIAdwaita",
            dependencies: ["OmniUICore", "OmniUIAdwaitaRenderer", "SwiftUIMacros"],
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "Sparkle",
            path: "Sources/Sparkle",
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "KitchenSink",
            dependencies: ["OmniSwiftUI", "OmniUI", "OmniUINotcursesRenderer"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
                .unsafeFlags(["-Xfrontend", "-solver-expression-time-threshold=300"]),
            ]
        ),
        .executableTarget(
            name: "KitchenSinkAdwaita",
            dependencies: ["OmniSwiftUI", "OmniSwiftData", "OmniUICore", "OmniUIAdwaita"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
                .unsafeFlags(["-Xfrontend", "-solver-expression-time-threshold=300"]),
                .unsafeFlags(["-module-alias", "SwiftUI=OmniSwiftUI"]),
                .unsafeFlags(["-module-alias", "SwiftData=OmniSwiftData"]),
            ]
        ),
        .executableTarget(
            name: "OmniUIAdwaitaSmoke",
            dependencies: ["OmniUIAdwaita"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "OmniUIAdwaitaSwiftUISmoke",
            dependencies: ["OmniUIAdwaita", "OmniSwiftData"],
            swiftSettings: [
                .unsafeFlags(["-warn-concurrency", "-strict-concurrency=complete"]),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
                .unsafeFlags(["-module-alias", "SwiftUI=OmniUIAdwaita"]),
                .unsafeFlags(["-module-alias", "SwiftData=OmniSwiftData"]),
            ]
        ),
        .executableTarget(
            name: "KitchenSinkAttractorRunner",
            dependencies: ["TheAgentWorkerKit"],
            path: "Sources/KitchenSinkAttractorRunner",
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "AttractorCLI",
            dependencies: ["OmniAIAttractor"],
            path: "Sources/AttractorCLI",
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "OmniAICode",
            dependencies: [
                "OmniAIAgent", "OmniAICore", "OmniMCP",
            ],
            path: "Sources/OmniAICode",
            swiftSettings: commonSwiftSettings
        ),
        .target(
            name: "TheAgentWorkerKit",
            dependencies: [
                "OmniAICore",
                "OmniACP",
                "OmniACPModel",
                "OmniAIAttractor",
                "OmniAgentMesh",
                "OmniMCP",
                "OmniSkills",
            ],
            path: "Sources/TheAgentWorker",
            exclude: ["main.swift"],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .executableTarget(
            name: "TheAgentWorkerCLI",
            dependencies: ["TheAgentWorkerKit"],
            path: "Sources/TheAgentWorker",
            exclude: [
                "ACP",
                "Attractor",
                "LocalTaskExecutor.swift",
                "MCP",
                "Review",
                "Scenarios",
                "Subagents",
                "TaskStreams",
                "WorkerCapabilities.swift",
                "WorkerDaemon.swift",
                "WorkerExecutorFactory.swift",
            ],
            sources: ["main.swift"],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "OmniAgentDeliveryCore",
            dependencies: [
                "OmniAgentMesh",
            ],
            path: "Sources/OmniAgentDeliveryCore",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "TheAgentControlPlaneKit",
            dependencies: [
                "OmniAIAgent",
                "OmniAICore",
                "OmniAgentMesh",
                "OmniAgentDeliveryCore",
                "OmniSkills",
                "TheAgentWorkerKit",
                "SwiftMail",
            ],
            path: "Sources/TheAgentControlPlane",
            exclude: ["main.swift"],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "TheAgentIngress",
            dependencies: [
                "OmniAgentMesh",
                "TheAgentControlPlaneKit",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/TheAgentIngress",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "TheAgentTelegram",
            dependencies: [
                "TheAgentIngress",
                "OmniAgentMesh",
            ],
            path: "Sources/TheAgentTelegram",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "TheAgentImessage",
            dependencies: imessageTargetDependencies,
            path: "Sources/TheAgentImessage",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .executableTarget(
            name: "TheAgentControlPlaneCLI",
            dependencies: ["TheAgentControlPlaneKit", "TheAgentIngress", "TheAgentTelegram", "TheAgentImessage"],
            path: "Sources/TheAgentControlPlane",
            exclude: [
                "Changes",
                "DAV",
                "Diagnostics",
                "Email",
                "Experiments",
                "Interaction",
                "Memory",
                "Missions",
                "NotificationInbox.swift",
                "Onboarding",
                "Policy",
                "Registry",
                "Routing",
                "Runtime",
                "RootAgentRuntime.swift",
                "RootAgentToolbox.swift",
                "RootOrchestratorProfile.swift",
                "ChannelActionRegistry.swift",
                "RootAgentServer.swift",
                "RootConversation.swift",
                "Scheduler",
                "Skills",
                "Supervision",
            ],
            sources: ["main.swift"],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .executableTarget(
            name: "TheAgentSupervisor",
            dependencies: ["TheAgentControlPlaneKit", "TheAgentWorkerKit", "OmniAgentMesh"],
            path: "Sources/TheAgentSupervisor",
            swiftSettings: swift6CommonSwiftSettings
        ),
        .target(
            name: "OmniAgentDeployKit",
            dependencies: [
                "OmniAgentDeliveryCore",
                "OmniAgentMesh",
                "TheAgentControlPlaneKit",
                "TheAgentWorkerKit",
            ],
            path: "Sources/OmniAgentDeploy",
            exclude: ["main.swift"],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .executableTarget(
            name: "OmniAgentDeployCLI",
            dependencies: ["OmniAgentDeployKit"],
            path: "Sources/OmniAgentDeploy",
            exclude: ["ChangePipeline.swift"],
            sources: ["main.swift"],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "OmniVFSTests",
            dependencies: [
                "OmniVFS",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "OmniKitTests",
            dependencies: [
                "OmniKit",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "OmniHTTPTests",
            dependencies: [
                "OmniHTTP",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "OmniAICoreTests",
            dependencies: [
                "OmniAICore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "OmniMCPTests",
            dependencies: [
                "OmniMCP",
                "OmniHTTP",
                "OmniAICore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "OmniAgentsSDKTests",
            dependencies: [
                "OmniAgentsSDK",
                "OmniSkills",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "OmniAgentMeshTests",
            dependencies: [
                "OmniAgentMesh",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "OmniSkillsTests",
            dependencies: [
                "OmniSkills",
                "OmniAgentMesh",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "OmniAIAgentTests",
            dependencies: [
                "OmniAIAgent",
                "OmniSkills",
                "OmniAICore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "TheAgentWorkerTests",
            dependencies: [
                "TheAgentWorkerKit",
                "TheAgentControlPlaneKit",
                "OmniAgentMesh",
                "OmniSkills",
                "OmniACP",
                "OmniACPModel",
                "OmniAIAttractor",
                "OmniMCP",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "TheAgentControlPlaneTests",
            dependencies: [
                "OmniAgentDeliveryCore",
                "TheAgentControlPlaneKit",
                "TheAgentWorkerKit",
                "OmniAICore",
                "OmniAgentMesh",
                "OmniSkills",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "TheAgentIngressTests",
            dependencies: [
                "TheAgentIngress",
                "TheAgentTelegram",
                "TheAgentControlPlaneKit",
                "TheAgentWorkerKit",
                "OmniAICore",
                "OmniAgentMesh",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "OmniAgentDeployTests",
            dependencies: [
                "OmniAgentDeliveryCore",
                "OmniAgentDeployKit",
                "TheAgentControlPlaneKit",
                "TheAgentWorkerKit",
                "OmniAgentMesh",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "OmniAgentScenarioTests",
            dependencies: [
                "OmniAgentDeliveryCore",
                "OmniAgentDeployKit",
                "TheAgentControlPlaneKit",
                "TheAgentWorkerKit",
                "OmniAgentMesh",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "OmniACPModelTests",
            dependencies: [
                "OmniACPModel",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "OmniACPTests",
            dependencies: [
                "OmniACP",
                "OmniACPModel",
                "OmniHTTP",
                "OmniAICore",
                .product(name: "Testing", package: "swift-testing"),
            ],
            resources: [
                .process("GoldenTests"),
                .copy("Fixtures"),
            ],
            swiftSettings: swift6CommonSwiftSettings
        ),
        .testTarget(
            name: "OmniAIAttractorTests",
            dependencies: [
                "OmniAIAttractor",
                "OmniAICore",
                "OmniAIAgent",
                "OmniACP",
                "OmniACPModel",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "OmniUICoreTests",
            dependencies: [
                "OmniUICore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
        .testTarget(
            name: "OmniUIAdwaitaRendererTests",
            dependencies: [
                "OmniUIAdwaitaRenderer",
                .product(name: "Testing", package: "swift-testing"),
            ],
            swiftSettings: commonSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
