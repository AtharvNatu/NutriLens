import Foundation
import NutriCore
import Observation

/// Today's strength session on the wrist: this week's prescriptions (readiness-adjusted), sets pre-filled from
/// last time, one-tap logging and the rest timer.
@MainActor
@Observable
final class StrengthSession {
    struct Item: Identifiable {
        var exercise: Exercise
        var planned: PlannedExercise
        var prescription: Prescription
        /// Previous sessions' sets, oldest first.
        var history: [[LoggedSet]]

        var id: String { planned.id }
    }

    let day: PlanDay
    let week: Int
    let readiness: Readiness
    let items: [Item]

    var index = 0 { didSet { prepareDraft() } }
    private(set) var logged: [String: [LoggedSet]] = [:]
    private(set) var skipped: Set<String> = []
    /// Next set's numbers, adjusted with the Digital Crown.
    var reps: Double = 10
    var load: Double = 5
    var repsLeft: Double = 2
    private(set) var restUntil: Date?

    init(day: PlanDay, week: Int, readiness: Readiness, plan: WorkoutPlan, context: WatchContext?) {
        self.day = day
        self.week = week
        self.readiness = readiness
        items = PlanEngine.adjusted(PlanEngine.session(for: day, week: week), readiness: readiness).compactMap { entry in
            guard let exercise = plan.exercise(entry.planned.exerciseID) else { return nil }
            return Item(exercise: exercise, planned: entry.planned, prescription: entry.prescription,
                        history: context?.history(of: exercise.id, weekday: day.weekday) ?? [])
        }
        prepareDraft()
    }

    var current: Item? { items.indices.contains(index) ? items[index] : nil }

    func sets(for item: Item) -> [LoggedSet] { logged[item.exercise.id] ?? [] }

    func isDone(_ item: Item) -> Bool { sets(for: item).count >= item.prescription.sets }

    var completedSets: Int { logged.values.map(\.count).reduce(0, +) }

    /// Logs the set, starts the rest timer and moves on once the prescribed sets are done.
    func logSet(now: Date = .now) {
        guard let item = current else { return }
        let set = LoggedSet(reps: Int(reps.rounded()), loadKg: item.exercise.usesLoad ? load : 0, repsInReserve: Int(repsLeft.rounded()))
        logged[item.exercise.id, default: []].append(set)
        skipped.remove(item.exercise.id)
        restUntil = now.addingTimeInterval(Double(item.planned.restSeconds.lowerBound))
        if sets(for: item).count == item.prescription.sets, index < items.count - 1 {
            index += 1
        }
    }

    func removeLastSet() {
        guard let item = current, !(logged[item.exercise.id] ?? []).isEmpty else { return }
        logged[item.exercise.id]?.removeLast()
        prepareDraft()
    }

    func skip() {
        guard let item = current else { return }
        skipped.insert(item.exercise.id)
        if index < items.count - 1 { index += 1 }
    }

    func endRest() { restUntil = nil }

    /// What's saved: every planned exercise, with its sets or marked skipped (as the iPhone logs it).
    var exercises: [LoggedExercise] {
        items.map { LoggedExercise(exerciseID: $0.exercise.id, sets: sets(for: $0), skipped: skipped.contains($0.exercise.id)) }
    }

    private func prepareDraft() {
        guard let item = current else { return }
        let last = logged[item.exercise.id]?.last ?? item.history.last?.last
        let draft = PlanEngine.prefill(usesLoad: item.exercise.usesLoad, prescription: item.prescription, last: last, week: week)
        reps = Double(draft.reps)
        load = draft.loadKg
        repsLeft = Double(draft.repsInReserve ?? 2)
    }
}
