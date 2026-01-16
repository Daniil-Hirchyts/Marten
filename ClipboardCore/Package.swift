// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipboardCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "ClipboardCore", targets: ["ClipboardCore"])
    ],
    targets: [
        .target(
            name: "ClipboardCore",
            path: "Sources",
            exclude: [
                "DataModel/Paste.xcdatamodeld"
            ],
            resources: [
                .copy("DataModel/Paste.momd")
            ]
        ),
        .testTarget(
            name: "ClipboardCoreTests",
            dependencies: ["ClipboardCore"],
            path: "Tests"
        ),
    ]
)
