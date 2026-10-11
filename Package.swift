// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "glance",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GlanceCore"),
        .executableTarget(name: "glance", dependencies: ["GlanceCore"]),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
        .testTarget(name: "glanceTests", dependencies: ["glance", "GlanceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
