// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "glance",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GlanceCore"),
        .testTarget(name: "GlanceCoreTests", dependencies: ["GlanceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
