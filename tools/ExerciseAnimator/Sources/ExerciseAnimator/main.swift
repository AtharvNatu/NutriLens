import Foundation

// swift run -c release ExerciseAnimator <video-output-dir> [--preview <contact-sheet-dir>] [--only <name>]
var arguments = Array(CommandLine.arguments.dropFirst())
guard let outputPath = arguments.first else {
    print("usage: ExerciseAnimator <output-dir> [--preview <dir>] [--only <name>]")
    exit(2)
}
arguments.removeFirst()
var previewDir: URL?
var only: String?
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    guard let value = arguments.first else { break }
    arguments.removeFirst()
    if flag == "--preview" { previewDir = URL(fileURLWithPath: value) }
    if flag == "--only" { only = value }
}

let output = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
if let previewDir { try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true) }

for animation in allAnimations where only == nil || animation.name == only {
    let url = output.appendingPathComponent("\(animation.name).mp4")
    try await writeVideo(animation, to: url)
    if let previewDir {
        try writeContactSheet(animation, to: previewDir.appendingPathComponent("\(animation.name).png"))
    }
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("\(animation.name): \(animation.frameCount) frames, \(String(format: "%.1f", Double(animation.frameCount) / Double(animation.fps))) s, \(size / 1024) KB")
}
