import Foundation
import Testing
@testable import NutriCore

@Suite("Dishes made your way")
struct DishRecipesTests {
    let db = NutritionDatabase.bundled

    func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) <= tolerance }

    @Test func everyRecipeUsesFoodsThatExistAndKeepsAPositiveBase() throws {
        #expect(DishRecipes.all.count == 18)
        // Made only of their adjustable parts (the coffee's spoon of water has no energy).
        let onlyParts: Set = ["seed_nut_mix", "egg_half_fry", "egg_full_fry", "coffee_buffalo_milk"]
        for recipe in DishRecipes.all where !onlyParts.contains(recipe.dishID) {
            let dish = try #require(db.food(id: recipe.dishID), "\(recipe.dishID)")
            for component in recipe.components {
                #expect(db.food(id: component.foodID) != nil, "\(recipe.dishID): \(component.foodID)")
                #expect(component.range.contains(component.typical))
            }
            // The typical ingredients mustn't add up to more than the dish itself (beyond rounding).
            let base = recipe.base(dish: dish, database: db)
            #expect(base.grams > 0, "\(recipe.dishID)")
            #expect(base.nutrients.kilocalories > 5, "\(recipe.dishID)")
        }
    }

    @Test func typicalAmountsGiveTheDishsUsualValues() throws {
        for recipe in DishRecipes.all {
            let dish = try #require(db.food(id: recipe.dishID))
            let result = recipe.result(amounts: [:], dish: dish, database: db)
            #expect(result.isTypical)
            #expect(close(result.grams, dish.servingGrams), "\(recipe.dishID)")
            // Within 0.3 g where a typical ingredient slightly exceeds the dish's value (masala omelette fat).
            #expect(close(result.nutrients.kilocalories, dish.perServing.kilocalories, 3), "\(recipe.dishID)")
            #expect(close(result.nutrients.protein, dish.perServing.protein, 0.3), "\(recipe.dishID)")
            #expect(close(result.nutrients.fat, dish.perServing.fat, 0.3), "\(recipe.dishID)")
            #expect(recipe.customized(dish, amounts: recipe.typicalAmounts, database: db) == dish)
        }
    }

    @Test func eachExtraEggCountsInFull() throws {
        let recipe = try #require(DishRecipes.recipe(for: "egg_bhurji"))
        let dish = try #require(db.food(id: "egg_bhurji"))
        let egg = try #require(db.food(id: "egg")).nutrients(for: .grams(50))
        let two = recipe.result(amounts: [:], dish: dish, database: db)
        let three = recipe.result(amounts: ["main": 3], dish: dish, database: db)
        #expect(close(three.nutrients.protein - two.nutrients.protein, egg.protein))
        #expect(close(three.nutrients.kilocalories - two.nutrients.kilocalories, egg.kilocalories))
        #expect(close(three.grams - two.grams, 50))
        #expect(three.summary == "3 eggs, 1.5 tsp oil")
        #expect(!three.isTypical)

        // Egg whites only, no oil.
        let whites = recipe.result(amounts: ["main": 0, "whites": 4, "fat": 0], dish: dish, database: db)
        #expect(whites.summary == "4 egg whites")
        #expect(whites.nutrients.fat < 1)
        #expect(whites.nutrients.protein > 14)
    }

    @Test func oilOnlyChangesFat() throws {
        let recipe = try #require(DishRecipes.recipe(for: "paneer_bhurji"))
        let dish = try #require(db.food(id: "paneer_bhurji"))
        let usual = recipe.result(amounts: [:], dish: dish, database: db)
        let more = recipe.result(amounts: ["fat": 3], dish: dish, database: db)
        #expect(close(more.nutrients.fat - usual.nutrients.fat, 10))          // 2 tsp × 5 g
        #expect(close(more.nutrients.protein, usual.nutrients.protein))
        #expect(more.summary == "75 g paneer, 3 tsp oil")
        let big = recipe.result(amounts: ["main": 150], dish: dish, database: db)
        #expect(close(big.nutrients.protein - usual.nutrients.protein, 75 * 0.19))
        #expect(big.summary == "150 g paneer, 1 tsp oil")
    }

    @Test func customizedFoodScalesWithServings() throws {
        let recipe = try #require(DishRecipes.recipe(for: "tofu_bhurji"))
        let dish = try #require(db.food(id: "tofu_bhurji"))
        let food = recipe.customized(dish, amounts: ["main": 200], database: db)
        let one = recipe.result(amounts: ["main": 200], dish: dish, database: db)
        #expect(food.id == dish.id)
        #expect(food.servingDescription == "1 portion (200 g tofu, 1 tsp oil)")
        #expect(close(food.perServing.protein, one.nutrients.protein))
        #expect(close(food.nutrients(for: .servings(2)).kilocalories, 2 * one.nutrients.kilocalories))
    }

    @Test func amountsStayInRange() throws {
        let recipe = try #require(DishRecipes.recipe(for: "egg_curry"))
        let dish = try #require(db.food(id: "egg_curry"))
        #expect(recipe.result(amounts: ["main": 40, "fat": -3], dish: dish, database: db).summary == "12 eggs")
        #expect(recipe.result(amounts: ["main": .nan], dish: dish, database: db).isTypical)
    }

    @Test func eggWhiteIsInTheFoodList() throws {
        let white = try #require(db.food(id: "egg_white"))
        #expect(white.servingGrams == 33)
        #expect(db.search("egg white").first?.id == "egg_white")
    }
}
