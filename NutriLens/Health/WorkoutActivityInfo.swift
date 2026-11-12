import HealthKit
import NutriCore

/// Display name and SF Symbol for HealthKit workout activity types.
struct WorkoutActivityInfo {
    let name: String
    let symbolName: String

    init(_ type: HKWorkoutActivityType) {
        switch type {
        case .walking: (name, symbolName) = ("Walking", "figure.walk")
        case .running: (name, symbolName) = ("Running", "figure.run")
        case .cycling: (name, symbolName) = ("Cycling", "figure.outdoor.cycle")
        case .swimming: (name, symbolName) = ("Swimming", "figure.pool.swim")
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            (name, symbolName) = ("Strength training", "figure.strengthtraining.traditional")
        case .yoga: (name, symbolName) = ("Yoga", "figure.yoga")
        case .highIntensityIntervalTraining: (name, symbolName) = ("HIIT", "figure.highintensity.intervaltraining")
        case .hiking: (name, symbolName) = ("Hiking", "figure.hiking")
        case .socialDance, .cardioDance: (name, symbolName) = ("Dance", "figure.dance")
        case .elliptical: (name, symbolName) = ("Elliptical", "figure.elliptical")
        case .rowing: (name, symbolName) = ("Rowing", "figure.rower")
        case .stairClimbing, .stairs: (name, symbolName) = ("Stairs", "figure.stairs")
        case .pilates: (name, symbolName) = ("Pilates", "figure.pilates")
        case .coreTraining: (name, symbolName) = ("Core training", "figure.core.training")
        case .badminton: (name, symbolName) = ("Badminton", "figure.badminton")
        case .cricket: (name, symbolName) = ("Cricket", "figure.cricket")
        case .tennis: (name, symbolName) = ("Tennis", "figure.tennis")
        case .soccer: (name, symbolName) = ("Football", "figure.soccer")
        case .basketball: (name, symbolName) = ("Basketball", "figure.basketball")
        case .mixedCardio: (name, symbolName) = ("Mixed cardio", "figure.mixed.cardio")
        default: (name, symbolName) = ("Workout", "figure.mixed.cardio")
        }
    }

    /// Aerobic activities that count toward the plan's weekly cardio minutes.
    static func isCardio(_ type: HKWorkoutActivityType) -> Bool {
        switch type {
        case .walking, .running, .hiking, .cycling, .elliptical, .stairClimbing, .stairs, .swimming,
             .mixedCardio, .rowing, .cardioDance, .socialDance, .highIntensityIntervalTraining: true
        default: false
        }
    }

    static func healthKitType(for kind: ActivityKind) -> HKWorkoutActivityType {
        switch kind {
        case .walking: .walking
        case .running: .running
        case .cycling: .cycling
        case .swimming: .swimming
        case .strength: .traditionalStrengthTraining
        case .yoga: .yoga
        case .hiit: .highIntensityIntervalTraining
        case .hiking: .hiking
        case .dance: .cardioDance
        case .other: .other
        }
    }
}
