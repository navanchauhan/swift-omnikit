// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-photon",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "swift-photon",
            targets: ["swift-photon"]),
        .library(
            name: "PhotonImessage",
            targets: ["PhotonImessage"]
        ),
        .executable(
            name: "photon-demo",
            targets: ["photon-demo"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.33.0"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.8.2"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.36.0"),
    ],
    targets: [
        .target(name: "swift-photon"),
        .target(
            name: "PhotonImessage",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "NIO", package: "swift-nio"),
            ],
            path: "Sources/PhotonImessage",
            exclude: ["proto"]
        ),
        .executableTarget(
            name: "photon-demo",
            dependencies: [
                .target(name: "PhotonImessage"),
            ],
            path: "Sources/photon-demo"
        ),
        .testTarget(
            name: "swift-photonTests",
            dependencies: ["swift-photon"]
        ),
    ]
)
