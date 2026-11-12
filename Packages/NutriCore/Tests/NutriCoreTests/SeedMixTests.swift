import Foundation
import Testing
@testable import NutriCore

@Suite("Seeds and nuts mix")
struct SeedMixTests {
    let db = NutritionDatabase.bundled

    @Test func watermelonSeedsAreListedAndFoundByName() throws {
        let seeds = try #require(db.food(id: "watermelon_seeds"))
        #expect(seeds.category == "nuts")
        #expect(seeds.per100g.protein > 25)
        #expect(db.search("Watermelon seeds").first?.id == "watermelon_seeds")
        #expect(db.search("magaj").first?.id == "watermelon_seeds")
        // The fruit still comes first for plain "watermelon".
        #expect(db.search("watermelon").first?.id == "watermelon")
    }

    @Test func mixIsExactlyItsIngredientsPerMeal() throws {
        let mix = try #require(db.food(id: "seed_nut_mix"))
        let recipe = try #require(DishRecipes.recipe(for: "seed_nut_mix"))
        // 5 g pumpkin, sunflower, watermelon, almonds, cashews; 4 g walnuts; 1 g pista = 30 g.
        let grams: [String: Double] = ["pumpkin_seeds": 5, "sunflower_seeds": 5, "watermelon_seeds": 5, "almonds": 5,
                                       "pistachios": 1, "walnuts": 4, "cashews": 5]
        #expect(Set(recipe.components.map(\.foodID)) == Set(grams.keys))
        for component in recipe.components { #expect(component.typical == grams[component.foodID], "\(component.foodID)") }
        #expect(mix.servingGrams == 30)

        var sum = Nutrients.zero
        for (id, g) in grams { sum = sum + (try #require(db.food(id: id))).nutrients(for: .grams(g)) }
        #expect(abs(mix.perServing.kilocalories - sum.kilocalories) < 0.1)
        #expect(abs(mix.perServing.protein - sum.protein) < 0.05)
        #expect(abs(mix.perServing.fat - sum.fat) < 0.05)
        #expect(recipe.isOnlyComponents(dish: mix, database: db))
        #expect((170...180).contains(mix.perServing.kilocalories))
    }

    @Test func eachGramCountsWhenAdjusted() throws {
        let mix = try #require(db.food(id: "seed_nut_mix"))
        let recipe = try #require(DishRecipes.recipe(for: "seed_nut_mix"))
        let almonds = try #require(db.food(id: "almonds"))
        var amounts = recipe.typicalAmounts
        amounts["almonds"] = 10
        amounts["pista"] = 0
        let result = recipe.result(amounts: amounts, dish: mix, database: db)
        #expect(!result.isTypical)
        #expect(abs(result.grams - 34) < 0.001)
        let pista = try #require(db.food(id: "pistachios"))
        let expected = mix.perServing.kilocalories + almonds.nutrients(for: .grams(5)).kilocalories - pista.nutrients(for: .grams(1)).kilocalories
        #expect(abs(result.nutrients.kilocalories - expected) < 0.2)
        #expect(!result.summary.contains("pista"))
        #expect(result.summary.contains("10 g almonds"))
        #expect(db.search("seed mix").first?.id == "seed_nut_mix")
    }
}
