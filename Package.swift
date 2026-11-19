// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AgentLamp",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "AgentLampCore"),
        .executableTarget(name: "AgentLamp", dependencies: ["AgentLampCore"]),
        .testTarget(name: "AgentLampCoreTests", dependencies: ["AgentLampCore"]),
    ]
)
