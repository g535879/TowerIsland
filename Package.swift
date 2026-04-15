// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TowerIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DIShared"),
        .executableTarget(name: "TowerIsland", dependencies: ["DIShared"], path: "Sources/DynamicIsland"),
        .executableTarget(name: "DIBridge", dependencies: ["DIShared"]),
        .testTarget(name: "TowerIslandTests", dependencies: ["TowerIsland", "DIBridge"]),
    ]
)
