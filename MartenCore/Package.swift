// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MartenCore",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "MartenCore", targets: ["MartenCore"])
    ],
    targets: [
        .target(
            name: "MartenCore",
            path: "Sources",
            exclude: [
                "DataModel/Marten.xcdatamodeld"
            ],
            resources: [
                .copy("DataModel/Marten.momd")
            ]
        ),
        .testTarget(
            name: "MartenCoreTests",
            dependencies: ["MartenCore"],
            path: "Tests"
        ),
    ]
)
