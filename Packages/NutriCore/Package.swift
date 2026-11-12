// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NutriCore",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "NutriCore", targets: ["NutriCore"]),
    ],
    targets: [
        .target(
            name: "NutriCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NutriCoreTests",
            dependencies: ["NutriCore"]
        ),
    ]
)
