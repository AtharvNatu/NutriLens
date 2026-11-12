import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@MainActor
private var watchContainers: [ModelContainer] = []

@MainActor
private func watchContext() -> ModelContext {
    let container = AppEnvironment.makeContainer(inMemory: true)
    watchContainers.append(container)
    return container.mainContext
}

/// A session run on the Watch: saved to Health once (by the Watch), shown on the iPhone with its sets.
@Suite("Sessions recorded on Apple Watch")
@MainActor
struct WatchImportTests {
    let start = Date.now.addingTimeInterval(-3_600)
    var end: Date { start.addingTimeInterval(25 * 60) }

    func defaults() -> UserDefaults { UserDefaults(suiteName: "watch-\(UUID())")! }

    func payload() -> WorkoutPayload {
        WorkoutPayload.watchSession(
            kind: .strength, title: "Legs + core", end: end, activeSeconds: 25 * 60, planWeek: 4, planWeekday: 5, readiness: .ready,
            energyRating: 4, exercises: [
                LoggedExercise(exerciseID: "01", sets: [LoggedSet(reps: 10, loadKg: 10, repsInReserve: 2), LoggedSet(reps: 9, loadKg: 10, repsInReserve: 2)]),
                LoggedExercise(exerciseID: "05", sets: [], skipped: true),
            ], stepLengthMeters: 0.7)
    }

    /// What the Watch does on finishing: save the workout to Health (the shared store), then build the message.
    func watchFinishes(health: MockHealthService) async throws -> WatchWorkoutRecord {
        let id = UUID()
        let payload = payload()
        let healthID = try await health.saveWorkout(kind: .strength, start: start, end: end, kilocalories: 176,
                                                    nutriLensID: id, payload: PayloadCoder.encode(payload))
        return WatchWorkoutRecord(id: id, healthKitID: healthID, start: start, end: end, energyKcal: 176.4, payload: payload)
    }

    func healthWorkouts(_ health: MockHealthService) async throws -> [WorkoutSummary] {
        try await health.workouts(from: .distantPast, to: .distantFuture)
    }

    @Test func messageCreatesTheLogWithoutASecondHealthWorkout() async throws {
        let health = MockHealthService()
        let context = watchContext()
        let store = defaults()
        let record = try await watchFinishes(health: health)

        #expect(try WatchImport.receive(record, context: context, defaults: store) == .inserted)
        let log = try #require(try context.fetch(FetchDescriptor<WorkoutLog>()).first)
        #expect(log.id == record.id)
        #expect(log.healthKitID == record.healthKitID)
        #expect(log.title == "Legs + core")
        #expect(log.kind == .strength)
        #expect(log.planWeekday == 5)
        #expect(log.energyRating == 4)
        #expect(log.energyKcal == 176)
        #expect(log.completedSets == 2)
        #expect(log.exercises.first { $0.exerciseID == "05" }?.skipped == true)
        // Health still holds only the Watch's workout.
        #expect(try await healthWorkouts(health).count == 1)

        // The same message again (WatchConnectivity retries) changes nothing.
        #expect(try WatchImport.receive(record, context: context, defaults: store) == .unchanged)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutLog>()) == 1)
    }

    @Test func healthSyncAfterTheMessageFindsTheSameLog() async throws {
        let health = MockHealthService()
        let context = watchContext()
        let store = defaults()
        let record = try await watchFinishes(health: health)
        try WatchImport.receive(record, context: context, defaults: store)
        #expect(WatchImport.awaitingHealth(defaults: store) == [record.id])

        let report = try await HealthSync.run(health: health, context: context, defaults: store)
        #expect(report == HealthSync.Report())
        #expect(try context.fetchCount(FetchDescriptor<WorkoutLog>()) == 1)
        // Health has it now, so it's no longer protected.
        #expect(WatchImport.awaitingHealth(defaults: store).isEmpty)
        #expect(try await healthWorkouts(health).count == 1)
    }

