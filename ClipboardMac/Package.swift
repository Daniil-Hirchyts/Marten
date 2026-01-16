// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipboardMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClipboardMac", targets: ["ClipboardMac"]),
        .executable(name: "ClipboardMacValidation", targets: ["ClipboardMacValidation"]),
    ],
    dependencies: [
        .package(path: "../ClipboardCore")
    ],
    targets: [
        .target(
            name: "ClipboardMacServices",
            dependencies: ["ClipboardCore"],
            path: "Sources/ClipboardMacServices"
        ),
        .executableTarget(
            name: "ClipboardMac",
            dependencies: ["ClipboardCore", "ClipboardMacServices"],
            path: "Sources/ClipboardMacApp"
        ),
        .executableTarget(
            name: "ClipboardMacValidation",
            dependencies: ["ClipboardMacServices", "ClipboardCore"],
            path: "Sources/ClipboardMacValidation"
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
