import CoreGraphics
import Foundation
import NutriCore
import Vision

/// Suggests foods for a photo using Apple's built-in on-device image classifier (Vision).
///
/// No third-party model is used. Vision's general classifier knows a limited set of dishes, so its
/// labels are only suggestions: they're mapped onto the nutrition table and the user always confirms
/// the dish and portion, or searches for it.
struct VisionFoodRecognizer: FoodRecognizing {
    let database: NutritionDatabase

    var engine: RecognitionEngine { .visionBuiltIn }

    func recognize(_ image: CGImage) async throws -> [FoodCandidate] {
        var request = ClassifyImageRequest()
        request.preferCPUInSimulator()
        let observations = try await request.perform(on: image)
        return RecognitionRanking.candidates(
            from: observations.map { ($0.identifier, Double($0.confidence)) },
            database: database,
            // Vision spreads probability over ~1,300 labels, so food labels score low.
            minimumConfidence: 0.01
        )
    }
}

extension VisionRequest {
    /// The Simulator has no Neural Engine and Vision's GPU path often fails there
    /// ("Could not create inference context"), so run every stage on the CPU. No-op on devices.
    mutating func preferCPUInSimulator() {
        #if targetEnvironment(simulator)
        for (stage, devices) in supportedComputeStageDevices {
            if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                setComputeDevice(cpu, for: stage)
            }
        }
        #endif
    }
}

/// Fixed results, for previews, tests and demo mode.
struct MockFoodRecognizer: FoodRecognizing {
    var results: [FoodCandidate]
    var engine: RecognitionEngine { .mock }

    func recognize(_ image: CGImage) async throws -> [FoodCandidate] {
        results
    }

    static func demo(database: NutritionDatabase) -> MockFoodRecognizer {
        let guesses: [(String, Double)] = [("misal_pav", 0.64), ("matki_usal", 0.12), ("pav_bhaji", 0.07), ("amti", 0.04)]
        return MockFoodRecognizer(results: guesses.compactMap { id, confidence in
            database.food(id: id).map { FoodCandidate(food: $0, confidence: confidence, label: id) }
        })
    }
}
