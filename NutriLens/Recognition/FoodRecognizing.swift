import CoreGraphics
import Foundation
import NutriCore

/// A food the recogniser thinks is in the photo.
struct FoodCandidate: Identifiable, Hashable, Sendable {
    var food: FoodItem
    /// 0...1
    var confidence: Double
    /// The classifier's own label, for display/debugging.
    var label: String

    var id: String { food.id }
}

/// Which classifier produced the candidates.
enum RecognitionEngine: Equatable, Sendable {
    /// Apple's general-purpose on-device image classifier (Vision).
    case visionBuiltIn
    /// Fixed answers (previews, tests, demo mode).
    case mock

    var displayName: String {
        switch self {
        case .visionBuiltIn: "Apple Vision (on device)"
        case .mock: "Demo recogniser"
        }
    }
}

protocol FoodRecognizing: Sendable {
    var engine: RecognitionEngine { get }
    /// Returns the most likely foods in the image, best first. Never sends the image off the device.
    func recognize(_ image: CGImage) async throws -> [FoodCandidate]
}

enum RecognitionRanking {
    /// How much each further suggestion for the same label is discounted (curry → chicken curry 100 %,
    /// paneer butter masala 85 %, chole 72 %, …).
    static let followingSuggestionWeight = 0.85

    /// Maps classifier labels to table foods (several Indian dishes per generic label), merges
    /// duplicates keeping the best score, drops weak guesses and returns the top `limit`.
    static func candidates(
        from observations: [(label: String, confidence: Double)],
        database: NutritionDatabase,
        minimumConfidence: Double = 0.02,
        limit: Int = 6
    ) -> [FoodCandidate] {
        var best: [String: FoodCandidate] = [:]
        for observation in observations where observation.confidence >= minimumConfidence {
            for (rank, food) in database.foods(forVisionLabel: observation.label).enumerated() {
                let confidence = observation.confidence * pow(followingSuggestionWeight, Double(rank))
                if let existing = best[food.id], existing.confidence >= confidence { continue }
                best[food.id] = FoodCandidate(food: food, confidence: confidence, label: observation.label)
            }
        }
        return best.values
            .sorted { $0.confidence != $1.confidence ? $0.confidence > $1.confidence : $0.food.name < $1.food.name }
            .prefix(limit)
            .map { $0 }
    }
}
