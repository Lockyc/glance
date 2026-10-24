// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "glance",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "glance", dependencies: ["GlanceCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
        .testTarget(name: "glanceTests", dependencies: ["glance", "GlanceCore", .product(name: "Sparkle", package: "Sparkle")]),
    ],
    swiftLanguageModes: [.v5]
)
