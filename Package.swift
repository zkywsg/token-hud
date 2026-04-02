// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "token_hudCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "token_hudCore",
            path: "Sources/token_hudCore"
        ),
        .testTarget(
            name: "token_hudCoreTests",
            dependencies: ["token_hudCore"],
            path: "Tests/token_hudCoreTests"
        ),
    ]
)
