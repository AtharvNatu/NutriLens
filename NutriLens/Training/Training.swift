import Foundation
import NutriCore
import SwiftData

/// Saving, estimating and summarising training sessions.
@MainActor
enum Training {
    /// MET for gentle jogging in place (Compendium "running in place").
    static let jogMET = 7.0

    /// Active energy for a session: (MET − 1) × body mass × hours, so resting energy isn't counted twice.
    static func estimatedEnergy(kind: WorkoutLogKind, minutes: Double, bodyMassKg: Double?, jogShare: Double = 0) -> Double {
        let kg = bodyMassKg ?? EnergyEstimator.defaultBodyMassKg
        let met: Double
        switch kind {
        case .walkJog: met = jogShare * jogMET + (1 - jogShare) * ActivityKind.walking.met
        default: met = kind.activity.met
        }
        return EnergyEstimator.activityKilocalories(met: met, bodyMassKg: kg, minutes: minutes).rounded()
    }

    /// Inserts the log and writes it to Apple Health with its sync payload. Returns an error message, or nil.
    static func save(_ log: WorkoutLog, env: AppEnvironment, context: ModelContext) async -> String? {
        log.updatedAt = .now
        context.insert(log)
        var message: String?
        if env.health.isAvailable {
            do {
                log.healthKitID = try await env.health.saveWorkout(
                    kind: log.kind.activity, start: log.start, end: log.end, kilocalories: log.energyKcal,
                    nutriLensID: log.id, payload: PayloadCoder.encode(log.payload)
                )
            } catch {
                message = "Saved in NutriLens, but not to Apple Health: \(error.localizedDescription)"
            }
        }
        do {
            try context.save()
        } catch {
            return "Couldn't save the session: \(error.localizedDescription)"
        }
        env.healthDidChange()
        return message
    }

    static func delete(_ log: WorkoutLog, env: AppEnvironment, context: ModelContext) async {
        if let id = log.healthKitID, env.health.isAvailable {
            try? await env.health.deleteWorkout(id: id)
        }
        Tombstone.record(log.id, type: SyncRecordType.workout, in: context)
        context.delete(log)
        try? context.save()
        env.healthDidChange()
    }

    /// Previous sessions' sets for an exercise, oldest first.
    ///
    /// With `weekday`, sessions from the same plan day are preferred: the plan tracks the main lift
    /// separately from lighter practice of the same movement on another day (e.g. Thursday squats vs
    /// Tuesday's light squats). Falls back to every session when that day has no history yet.
    static func history(of exerciseID: String, in logs: [WorkoutLog], weekday: Int? = nil, before date: Date = .distantFuture) -> [[LoggedSet]] {
        func sets(_ logs: [WorkoutLog]) -> [[LoggedSet]] {
            logs.filter { $0.start < date }
                .sorted { $0.start < $1.start }
                .compactMap { log in log.exercises.first { $0.exerciseID == exerciseID && !$0.skipped }?.sets }
                .filter { !$0.isEmpty }
        }
        if let weekday {
            let sameDay = sets(logs.filter { $0.planWeekday == weekday })
            if !sameDay.isEmpty { return sameDay }
        }
        return sets(logs)
    }

    /// Readiness changes the session: the tired version uses at most 2 sets and drops optional work.
    static func adjusted(_ session: [(planned: PlannedExercise, prescription: Prescription)], readiness: Readiness)
        -> [(planned: PlannedExercise, prescription: Prescription)] {
        PlanEngine.adjusted(session, readiness: readiness)
    }

    /// Start and end of the plan week containing `date` (plan weeks begin on the plan's start weekday).
    static func planWeekInterval(containing date: Date, start: Date, calendar: Calendar = .current) -> DateInterval {
        let week = PlanEngine.week(for: date, startDate: start, calendar: calendar) ?? 1
        let begin = calendar.date(byAdding: .day, value: (week - 1) * 7, to: calendar.startOfDay(for: start)) ?? calendar.startOfDay(for: date)
        return DateInterval(start: begin, duration: 7 * 86_400)
    }

