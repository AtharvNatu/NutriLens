import Foundation
import Testing
@testable import NutriCore

@Suite("Daily macro targets from the plan")
struct MacroPlannerTests {
    let plan = PlanContent.homeStrength12Week
    let policy = ExerciseCreditPolicy(source: .workoutsAndSteps, fraction: 0.5)

    func targets(weekday: Int, week: Int = 4, steps: Double = 10_000, policy: ExerciseCreditPolicy? = nil) -> MacroTargets {
        MacroPlanner.targets(day: plan.day(weekday: weekday), week: week, calorieTarget: 2_000, policy: policy ?? self.policy,
                             bodyMassKg: 84.6, expectedSteps: steps, stepLengthMeters: 0.75)
    }

    @Test func macrosAddUpToTheDaysEnergy() {
        for weekday in 1...7 {
            let t = targets(weekday: weekday)
            let kcal = t.protein * 4 + t.carbohydrates * 4 + t.fat * 9
            #expect(abs(kcal - t.kilocalories) <= 6, "weekday \(weekday)")
            #expect((130...160).contains(t.protein))
        }
    }

    @Test func strengthDaysGetMoreProteinAndCarbsThanRestDays() {
        let thursday = targets(weekday: 5)
        let sunday = targets(weekday: 1)
        let wednesday = targets(weekday: 4)
        #expect(thursday.dayKind == .strength)
        #expect(sunday.dayKind == .rest)
        #expect(wednesday.dayKind == .cardioYoga)
        #expect(thursday.protein == 160)
        #expect(sunday.protein == 145)
        #expect(wednesday.protein == 150)
        #expect(thursday.carbohydrates > wednesday.carbohydrates)
        #expect(wednesday.carbohydrates > sunday.carbohydrates)
        #expect(thursday.fat < sunday.fat)
        // Thursday, week 4: 45 min strength + 15 min walk ≈ 211 kcal; 8,500 other steps ≈ 270 kcal; half credited.
        #expect(abs(thursday.plannedWorkoutEnergy - 212) <= 1)
        #expect(abs(thursday.plannedStepEnergy - 270) <= 1)
        #expect(abs(thursday.kilocalories - 2_241) <= 1)
    }

    @Test func moreUsualStepsMeanMoreFuel() {
        #expect(targets(weekday: 1, steps: 12_000).carbohydrates > targets(weekday: 1, steps: 8_000).carbohydrates)
    }

    @Test func withoutExerciseCreditTheEnergyStaysButTheSplitShifts() {
        let none = ExerciseCreditPolicy.none
        let strength = targets(weekday: 5, policy: none)
        let rest = targets(weekday: 1, policy: none)
        #expect(strength.kilocalories == 2_000)
        #expect(rest.kilocalories == 2_000)
        #expect(strength.carbohydrates > rest.carbohydrates)
    }

    @Test func usualStepsFromRecentDays() {
        #expect(MacroPlanner.usualSteps([]) == 10_000)
        #expect(MacroPlanner.usualSteps([9_800, 10_250, 0, 8_100, 10_400, 300]) == 10_000)
        #expect(MacroPlanner.usualSteps([8_000, 8_600, 9_100]) == 8_500)
        // Too few real days: assume 10,000.
        #expect(MacroPlanner.usualSteps([4_000, 200]) == 10_000)
    }
}
