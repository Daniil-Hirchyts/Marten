// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MartenCore",
    platforms: [
        .iOS("26.0"),
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
