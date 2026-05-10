// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OmniUIDropIn",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "OmniUI", targets: ["OmniUI"]),
    ],
    targets: [
        .target(name: "OmniUI"),
    ]
)
