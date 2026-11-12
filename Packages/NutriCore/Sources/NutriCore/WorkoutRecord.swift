import Foundation

// Types shared by the iPhone app and the Watch app, so both write the same Apple Health metadata.

/// Metadata keys NutriLens adds to what it saves in Apple Health.
public enum HealthSyncKey {
    /// The NutriLens record's UUID string.
    public static let recordID = "NLRecordID"
    /// JSON with the fields Health can't hold itself (meal type, logged sets, all 22 scale values…).
    public static let payload = "NLPayload"
}

/// Kinds of logged training.
public enum WorkoutLogKind: String, Codable, CaseIterable, Sendable {
    case strength, walk, walkJog, yoga, other

    public var displayName: String {
        switch self {
        case .strength: "Strength"
        case .walk: "Indoor walk"
        case .walkJog: "Walk/jog intervals"
        case .yoga: "Yoga"
        case .other: "Workout"
        }
    }

    public var symbolName: String {
        switch self {
        case .strength: "dumbbell.fill"
        case .walk: "figure.walk"
        case .walkJog: "figure.run"
        case .yoga: "figure.yoga"
        case .other: "figure.mixed.cardio"
        }
    }

    public var activity: ActivityKind {
        switch self {
        case .strength: .strength
        case .walk: .walking
        case .walkJog: .running
        case .yoga: .yoga
        case .other: .other
        }
    }
}

/// Sets logged for one exercise in a session.
public struct LoggedExercise: Codable, Hashable, Identifiable, Sendable {
    public var exerciseID: String
    public var sets: [LoggedSet]
    public var skipped: Bool = false

    public var id: String { exerciseID }

    public init(exerciseID: String, sets: [LoggedSet], skipped: Bool = false) {
        self.exerciseID = exerciseID
        self.sets = sets
        self.skipped = skipped
    }
}

/// A workout's fields Apple Health can't store natively, carried as JSON in the workout's metadata
/// (`HealthSyncKey.payload`) so another device can rebuild the full log.
public struct WorkoutPayload: Codable, Equatable, Sendable {
    public var kind: String
    public var title: String
    public var planWeek: Int?
    public var planWeekday: Int?
    public var cardioMinutes: Double
    public var readiness: String
    public var energyRating: Int
    public var notes: String
    public var exercises: [LoggedExercise]
    public var updatedAt: Date
    /// Added later, so optional for payloads written by earlier versions.
    public var steps: Int? = nil
    public var distanceKm: Double? = nil

    public init(kind: String, title: String, planWeek: Int?, planWeekday: Int?, cardioMinutes: Double, readiness: String,
                energyRating: Int, notes: String, exercises: [LoggedExercise], updatedAt: Date, steps: Int? = nil, distanceKm: Double? = nil) {
        self.kind = kind
        self.title = title
        self.planWeek = planWeek
        self.planWeekday = planWeekday
        self.cardioMinutes = cardioMinutes
        self.readiness = readiness
        self.energyRating = energyRating
        self.notes = notes
        self.exercises = exercises
        self.updatedAt = updatedAt
        self.steps = steps
        self.distanceKm = distanceKm
    }
}

/// JSON for Health metadata payloads (ISO 8601 dates, sorted keys).
public enum PayloadCoder {
    public static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from string: String?) -> T? {
        guard let string else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: Data(string.utf8))
    }
}

extension PlanEngine {
    /// Readiness changes the session: the tired version uses at most 2 sets and drops optional work.
    public static func adjusted(_ session: [(planned: PlannedExercise, prescription: Prescription)], readiness: Readiness)
        -> [(planned: PlannedExercise, prescription: Prescription)] {
        switch readiness {
        case .ready: session
        case .unwell: []
        case .tired:
            session.filter { !$0.planned.optional }.map { item in
                var rx = item.prescription
                rx.sets = min(rx.sets, 2)
                return (item.planned, rx)
            }
        }
    }

    /// The numbers to start a set with: the last set logged (this session, else last time), otherwise the middle
    /// of the range, 5 kg for loaded exercises and the phase's reps in reserve.
    public static func prefill(usesLoad: Bool, prescription rx: Prescription, last: LoggedSet?, week: Int) -> LoggedSet {
        LoggedSet(
            reps: last?.reps ?? (rx.seconds ? rx.low : (rx.low + rx.high) / 2),
            loadKg: usesLoad ? (last?.loadKg ?? 5) : 0,
            repsInReserve: last?.repsInReserve ?? (PlanPhase.forWeek(week) == .build ? 2 : 3)
        )
    }

    /// Moderate minutes a walk/jog session counts: the interval block (warm-up and cool-down are extra).
    public static func intervalCardioMinutes(stage: JogStage, elapsedMinutes: Double) -> Double {
        let block = Double(stage.repeats * (stage.jogSeconds + stage.walkSeconds)) / 60
        return min(elapsedMinutes, block)
    }
}
