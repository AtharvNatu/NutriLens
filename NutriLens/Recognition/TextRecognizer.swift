import CoreGraphics
import NutriCore
import Vision

/// Reads text from an image on the device with Vision, for scale screenshots.
enum TextRecognizer {
    static func lines(in image: CGImage) async throws -> [RecognizedLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Numbers and short labels: language correction tends to "fix" values.
        request.usesLanguageCorrection = false
        request.preferCPUInSimulator()
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            // Vision boxes are normalised with the origin at the bottom-left.
            let box = observation.boundingBox.cgRect
            return RecognizedLine(text, x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        }
    }

    /// Reads one or more screenshots of the same scale reading and combines them.
    static func reading(from images: [CGImage]) async throws -> BodyReading {
        var combined = BodyReading()
        for image in images {
            combined = combined.merged(with: ScaleScreenshotParser.parse(try await lines(in: image)))
        }
        return combined
    }
}
