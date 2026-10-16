// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PodsBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "PodsBar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/PodsBar",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "PodsBarTests", dependencies: ["PodsBar"])
    ]
)
