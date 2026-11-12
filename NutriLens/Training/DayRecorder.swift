import Foundation
import NutriCore
import SwiftData

/// Builds and stores a `DayRecord` per day from your logs and Apple Health, using the same maths as
/// the Today screen, so any past day can be looked up in the calendar later.
@MainActor
enum DayRecorder {
    /// Refreshes the records for `requested` days (future days are skipped) and returns them, oldest first.
    ///
    /// Your NutriLens logs always replace what's stored. Apple Health values only replace stored ones when
    /// Health returns something for that day, so a recorded day keeps its numbers if Health data is later
    /// unavailable (permission turned off, data deleted, a device without that history).
    @discardableResult
    static func record(days requested: [Date], health: any HealthDataProviding, context: ModelContext,
                       defaults: UserDefaults = .standard, calendar: Calendar = .current, now: Date = .now) async -> [DayRecord] {
        let days = Array(Set(requested.map { calendar.startOfDay(for: $0) })).filter { $0 <= now }.sorted()
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return [] }
        let weightFrom = calendar.date(byAdding: .day, value: -35, to: first) ?? first

        // NutriLens logs.
        let meals = (try? context.fetch(FetchDescriptor(predicate: MealEntry.predicate(from: first, to: end)))) ?? []
        let logs = (try? context.fetch(FetchDescriptor(predicate: WorkoutLog.predicate(from: first, to: end)))) ?? []
        let measurements = (try? context.fetch(FetchDescriptor<BodyMeasurement>(
            predicate: #Predicate { $0.date >= weightFrom && $0.date < end }, sortBy: [SortDescriptor(\.date)]))) ?? []

        // Apple Health (each query on its own, so one failure doesn't hide the rest).
        let activity = (try? await health.activity(for: days)) ?? [:]
        let workouts = (try? await health.workouts(from: first, to: end)) ?? []
        var workoutSteps: [UUID: Double] = [:]
        for workout in workouts {
            workoutSteps[workout.id] = (try? await health.stepCount(from: workout.start, to: workout.end)) ?? 0
        }
        let sleepSamples = (try? await health.sleepSamples(from: first.addingTimeInterval(-15 * 86_400), to: end)) ?? []
        let nights = SleepAnalyzer.nights(from: sleepSamples, calendar: calendar)
        let healthWeights = ((try? await health.bodySamples(from: weightFrom, to: end)) ?? [])
            .compactMap { s in s.values[.weight].map { WeightPoint(date: s.date, kg: $0) } }
        let localWeights = measurements.filter { $0.weightKg > 0 && $0.healthKitID == nil }.map { WeightPoint(date: $0.date, kg: $0.weightKg) }
        let weights = WeightTrend.deduplicated(healthWeights + localWeights)
        let latestWeight = weights.isEmpty ? ((try? await health.latestBodyMass()) ?? nil) : nil

        // Settings.
        let target = defaults.object(forKey: SettingsKey.dailyCalorieTarget) as? Double ?? SettingsDefault.dailyCalorieTarget
        let stepLength = defaults.object(forKey: SettingsKey.stepLengthMeters) as? Double ?? SettingsDefault.stepLengthMeters
        let sleepGoal = defaults.object(forKey: SettingsKey.sleepGoalHours) as? Double ?? SettingsDefault.sleepGoalHours
        let policy = defaults.creditPolicy

        // Stored records.
        let keys = days.map { DayRecord.key(for: $0, calendar: calendar) }
        let stored = (try? context.fetch(FetchDescriptor<DayRecord>(predicate: #Predicate { keys.contains($0.dayKey) }))) ?? []
        let byKey = Dictionary(stored.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })

        var result: [DayRecord] = []
        for day in days {
            let key = DayRecord.key(for: day, calendar: calendar)
            let record: DayRecord
            let before: DayRecord.Content?
            if let existing = byKey[key] {
                record = existing
                before = existing.content
            } else {
                record = DayRecord(dayKey: key, date: day)
                context.insert(record)
                before = nil
            }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let inDay: (Date) -> Bool = { $0 >= day && $0 < dayEnd }

            // Food: your log is the source of truth.
            let dayMeals = meals.filter { inDay($0.date) }
            let eaten = dayMeals.map(\.nutrients).total()
            record.eatenKcal = eaten.kilocalories
            record.protein = eaten.protein
            record.carbohydrates = eaten.carbohydrates
            record.fat = eaten.fat
            record.mealCount = dayMeals.count

            // Workouts: Health's, plus sessions logged here that aren't in Health.
            // A session the Watch also recorded counts once, with the Watch's measured energy.
            let dayAll = workouts.filter { inDay($0.start) }
            let dayHealth = Training.countedWorkouts(dayAll)
            let localOnly = Training.uncountedLogs(logs.filter { inDay($0.start) }, workouts: dayAll)
            let everything = DateInterval(start: .distantPast, end: .distantFuture)
            let dayLogs = logs.filter { inDay($0.start) }
            let fromHealth = dayHealth.isEmpty ? record.workouts.filter(\.fromHealth) : Training.displayedWorkouts(dayAll, logs: dayLogs).map { w in
                DayWorkout(name: w.name, symbolName: w.symbolName, start: w.start, minutes: w.duration / 60,
                           kilocalories: w.energyBurned ?? 0, steps: Int(workoutSteps[w.id] ?? 0),
                           cardioMinutes: Training.cardioMinutes(workouts: dayAll.filter { $0.id == w.id || (Training.isFromNutriLens($0) && Training.sameSession($0.start, $0.end, w.start, w.end)) },
                                                         logs: [], in: everything),
                           source: w.sourceName)
            }
            let local = localOnly.map { l in
                DayWorkout(name: l.title.isEmpty ? l.kind.displayName : l.title, symbolName: l.kind.symbolName, start: l.start,
                           minutes: l.duration / 60, kilocalories: l.energyKcal, steps: l.steps, cardioMinutes: l.cardioMinutes,
                           source: "NutriLens", fromHealth: false)
            }
            record.workouts = (fromHealth + local).sorted { $0.start < $1.start }
            record.workoutEnergy = record.workouts.map(\.kilocalories).reduce(0, +)

            // Activity, and walking energy from steps outside workouts.
            if let a = activity[day] {
                if a.steps > 0 { record.steps = a.steps }
                if a.activeEnergy > 0 { record.activeEnergy = a.activeEnergy }
                if a.basalEnergy > 0 { record.basalEnergy = a.basalEnergy }
            }
            let stepsInWorkouts = record.workouts.map { Double($0.steps) }.reduce(0, +)
            let bodyMass = weights.last(where: { $0.date < dayEnd })?.kg ?? latestWeight ?? EnergyEstimator.defaultBodyMassKg
            record.stepEnergy = StepEnergy.kilocalories(steps: max(0, record.steps - stepsInWorkouts),
                                                        bodyMassKg: bodyMass, stepLengthMeters: stepLength)
            let balance = CalorieBalance(eaten: record.eatenKcal, activeEnergy: record.activeEnergy, basalEnergy: record.basalEnergy,
                                         workoutEnergy: record.workoutEnergy, stepEnergy: record.stepEnergy, target: target, policy: policy)
            record.targetKcal = target
            record.budgetKcal = balance.budget

            // Sleep: the night that ended this morning.
            if let night = nights.last(where: { calendar.isDate($0.night, inSameDayAs: day) }) {
                record.asleepSeconds = night.asleep
                record.sleepScore = SleepScore.score(night, previousNights: nights, goalHours: sleepGoal, calendar: calendar)?.total
            }

            // Weight: the day's last weigh-in.
            if let w = weights.last(where: { inDay($0.date) }) { record.weightKg = w.kg }

            // Only a real change counts as an edit (backups merge by this time).
            if before != record.content { record.updatedAt = now }
            result.append(record)
        }
        try? context.save()
        return result
    }

    /// The last `count` days up to `now`.
    static func recentDays(_ count: Int = 7, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Start-of-day dates of the month containing `date`.
    static func days(inMonthOf date: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let count = calendar.range(of: .day, in: .month, for: date)?.count else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }
}