    @Test func messageAfterHealthSyncFindsTheSameLog() async throws {
        let health = MockHealthService()
        let context = watchContext()
        let store = defaults()
        let record = try await watchFinishes(health: health)

        let report = try await HealthSync.run(health: health, context: context, defaults: store)
        #expect(report.inserted == 1)
        #expect(try WatchImport.receive(record, context: context, defaults: store) == .unchanged)
        let logs = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.completedSets == 2)
        #expect(try await healthWorkouts(health).count == 1)
    }

    @Test func logIsKeptUntilHealthCatchesUp() async throws {
        let health = MockHealthService()
        let context = watchContext()
        let store = defaults()
        // Health on this iPhone has another NutriLens workout, but not yet the Watch's.
        let other = WorkoutLog(kind: .walk, title: "Indoor walk", start: start.addingTimeInterval(-86_400), end: start.addingTimeInterval(-84_600))
        context.insert(other)
        other.healthKitID = try await health.saveWorkout(kind: .walking, start: other.start, end: other.end, kilocalories: 90,
                                                         nutriLensID: other.id, payload: PayloadCoder.encode(other.payload))
        let record = WatchWorkoutRecord(id: UUID(), healthKitID: UUID(), start: start, end: end, energyKcal: 176, payload: payload())
        try WatchImport.receive(record, context: context, defaults: store)

        let report = try await HealthSync.run(health: health, context: context, defaults: store)
        #expect(report.removed == 0)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutLog>()) == 2)

        // Days later, still missing from Health: it was deleted there, so it goes.
        let later = Date.now.addingTimeInterval(WatchImport.awaitingHealthLimit + 3_600)
        #expect(WatchImport.awaitingHealth(defaults: store, now: later).isEmpty)
        let laterReport = try await HealthSync.run(health: health, context: context, now: later, defaults: store)
        #expect(laterReport.removed == 1)
    }

    @Test func aSessionDeletedOnTheIPhoneIsNotBroughtBack() async throws {
        let context = watchContext()
        let record = WatchWorkoutRecord(id: UUID(), healthKitID: UUID(), start: start, end: end, energyKcal: 150, payload: payload())
        Tombstone.record(record.id, type: SyncRecordType.workout, in: context)
        #expect(try WatchImport.receive(record, context: context, defaults: defaults()) == .deleted)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutLog>()) == 0)
    }

    @Test func aNewerEditFromTheWatchUpdatesTheLog() throws {
        let context = watchContext()
        let store = defaults()
        var record = WatchWorkoutRecord(id: UUID(), healthKitID: nil, start: start, end: end, energyKcal: 0, payload: payload())
        try WatchImport.receive(record, context: context, defaults: store)
        // Sent without Health (save failed on the Watch): not protected, energy filled in later.
        #expect(WatchImport.awaitingHealth(defaults: store).isEmpty)
        record.payload.energyRating = 2
        record.payload.updatedAt = end.addingTimeInterval(60)
        record.healthKitID = UUID()
        record.energyKcal = 180
        #expect(try WatchImport.receive(record, context: context, defaults: store) == .updated)
        let log = try #require(try context.fetch(FetchDescriptor<WorkoutLog>()).first)
        #expect(log.energyRating == 2)
        #expect(log.healthKitID == record.healthKitID)
        #expect(log.energyKcal == 180)
    }

    @Test func theWatchWorkoutCountsOnceForTheDay() async throws {
        let health = MockHealthService()
        let record = try await watchFinishes(health: health)
        let context = watchContext()
        try WatchImport.receive(record, context: context, defaults: defaults())
        let workouts = try await healthWorkouts(health)
        let logs = try context.fetch(FetchDescriptor<WorkoutLog>())
        #expect(Training.countedWorkouts(workouts).count == 1)
        #expect(Training.uncountedLogs(logs, workouts: workouts).isEmpty)
        #expect(Training.displayedWorkouts(workouts, logs: logs).count == 1)
    }

    @Test func contextCarriesRecentSetsAndTheSleepSuggestion() throws {
        let context = watchContext()
        let log = WorkoutLog(kind: .strength, title: "Legs + core", start: start.addingTimeInterval(-7 * 86_400), end: end.addingTimeInterval(-7 * 86_400))
        log.planWeekday = 5
        log.exercises = payload().exercises
        context.insert(log)
        let walk = WorkoutLog(kind: .walk, title: "Indoor walk", start: start, end: end)
        context.insert(walk)
        let planStart = Date.now.addingTimeInterval(-22 * 86_400)
        let message = WatchImport.context(logs: [log, walk], planStart: planStart, lastNightAsleep: 5 * 3600, stepLengthMeters: 0.72)
        #expect(message.planStart == planStart)
        #expect(message.stepLengthMeters == 0.72)
        #expect(message.readiness(on: .now) == .tired)
        #expect(message.history(of: "01", weekday: 5) == [log.exercises[0].sets])
        #expect(message.history(of: "05", weekday: 5).isEmpty)
        #expect(WatchImport.context(logs: [], planStart: planStart, lastNightAsleep: 7.5 * 3600, stepLengthMeters: 0.7).readiness(on: .now) == .ready)
    }
}
