// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpillAuraCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpillAuraCore", targets: ["SpillAuraCore"]),
    ],
    targets: [
        .target(
            name: "SpillAuraCore",
            path: "Sources/SpillAuraCore"
        ),
    ]
)
