// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftMail",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "SwiftMail", targets: ["SwiftMail"]),
    ],
    targets: [
        .target(name: "SwiftMail"),
    ]
)
