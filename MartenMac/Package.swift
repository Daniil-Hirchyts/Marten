// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MartenMac",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "MartenMacServices", targets: ["MartenMacServices"]),
    ],
    dependencies: [
        .package(path: "../MartenCore")
    ],
    targets: [
        .target(
            name: "MartenMacServices",
            dependencies: ["MartenCore"],
            path: "Sources/MartenMacServices",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "MartenMac",
            dependencies: ["MartenCore", "MartenMacServices"],
            path: "Sources/MartenMacApp"
        ),
        .testTarget(
            name: "MartenMacTests",
            dependencies: ["MartenMacServices", "MartenCore"],
            path: "Tests/MartenMacTests"
        ),
        .testTarget(
            name: "MartenMacAppTests",
            dependencies: ["MartenMac", "MartenCore", "MartenMacServices"],
            path: "Tests/MartenMacAppTests"
        ),
        .testTarget(
            name: "MartenMacUITests",
            dependencies: ["MartenMac"],
            path: "Tests/MartenMacUITests"
        ),
    ]
)
