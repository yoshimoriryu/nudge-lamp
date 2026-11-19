// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NudgeLamp",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "NudgeLampCore"),
        .executableTarget(name: "NudgeLamp", dependencies: ["NudgeLampCore"]),
        .testTarget(name: "NudgeLampCoreTests", dependencies: ["NudgeLampCore"]),
    ]
)
