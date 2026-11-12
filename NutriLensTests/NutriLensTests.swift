import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@Suite("Mock Health service")
struct MockHealthServiceTests {
    @Test func savesAndDeletesMeals() async throws {
        let health = MockHealthService()
        let meal = MealSample(name: "Pizza", date: .now, nutrients: Nutrients(kilocalories: 285, protein: 12, carbohydrates: 35, fat: 11))
        let id = try await health.saveMeal(meal)
        #expect(health.snapshot.meals[id] == meal)

        try await health.deleteMeal(id: id)
        #expect(health.snapshot.meals.isEmpty)

        await #expect(throws: HealthDataError.self) {
            try await health.deleteMeal(id: id)
        }
    }

    @Test func unavailableHealthRefusesWrites() async {
        let health = MockHealthService(isAvailable: false)
        #expect(await health.shouldRequestAuthorization() == false)
        await #expect(throws: HealthDataError.self) {
            _ = try await health.saveMeal(MealSample(name: "x", date: .now, nutrients: .zero))
        }
    }

    @Test func authorizationFlow() async throws {
        let health = MockHealthService()
        #expect(await health.shouldRequestAuthorization())
        try await health.requestAuthorization()
        #expect(await health.shouldRequestAuthorization() == false)
    }

    @Test func manualWorkoutAddsActiveEnergy() async throws {
        let calendar = Calendar.current
        let health = MockHealthService(calendar: calendar)
        let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        try await health.saveWorkout(kind: .running, start: start, end: start.addingTimeInterval(1_800), kilocalories: 343)

        let workouts = try await health.workouts(from: calendar.startOfDay(for: start), to: start.addingTimeInterval(86_400))
        #expect(workouts.count == 1)
        #expect(workouts.first?.name == "Running")
        #expect(workouts.first?.energyBurned == 343)
        #expect(try await health.activity(on: start).activeEnergy == 343)
    }

    @Test func sampleDataCoversAWeek() async throws {
        let health = MockHealthService.sample()
        let days = DailyTotals.days(endingOn: .now, count: 7)
        let activity = try await health.activity(for: days)
        #expect(activity.count == 7)
        #expect(activity.values.allSatisfy { $0.basalEnergy > 0 })
        let mass = try #require(try await health.latestBodyMass())
        #expect((60...120).contains(mass))
        let nights = SleepAnalyzer.nights(from: try await health.sleepSamples(from: .now.addingTimeInterval(-15 * 86_400), to: .now))
        #expect(nights.count >= 13)
        #expect(nights.allSatisfy { $0.hasStages && $0.asleep > 5 * 3600 })
    }

    @Test func stepCountForAnInterval() async throws {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        let health = MockHealthService(state: .init(activity: [day: ActivitySummary(steps: 8_640, activeEnergy: 0, basalEnergy: 0)]), calendar: calendar)
        // 8,640 steps over 24 h = 6 per minute; a 30-minute window gets 180.
        let steps = try await health.stepCount(from: day.addingTimeInterval(3_600), to: day.addingTimeInterval(3_600 + 1_800))
        #expect(abs(steps - 180) < 0.001)
        #expect(abs(try await health.stepCount(from: day, to: day.addingTimeInterval(86_400)) - 8_640) < 0.001)
        #expect(try await health.stepCount(from: day, to: day) == 0)
    }

    @Test func activityForUnknownDaysIsZero() async throws {
        let health = MockHealthService()
        let summary = try await health.activity(on: .distantPast)
        #expect(summary == .zero)
    }
}

@Suite("Recognition ranking")
struct RecognitionRankingTests {
    let db = NutritionDatabase.bundled

    @Test func genericLabelSuggestsSeveralIndianDishes() {
        let candidates = RecognitionRanking.candidates(from: [(label: "curry", confidence: 0.5)], database: db)
        #expect(candidates.first?.food.id == "chicken_curry")
        #expect(candidates.first?.confidence == 0.5)
        #expect(candidates.count == 6)
        #expect(abs(candidates[1].confidence - 0.5 * RecognitionRanking.followingSuggestionWeight) < 1e-9)
        #expect(candidates.allSatisfy { $0.label == "curry" })
    }