    /// Moderate cardio minutes in an interval: Health cardio workouts plus logs not (yet) in Health.
    /// For sessions NutriLens logged, the session's own moderate minutes count (a walk/jog session's
    /// 12-minute interval block, not its full 20 minutes; the easy walk after strength work).
    /// A session the Watch also recorded counts once, with the larger of the two values.
    static func cardioMinutes(workouts: [WorkoutSummary], logs: [WorkoutLog], in interval: DateInterval) -> Double {
        func minutes(_ workout: WorkoutSummary) -> Double {
            if workout.nutriLensID != nil, let payload = PayloadCoder.decode(WorkoutPayload.self, from: workout.payload) {
                return payload.cardioMinutes
            }
            return workout.isCardio ? workout.duration / 60 : 0
        }
        let inInterval = workouts.filter { interval.contains($0.start) }
        let counted = countedWorkouts(inInterval)
        func extra(_ value: Double, start: Date, end: Date) -> Double {
            let recorded = counted.filter { !isFromNutriLens($0) && sameSession(start, end, $0.start, $0.end) }.map(minutes).reduce(0, +)
            return max(0, value - recorded)
        }
        let countedIDs = Set(counted.map(\.id))
        let fromHealth = counted.map(minutes).reduce(0, +)
            + inInterval.filter { !countedIDs.contains($0.id) }.map { extra(minutes($0), start: $0.start, end: $0.end) }.reduce(0, +)
        let localOnly = logs.filter { $0.healthKitID == nil && interval.contains($0.start) }
            .map { extra($0.cardioMinutes, start: $0.start, end: $0.end) }.reduce(0, +)
        return fromHealth + localOnly
    }

    // MARK: One session, two recordings

    /// Whether NutriLens wrote this Health workout.
    static func isFromNutriLens(_ workout: WorkoutSummary) -> Bool {
        workout.nutriLensID != nil || workout.sourceName == "NutriLens"
    }

    /// Two recordings are the same session when they overlap for at least half of the shorter one
    /// (a session logged here while the Watch records it starts and ends a few minutes apart).
    static func sameSession(_ aStart: Date, _ aEnd: Date, _ bStart: Date, _ bEnd: Date) -> Bool {
        let overlap = min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart))
        let shorter = min(aEnd.timeIntervalSince(aStart), bEnd.timeIntervalSince(bStart))
        return overlap > 0 && overlap >= shorter / 2
    }

    /// Health workouts to count, with NutriLens's copy left out wherever the Watch (or another app) recorded the
    /// same session: the Watch measured its energy and steps, NutriLens only estimated them.
    static func countedWorkouts(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        let recorded = workouts.filter { !isFromNutriLens($0) }
        return workouts.filter { w in
            !isFromNutriLens(w) || !recorded.contains { sameSession(w.start, w.end, $0.start, $0.end) }
        }
    }

    /// The workout the Watch (or another app) recorded during this session, if any.
    static func recording(of log: WorkoutLog, in workouts: [WorkoutSummary]) -> WorkoutSummary? {
        workouts.filter { !isFromNutriLens($0) && sameSession(log.start, log.end, $0.start, $0.end) }
            .max { a, b in
                min(a.end, log.end).timeIntervalSince(max(a.start, log.start)) < min(b.end, log.end).timeIntervalSince(max(b.start, log.start))
            }
    }

    /// Sessions logged here that count on their own: not in Health and not recorded by the Watch.
    static func uncountedLogs(_ logs: [WorkoutLog], workouts: [WorkoutSummary]) -> [WorkoutLog] {
        logs.filter { $0.healthKitID == nil && recording(of: $0, in: workouts) == nil }
    }

    /// Counted workouts for display: a Watch recording of a session logged here takes the session's name.
    static func displayedWorkouts(_ workouts: [WorkoutSummary], logs: [WorkoutLog]) -> [WorkoutSummary] {
        countedWorkouts(workouts).map { w in
            guard !isFromNutriLens(w),
                  let log = logs.first(where: { recording(of: $0, in: workouts)?.id == w.id }), !log.title.isEmpty else { return w }
            var named = w
            named.name = log.title
            named.sourceName = "\(w.sourceName) · logged in NutriLens"
            return named
        }
    }
}
