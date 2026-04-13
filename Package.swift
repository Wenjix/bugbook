// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Dahso",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "DahsoCore",
            targets: ["DahsoCore"]
        ),
        .executable(
            name: "DahsoCLI",
            targets: ["DahsoCLI"]
        ),
        .executable(
            name: "Dahso",
            targets: ["Dahso"]
        ),
        .executable(
            name: "DahsoMobile",
            targets: ["DahsoMobile"]
        ),
        .executable(
            name: "DahsoMCPSpike",
            targets: ["DahsoMCPSpike"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "6.0.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
        // GhosttyKit: GPU-accelerated terminal engine (replaces SwiftTerm)
    ],
    targets: [
        // Shared library — models, storage, engines
        .target(
            name: "DahsoCore",
            path: "Sources/DahsoCore"
        ),
        // CLI executable
        .executableTarget(
            name: "DahsoCLI",
            dependencies: [
                "DahsoCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/DahsoCLI"
        ),
        // SwiftUI app
        .executableTarget(
            name: "Dahso",
            dependencies: [
                "DahsoCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                "GhosttyKit",
            ],
            path: "Sources/Dahso",
            exclude: ["MCP"],
            swiftSettings: [
                .define("DAHSO_BROWSER_CHROMIUM")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("WebKit"),
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
            ]
        ),
        // iPhone-friendly SwiftUI app
        .executableTarget(
            name: "DahsoMobile",
            dependencies: ["DahsoCore"],
            path: "Sources/DahsoMobile"
        ),
        .executableTarget(
            name: "DahsoMCPSpike",
            path: "Sources/Dahso/MCP"
        ),
        // Unit tests for DahsoCore
        .testTarget(
            name: "DahsoCoreTests",
            dependencies: ["DahsoCore"],
            path: "Tests/DahsoCoreTests"
        ),
        // Integration tests for Dahso app layer (models, state)
        .testTarget(
            name: "DahsoTests",
            dependencies: [
                "Dahso",
                "DahsoCore",
            ],
            path: "Tests/DahsoTests",
            exclude: ["perf_baseline.tsv"]
        ),
        .testTarget(
            name: "DahsoCLITests",
            dependencies: [
                "DahsoCLI",
                "DahsoCore",
            ],
            path: "Tests/DahsoCLITests"
        ),
        // GhosttyKit static library (Metal-backed terminal engine)
        .binaryTarget(
            name: "GhosttyKit",
            path: "Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
