// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "InfiniteChart",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .macCatalyst(.v13),
    ],
    products: [
        .library(
            name: "InfiniteChart",
            targets: ["InfiniteChart"]
        ),
    ],
    targets: [
        .target(
            name: "InfiniteChart"
        ),
        .testTarget(
            name: "InfiniteChartTests",
            dependencies: ["InfiniteChart"]
        ),
    ]
)
