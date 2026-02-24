// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MartenIOS",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .watchOS("26.0")
    ],
    products: [
        .library(name: "MartenIOSApp", targets: ["MartenIOSApp"]),
        .library(name: "MartenWatchApp", targets: ["MartenWatchApp"])
    ],
    dependencies: [
        .package(path: "../MartenCore")
    ],
    targets: [
        .target(
            name: "MartenIOSApp",
            dependencies: [
                .product(name: "MartenCore", package: "MartenCore")
            ],
            path: "Sources/MartenIOSApp",
            resources: [.process("Resources")]
        ),
        .target(
            name: "MartenWatchApp",
            dependencies: [
                .product(name: "MartenCore", package: "MartenCore")
            ],
            path: "Sources/MartenWatchApp"
        ),
        .testTarget(
            name: "MartenIOSAppTests",
            dependencies: [
                "MartenIOSApp",
                .product(name: "MartenCore", package: "MartenCore")
            ],
            path: "Tests/MartenIOSAppTests"
        ),
    ]
)
