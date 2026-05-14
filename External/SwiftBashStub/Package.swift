// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftBash",
    products: [
        .library(name: "BashInterpreter", targets: ["BashInterpreter"]),
        .library(name: "BashCommandKit", targets: ["BashCommandKit"]),
    ],
    targets: [
        .target(name: "BashInterpreter"),
        .target(name: "BashCommandKit"),
    ]
)
