// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "glance",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/nesevis/exhaust", exact: "1.9.0"),
    ],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "glance", dependencies: ["GlanceCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore", .product(name: "Exhaust", package: "exhaust")]),
        .testTarget(name: "glanceTests", dependencies: ["glance", "GlanceCore", .product(name: "Sparkle", package: "Sparkle")]),
    ],
    swiftLanguageModes: [.v5]
)
