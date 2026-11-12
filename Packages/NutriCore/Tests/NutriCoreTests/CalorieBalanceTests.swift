import Foundation
import Testing
@testable import NutriCore

@Suite("Calorie balance")
struct CalorieBalanceTests {
    @Test func burnedIsActivePlusBasal() {
        let b = CalorieBalance(eaten: 1800, activeEnergy: 450, basalEnergy: 1650, target: 2000)
        #expect(b.burned == 2100)
    }

    @Test func netIsEatenMinusBurned() {
        let deficit = CalorieBalance(eaten: 1800, activeEnergy: 450, basalEnergy: 1650, target: 2000)
        #expect(deficit.net == -300)
        #expect(deficit.isDeficit)

        let surplus = CalorieBalance(eaten: 2600, activeEnergy: 200, basalEnergy: 1700, target: 2000)
        #expect(surplus.net == 700)
        #expect(!surplus.isDeficit)
    }

    @Test func remainingAgainstTarget() {
        let b = CalorieBalance(eaten: 1500, activeEnergy: 400, basalEnergy: 1600, target: 2000)
        #expect(b.budget == 2000)
        #expect(b.remaining == 500)
        #expect(!b.isOverBudget)
        #expect(b.progress == 0.75)
    }

    @Test func overTargetGivesNegativeRemaining() {
        let b = CalorieBalance(eaten: 2300, activeEnergy: 0, basalEnergy: 0, target: 2000)
        #expect(b.remaining == -300)
        #expect(b.isOverBudget)
        #expect(b.progress == 1.15)
    }

    @Test func allActiveEnergyCanBeAddedToBudget() {
        let b = CalorieBalance(eaten: 2300, activeEnergy: 500, basalEnergy: 1600, target: 2000,
                               policy: ExerciseCreditPolicy(source: .allActiveEnergy, fraction: 1))
        #expect(b.exerciseCredit == 500)
        #expect(b.budget == 2500)
        #expect(b.remaining == 200)
        #expect(!b.isOverBudget)
        // Net balance doesn't depend on the budget option.
        #expect(b.net == 2300 - 2100)
    }

    @Test func workoutsOnlyCreditUsesFraction() {
        let b = CalorieBalance(eaten: 1800, activeEnergy: 600, basalEnergy: 1650, workoutEnergy: 340, target: 2000,
                               policy: ExerciseCreditPolicy(source: .workouts, fraction: 0.5))
        #expect(b.exerciseCredit == 170)
        #expect(b.budget == 2170)
        #expect(b.remaining == 370)
    }

    @Test func noCreditByDefault() {
        let b = CalorieBalance(eaten: 1800, activeEnergy: 600, basalEnergy: 1650, workoutEnergy: 340, target: 2000)
        #expect(b.exerciseCredit == 0)
        #expect(b.budget == 2000)
    }

    @Test func loggedWorkoutNotYetInHealthStillCountsAsBurned() {
        // A manual workout of 300 kcal, but Health has only 120 kcal active energy so far.
        let b = CalorieBalance(eaten: 1500, activeEnergy: 120, basalEnergy: 1000, workoutEnergy: 300, target: 2000,
                               policy: ExerciseCreditPolicy(source: .allActiveEnergy, fraction: 1))
        #expect(b.burned == 1300)
        #expect(b.exerciseCredit == 300)
    }

    @Test func stepsCountTowardBurnedAndCredit() {
        // iPhone-only day: Health active energy 120, a 200 kcal workout, 150 kcal walking from steps.
        let b = CalorieBalance(eaten: 1800, activeEnergy: 120, basalEnergy: 1700, workoutEnergy: 200, stepEnergy: 150, target: 2000,
                               policy: ExerciseCreditPolicy(source: .workoutsAndSteps, fraction: 0.5))
        #expect(b.effectiveActiveEnergy == 350)
        #expect(b.burned == 2050)
        #expect(b.exerciseCredit == 175)
        #expect(b.budget == 2175)
        // With Apple Watch, active energy already includes the walking: no double counting.
        let watch = CalorieBalance(eaten: 1800, activeEnergy: 600, basalEnergy: 1700, workoutEnergy: 200, stepEnergy: 150, target: 2000)
        #expect(watch.effectiveActiveEnergy == 600)
        // "Workouts only" ignores steps.
        #expect(ExerciseCreditPolicy(source: .workouts, fraction: 1).credit(workoutEnergy: 200, stepEnergy: 150, activeEnergy: 0) == 200)
        #expect(ExerciseCreditPolicy(source: .allActiveEnergy, fraction: 1).credit(workoutEnergy: 200, stepEnergy: 150, activeEnergy: 300) == 350)
    }

    @Test func stepEnergyAndDistance() {
        // 8,000 steps × 0.75 m = 6 km; × 80 kg × 0.5 kcal/kg/km = 240 kcal.
        #expect(StepEnergy.distanceKm(steps: 8_000) == 6)
        #expect(StepEnergy.kilocalories(steps: 8_000, bodyMassKg: 80) == 240)
        #expect(StepEnergy.kilocalories(steps: 8_000, bodyMassKg: 80, stepLengthMeters: 0.8) == 256)
        #expect(StepEnergy.kilocalories(steps: -5, bodyMassKg: 80) == 0)
    }

