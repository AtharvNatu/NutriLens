import Foundation
import NutriCore
import SwiftData

/// Where a body reading came from.
enum BodyReadingSource: String, Codable {
    case screenshot, manual, appleHealth

    var displayName: String {
        switch self {
        case .screenshot: "Scale screenshot"
        case .manual: "Entered by hand"
        case .appleHealth: "Apple Health"
        }
    }
}

/// One smart-scale reading (up to 22 values) or a manual weight/waist entry.
/// All properties have defaults so the model can sync with CloudKit later.
@Model
final class BodyMeasurement {
    var id: UUID = UUID()
    var date: Date = Date.now
    var updatedAt: Date = Date.now
    var sourceRaw: String = BodyReadingSource.manual.rawValue
    /// `BodyMetric.rawValue` → value in the metric's display unit.
    var values: [String: Double] = [:]
    /// `BodyMetric.rawValue` → the scale app's label ("High", "Healthy", …).
    var statuses: [String: String] = [:]
    /// Copy of the weight for sorting and quick queries (0 if none).
    var weightKg: Double = 0
    var note: String = ""
    /// UUID of the body-mass sample written to Apple Health.
    var healthKitID: UUID?
    /// Device that created this copy (see `CloudDeduplicator`); "" for records made before iCloud sync.
    var originDevice: String = ""

    init(id: UUID = UUID(), date: Date, source: BodyReadingSource, reading: BodyReading, note: String = "") {
        self.id = id
        self.originDevice = DeviceIdentity.id()
        self.date = date
        self.sourceRaw = source.rawValue
        self.note = note
        apply(reading)
    }

    var source: BodyReadingSource { BodyReadingSource(rawValue: sourceRaw) ?? .manual }

    var reading: BodyReading {
        var values: [BodyMetric: Double] = [:]
        for (key, value) in self.values { if let m = BodyMetric(rawValue: key) { values[m] = value } }
        var statuses: [BodyMetric: String] = [:]
        for (key, value) in self.statuses { if let m = BodyMetric(rawValue: key) { statuses[m] = value } }
        return BodyReading(date: date, values: values, statuses: statuses)
    }

    func apply(_ reading: BodyReading) {
        values = Dictionary(uniqueKeysWithValues: reading.values.map { ($0.key.rawValue, $0.value) })
        statuses = Dictionary(uniqueKeysWithValues: reading.statuses.map { ($0.key.rawValue, $0.value) })
        weightKg = reading.values[.weight] ?? 0
        updatedAt = .now
    }

    func value(_ metric: BodyMetric) -> Double? { values[metric.rawValue] }
}

/// A training session recorded in the app (strength sets, walks, intervals, yoga).
@Model
final class WorkoutLog {
    var id: UUID = UUID()
    var start: Date = Date.now
    var end: Date = Date.now
    var updatedAt: Date = Date.now
    var kindRaw: String = WorkoutLogKind.strength.rawValue
    var title: String = ""
    /// Plan week (1…12+) and `Calendar` weekday, when the session followed the plan.
    var planWeek: Int?
    var planWeekday: Int?
    var energyKcal: Double = 0
    /// Moderate cardio minutes this session counts toward the weekly target.
    var cardioMinutes: Double = 0
    /// Steps during the session (iPhone pedometer, or Apple Health afterwards).
    var steps: Int = 0
    /// Distance walked, from steps × your step length, in km.
    var distanceKm: Double = 0
    var readinessRaw: String = Readiness.ready.rawValue
    /// 1–5, how you felt (the plan's energy score).
    var energyRating: Int = 0
    var notes: String = ""
    var exercises: [LoggedExercise] = []
    /// UUID of the HKWorkout saved to Apple Health.
    var healthKitID: UUID?
    /// Device that created this copy (see `CloudDeduplicator`); "" for records made before iCloud sync.
    var originDevice: String = ""

    init(id: UUID = UUID(), kind: WorkoutLogKind, title: String, start: Date, end: Date) {
        self.id = id
        self.originDevice = DeviceIdentity.id()
        self.kindRaw = kind.rawValue
        self.title = title
        self.start = start
        self.end = end
    }

    var kind: WorkoutLogKind { WorkoutLogKind(rawValue: kindRaw) ?? .other }
    var readiness: Readiness { Readiness(rawValue: readinessRaw) ?? .ready }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    var completedSets: Int { exercises.flatMap(\.sets).count }

    static func predicate(from start: Date, to end: Date) -> Predicate<WorkoutLog> {
        #Predicate<WorkoutLog> { $0.start >= start && $0.start < end }
    }
}

/// Remembers deletions so a backup file imported on another device removes the same records.
@Model
final class DeletedRecord {
    var id: UUID = UUID()
    var recordType: String = ""
    var deletedAt: Date = Date.now
    /// Device that created this copy (see `CloudDeduplicator`); "" for records made before iCloud sync.
    var originDevice: String = ""

    init(id: UUID, recordType: String) {
        self.id = id
        self.originDevice = DeviceIdentity.id()
        self.recordType = recordType
    }
}

enum SyncRecordType {
    static let meal = "meal"
    static let body = "body"
    static let workout = "workout"
    static let customFood = "customFood"
}

/// All SwiftData models, for the container.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [MealEntry.self, BodyMeasurement.self, WorkoutLog.self, CustomFood.self, DeletedRecord.self, DayRecord.self]
}
