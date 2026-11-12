import Foundation
import NutriCore
import Synchronization

/// In-memory `HealthDataProviding` for previews, unit tests, the Simulator demo mode,
/// and devices without Apple Health.
final class MockHealthService: HealthDataProviding {
    struct State {
        var authorized = false
        var activity: [Date: ActivitySummary] = [:]
        var workouts: [WorkoutSummary] = []
        var bodyMass: Double?
        var meals: [UUID: MealSample] = [:]
        var sleep: [SleepSample] = []
        var body: [BodySample] = []
        var profile = HealthProfile()
    }

    let isAvailable: Bool
    private let calendar: Calendar
    private let state: Mutex<State>

    init(isAvailable: Bool = true, state: State = State(), calendar: Calendar = .current) {
        self.isAvailable = isAvailable
        self.calendar = calendar
        self.state = Mutex(state)
    }

    /// A few weeks of plausible, made-up data ending today.
    static func sample(now: Date = .now, calendar: Calendar = .current) -> MockHealthService {
        var state = State(authorized: true, bodyMass: 84.6)
        state.profile = HealthProfile(sex: .male, birthDate: calendar.date(byAdding: .year, value: -30, to: now), heightCm: 183)
        let today = calendar.startOfDay(for: now)
        let steps: [Double] = [6_420, 11_380, 8_950, 4_210, 12_760, 9_340, 7_815]
        let active: [Double] = [310, 620, 455, 190, 705, 480, 385]
        let basal: [Double] = [1_840, 1_852, 1_848, 1_839, 1_861, 1_850, 1_220]
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let i = 6 - offset % 7
            state.activity[day] = ActivitySummary(steps: steps[i], activeEnergy: active[i], basalEnergy: basal[i])
        }
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        state.workouts = [
            WorkoutSummary(id: UUID(), name: "Walking", symbolName: "figure.walk", start: at(0, 7, 5), end: at(0, 7, 35), energyBurned: 142, sourceName: "Apple Watch", isCardio: true),
            WorkoutSummary(id: UUID(), name: "Strength training", symbolName: "figure.strengthtraining.traditional", start: at(-1, 18, 30), end: at(-1, 19, 20), energyBurned: 205, sourceName: "NutriLens"),
            WorkoutSummary(id: UUID(), name: "Walking", symbolName: "figure.walk", start: at(-2, 17, 45), end: at(-2, 18, 25), energyBurned: 180, sourceName: "Apple Watch", isCardio: true),
            WorkoutSummary(id: UUID(), name: "Yoga", symbolName: "figure.yoga", start: at(-2, 18, 30), end: at(-2, 18, 42), energyBurned: 38, sourceName: "NutriLens"),
            WorkoutSummary(id: UUID(), name: "Strength training", symbolName: "figure.strengthtraining.traditional", start: at(-3, 18, 0), end: at(-3, 18, 55), energyBurned: 221, sourceName: "NutriLens"),
            WorkoutSummary(id: UUID(), name: "Walking", symbolName: "figure.walk", start: at(-4, 12, 10), end: at(-4, 12, 55), energyBurned: 176, sourceName: "iPhone", isCardio: true),
        ].filter { $0.start <= now }

        // Sleep: two weeks of nights, Apple Watch-style stages.
        var generator = SeededGenerator(seed: 7)
        for night in 0..<14 {
            let bed = at(-night - 1, 23, Int.random(in: 0...45, using: &generator))
            let hours = [7.2, 6.4, 7.8, 8.1, 5.6, 7.0, 7.5][night % 7]
            // Nothing from the future: in the early hours, last night isn't over yet.
            guard bed.addingTimeInterval(hours * 3600 + 20 * 60) <= now else { continue }
            var t = bed.addingTimeInterval(15 * 60)
            state.sleep.append(SleepSample(start: bed, end: bed.addingTimeInterval(hours * 3600 + 20 * 60), stage: .inBed))
            let pattern: [(SleepStage, Double)] = [(.core, 0.22), (.deep, 0.12), (.core, 0.16), (.rem, 0.12), (.awake, 0.02), (.core, 0.18), (.rem, 0.12), (.deep, 0.06)]
            for (stage, share) in pattern {
                let end = t.addingTimeInterval(hours * 3600 * share)
                state.sleep.append(SleepSample(start: t, end: end, stage: stage))
                t = end
            }
        }