    @Test func mergesDuplicatesAndDropsNoise() {
        let observations: [(label: String, confidence: Double)] = [
            ("hamburger", 0.30),   // → vada pav first
            ("sandwich", 0.45),    // → veg sandwich, vada pav (0.45 × 0.85 beats 0.30)
            ("keyboard", 0.90),    // not food
            ("samosa", 0.005),     // below threshold
        ]
        let candidates = RecognitionRanking.candidates(from: observations, database: db)
        #expect(candidates.first?.food.id == "veg_sandwich")
        let vadaPav = candidates.first { $0.food.id == "vada_pav" }
        #expect(vadaPav?.label == "sandwich")
        #expect(abs((vadaPav?.confidence ?? 0) - 0.3825) < 1e-9)
        #expect(Set(candidates.map(\.food.id)).count == candidates.count)
        #expect(!candidates.contains { $0.food.id == "samosa" })
    }

    @Test func limitsResults() {
        let labels = ["biryani", "samosa", "crepe", "dumpling"]
        let observations = labels.enumerated().map { (label: $1, confidence: 0.5 - Double($0) * 0.05) }
        let candidates = RecognitionRanking.candidates(from: observations, database: db, limit: 3)
        #expect(candidates.map(\.food.id) == ["chicken_biryani", "samosa", "veg_biryani"])
    }

    @Test func mockRecognizerReturnsDemoGuesses() async throws {
        let recognizer = MockFoodRecognizer.demo(database: db)
        let image = try #require(DemoContent.samplePhoto(size: 64).cgImage)
        let results = try await recognizer.recognize(image)
        #expect(results.first?.food.id == "misal_pav")
        #expect(recognizer.engine == .mock)
    }

    @Test func recognizerUsesOnlyApplesBuiltInClassifier() {
        #expect(VisionFoodRecognizer(database: db).engine == .visionBuiltIn)
        // No third-party Core ML model may ship in the app bundle.
        #expect((Bundle.main.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) ?? []).isEmpty)
    }
}

@Suite("Meal log")
@MainActor
struct MealEntryTests {
    @Test func entryStoresScaledNutrients() throws {
        let container = AppEnvironment.makeContainer(inMemory: true)
        let context = container.mainContext
        let pizza = try #require(NutritionDatabase.bundled.food(id: "pizza"))
        let portion = Portion.servings(2)
        let entry = MealEntry(
            date: .now,
            name: pizza.name,
            foodID: pizza.id,
            grams: portion.grams(for: pizza),
            nutrients: pizza.nutrients(for: portion),
            mealType: .dinner,
            source: .photo
        )
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<MealEntry>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.grams == 214)
        #expect(abs((fetched.first?.kilocalories ?? 0) - 569.24) < 0.001)
        #expect(fetched.first?.mealType == .dinner)
        #expect(fetched.first?.source == .photo)
        #expect(fetched.first?.nutrients == pizza.nutrients(for: portion))
    }

    @Test func dayPredicateExcludesOtherDays() throws {
        let calendar = Calendar.current
        let container = AppEnvironment.makeContainer(inMemory: true)
        let context = container.mainContext
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        for date in [yesterday.addingTimeInterval(3_600), today.addingTimeInterval(60), today.addingTimeInterval(80_000), tomorrow] {
            context.insert(MealEntry(date: date, name: "x", foodID: nil, grams: 100, nutrients: .zero, mealType: .snack, source: .custom))
        }
        let todays = try context.fetch(FetchDescriptor(predicate: MealEntry.predicate(from: today, to: tomorrow)))
        #expect(todays.count == 2)
    }

    @Test func demoSeedProducesAWeekOfMeals() throws {
        let container = AppEnvironment.makeContainer(inMemory: true)
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: .now)!
        DemoContent.seed(into: container.mainContext, database: .bundled, now: noon, calendar: calendar)
        let all = try container.mainContext.fetch(FetchDescriptor<MealEntry>())
        #expect(all.count >= 25)
        let days = Set(all.map { calendar.startOfDay(for: $0.date) })
        #expect(days.count == 7)
    }

    @Test(arguments: [(7, MealType.breakfast), (12, .lunch), (16, .snack), (19, .dinner), (23, .snack), (2, .snack)])
    func suggestedMealType(hour: Int, expected: MealType) {
        let date = Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: .now)!
        #expect(MealType.suggested(for: date) == expected)
    }
}

@Suite("Formatting")
struct FormatTests {
    @Test func signedKilocalories() {
        #expect(Format.signedKcal(-300.4) == "−300")
        #expect(Format.signedKcal(250) == "+250")
        #expect(Format.signedKcal(0.2) == "0")
    }
}
