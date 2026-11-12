import Foundation
import Testing
@testable import NutriCore

@Suite("Watch messages and logs")
struct WatchSyncTests {
    let calendar = Calendar.current
    var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 18))! }

    func sets(_ reps: Int..., kg: Double) -> [LoggedSet] { reps.map { LoggedSet(reps: $0, loadKg: kg, repsInReserve: 2) } }

    @Test func contextRoundTripsThroughAMessage() throws {
        let context = WatchContext(sentAt: day, planStart: day.addingTimeInterval(-22 * 86_400), suggestedReadiness: .tired,
                                   readinessDay: calendar.startOfDay(for: day), stepLengthMeters: 0.72,
                                   history: [WatchContext.historyKey("01", weekday: 5): [sets(10, 9, kg: 10)]])
        let message = try WatchMessage.encode(context)
        #expect(Set(message.keys) == [WatchMessage.contextKey])
        #expect(WatchMessage.context(from: message[WatchMessage.contextKey]) == context)
        #expect(WatchMessage.workout(from: message[WatchMessage.contextKey]) == nil)
    }

    @Test func aNewerFormatIsIgnored() throws {
        var context = WatchContext(sentAt: day, planStart: day, suggestedReadiness: .ready, readinessDay: day, stepLengthMeters: 0.7, history: [:])
        context.version = WatchContext.version + 1
        let data = try #require(try WatchMessage.encode(context)[WatchMessage.contextKey])
        #expect(WatchMessage.context(from: data) == nil)
        #expect(WatchMessage.context(from: nil) == nil)
        #expect(WatchMessage.context(from: Data("junk".utf8)) == nil)
    }

    @Test func historyKeepsTheLastTwoSessionsPerDayAndOverall() {
        let sessions = [
            WatchContext.Session(start: day.addingTimeInterval(-14 * 86_400), weekday: 5, exercises: [LoggedExercise(exerciseID: "01", sets: sets(8, 8, kg: 8))]),
            WatchContext.Session(start: day.addingTimeInterval(-7 * 86_400), weekday: 5, exercises: [LoggedExercise(exerciseID: "01", sets: sets(10, 9, kg: 8))]),
            // Light practice on Tuesday: kept apart from Thursday's main lift.
            WatchContext.Session(start: day.addingTimeInterval(-2 * 86_400), weekday: 3, exercises: [
                LoggedExercise(exerciseID: "01", sets: sets(12, kg: 4)),
                LoggedExercise(exerciseID: "05", sets: [], skipped: true),
            ]),
            WatchContext.Session(start: day.addingTimeInterval(-21 * 86_400), weekday: 5, exercises: [LoggedExercise(exerciseID: "01", sets: sets(6, kg: 6))]),
        ]
        let context = WatchContext(sentAt: day, planStart: day, suggestedReadiness: .ready, readinessDay: day, stepLengthMeters: 0.7,
                                   history: WatchContext.history(from: sessions))
        #expect(context.history(of: "01", weekday: 5) == [sets(8, 8, kg: 8), sets(10, 9, kg: 8)])
        #expect(context.history(of: "01", weekday: 3) == [sets(12, kg: 4)])
        // A day with no history of its own falls back to any day's.
        #expect(context.history(of: "01", weekday: 7) == [sets(10, 9, kg: 8), sets(12, kg: 4)])
        // Skipped exercises leave no history.
        #expect(context.history(of: "05", weekday: 3).isEmpty)
    }

    @Test func readinessSuggestionOnlyAppliesToItsDay() {
        let context = WatchContext(sentAt: day, planStart: day, suggestedReadiness: .tired, readinessDay: calendar.startOfDay(for: day),
                                   stepLengthMeters: 0.7, history: [:])
        #expect(context.readiness(on: day) == .tired)
        #expect(context.readiness(on: day.addingTimeInterval(86_400)) == .ready)
    }

    @Test func tiredVersionCapsSetsAndDropsOptionalWork() throws {
        let plan = PlanContent.homeStrength12Week
        let monday = try #require(plan.day(weekday: 2))
        let full = PlanEngine.session(for: monday, week: 5)
        #expect(full.contains { $0.planned.optional })
        let tired = PlanEngine.adjusted(full, readiness: .tired)
        #expect(!tired.contains { $0.planned.optional })
        #expect(tired.allSatisfy { $0.prescription.sets <= 2 })
        #expect(PlanEngine.adjusted(full, readiness: .unwell).isEmpty)
        #expect(PlanEngine.adjusted(full, readiness: .ready).count == full.count)
    }

    @Test func setsArePrefilledFromLastTime() {
        let rx = Prescription(sets: 2, 8, 12)
        let last = LoggedSet(reps: 11, loadKg: 12.5, repsInReserve: 1)
        #expect(PlanEngine.prefill(usesLoad: true, prescription: rx, last: last, week: 4) == last)
        #expect(PlanEngine.prefill(usesLoad: true, prescription: rx, last: nil, week: 4) == LoggedSet(reps: 10, loadKg: 5, repsInReserve: 2))
        #expect(PlanEngine.prefill(usesLoad: false, prescription: Prescription(sets: 2, 20, 30, seconds: true), last: nil, week: 1)
                == LoggedSet(reps: 20, loadKg: 0, repsInReserve: 3))
    }

    @Test func workoutRecordRoundTripsWithItsHealthPayload() throws {
        let payload = WorkoutPayload.watchSession(
            kind: .strength, title: "Legs + core", end: day, activeSeconds: 1_500, planWeek: 4, planWeekday: 5, readiness: .tired,
            energyRating: 4, exercises: [LoggedExercise(exerciseID: "01", sets: sets(10, 10, kg: 10)), LoggedExercise(exerciseID: "05", sets: [], skipped: true)],
            stepLengthMeters: 0.7)
        #expect(payload.kind == "strength")
        #expect(payload.cardioMinutes == 0)
        #expect(payload.readiness == "tired")
        #expect(payload.updatedAt == day)
        // The Health metadata decodes to the same payload the iPhone reads.
        #expect(PayloadCoder.decode(WorkoutPayload.self, from: PayloadCoder.encode(payload)) == payload)

        let record = WatchWorkoutRecord(id: UUID(), healthKitID: UUID(), start: day.addingTimeInterval(-1_520), end: day, energyKcal: 176.4, payload: payload)
        let message = try WatchMessage.encode(record)
        #expect(WatchMessage.workout(from: message[WatchMessage.workoutKey]) == record)
        #expect(WatchMessage.context(from: message[WatchMessage.workoutKey]) == nil)
    }

    @Test func cardioMinutesAndDistanceMatchTheIPhoneRules() throws {
        let walk = WorkoutPayload.watchSession(kind: .walk, title: "Indoor walk", end: day, activeSeconds: 1_800, planWeek: 4, planWeekday: 4,
                                               readiness: .ready, energyRating: 3, steps: 3_000, distanceMeters: 0, stepLengthMeters: 0.7)
        #expect(walk.cardioMinutes == 30)
        #expect(walk.steps == 3_000)
        #expect(abs((walk.distanceKm ?? 0) - 2.1) < 0.001)

        let stage = try #require(PlanContent.homeStrength12Week.jogStages.first)
        let jog = WorkoutPayload.watchSession(kind: .walkJog, title: "Walk/jog stage 1", end: day, activeSeconds: 20 * 60, planWeek: 4,
                                              planWeekday: 6, readiness: .ready, energyRating: 3, jogStage: stage, distanceMeters: 2_480,
                                              stepLengthMeters: 0.7)
        // Only the 12-minute interval block counts as moderate; warm-up and cool-down are extra.
        #expect(jog.cardioMinutes == 12)
        #expect(jog.distanceKm == 2.48)

        let yoga = WorkoutPayload.watchSession(kind: .yoga, title: "Gentle yoga", end: day, activeSeconds: 600, planWeek: 4, planWeekday: 4,
                                               readiness: .ready, energyRating: 5, stepLengthMeters: 0.7)
        #expect(yoga.cardioMinutes == 0)
    }
}
