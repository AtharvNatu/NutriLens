import Foundation
import Testing
@testable import NutriCore

@Suite("Workout plan")
struct PlanTests {
    let plan = PlanContent.homeStrength12Week
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    @Test func libraryHasTwentyNumberedGuidesAndEveryReferenceResolves() {
        let numbered = plan.exercises.filter { $0.id.first?.isNumber == true }
        #expect(numbered.count == 20)
        #expect(Set(plan.exercises.map(\.id)).count == plan.exercises.count)
        #expect(Set(plan.exercises.map(\.videoName)).count == plan.exercises.count)
        for day in plan.days {
            for planned in day.exercises {
                #expect(plan.exercise(planned.exerciseID) != nil, "\(day.title) references \(planned.exerciseID)")
            }
        }
        for step in plan.yoga { #expect(plan.exercise(step.exerciseID)?.category == .yoga) }
        // Every strength guide is used somewhere in the week.
        let used = Set(plan.days.flatMap { $0.exercises.map(\.exerciseID) })
        #expect(numbered.allSatisfy { used.contains($0.id) })
    }

    @Test func weekHasFourStrengthDaysTwoCardioAndARestDay() {
        #expect(plan.days.count == 7)
        #expect(Set(plan.days.map(\.weekday)) == Set(1...7))
        #expect(plan.days.filter { $0.kind == .strength }.map(\.weekday).sorted() == [2, 3, 5, 7])
        #expect(plan.days.filter { $0.kind == .cardioYoga }.map(\.weekday).sorted() == [4, 6])
        #expect(plan.day(weekday: 1)?.kind == .rest)
    }

    @Test func weekNumbering() {
        let start = date(2026, 10, 21)
        #expect(PlanEngine.week(for: date(2026, 10, 20), startDate: start, calendar: calendar) == nil)
        #expect(PlanEngine.week(for: start, startDate: start, calendar: calendar) == 1)
        #expect(PlanEngine.week(for: date(2026, 10, 27), startDate: start, calendar: calendar) == 1)
        #expect(PlanEngine.week(for: date(2026, 10, 28), startDate: start, calendar: calendar) == 2)
        #expect(PlanEngine.week(for: date(2027, 1, 12), startDate: start, calendar: calendar) == 12)
        #expect(PlanEngine.week(for: date(2027, 1, 13), startDate: start, calendar: calendar) == 13)
    }

    @Test(arguments: [(1, PlanPhase.learn), (2, .settle), (3, .build), (5, .build), (6, .easeOff),
                      (7, .rebuild), (8, .rebuild), (9, .continueBuild), (11, .continueBuild), (12, .review), (14, .review)])
    func phases(week: Int, phase: PlanPhase) {
        #expect(PlanPhase.forWeek(week) == phase)
    }

    var benchPress: PlannedExercise { plan.day(weekday: 2)!.exercises[0] }
    var optionalPushUp: PlannedExercise { plan.day(weekday: 2)!.exercises.first { $0.optional }! }

    @Test func prescriptionsFollowThePhaseTable() {
        // Flat press: Intro 2 × 8–12, Build 3 × 8–15.
        #expect(PlanEngine.prescription(for: benchPress, week: 1) == Prescription(sets: 1, 8, 12))
        #expect(PlanEngine.prescription(for: benchPress, week: 2) == Prescription(sets: 2, 8, 12))
        #expect(PlanEngine.prescription(for: benchPress, week: 4) == Prescription(sets: 3, 8, 15))
        #expect(PlanEngine.prescription(for: benchPress, week: 6) == Prescription(sets: 2, 8, 15))
        #expect(PlanEngine.prescription(for: benchPress, week: 9) == Prescription(sets: 3, 8, 15))
        #expect(PlanEngine.prescription(for: benchPress, week: 12) == Prescription(sets: 2, 8, 15))
    }

    @Test func twoSetBuildDropsToOneInDeloadWeeks() {
        let incline = plan.day(weekday: 2)!.exercises[1]
        #expect(incline.build.sets == 2)
        #expect(PlanEngine.prescription(for: incline, week: 6)?.sets == 1)
    }

    @Test func optionalPushUpsOnlyFromWeekFiveAndNotInDeloads() {
        for week in [1, 2, 3, 4, 6, 12] {
            #expect(PlanEngine.prescription(for: optionalPushUp, week: week) == nil, "week \(week)")
        }
        for week in [5, 7, 10] {
            #expect(PlanEngine.prescription(for: optionalPushUp, week: week) == Prescription(sets: 2, 6, 15), "week \(week)")
        }
        #expect(PlanEngine.session(for: plan.day(weekday: 2)!, week: 1).count == 5)
        #expect(PlanEngine.session(for: plan.day(weekday: 2)!, week: 5).count == 6)
    }

    @Test func prescriptionLabels() {
        #expect(Prescription(sets: 2, 8, 12, perSide: true).label == "2 × 8–12 / side")
        #expect(Prescription(sets: 2, 15, 30, perSide: true, seconds: true).label == "2 × 15–30 s / side")
    }

    @Test(arguments: [(1, 80), (2, 80), (3, 120), (4, 120), (5, 140), (6, 100), (7, 150), (11, 150), (12, 120)])
    func cardioMinutesAddUpToTheWeeklyTarget(week: Int, total: Int) {
        let minutes = plan.days.map { PlanEngine.cardioMinutes(kind: $0.kind, week: week) }.reduce(0, +)
        #expect(minutes == total)
        #expect(PlanEngine.weeklyCardioTarget(week: week).lowerBound <= minutes)
    }

    @Test func jogIntervalSessionsLastTwentyMinutes() {
        for stage in plan.jogStages {
            let intervals = PlanEngine.intervals(for: stage)
            #expect(intervals.map(\.seconds).reduce(0, +) == 20 * 60)
            #expect(intervals.filter { $0.kind == .jog }.count == 6)
        }
        #expect(!PlanEngine.jogAllowed(week: 2, weekday: 6))
        #expect(PlanEngine.jogAllowed(week: 3, weekday: 6))
        #expect(!PlanEngine.jogAllowed(week: 5, weekday: 5))
    }

    @Test func yogaSequenceIsAboutTenMinutes() {
        let total = plan.yoga.map(\.seconds).reduce(0, +)
        #expect((480...720).contains(total))
    }

    @Test func readinessFromSleep() {
        #expect(Readiness.suggested(lastNightAsleep: nil) == .ready)
        #expect(Readiness.suggested(lastNightAsleep: 7.5 * 3600) == .ready)
        #expect(Readiness.suggested(lastNightAsleep: 5 * 3600) == .tired)
    }
}

@Suite("Progression advice")
struct ProgressionTests {
    let rx = Prescription(sets: 3, 8, 15)

