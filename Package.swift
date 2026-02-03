// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageTracker",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "UsageTracker",
            path: "Sources/UsageTracker"
        ),
        .testTarget(
            name: "UsageTrackerTests",
            dependencies: ["UsageTracker"],
            path: "Tests/UsageTrackerTests"
        )
    ]
)
