import Foundation

/// What the iPhone sends the Watch (WatchConnectivity application context): the plan's start, your settings,
/// today's readiness suggestion and recent sets, so the Watch can run today's session on its own.
public struct WatchContext: Codable, Equatable, Sendable {
    /// Bumped when the format changes in a way an older Watch app can't read.
    public static let version = 1

    public var version: Int = WatchContext.version
    public var sentAt: Date
    public var planStart: Date
    /// Sleep-based suggestion for today (the Watch lets you change it).
    public var suggestedReadiness: Readiness
    /// The day `suggestedReadiness` applies to.
    public var readinessDay: Date
    public var stepLengthMeters: Double
    /// Recent sets, keyed by `historyKey`: up to the last two sessions per exercise, oldest first.
    public var history: [String: [[LoggedSet]]]

    public init(sentAt: Date, planStart: Date, suggestedReadiness: Readiness, readinessDay: Date, stepLengthMeters: Double,
                history: [String: [[LoggedSet]]]) {
        self.sentAt = sentAt
        self.planStart = planStart
        self.suggestedReadiness = suggestedReadiness
        self.readinessDay = readinessDay
        self.stepLengthMeters = stepLengthMeters
        self.history = history
    }

    /// Key for one exercise on one plan weekday (0 = any day).
    public static func historyKey(_ exerciseID: String, weekday: Int) -> String { "\(weekday)|\(exerciseID)" }

    /// One past session of an exercise, as the iPhone has it logged.
    public struct Session: Sendable {
        public var start: Date
        public var weekday: Int?
        public var exercises: [LoggedExercise]

        public init(start: Date, weekday: Int?, exercises: [LoggedExercise]) {
            self.start = start
            self.weekday = weekday
            self.exercises = exercises
        }
    }

    /// The last two sessions of each exercise, both per plan weekday and for any day. Mirrors the iPhone's
    /// `Training.history`: the main lift's history is kept apart from lighter practice on another day.
    public static func history(from sessions: [Session], keep: Int = 2) -> [String: [[LoggedSet]]] {
        var result: [String: [[LoggedSet]]] = [:]
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            for exercise in session.exercises where !exercise.skipped && !exercise.sets.isEmpty {
                var keys = [historyKey(exercise.exerciseID, weekday: 0)]
                if let day = session.weekday { keys.append(historyKey(exercise.exerciseID, weekday: day)) }
                for key in keys {
                    result[key, default: []].append(exercise.sets)
                    if result[key, default: []].count > keep { result[key]?.removeFirst() }
                }
            }
        }
        return result
    }

    /// Previous sessions' sets for an exercise, oldest first: the same plan day's when there are any, else any day's.
    public func history(of exerciseID: String, weekday: Int) -> [[LoggedSet]] {
        if let sameDay = history[Self.historyKey(exerciseID, weekday: weekday)], !sameDay.isEmpty { return sameDay }
        return history[Self.historyKey(exerciseID, weekday: 0)] ?? []
    }

    /// Readiness to suggest on `date`: the iPhone's, if it's for that day.
    public func readiness(on date: Date, calendar: Calendar = .current) -> Readiness {
        calendar.isDate(readinessDay, inSameDayAs: date) ? suggestedReadiness : .ready
    }
}

/// A session finished on the Watch, sent to the iPhone (WatchConnectivity user info). The Watch has already saved
/// it to Apple Health (`healthKitID`), so the iPhone only stores the log and never saves a second workout.
public struct WatchWorkoutRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var healthKitID: UUID?
    public var start: Date
    public var end: Date
    /// Active energy the Watch measured, kcal.
    public var energyKcal: Double
    public var payload: WorkoutPayload

    public init(id: UUID, healthKitID: UUID?, start: Date, end: Date, energyKcal: Double, payload: WorkoutPayload) {
        self.id = id
        self.healthKitID = healthKitID
        self.start = start
        self.end = end
        self.energyKcal = energyKcal
        self.payload = payload
    }
}

/// Packing for WatchConnectivity dictionaries (property-list values only, so each message travels as JSON data).
public enum WatchMessage {
    public static let contextKey = "nutrilens.context"
    public static let workoutKey = "nutrilens.workout"

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ context: WatchContext) throws -> [String: Data] {
        [contextKey: try encoder.encode(context)]
    }

    public static func encode(_ record: WatchWorkoutRecord) throws -> [String: Data] {
        [workoutKey: try encoder.encode(record)]
    }

    /// nil for messages without a context, or from a newer, incompatible iPhone app.
    public static func context(from data: Data?) -> WatchContext? {
        guard let data, let context = try? decoder.decode(WatchContext.self, from: data),
              context.version <= WatchContext.version else { return nil }
        return context
    }

    public static func workout(from data: Data?) -> WatchWorkoutRecord? {
        guard let data else { return nil }
        return try? decoder.decode(WatchWorkoutRecord.self, from: data)
    }
}

extension WorkoutPayload {
    /// The payload for a session recorded on the Watch: the same fields the iPhone writes for its own logs.
    /// - Parameters:
    ///   - activeSeconds: time without pauses.
    ///   - distanceMeters: measured by the Watch; when 0, steps × step length is used, as on the iPhone.
    public static func watchSession(kind: WorkoutLogKind, title: String, end: Date, activeSeconds: TimeInterval,
                                    planWeek: Int?, planWeekday: Int?, readiness: Readiness, energyRating: Int,
                                    exercises: [LoggedExercise] = [], jogStage: JogStage? = nil,
                                    steps: Double = 0, distanceMeters: Double = 0, stepLengthMeters: Double) -> WorkoutPayload {
        let minutes = activeSeconds / 60
        let cardio: Double = switch kind {
        case .walk: minutes
        case .walkJog: jogStage.map { PlanEngine.intervalCardioMinutes(stage: $0, elapsedMinutes: minutes) } ?? minutes
        default: 0
        }
        let km = distanceMeters > 0 ? distanceMeters / 1000 : StepEnergy.distanceKm(steps: steps, stepLengthMeters: stepLengthMeters)
        return WorkoutPayload(kind: kind.rawValue, title: title, planWeek: planWeek, planWeekday: planWeekday, cardioMinutes: cardio,
                              readiness: readiness.rawValue, energyRating: energyRating, notes: "", exercises: exercises,
                              updatedAt: end, steps: Int(steps.rounded()), distanceKm: (km * 100).rounded() / 100)
    }
}
