// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BugbookSwift",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // Shared library — models, storage, engines
        .target(
            name: "BugbookCore",
            path: "Sources/BugbookCore"
        ),
        // CLI executable
        .executableTarget(
            name: "BugbookCLI",
            dependencies: [
                "BugbookCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/BugbookCLI"
        ),
        // SwiftUI app
        .executableTarget(
            name: "BugbookSwift",
            dependencies: ["BugbookCore"],
            path: "Sources/BugbookSwift"
        ),
    ]
)
