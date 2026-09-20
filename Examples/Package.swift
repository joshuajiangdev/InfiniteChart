// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "InfiniteChartExamples",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [
        .executable(name: "BTCMacExample", targets: ["BTCMacExample"]),
        .executable(name: "BTCiOSExample", targets: ["BTCiOSExample"]),
    ],
    dependencies: [
        .package(name: "InfiniteChart", path: ".."),
    ],
    targets: [
        .target(
            name: "BTCExampleSupport",
            dependencies: [.product(name: "InfiniteChart", package: "InfiniteChart")],
            path: "Shared",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "BTCMacExample",
            dependencies: ["BTCExampleSupport"],
            path: "macOS"
        ),
        .executableTarget(
            name: "BTCiOSExample",
            dependencies: ["BTCExampleSupport"],
            path: "iOS",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "BTCExampleSupportTests",
            dependencies: ["BTCExampleSupport"],
            path: "Tests/BTCExampleSupportTests"
        ),
    ]
)
