import Foundation
import NutriCore

/// Fields Apple Health can't store natively, carried as JSON in sample metadata
/// (`HealthSyncKey.payload`) so another device can rebuild the full record.
struct MealPayload: Codable, Equatable {
    var foodID: String?
    var grams: Double
    var mealType: String
    var source: String
    var updatedAt: Date
}

struct BodyPayload: Codable, Equatable {
    var reading: BodyReading
    var source: String
    var note: String
    var updatedAt: Date
}

extension MealEntry {
    var payload: MealPayload {
        MealPayload(foodID: foodID, grams: grams, mealType: mealTypeRaw, source: sourceRaw, updatedAt: updatedAt)
    }

    var healthSample: MealSample {
        MealSample(name: name, date: date, nutrients: nutrients, nutriLensID: id, payload: PayloadCoder.encode(payload))
    }
}

extension BodyMeasurement {
    var payload: BodyPayload {
        BodyPayload(reading: reading, source: sourceRaw, note: note, updatedAt: updatedAt)
    }
}

extension WorkoutLog {
    var payload: WorkoutPayload {
        WorkoutPayload(kind: kindRaw, title: title, planWeek: planWeek, planWeekday: planWeekday, cardioMinutes: cardioMinutes,
                       readiness: readinessRaw, energyRating: energyRating, notes: notes, exercises: exercises, updatedAt: updatedAt,
                       steps: steps, distanceKm: distanceKm)
    }

    func apply(_ p: WorkoutPayload) {
        kindRaw = p.kind
        title = p.title
        planWeek = p.planWeek
        planWeekday = p.planWeekday
        cardioMinutes = p.cardioMinutes
        readinessRaw = p.readiness
        energyRating = p.energyRating
        notes = p.notes
        exercises = p.exercises
        updatedAt = p.updatedAt
        steps = p.steps ?? 0
        distanceKm = p.distanceKm ?? 0
    }
}
