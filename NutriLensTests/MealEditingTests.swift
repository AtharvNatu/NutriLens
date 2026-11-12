import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@MainActor
private var editingContainers: [ModelContainer] = []

@Suite("Editing and deleting logged meals")
@MainActor
struct MealEditingTests {
    func makeEnv(_ health: MockHealthService) -> AppEnvironment {
        let container = AppEnvironment.makeContainer(inMemory: true)
        editingContainers.append(container)
        return AppEnvironment(health: health, recognizer: MockFoodRecognizer.demo(database: .bundled), database: .bundled,
                              modelContainer: container)
    }

    func logged(_ env: AppEnvironment, health: MockHealthService) async throws -> MealEntry {
        let entry = MealEntry(date: .now.addingTimeInterval(-3_600), name: "Paneer bhurji", foodID: "paneer_bhurji", grams: 200,
                              nutrients: Nutrients(kilocalories: 400, protein: 24, carbohydrates: 10, fat: 30), mealType: .lunch, source: .search)
        env.modelContainer.mainContext.insert(entry)
        entry.updatedAt = .now.addingTimeInterval(-3_600)
        entry.healthKitID = try await health.saveMeal(entry.healthSample)
        try env.modelContainer.mainContext.save()
        return entry
    }

    @Test func changingTheAmountScalesTheNutrition() {
        let entry = MealEntry(date: .now, name: "Dal", foodID: nil, grams: 200,
                              nutrients: Nutrients(kilocalories: 300, protein: 18, carbohydrates: 40, fat: 6), mealType: .dinner, source: .search)
        var edit = MealEdit(entry)
        edit.setGrams(300)
        #expect(edit.nutrients.kilocalories == 450)
        #expect(edit.nutrients.protein == 27)
        edit.setGrams(-5)
        #expect(edit.grams == 0 && edit.nutrients.kilocalories == 0)

        // Typed values win until the amount changes again.
        edit.setGrams(100)
        edit.nutrients.protein = 12
        edit.mealType = .lunch
        edit.apply(to: entry)
        #expect(entry.grams == 100 && entry.protein == 12 && entry.kilocalories == 150 && entry.mealType == .lunch)

        // A meal logged without a weight keeps its nutrition when the amount is typed.
        let noWeight = MealEntry(date: .now, name: "Thali", foodID: nil, grams: 0, nutrients: Nutrients(kilocalories: 700, protein: 20, carbohydrates: 90, fat: 25),
                                 mealType: .lunch, source: .custom)
        var e2 = MealEdit(noWeight)
        e2.setGrams(400)
        #expect(e2.nutrients.kilocalories == 700)
    }

    @Test func savingAnEditReplacesTheHealthSampleAndSyncsToTheOtherDevice() async throws {
        let health = MockHealthService(state: MockHealthService.State(authorized: true))
        let phone = makeEnv(health)
        let entry = try await logged(phone, health: health)
        let oldHealthID = try #require(entry.healthKitID)

        // The iPad has the meal from an earlier sync.
        let iPad = makeEnv(health)
        _ = try await HealthSync.run(health: health, context: iPad.modelContainer.mainContext)

        var edit = MealEdit(entry)
        edit.setGrams(300)
        edit.mealType = .dinner
        edit.apply(to: entry)
        let warning = await MealLog.saveChanges(to: entry, env: phone, context: phone.modelContainer.mainContext)
        #expect(warning == nil)
        #expect(entry.healthKitID != oldHealthID)

        let records = try await health.mealRecords(from: .distantPast, to: .distantFuture)
        #expect(records.count == 1)
        #expect(records.first?.nutrients.kilocalories == 600)

        let report = try await HealthSync.run(health: health, context: iPad.modelContainer.mainContext)
        #expect(report.updated == 1 && report.removed == 0)
        let synced = try #require(try iPad.modelContainer.mainContext.fetch(FetchDescriptor<MealEntry>()).first)
        #expect(synced.kilocalories == 600 && synced.grams == 300 && synced.mealType == .dinner)
        #expect(synced.healthKitID == entry.healthKitID)
    }

    @Test func deletingRemovesItEverywhere() async throws {
        let health = MockHealthService(state: MockHealthService.State(authorized: true))
        let env = makeEnv(health)
        let entry = try await logged(env, health: health)
        let context = env.modelContainer.mainContext
        let warning = await MealLog.delete([entry], env: env, context: context)
        #expect(warning == nil)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
        #expect(try await health.mealRecords(from: .distantPast, to: .distantFuture).isEmpty)
        // A fresh sync doesn't bring it back.
        _ = try await HealthSync.run(health: health, context: context)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }
}

@Suite("Recipes in the Food tab")
@MainActor
struct RecipesFoodTests {
    @Test func aRecipeLogsAsOneServing() throws {
        let recipe = try #require(ProteinRecipes.recipe(id: "quick_matar_paneer"))
        let food = recipe.foodItem(database: .bundled)
        #expect(food.nutrients(for: .servings(1)) == food.perServing)
        #expect(food.perServing.protein >= 15)
        #expect(MealType.allCases.map(\.recipeMeal) == ProteinRecipe.Meal.allCases)
        #expect(FoodSection.allCases == [.log, .recipes, .history])
        #expect(FoodSection(launchName: "recipes") == .recipes)
    }
}
