import Foundation

/// A day's macro targets, set from that day's planned training and your usual steps rather than by hand.
public struct MacroTargets: Equatable, Sendable {
    public var protein: Double
    public var carbohydrates: Double
    public var fat: Double
    /// Energy the three add up to: your calorie target plus the planned day's exercise credit.
    public var kilocalories: Double
    public var dayKind: SessionKind
    /// Planned session energy (strength, walks, yoga) and walking from your usual steps, kcal.
    public var plannedWorkoutEnergy: Double
    public var plannedStepEnergy: Double
    public var expectedSteps: Double

    /// "Strength day", "Walk + yoga day", "Rest day".
    public var dayTitle: String {
        switch dayKind {
        case .strength: "Strength day"
        case .cardioYoga: "Walk + yoga day"
        case .rest: "Rest day"
        }
    }
}

/// Works out each day's protein, carbohydrate and fat targets.
///
/// * **Energy**: your calorie target plus the planned day's exercise, credited the way Today credits exercise
///   (by default half of workouts + walking). Planned exercise is the plan's session for that weekday and week
///   (strength ≈ 45 min plus its easy walk; walk + yoga days the week's walking minutes plus 12 min yoga) and your
///   usual steps (the median of recent days, 10,000 when there's no history).
/// * **Protein**: the plan's 130–160 g a day, from body weight: 2.0 g/kg on strength days, 1.8 on walk + yoga days,
///   1.7 on rest days.
/// * **Fat**: 25 % of energy on strength days, 27 % on walk + yoga days, 30 % on rest days, never under 0.6 g/kg.
/// * **Carbohydrates**: the rest ("grains or potatoes for training fuel"), so they rise on training days.
public enum MacroPlanner {
    public static let defaultSteps = 10_000.0
    /// Strength session length (the plan's 50–65 min includes warm-up and the easy walk, counted separately).
    public static let strengthMinutes = 45.0
    public static let yogaMinutes = 12.0
    /// Steps per minute of brisk walking, to avoid counting a planned walk twice (it's part of your daily steps).
    public static let walkingStepsPerMinute = 100.0

    public static func targets(day: PlanDay?, week: Int?, calorieTarget: Double, policy: ExerciseCreditPolicy,
                               bodyMassKg: Double?, expectedSteps: Double, stepLengthMeters: Double = StepEnergy.defaultStepLengthMeters) -> MacroTargets {
        let kind = day?.kind ?? .rest
        let w = week ?? 1
        let kg = bodyMassKg.flatMap { $0 > 0 ? $0 : nil } ?? EnergyEstimator.defaultBodyMassKg
        let walkMinutes = Double(PlanEngine.cardioMinutes(kind: kind, week: w))
        var workout = EnergyEstimator.activityKilocalories(met: ActivityKind.walking.met, bodyMassKg: kg, minutes: walkMinutes)
        switch kind {
        case .strength: workout += EnergyEstimator.activityKilocalories(met: ActivityKind.strength.met, bodyMassKg: kg, minutes: strengthMinutes)
        case .cardioYoga: workout += EnergyEstimator.activityKilocalories(met: ActivityKind.yoga.met, bodyMassKg: kg, minutes: yogaMinutes)
        case .rest: break
        }
        let steps = max(0, expectedSteps)
        let everydaySteps = max(0, steps - walkMinutes * walkingStepsPerMinute)
        let stepEnergy = StepEnergy.kilocalories(steps: everydaySteps, bodyMassKg: kg, stepLengthMeters: stepLengthMeters)
        let energy = max(0, calorieTarget) + policy.credit(workoutEnergy: workout, stepEnergy: stepEnergy, activeEnergy: workout + stepEnergy)

        let proteinPerKg: Double, fatShare: Double
        switch kind {
        case .strength: (proteinPerKg, fatShare) = (2.0, 0.25)
        case .cardioYoga: (proteinPerKg, fatShare) = (1.8, 0.27)
        case .rest: (proteinPerKg, fatShare) = (1.7, 0.30)
        }
        let protein = roundTo5(min(max(proteinPerKg * kg, 130), 160))
        let fat = max(fatShare * energy / 9, 0.6 * kg).rounded()
        let carbs = max(50, (energy - protein * 4 - fat * 9) / 4).rounded()
        return MacroTargets(protein: protein, carbohydrates: carbs, fat: fat, kilocalories: energy.rounded(), dayKind: kind,
                            plannedWorkoutEnergy: workout.rounded(), plannedStepEnergy: stepEnergy.rounded(), expectedSteps: steps)
    }

    /// Your usual daily steps: the median of recent days with real walking (over 1,000 steps), or 10,000 with
    /// fewer than 3 such days.
    public static func usualSteps(_ recent: [Double]) -> Double {
        let days = recent.filter { $0 > 1_000 }.sorted()
        guard days.count >= 3 else { return defaultSteps }
        let mid = days.count / 2
        let median = days.count.isMultiple(of: 2) ? (days[mid - 1] + days[mid]) / 2 : days[mid]
        return (median / 500).rounded() * 500
    }

    static func roundTo5(_ value: Double) -> Double { (value / 5).rounded() * 5 }
}
