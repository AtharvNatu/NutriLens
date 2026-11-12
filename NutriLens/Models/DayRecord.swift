import Foundation
import NutriCore
import SwiftData

/// A workout as remembered in a day's record.
struct DayWorkout: Codable, Hashable, Identifiable {
    var name: String
    var symbolName: String
    var start: Date
    var minutes: Double
    var kilocalories: Double
    var steps: Int
    /// Moderate minutes it counts toward the weekly cardio target.
    var cardioMinutes: Double = 0
    var source: String
    /// Read from Apple Health (kept if Health later returns nothing for the day), or logged only in NutriLens.
    var fromHealth: Bool = true

    var id: String { "\(start.timeIntervalSince1970)-\(name)" }
}

/// Everything about one calendar day, stored so old days can be browsed in the calendar at any time,
/// even if Apple Health data is later removed or unavailable on this device.
/// Defaults on every property keep it CloudKit-ready.
@Model
final class DayRecord {
    /// "2026-11-12" in the device's calendar.
    var dayKey: String = ""
    /// Start of the day.
    var date: Date = Date.now
    var updatedAt: Date = Date.now

    var eatenKcal: Double = 0
    var protein: Double = 0
    var carbohydrates: Double = 0
    var fat: Double = 0
    var mealCount: Int = 0

    var activeEnergy: Double = 0
    var basalEnergy: Double = 0
    var workoutEnergy: Double = 0
    var stepEnergy: Double = 0
    var steps: Double = 0
    var targetKcal: Double = 0
    var budgetKcal: Double = 0

    var workouts: [DayWorkout] = []

    var asleepSeconds: Double = 0
    var sleepScore: Int?
    var weightKg: Double?
    /// Device that created this copy (see `CloudDeduplicator`); "" for records made before iCloud sync.
    var originDevice: String = ""

    init(dayKey: String, date: Date) {
        self.dayKey = dayKey
        self.originDevice = DeviceIdentity.id()
        self.date = date
    }

    /// Everything stored except the timestamps, to tell whether a refresh changed anything.
    struct Content: Equatable {
        var food: [Double]
        var mealCount: Int
        var energy: [Double]
        var workouts: [DayWorkout]
        var asleepSeconds: Double
        var sleepScore: Int?
        var weightKg: Double?
    }

    var content: Content {
        Content(food: [eatenKcal, protein, carbohydrates, fat], mealCount: mealCount,
                energy: [activeEnergy, basalEnergy, workoutEnergy, stepEnergy, steps, targetKcal, budgetKcal],
                workouts: workouts, asleepSeconds: asleepSeconds, sleepScore: sleepScore, weightKg: weightKg)
    }

    var cardioMinutes: Double { workouts.map(\.cardioMinutes).reduce(0, +) }
    var eaten: Nutrients { Nutrients(kilocalories: eatenKcal, protein: protein, carbohydrates: carbohydrates, fat: fat) }

    /// Burned = active (never below workouts + walking) + resting.
    var burnedKcal: Double { max(activeEnergy, workoutEnergy + stepEnergy) + basalEnergy }
    var netKcal: Double { eatenKcal - burnedKcal }
    var hasFood: Bool { mealCount > 0 }
    var hasAnything: Bool { hasFood || !workouts.isEmpty || steps > 0 || asleepSeconds > 0 || weightKg != nil }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
