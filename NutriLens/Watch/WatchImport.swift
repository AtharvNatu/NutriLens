import Foundation
import NutriCore
import SwiftData

/// Stores sessions recorded on Apple Watch.
///
/// The Watch saves each session to Apple Health itself (with the log's ID and payload, like the iPhone does), then
/// sends the log here. Whichever arrives first, the WatchConnectivity message or Health's copy (`HealthSync`), creates
/// the log; the other finds it by ID. Nothing here writes to Health, so a session is never saved twice.
@MainActor
enum WatchImport {
    enum Outcome: Equatable {
        case inserted, updated, unchanged
        /// Deleted on the iPhone already (tombstone): not brought back.
        case deleted
    }

    /// How long a Watch session is kept while Health hasn't synced its workout to the iPhone yet.
    static let awaitingHealthLimit: TimeInterval = 2 * 86_400

    @discardableResult
    static func receive(_ record: WatchWorkoutRecord, context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) throws -> Outcome {
        let id = record.id
        let tombstones = try context.fetch(FetchDescriptor<DeletedRecord>(predicate: #Predicate { $0.id == id }))
        if !tombstones.isEmpty { return .deleted }
        let existing = try context.fetch(FetchDescriptor<WorkoutLog>(predicate: #Predicate { $0.id == id })).first
        let outcome: Outcome
        if let log = existing {
            var changed = false
            // Health's copy carries the time in whole seconds (ISO 8601), so the same edit can differ by a fraction.
            if record.payload.updatedAt.timeIntervalSince(log.updatedAt) >= 1 {
                log.apply(record.payload)
                log.start = record.start
                log.end = record.end
                changed = true
            }
            if log.healthKitID == nil, let healthID = record.healthKitID {
                log.healthKitID = healthID
                changed = true
            }
            if log.energyKcal == 0, record.energyKcal > 0 {
                log.energyKcal = record.energyKcal
                changed = true
            }
            outcome = changed ? .updated : .unchanged
        } else {
            let log = WorkoutLog(id: id, kind: WorkoutLogKind(rawValue: record.payload.kind) ?? .other, title: record.payload.title,
                                 start: record.start, end: record.end)
            log.apply(record.payload)
            log.energyKcal = record.energyKcal.rounded()
            log.healthKitID = record.healthKitID
            context.insert(log)
            outcome = .inserted
            if record.healthKitID != nil { markAwaitingHealth(id, at: now, defaults: defaults) }
        }
        try context.save()
        return outcome
    }

    // MARK: Waiting for Health

    private static let key = "watchLogsAwaitingHealth"

    /// IDs of Watch sessions whose Health workout hasn't reached this iPhone yet. `HealthSync` mustn't take their
    /// absence from Health for a deletion. Entries expire after `awaitingHealthLimit`.
    static func awaitingHealth(defaults: UserDefaults = .standard, now: Date = .now) -> Set<UUID> {
        let stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        return Set(stored.compactMap { id, time in
            now.timeIntervalSince1970 - time < awaitingHealthLimit ? UUID(uuidString: id) : nil
        })
    }

    static func markAwaitingHealth(_ id: UUID, at now: Date = .now, defaults: UserDefaults = .standard) {
        var stored = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
        stored = stored.filter { now.timeIntervalSince1970 - $0.value < awaitingHealthLimit }
        stored[id.uuidString] = now.timeIntervalSince1970
        defaults.set(stored, forKey: key)
    }

    /// Health now has these workouts: stop protecting them.
    static func healthHas(_ ids: Set<UUID>, defaults: UserDefaults = .standard) {
        guard var stored = defaults.dictionary(forKey: key) as? [String: Double], !stored.isEmpty else { return }
        let before = stored.count
        stored = stored.filter { !ids.contains(UUID(uuidString: $0.key) ?? UUID()) }
        if stored.count != before { defaults.set(stored, forKey: key) }
    }

    // MARK: What the Watch needs

    /// Plan start, settings, today's readiness suggestion and recent sets for the Watch.
    static func context(logs: [WorkoutLog], planStart: Date, lastNightAsleep: TimeInterval?, stepLengthMeters: Double,
                        now: Date = .now) -> WatchContext {
        let sessions = logs.filter { $0.kind == .strength }.map {
            WatchContext.Session(start: $0.start, weekday: $0.planWeekday, exercises: $0.exercises)
        }
        return WatchContext(sentAt: now, planStart: planStart, suggestedReadiness: Readiness.suggested(lastNightAsleep: lastNightAsleep),
                            readinessDay: Calendar.current.startOfDay(for: now), stepLengthMeters: stepLengthMeters,
                            history: WatchContext.history(from: sessions))
    }
}
