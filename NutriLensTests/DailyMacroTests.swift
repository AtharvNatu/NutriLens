import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@MainActor
private var macroContainers: [ModelContainer] = []

/// Macro targets are no longer set by hand: each day's come from its plan session, your weight and usual steps.
@Suite("Daily macro targets")
@MainActor
struct DailyMacroTests {
    let calendar = Calendar.current
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 9))!  // a Thursday

    func makeEnv(_ health: MockHealthService) -> AppEnvironment {
        let container = AppEnvironment.makeContainer(inMemory: true)
        macroContainers.append(container)
        return AppEnvironment(health: health, recognizer: MockFoodRecognizer.demo(database: .bundled), database: .bundled,
                              modelContainer: container)
    }

    func defaults() -> UserDefaults { UserDefaults(suiteName: "macros-\(UUID())")! }

    @Test func targetsFollowTheDaysPlanWeightAndUsualSteps() async throws {
        var state = MockHealthService.State(authorized: true, bodyMass: 84.6)
        let today = calendar.startOfDay(for: now)
        for back in 1...14 {
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            state.activity[day] = ActivitySummary(steps: back.isMultiple(of: 3) ? 8_200 : 10_100, activeEnergy: 400, basalEnergy: 1_700)
        }
        let env = makeEnv(MockHealthService(state: state, calendar: calendar))
        await env.refreshMacroInputs(now: now)
        #expect(env.macroInputs == AppEnvironment.MacroInputs(bodyMassKg: 84.6, usualSteps: 10_000))

        let store = defaults()
        let thursday = env.macroTargets(on: now, defaults: store)
        let sunday = env.macroTargets(on: calendar.date(byAdding: .day, value: 3, to: now)!, defaults: store)
        #expect(thursday.dayKind == .strength)
        #expect(sunday.dayKind == .rest)
        #expect(thursday.protein == 160)
        #expect(thursday.carbohydrates > sunday.carbohydrates)
        #expect(thursday == MacroPlanner.targets(day: env.plan.day(weekday: 5), week: env.planWeek(on: now), calorieTarget: 2_000,
                                                 policy: store.creditPolicy, bodyMassKg: 84.6, expectedSteps: 10_000))

        // A higher calorie target raises the targets (carbohydrates take the difference).
        store.set(2_300.0, forKey: SettingsKey.dailyCalorieTarget)
        #expect(env.macroTargets(on: now, defaults: store).carbohydrates > thursday.carbohydrates)
    }

    @Test func weightFallsBackToTheLastScaleReading() async throws {
        let env = makeEnv(MockHealthService(state: MockHealthService.State(authorized: true), calendar: calendar))
        let reading = BodyMeasurement(date: now.addingTimeInterval(-86_400), source: .screenshot,
                                      reading: BodyReading(values: [.weight: 82.4]))
        env.modelContainer.mainContext.insert(reading)
        try env.modelContainer.mainContext.save()
        await env.refreshMacroInputs(now: now)
        #expect(env.macroInputs.bodyMassKg == 82.4)
        // No step history: 10,000 a day is assumed.
        #expect(env.macroInputs.usualSteps == 10_000)
    }
}
