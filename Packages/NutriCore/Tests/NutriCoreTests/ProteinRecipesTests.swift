import Foundation
import Testing
@testable import NutriCore

@Suite("Quick protein recipes")
struct ProteinRecipesTests {
    let db = NutritionDatabase.bundled

    @Test func everyRecipeIsQuickProteinRichAndComplete() {
        #expect(ProteinRecipes.all.count >= 15)
        #expect(Set(ProteinRecipes.all.map(\.id)).count == ProteinRecipes.all.count)
        for recipe in ProteinRecipes.all {
            #expect(recipe.minutes > 0 && recipe.minutes <= 30, "\(recipe.id)")
            #expect(!recipe.meals.isEmpty && !recipe.steps.isEmpty, "\(recipe.id)")
            for item in recipe.ingredients where item.foodID != nil {
                #expect(db.food(id: item.foodID!) != nil, "\(recipe.id): \(item.foodID!)")
                #expect(item.grams > 0, "\(recipe.id): \(item.text)")
            }
            let n = recipe.nutrition(database: db).nutrients
            #expect(n.protein >= 15, "\(recipe.id) has \(n.protein) g protein")
            #expect((150...800).contains(n.kilocalories), "\(recipe.id) has \(n.kilocalories) kcal")
            // Protein-rich: at least 12 % of the calories from protein.
            #expect(n.protein * 4 / n.kilocalories >= 0.12, "\(recipe.id)")
        }
    }

    @Test func everyMealHasRecipes() {
        for meal in ProteinRecipe.Meal.allCases {
            #expect(ProteinRecipes.filtered(meal: meal).count >= 3, "\(meal)")
        }
        for diet in ProteinRecipe.Diet.allCases {
            #expect(!ProteinRecipes.filtered(meal: nil, diets: [diet]).isEmpty, "\(diet)")
        }
    }

    @Test func nutritionIsTheSumOfIngredients() throws {
        let recipe = try #require(ProteinRecipes.recipe(id: "egg_bhurji_toast"))
        let egg = try #require(db.food(id: "egg"))
        let (n, grams) = recipe.nutrition(database: db)
        #expect(grams == 150 + 40 + 40 + 5 + 64)
        #expect(n.protein > egg.nutrients(for: .grams(150)).protein)
        let food = recipe.foodItem(database: db)
        #expect(food.id == "recipe.egg_bhurji_toast")
        #expect(abs(food.perServing.kilocalories - n.kilocalories) < 0.01)
        #expect(food.servingGrams == grams)
    }

    @Test func sortedByProteinAndFiltered() {
        let veg = ProteinRecipes.filtered(meal: .breakfast, diets: [.veg])
        #expect(veg.allSatisfy { $0.diet == .veg && $0.meals.contains(.breakfast) })
        let proteins = veg.map { $0.nutrition(database: db).nutrients.protein }
        #expect(proteins == proteins.sorted(by: >))
    }

    @Test func namesAreEnglishLettersOnly() {
        let devanagari = try! Regex("[\\u{0900}-\\u{097F}]")
        for r in ProteinRecipes.all {
            let text = [r.name, r.summary, r.ahead ?? "", r.tip ?? ""] + r.steps + r.ingredients.map(\.text)
            #expect(text.allSatisfy { !$0.contains(devanagari) }, "\(r.id)")
        }
    }
}
