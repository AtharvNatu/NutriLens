import Foundation
import NutriCore

/// Energy and steps for one day, from Apple Health.
struct ActivitySummary: Equatable, Sendable {
    var steps: Double
    /// Active energy burned, kcal.
    var activeEnergy: Double
    /// Resting (basal) energy burned, kcal.
    var basalEnergy: Double

    static let zero = ActivitySummary(steps: 0, activeEnergy: 0, basalEnergy: 0)

    var totalEnergy: Double { activeEnergy + basalEnergy }
}

/// A workout read from Apple Health.
struct WorkoutSummary: Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var symbolName: String
    var start: Date
    var end: Date
    /// Active energy burned during the workout, kcal, if recorded.
    var energyBurned: Double?
    var sourceName: String
    /// Set when NutriLens wrote this workout.
    var nutriLensID: UUID? = nil
    var payload: String? = nil
    /// Walking, running, hiking and similar, which count toward the cardio target.
    var isCardio: Bool = false

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A meal to write to Apple Health.
struct MealSample: Sendable, Equatable {
    var name: String
    var date: Date
    var nutrients: Nutrients
    var nutriLensID: UUID? = nil
    var payload: String? = nil
}

/// A meal NutriLens wrote to Health (possibly on another device).
struct MealRecord: Sendable, Equatable {
    var healthKitID: UUID
    var nutriLensID: UUID
    var payload: String?
    var name: String
    var date: Date
    var nutrients: Nutrients
}

/// Body measurements recorded at one moment by one source (scale app, NutriLens, …).
struct BodySample: Identifiable, Sendable, Equatable {
    var id: UUID
    var date: Date
    var values: [BodyMetric: Double]
    var sourceName: String
    var nutriLensID: UUID? = nil
    var payload: String? = nil
}

enum HealthDataError: LocalizedError {
    case unavailable
    case notFound

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health isn't available on this device."
        case .notFound: "The item couldn't be found in Apple Health."
        }
    }
}

/// Everything the app needs from Apple Health. `HealthKitService` talks to HealthKit;
/// `MockHealthService` is used in previews, tests and the demo mode.
protocol HealthDataProviding: AnyObject, Sendable {
    /// Whether Health data can be read and written at all on this device.
    var isAvailable: Bool { get }

    /// Whether the permission sheet still needs to be shown (new data types or first launch).
    func shouldRequestAuthorization() async -> Bool
    func requestAuthorization() async throws

    /// Steps, active and basal energy for each start-of-day in `days`.
    func activity(for days: [Date]) async throws -> [Date: ActivitySummary]
    /// Workouts that started in `[start, end)`, newest first (at most 200).
    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSummary]
    /// Every workout NutriLens saved (on any of your devices) that started in `[start, end)`. No limit,
    /// because sync treats a missing workout as deleted.
    func nutriLensWorkouts(from start: Date, to end: Date) async throws -> [WorkoutSummary]
    /// Steps recorded in `[start, end)` (de-duplicated across iPhone and Apple Watch).
    func stepCount(from start: Date, to end: Date) async throws -> Double
    /// Most recent body mass in kilograms.
    func latestBodyMass() async throws -> Double?

    /// Saves the meal's energy and macros as one food correlation; returns its UUID.
    func saveMeal(_ meal: MealSample) async throws -> UUID
    /// Deletes a meal previously saved with `saveMeal`.
    func deleteMeal(id: UUID) async throws
    /// Meals NutriLens saved (on any of your devices) in `[start, end)`.
    func mealRecords(from start: Date, to end: Date) async throws -> [MealRecord]

    /// Saves a workout with its active energy; returns the workout's UUID.
    func saveWorkout(kind: ActivityKind, start: Date, end: Date, kilocalories: Double, nutriLensID: UUID?, payload: String?) async throws -> UUID
    func deleteWorkout(id: UUID) async throws

    /// Sleep-analysis samples overlapping `[start, end)`, from every source.
    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample]
    /// Records a night entered by hand (in bed and asleep for the same span).
    func saveSleep(start: Date, end: Date) async throws

    /// Body measurements in `[start, end)` from every source, grouped by moment and source.
    func bodySamples(from start: Date, to end: Date) async throws -> [BodySample]
    /// Writes the values Health supports (weight, body fat, BMI, lean mass, waist); returns the weight sample's UUID.
    func saveBody(_ reading: BodyReading, date: Date, nutriLensID: UUID, payload: String?) async throws -> UUID
    /// Deletes every sample NutriLens wrote for this body record.
    func deleteBody(nutriLensID: UUID) async throws

    /// Sex, date of birth and latest height from Apple Health (any may be missing).
    func healthProfile() async -> HealthProfile
}

struct HealthProfile: Sendable, Equatable {
    var sex: Sex?
    var birthDate: Date?
    var heightCm: Double?
}

extension HealthDataProviding {
    func activity(on day: Date, calendar: Calendar = .current) async throws -> ActivitySummary {
        let start = calendar.startOfDay(for: day)
        return try await activity(for: [start])[start] ?? .zero
    }

    func saveWorkout(kind: ActivityKind, start: Date, end: Date, kilocalories: Double) async throws {
        _ = try await saveWorkout(kind: kind, start: start, end: end, kilocalories: kilocalories, nutriLensID: nil, payload: nil)
    }
}