        // Weight readings: about three per week, gently trending down.
        for day in stride(from: 56, through: 0, by: -2) {
            let kg = 84.6 + Double(day) * 0.035 + Double.random(in: -0.35...0.35, using: &generator)
            state.body.append(BodySample(id: UUID(), date: at(-day, 7, 10), values: [.weight: (kg * 10).rounded() / 10], sourceName: "NutriLens"))
        }
        return MockHealthService(state: state, calendar: calendar)
    }

    /// Read-only access to the stored state, for tests.
    var snapshot: State { state.withLock { $0 } }

    func shouldRequestAuthorization() async -> Bool {
        isAvailable && !state.withLock { $0.authorized }
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        state.withLock { $0.authorized = true }
    }

    func activity(for days: [Date]) async throws -> [Date: ActivitySummary] {
        let stored = state.withLock { $0.activity }
        var result: [Date: ActivitySummary] = [:]
        for day in days.map(calendar.startOfDay(for:)) {
            result[day] = stored[day] ?? .zero
        }
        return result
    }

    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSummary] {
        state.withLock { $0.workouts }
            .filter { $0.start >= start && $0.start < end }
            .sorted { $0.start > $1.start }
    }

    func nutriLensWorkouts(from start: Date, to end: Date) async throws -> [WorkoutSummary] {
        try await workouts(from: start, to: end).filter { $0.nutriLensID != nil }
    }

    /// Spreads each stored day's steps evenly over the day.
    func stepCount(from start: Date, to end: Date) async throws -> Double {
        guard end > start else { return 0 }
        let stored = state.withLock { $0.activity }
        var total = 0.0
        var day = calendar.startOfDay(for: start)
        while day < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let overlap = min(end, next).timeIntervalSince(max(start, day))
            if overlap > 0 { total += (stored[day]?.steps ?? 0) * overlap / next.timeIntervalSince(day) }
            day = next
        }
        return total
    }

    func latestBodyMass() async throws -> Double? {
        state.withLock { s in s.body.last(where: { $0.values[.weight] != nil })?.values[.weight] ?? s.bodyMass }
    }

    func saveMeal(_ meal: MealSample) async throws -> UUID {
        guard isAvailable else { throw HealthDataError.unavailable }
        let id = UUID()
        state.withLock { $0.meals[id] = meal }
        return id
    }

    func deleteMeal(id: UUID) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        let removed = state.withLock { $0.meals.removeValue(forKey: id) }
        if removed == nil { throw HealthDataError.notFound }
    }

    func mealRecords(from start: Date, to end: Date) async throws -> [MealRecord] {
        state.withLock { $0.meals }.compactMap { id, meal in
            guard let nlID = meal.nutriLensID, meal.date >= start, meal.date < end else { return nil }
            return MealRecord(healthKitID: id, nutriLensID: nlID, payload: meal.payload, name: meal.name, date: meal.date, nutrients: meal.nutrients)
        }.sorted { $0.date < $1.date }
    }

    func saveWorkout(kind: ActivityKind, start: Date, end: Date, kilocalories: Double, nutriLensID: UUID?, payload: String?) async throws -> UUID {
        guard isAvailable else { throw HealthDataError.unavailable }
        let workout = WorkoutSummary(
            id: UUID(), name: kind.displayName, symbolName: kind.symbolName, start: start, end: end,
            energyBurned: kilocalories, sourceName: "NutriLens", nutriLensID: nutriLensID, payload: payload,
            isCardio: [.walking, .running, .cycling, .hiking, .swimming, .hiit, .dance].contains(kind)
        )
        let day = calendar.startOfDay(for: start)
        state.withLock {
            $0.workouts.append(workout)
            $0.activity[day, default: .zero].activeEnergy += kilocalories
        }
        return workout.id
    }

    func deleteWorkout(id: UUID) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        let removed = state.withLock { s in
            let before = s.workouts.count
            s.workouts.removeAll { $0.id == id }
            return before != s.workouts.count
        }
        if !removed { throw HealthDataError.notFound }
    }

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        state.withLock { $0.sleep }.filter { $0.end > start && $0.start < end }
    }

    func saveSleep(start: Date, end: Date) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        state.withLock {
            $0.sleep.append(SleepSample(start: start, end: end, stage: .inBed))
            $0.sleep.append(SleepSample(start: start, end: end, stage: .asleepUnspecified))
        }
    }

    func bodySamples(from start: Date, to end: Date) async throws -> [BodySample] {
        state.withLock { $0.body }.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
    }

    func saveBody(_ reading: BodyReading, date: Date, nutriLensID: UUID, payload: String?) async throws -> UUID {
        guard isAvailable else { throw HealthDataError.unavailable }
        let supported: Set<BodyMetric> = [.weight, .bodyFat, .bmi, .leanBodyMass, .waist]
        let values = reading.values.filter { supported.contains($0.key) }
        guard !values.isEmpty else { throw HealthDataError.notFound }
        let sample = BodySample(id: UUID(), date: date, values: values, sourceName: "NutriLens", nutriLensID: nutriLensID, payload: payload)
        state.withLock { $0.body.append(sample) }
        return sample.id
    }

    func healthProfile() async -> HealthProfile {
        state.withLock { $0.profile }
    }

    func deleteBody(nutriLensID: UUID) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        state.withLock { $0.body.removeAll { $0.nutriLensID == nutriLensID } }
    }
}
