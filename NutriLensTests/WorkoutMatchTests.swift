import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@MainActor
private var matchContainers: [ModelContainer] = []

@Suite("A session the Watch also recorded counts once")
@MainActor
struct WorkoutMatchTests {
    let calendar = Calendar.current
    var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 12))! }

    func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    /// 12 Nov: Watch walk 1:37–2:07 PM, Watch strength 6:20:47–6:45:22 PM, "Legs + core" logged 6:23:30–6:45:07 PM.
    func watchWorkouts() -> [WorkoutSummary] {
        [
            WorkoutSummary(id: UUID(), name: "Walking", symbolName: "figure.walk", start: at(13, 37), end: at(14, 7), energyBurned: 220.5,
                           sourceName: "Apple Watch", isCardio: true),
            WorkoutSummary(id: UUID(), name: "Strength training", symbolName: "figure.strengthtraining.traditional",
                           start: at(18, 20, 47), end: at(18, 45, 22), energyBurned: 175.5, sourceName: "Apple Watch"),
        ]
    }

    func legsAndCore() -> WorkoutLog {
        let log = WorkoutLog(kind: .strength, title: "Legs + core", start: at(18, 23, 30), end: at(18, 45, 7))
        log.energyKcal = 175
        log.steps = 434
        return log
    }

    @Test func overlapRule() {
        #expect(Training.sameSession(at(18, 23), at(18, 45), at(18, 20), at(18, 45)))
        // Back to back, or a short overlap, are two sessions.
        #expect(!Training.sameSession(at(18, 0), at(18, 30), at(18, 30), at(19, 0)))
        #expect(!Training.sameSession(at(18, 0), at(18, 40), at(18, 30), at(19, 10)))
    }

    @Test func nutriLensCopyInHealthIsLeftOut() async throws {
        let health = MockHealthService(state: MockHealthService.State(authorized: true), calendar: calendar)
        let log = legsAndCore()
        _ = try await health.saveWorkout(kind: .strength, start: log.start, end: log.end, kilocalories: 175, nutriLensID: log.id, payload: nil)
        let all = try await health.workouts(from: .distantPast, to: .distantFuture) + watchWorkouts()

        let counted = Training.countedWorkouts(all)
        #expect(counted.count == 2)
        #expect(counted.compactMap(\.energyBurned).reduce(0, +) == 396)
        #expect(Training.recording(of: log, in: all)?.name == "Strength training")

        let shown = Training.displayedWorkouts(all, logs: [log])
        #expect(shown.map(\.name).sorted() == ["Legs + core", "Walking"])
        #expect(shown.first { $0.name == "Legs + core" }?.energyBurned == 175.5)
    }

    @Test func aNutriLensSessionWithoutTheWatchStillCounts() async throws {
        let health = MockHealthService(state: MockHealthService.State(authorized: true), calendar: calendar)
        let log = legsAndCore()
        _ = try await health.saveWorkout(kind: .strength, start: log.start, end: log.end, kilocalories: 175, nutriLensID: log.id, payload: nil)
        let all = try await health.workouts(from: .distantPast, to: .distantFuture) + [watchWorkouts()[0]]
        #expect(Training.countedWorkouts(all).count == 2)
        #expect(Training.recording(of: log, in: all) == nil)
        // Not saved to Health: counts on its own unless the Watch recorded it.
        #expect(Training.uncountedLogs([log], workouts: [watchWorkouts()[0]]).count == 1)
        #expect(Training.uncountedLogs([log], workouts: watchWorkouts()).isEmpty)
    }

    @Test func dayRecordCountsTheSessionOnce() async throws {
        let container = AppEnvironment.makeContainer(inMemory: true)
        matchContainers.append(container)
        let context = container.mainContext
        var state = MockHealthService.State(authorized: true, bodyMass: 81)
        state.activity[day] = ActivitySummary(steps: 6_813, activeEnergy: 716, basalEnergy: 1_660)
        state.workouts = watchWorkouts()
        let health = MockHealthService(state: state, calendar: calendar)
        let log = legsAndCore()
        context.insert(log)
        log.healthKitID = try await health.saveWorkout(kind: .strength, start: log.start, end: log.end, kilocalories: 175,
                                                       nutriLensID: log.id, payload: nil)
        try context.save()

        let defaults = UserDefaults(suiteName: "match-\(UUID())")!
        let record = try #require(await DayRecorder.record(days: [day], health: health, context: context, defaults: defaults,
                                                         now: at(23, 0)).first)
        #expect(record.workouts.map(\.name) == ["Walking", "Legs + core"])
        #expect(record.workoutEnergy == 396)
    }
}