    @Test(arguments: [(0.0, 6_000), (4_210.0, 4_500), (5_480.0, 6_000), (8_900.0, 9_000), (12_000.0, 9_000), (1_200.0, 3_000)])
    func plansStepGoalSuggestion(average: Double, expected: Int) {
        #expect(StepEnergy.suggestedGoal(sevenDayAverage: average) == expected)
    }

    @Test(arguments: [(-0.5, 0.0), (0.25, 0.25), (1.7, 1.0), (Double.nan, 0.0)])
    func creditFractionIsClamped(input: Double, expected: Double) {
        #expect(ExerciseCreditPolicy(source: .workouts, fraction: input).fraction == expected)
    }

    @Test func zeroTargetHasZeroProgress() {
        let b = CalorieBalance(eaten: 500, activeEnergy: 0, basalEnergy: 0, target: 0)
        #expect(b.progress == 0)
        #expect(b.remaining == -500)
    }

    @Test func negativeInputsAreClamped() {
        let b = CalorieBalance(eaten: -10, activeEnergy: -5, basalEnergy: -1, target: -2000)
        #expect(b.eaten == 0 && b.burned == 0 && b.target == 0)
        #expect(b.net == 0)
    }

    @Test func emptyDay() {
        let b = CalorieBalance(eaten: 0, activeEnergy: 0, basalEnergy: 0, target: 2000)
        #expect(b.remaining == 2000)
        #expect(b.net == 0)
        #expect(!b.isDeficit)
    }

    @Test func metEstimateIsActiveEnergyOnly() {
        // (9.8 − 1) MET × 70 kg × 0.5 h = 308 kcal: resting energy (1 MET) is counted separately as basal.
        #expect(abs(EnergyEstimator.activityKilocalories(met: 9.8, bodyMassKg: 70, minutes: 30) - 308) < 1e-9)
        #expect(EnergyEstimator.activityKilocalories(met: ActivityKind.walking.met, bodyMassKg: 80, minutes: 60) == 200)
        #expect(EnergyEstimator.activityKilocalories(met: 1, bodyMassKg: 80, minutes: 60) == 0)
        #expect(EnergyEstimator.activityKilocalories(met: 5, bodyMassKg: 70, minutes: 0) == 0)
        #expect(EnergyEstimator.activityKilocalories(met: 5, bodyMassKg: -1, minutes: 30) == 0)
    }

    @Test func everyActivityHasDisplayData() {
        for kind in ActivityKind.allCases {
            #expect(kind.met > 0)
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.symbolName.isEmpty)
        }
    }
}

@Suite("Daily totals")
struct DailyTotalsTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        c.firstWeekday = 2 // Monday
        return c
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func weekStartsOnCalendarsFirstWeekday() {
        // Wednesday 12 Nov 2025 -> Monday 10 … Sunday 16.
        let week = DailyTotals.week(containing: date(2025, 11, 12), calendar: calendar)
        #expect(week.count == 7)
        #expect(week.first == calendar.startOfDay(for: date(2025, 11, 10)))
        #expect(week.last == calendar.startOfDay(for: date(2025, 11, 16)))
    }

    @Test func daysEndingOn() {
        let days = DailyTotals.days(endingOn: date(2025, 3, 2), count: 3, calendar: calendar)
        #expect(days == [date(2025, 2, 28), date(2025, 3, 1), date(2025, 3, 2)].map(calendar.startOfDay))
        #expect(DailyTotals.days(endingOn: date(2025, 3, 2), count: 0, calendar: calendar).isEmpty)
    }

    @Test func totalsGroupByDayAndIgnoreOtherDays() {
        let n = Nutrients(kilocalories: 100, protein: 10, carbohydrates: 10, fat: 2)
        let entries = [
            LoggedAmount(date: date(2025, 11, 10, 8), nutrients: n),
            LoggedAmount(date: date(2025, 11, 10, 23), nutrients: n.scaled(by: 2)),
            LoggedAmount(date: date(2025, 11, 12, 0), nutrients: n),
            LoggedAmount(date: date(2025, 11, 20), nutrients: n.scaled(by: 10)), // outside the week
        ]
        let week = DailyTotals.week(containing: date(2025, 11, 12), calendar: calendar)
        let totals = DailyTotals.totals(of: entries, for: week, calendar: calendar)

        #expect(totals.count == 7)
        #expect(totals[0].nutrients.kilocalories == 300)
        #expect(totals[0].entryCount == 2)
        #expect(totals[1].nutrients == .zero)
        #expect(totals[2].nutrients.kilocalories == 100)
        #expect(totals.map(\.nutrients.kilocalories).reduce(0, +) == 400)
        #expect(DailyTotals.averageKilocalories(of: totals) == 200)
    }

    @Test func averageOfEmptyWeekIsZero() {
        let week = DailyTotals.week(containing: date(2025, 11, 12), calendar: calendar)
        #expect(DailyTotals.averageKilocalories(of: DailyTotals.totals(of: [], for: week, calendar: calendar)) == 0)
    }
}
