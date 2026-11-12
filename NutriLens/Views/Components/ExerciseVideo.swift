import AVFoundation
import NutriCore
import SwiftUI
import UIKit

/// Plays a bundled exercise demonstration on a silent, endless loop.
struct LoopingVideoView: UIViewRepresentable {
    let name: String

    static func url(for name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mp4")
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.load(name)
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.load(name)
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var looper: AVPlayerLooper?
        private var current: String?

        func load(_ name: String) {
            guard name != current else { return }
            current = name
            stop()
            guard let url = LoopingVideoView.url(for: name) else { return }
            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            backgroundColor = UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
            player.play()
        }

        func stop() {
            playerLayer.player?.pause()
            looper?.disableLooping()
            looper = nil
            playerLayer.player = nil
        }
    }
}

/// A demonstration video in a rounded frame, with a fallback when the file is missing.
struct ExerciseVideoCard: View {
    let exercise: Exercise

    var body: some View {
        Group {
            if LoopingVideoView.url(for: exercise.videoName) != nil {
                LoopingVideoView(name: exercise.videoName)
            } else {
                ContentUnavailableView(exercise.name, systemImage: "film", description: Text("Demo video missing"))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityLabel("Looping demonstration of \(exercise.name)")
    }
}

/// A still frame from an exercise video, for lists.
struct ExerciseThumbnail: View {
    let exercise: Exercise
    var size: CGFloat = 52
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(red: 0.94, green: 0.95, blue: 0.97)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.2))
        .task(id: exercise.videoName) {
            image = await ThumbnailCache.shared.image(for: exercise.videoName)
        }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var images: [String: UIImage] = [:]

    func image(for name: String) async -> UIImage? {
        if let cached = images[name] { return cached }
        guard let url = LoopingVideoView.url(for: name), let cgImage = await Self.frame(from: url) else { return nil }
        let image = UIImage(cgImage: cgImage)
        images[name] = image
        return image
    }

    /// A frame from 40 % into the clip, where the movement is under way.
    nonisolated private static func frame(from url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.appliesPreferredTrackTransform = true
        guard let duration = try? await asset.load(.duration) else { return nil }
        return try? await generator.image(at: CMTimeMultiplyByFloat64(duration, multiplier: 0.4)).image
    }
}
