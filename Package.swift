// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BugbookSwift",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "BugbookSwift",
            path: "Sources/BugbookSwift"
        )
    ]
)
