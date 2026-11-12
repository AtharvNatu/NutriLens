// swift-tools-version: 6.0
// Renders NutriLens's looping exercise demonstration videos (original artwork, no third-party footage).
// Usage: swift run -c release ExerciseAnimator <output-dir> [--preview <dir>] [--only ex01-goblet-squat]
import PackageDescription

let package = Package(
    name: "ExerciseAnimator",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "ExerciseAnimator", path: "Sources/ExerciseAnimator"),
    ]
)
