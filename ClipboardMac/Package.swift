// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipboardMac",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "ClipboardMacServices", targets: ["ClipboardMacServices"]),
    ],
    dependencies: [
        .package(path: "../ClipboardCore")
    ],
    targets: [
        .target(
            name: "ClipboardMacServices",
            dependencies: ["ClipboardCore"],
            path: "Sources/ClipboardMacServices",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ClipboardMac",
            dependencies: ["ClipboardCore", "ClipboardMacServices"],
            path: "Sources/ClipboardMacApp"
        ),
        .testTarget(
            name: "ClipboardMacTests",
            dependencies: ["ClipboardMacServices", "ClipboardCore"],
            path: "Tests/ClipboardMacTests"
        ),
        .testTarget(
            name: "ClipboardMacAppTests",
            dependencies: ["ClipboardMac", "ClipboardCore", "ClipboardMacServices"],
            path: "Tests/ClipboardMacAppTests"
        ),
        .testTarget(
            name: "ClipboardMacUITests",
            dependencies: ["ClipboardMac"],
            path: "Tests/ClipboardMacUITests"
        ),
    ]
)
