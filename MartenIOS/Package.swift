// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MartenIOS",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "MartenIOSApp", targets: ["MartenIOSApp"])
    ],
    dependencies: [
        .package(path: "../MartenCore")
    ],
    targets: [
        .target(
            name: "MartenIOSApp",
            dependencies: ["MartenCore"],
            path: "Sources/MartenIOSApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "MartenIOSAppTests",
            dependencies: ["MartenIOSApp", "MartenCore"],
            path: "Tests/MartenIOSAppTests"
        ),
    ]
)
