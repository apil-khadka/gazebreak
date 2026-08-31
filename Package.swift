// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GazeBreak",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "GazeBreak", targets: ["GazeBreak"])
    ],
    targets: [
        .executableTarget(
            name: "GazeBreak",
            path: "Sources/GazeBreak",
            resources: [.process("Resources")]
        )
    ]
)
