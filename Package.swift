// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PodsBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PodsBar",
            path: "Sources/PodsBar",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
