// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Bugbook",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "BugbookCore",
            targets: ["BugbookCore"]
        ),
        .executable(
            name: "BugbookCLI",
            targets: ["BugbookCLI"]
        ),
        .executable(
            name: "Bugbook",
            targets: ["Bugbook"]
        ),
        .executable(
            name: "BugbookMobile",
            targets: ["BugbookMobile"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.0.1"),
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
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/BugbookCLI"
        ),
        // SwiftUI app
        .executableTarget(
            name: "Bugbook",
            dependencies: [
                "BugbookCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Sentry", package: "sentry-cocoa"),
            ],
            path: "Sources/Bugbook"
        ),
        // iPhone-friendly SwiftUI app
        .executableTarget(
            name: "BugbookMobile",
            dependencies: ["BugbookCore"],
            path: "Sources/BugbookMobile"
        ),
        // Unit tests for BugbookCore
        .testTarget(
            name: "BugbookCoreTests",
            dependencies: ["BugbookCore"],
            path: "Tests/BugbookCoreTests"
        ),
        // Integration tests for Bugbook app layer (models, state)
        .testTarget(
            name: "BugbookTests",
            dependencies: [
                "Bugbook",
                "BugbookCore",
            ],
            path: "Tests/BugbookTests"
        ),
        .testTarget(
            name: "BugbookCLITests",
            dependencies: [
                "BugbookCLI",
                "BugbookCore",
            ],
            path: "Tests/BugbookCLITests"
        ),
    ]
)