    func sets(_ reps: [Int], _ kg: Double) -> [LoggedSet] { reps.map { LoggedSet(reps: $0, loadKg: kg) } }

    @Test func noHistory() {
        #expect(ProgressionAdvisor.advice(history: [], prescription: rx) == .firstTime)
    }

    @Test func topOfRangeTwiceEarnsAnIncrease() {
        let history = [sets([15, 15, 15], 5), sets([15, 15, 16], 5)]
        #expect(ProgressionAdvisor.advice(history: history, prescription: rx) == .increaseLoad(from: 5))
    }

    @Test func onceAtTheTopIsNotEnough() {
        let history = [sets([12, 11, 10], 5), sets([15, 15, 15], 5)]
        #expect(ProgressionAdvisor.advice(history: history, prescription: rx) == .addReps(load: 5))
    }

    @Test func loadChangeResetsTheCount() {
        let history = [sets([15, 15, 15], 5), sets([15, 15, 15], 7.5)]
        #expect(ProgressionAdvisor.advice(history: history, prescription: rx) == .addReps(load: 7.5))
    }

    @Test func missingSetsDoNotCount() {
        let history = [sets([15, 15], 5), sets([15, 15], 5)]
        #expect(ProgressionAdvisor.advice(history: history, prescription: rx) == .addReps(load: 5))
    }

    @Test func belowTheRangeSuggestsHolding() {
        let history = [sets([9, 7, 6], 10)]
        #expect(ProgressionAdvisor.advice(history: history, prescription: rx) == .holdOrReduce(load: 10))
        #expect(ProgressionAdvice.holdOrReduce(load: 10).message.contains("10 kg"))
        #expect(ProgressionAdvice.addReps(load: 0).message.contains("bodyweight"))
    }
}
