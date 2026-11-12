import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@MainActor
private var recorderContainers: [ModelContainer] = []

@MainActor
private func recorderContext() -> ModelContext {
    let container = AppEnvironment.makeContainer(inMemory: true)
    recorderContainers.append(container)
    return container.mainContext
}

@Suite("Daily records for the calendar")
@MainActor
struct DayRecorderTests {
    let calendar = Calendar.current
    let defaults = UserDefaults(suiteName: "day-recorder-\(UUID())")!
    var day: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 10))! }
    var now: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 12))! }

    func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let d = calendar.date(byAdding: .day, value: dayOffset, to: day)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
    }

    func health() -> MockHealthService {
        var state = MockHealthService.State(authorized: true, bodyMass: 80)
        state.activity[day] = ActivitySummary(steps: 12_000, activeEnergy: 650, basalEnergy: 1_800)
        state.workouts = [
            WorkoutSummary(id: UUID(), name: "Walking", symbolName: "figure.walk", start: at(7), end: at(8), energyBurned: 200,
                           sourceName: "Apple Watch", isCardio: true),
        ]
        // 23:00 → 06:30 the night before.
        state.sleep = [SleepSample(start: at(23, dayOffset: -1), end: at(6, 30), stage: .core)]
        state.body = [BodySample(id: UUID(), date: at(7, 30), values: [.weight: 81.2], sourceName: "Scale")]
        return MockHealthService(state: state, calendar: calendar)
    }

    func addLogs(to context: ModelContext) {
        let food = NutritionDatabase.bundled.foods.first!
        context.insert(MealEntry(date: at(9), name: "Breakfast", foodID: food.id, grams: 100,
                                 nutrients: Nutrients(kilocalories: 450, protein: 30, carbohydrates: 50, fat: 12), mealType: .breakfast, source: .search))
        context.insert(MealEntry(date: at(20), name: "Dinner", foodID: food.id, grams: 100,
                                 nutrients: Nutrients(kilocalories: 700, protein: 40, carbohydrates: 80, fat: 20), mealType: .dinner, source: .search))
        // A meal on the next day must not count.
        context.insert(MealEntry(date: at(9, dayOffset: 1), name: "Other day", foodID: food.id, grams: 100,
                                 nutrients: Nutrients(kilocalories: 999, protein: 1, carbohydrates: 1, fat: 1), mealType: .breakfast, source: .search))
        let strength = WorkoutLog(kind: .strength, title: "Day 1 strength", start: at(18), end: at(18, 50))
        strength.energyKcal = 150
        strength.steps = 300
        context.insert(strength)
    }

    @Test func recordsFoodWorkoutsActivitySleepAndWeight() async throws {
        let context = recorderContext()
        addLogs(to: context)
        let records = await DayRecorder.record(days: [at(15)], health: health(), context: context, defaults: defaults, now: now)
        let r = try #require(records.first)
        #expect(records.count == 1)
        #expect(r.dayKey == "2026-03-10")
        #expect(r.date == day)

        #expect(r.eatenKcal == 1_150)
        #expect(r.protein == 70)
        #expect(r.carbohydrates == 130)
        #expect(r.fat == 32)
        #expect(r.mealCount == 2)

        // Health's walk and the strength session that isn't in Health yet.
        #expect(r.workouts.map(\.name) == ["Walking", "Day 1 strength"])
        #expect(r.workouts.map(\.fromHealth) == [true, false])
        #expect(r.workoutEnergy == 350)
        #expect(r.cardioMinutes == 60)

        // Walking energy from steps outside workouts (the mock spreads 12,000 steps over the day: 500 in the walk).
        #expect(r.workouts[0].steps == 500)
        let expectedStepEnergy = StepEnergy.kilocalories(steps: 12_000 - 500 - 300, bodyMassKg: 81.2,
                                                         stepLengthMeters: SettingsDefault.stepLengthMeters)
        #expect(abs(r.stepEnergy - expectedStepEnergy) < 0.001)
        let balance = CalorieBalance(eaten: 1_150, activeEnergy: 650, basalEnergy: 1_800, workoutEnergy: 350,
                                     stepEnergy: expectedStepEnergy, target: SettingsDefault.dailyCalorieTarget, policy: defaults.creditPolicy)
        #expect(abs(r.budgetKcal - balance.budget) < 0.001)
        #expect(abs(r.burnedKcal - balance.burned) < 0.001)

        #expect(r.asleepSeconds == 7.5 * 3600)
        #expect(r.sleepScore != nil)
        #expect(r.weightKg == 81.2)
    }

    @Test func keepsHealthValuesWhenHealthLaterReturnsNothing() async throws {
        let context = recorderContext()
        addLogs(to: context)
        await DayRecorder.record(days: [day], health: health(), context: context, defaults: defaults, now: now)

        // Later: Health has nothing (permission off, data removed); a meal was deleted.
        let dinner = try #require(try context.fetch(FetchDescriptor<MealEntry>()).first { $0.name == "Dinner" })
        context.delete(dinner)
        let records = await DayRecorder.record(days: [day], health: MockHealthService(calendar: calendar), context: context,
                                               defaults: defaults, now: now)
        let r = try #require(records.first)
        #expect(try context.fetch(FetchDescriptor<DayRecord>()).count == 1)
        // Your own log is always current…
        #expect(r.eatenKcal == 450)
        #expect(r.mealCount == 1)
        // …while what came from Health is kept.
        #expect(r.steps == 12_000)
        #expect(r.activeEnergy == 650)
        #expect(r.basalEnergy == 1_800)
        #expect(r.workouts.map(\.name) == ["Walking", "Day 1 strength"])
        #expect(r.cardioMinutes == 60)
        #expect(r.asleepSeconds == 7.5 * 3600)
        #expect(r.weightKg == 81.2)
    }

    @Test func updatedAtOnlyMovesWhenTheDayChanges() async throws {
        let context = recorderContext()
        addLogs(to: context)
        let h = health()
        let first = try #require(await DayRecorder.record(days: [day], health: h, context: context, defaults: defaults, now: now).first)
        #expect(first.updatedAt == now)
        let again = try #require(await DayRecorder.record(days: [day], health: h, context: context, defaults: defaults,
                                                          now: now.addingTimeInterval(3_600)).first)
        #expect(again.updatedAt == now)
        context.insert(MealEntry(date: at(16), name: "Snack", foodID: nil, grams: 30,
                                 nutrients: Nutrients(kilocalories: 120, protein: 3, carbohydrates: 15, fat: 5), mealType: .snack, source: .search))
        let changed = try #require(await DayRecorder.record(days: [day], health: h, context: context, defaults: defaults,
                                                            now: now.addingTimeInterval(7_200)).first)
        #expect(changed.updatedAt == now.addingTimeInterval(7_200))
    }

    @Test func skipsFutureDaysAndListsMonths() async {
        let context = recorderContext()
        let records = await DayRecorder.record(days: [day, at(9, dayOffset: 30)], health: health(), context: context, defaults: defaults, now: now)
        #expect(records.map(\.dayKey) == ["2026-03-10"])

        let march = DayRecorder.days(inMonthOf: day, calendar: calendar)
        #expect(march.count == 31)
        #expect(march.first == calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        #expect(DayRecorder.recentDays(7, now: now, calendar: calendar).count == 7)
        #expect(DayRecord.key(for: at(23, 59)) == "2026-03-10")
    }
}
