import Foundation

/// How much exercise energy is added back to the day's intake budget.
public struct ExerciseCreditPolicy: Codable, Equatable, Sendable {
    public enum Source: String, Codable, CaseIterable, Sendable {
        /// The budget is the fixed target.
        case none
        /// Energy burned in recorded workouts (logged sessions, Apple Watch workouts, …).
        case workouts
        /// Workouts plus walking outside them, estimated from your steps.
        case workoutsAndSteps
        /// All active energy Apple Health reports, including everyday movement.
        case allActiveEnergy

        public var displayName: String {
            switch self {
            case .none: "Don't add exercise"
            case .workouts: "Workouts only"
            case .workoutsAndSteps: "Workouts + steps"
            case .allActiveEnergy: "All active energy"
            }
        }
    }

    public var source: Source
    /// Share of that energy to add, 0...1. Fitness trackers tend to overestimate burn, so 50 % is a common choice.
    public var fraction: Double

    public init(source: Source = .none, fraction: Double = 0.5) {
        self.source = source
        self.fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
    }

    public static let none = ExerciseCreditPolicy(source: .none, fraction: 0)

    /// Kilocalories added to the target under this policy.
    public func credit(workoutEnergy: Double, stepEnergy: Double = 0, activeEnergy: Double) -> Double {
        let workouts = max(0, workoutEnergy), steps = max(0, stepEnergy)
        switch source {
        case .none: return 0
        case .workouts: return workouts * fraction
        case .workoutsAndSteps: return (workouts + steps) * fraction
        // Workouts and walking are part of active energy; never credit less than they would.
        case .allActiveEnergy: return max(max(0, activeEnergy), workouts + steps) * fraction
        }
    }
}

/// A day's energy balance: what was eaten against what was burned and the user's intake target.
///
/// * `burned` = active energy + resting (basal) energy, as Apple Health reports them. Active energy is
///   never taken as less than logged workouts plus walking estimated from steps, which matters when only
///   an iPhone (no Apple Watch) records your day.
/// * `net` = eaten − burned. Negative means a calorie deficit for the day.
/// * `exerciseCredit` = the part of today's exercise added back to the target, per the policy.
/// * `budget` = target + exercise credit.
/// * `remaining` = budget − eaten. Negative means the target was exceeded.
public struct CalorieBalance: Equatable, Sendable {
    public var eaten: Double
    public var activeEnergy: Double
    public var basalEnergy: Double
    /// Energy from today's workouts (a subset of active energy when both come from Apple Health).
    public var workoutEnergy: Double
    /// Walking energy estimated from steps taken outside workouts (see `StepEnergy`).
    public var stepEnergy: Double
    public var target: Double
    public var policy: ExerciseCreditPolicy

    public init(
        eaten: Double,
        activeEnergy: Double,
        basalEnergy: Double,
        workoutEnergy: Double = 0,
        stepEnergy: Double = 0,
        target: Double,
        policy: ExerciseCreditPolicy = .none
    ) {
        self.eaten = max(0, eaten)
        self.activeEnergy = max(0, activeEnergy)
        self.basalEnergy = max(0, basalEnergy)
        self.workoutEnergy = max(0, workoutEnergy)
        self.stepEnergy = max(0, stepEnergy)
        self.target = max(0, target)
        self.policy = policy
    }

    /// Active energy, but never less than recorded workouts plus walking from steps
    /// (iPhone-only days, or a workout not yet reflected in Health's total).
    public var effectiveActiveEnergy: Double { max(activeEnergy, workoutEnergy + stepEnergy) }

    public var burned: Double { effectiveActiveEnergy + basalEnergy }

    public var net: Double { eaten - burned }

    public var exerciseCredit: Double {
        policy.credit(workoutEnergy: workoutEnergy, stepEnergy: stepEnergy, activeEnergy: activeEnergy)
    }

    public var budget: Double { target + exerciseCredit }

    public var remaining: Double { budget - eaten }

    public var isOverBudget: Bool { eaten > budget }

    /// Fraction of the budget eaten, 0 when there is no budget. Not clamped, so 1.2 means 20 % over.
    public var progress: Double {
        budget > 0 ? eaten / budget : 0
    }

    /// Whether the day is a deficit (burned more than eaten).
    public var isDeficit: Bool { net < 0 }
}

/// Simple estimates used when Apple Health has no data of its own.
public enum EnergyEstimator {
    /// **Active** kilocalories for an activity: (MET − 1) × body mass (kg) × duration (hours).
    ///
    /// One MET is the resting rate, which Apple Health already counts as resting (basal) energy, so it's
    /// subtracted to avoid counting it twice. This matches what Apple Health calls active energy.
    public static func activityKilocalories(met: Double, bodyMassKg: Double, minutes: Double) -> Double {
        guard met > 1, bodyMassKg > 0, minutes > 0 else { return 0 }
        return (met - 1) * bodyMassKg * minutes / 60
    }

    /// Body mass assumed when Apple Health has none.
    public static let defaultBodyMassKg = 70.0
}

/// Walking energy from a step count.
public enum StepEnergy {
    /// Step length the plan uses for planning (0.75 m). Calibrate: measured distance ÷ steps.
    public static let defaultStepLengthMeters = 0.75
    /// Net energy cost of walking at normal speeds, above resting: about 0.5 kcal per kg per km.
    public static let netKcalPerKgPerKm = 0.5

    public static func distanceKm(steps: Double, stepLengthMeters: Double = defaultStepLengthMeters) -> Double {
        guard steps > 0, stepLengthMeters > 0 else { return 0 }
        return steps * stepLengthMeters / 1_000
    }

    /// Active kilocalories for walking `steps`.
    public static func kilocalories(steps: Double, bodyMassKg: Double, stepLengthMeters: Double = defaultStepLengthMeters) -> Double {
        guard bodyMassKg > 0 else { return 0 }
        return distanceKm(steps: steps, stepLengthMeters: stepLengthMeters) * bodyMassKg * netKcalPerKgPerKm
    }

    /// The plan's step guidance: start from your 7-day average and add about 500 steps a day every
    /// 1–2 weeks, up to an optional 6,000–9,000 range. Rounded to the nearest 500.
    public static func suggestedGoal(sevenDayAverage: Double) -> Int {
        guard sevenDayAverage > 0 else { return 6_000 }
        let next = (sevenDayAverage / 500).rounded() * 500 + 500
        return Int(min(max(next, 3_000), 9_000))
    }
}

/// Activities offered for manual workout entry, with typical MET values from the
/// Compendium of Physical Activities.
public enum ActivityKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case walking, running, cycling, swimming, strength, yoga, hiit, hiking, dance, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .strength: "Strength training"
        case .yoga: "Yoga"
        case .hiit: "HIIT"
        case .hiking: "Hiking"
        case .dance: "Dance"
        case .other: "Other"
        }
    }

    /// Moderate-intensity MET value.
    public var met: Double {
        switch self {
        case .walking: 3.5
        case .running: 9.8
        case .cycling: 7.5
        case .swimming: 7.0
        case .strength: 3.5
        case .yoga: 2.5
        case .hiit: 8.0
        case .hiking: 6.0
        case .dance: 5.0
        case .other: 4.0
        }
    }

    public var symbolName: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .strength: "figure.strengthtraining.traditional"
        case .yoga: "figure.yoga"
        case .hiit: "figure.highintensity.intervaltraining"
        case .hiking: "figure.hiking"
        case .dance: "figure.dance"
        case .other: "figure.mixed.cardio"
        }
    }
}
