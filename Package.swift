// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Dimmer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Dimmer",
            targets: ["Dimmer"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Dimmer",
            path: "Sources/Dimmer"
        ),
        .testTarget(
            name: "DimmerTests",
            dependencies: ["Dimmer"],
            path: "Tests/DimmerTests"
        )
    ]
)
