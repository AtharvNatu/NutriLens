import Foundation
import Testing
@testable import NutriCore

@Suite("Dishes from ingredients and templates")
struct IngredientDishTests {
    let db = NutritionDatabase.bundled

    func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.5) -> Bool { abs(a - b) <= tolerance }

    @Test func soyaPulaoFromADescription() throws {
        let result = IngredientParser.parse("150 g cooked white rice, 50 g veggies, 65 g soya chunks and 2 tsp oil", database: db)
        #expect(result.unmatched.isEmpty)
        #expect(result.items.map(\.foodID) == ["white_rice", "mixed_veg_raw", "soya_chunks_boiled", "oil"])
        #expect(result.items.map(\.grams) == [150, 50, 65, 10])
        let dish = IngredientDish(name: "Soya pulao", items: result.items)
        // 195 + 21.5 + 74.75 + 88.4 kcal; protein 4.05 + 1.15 + 11.05.
        #expect(close(dish.nutrients.kilocalories, 379.7))
        #expect(close(dish.nutrients.protein, 16.25, 0.05))
        #expect(dish.grams == 275)
        let food = dish.foodItem()
        #expect(food.name == "Soya pulao")
        #expect(close(food.perServing.kilocalories, dish.nutrients.kilocalories, 0.01))
        #expect(food.servingDescription == "1 dish")
        #expect(food.notes == "From your ingredients: 150 g rice, 65 g soya chunks, 50 g mixed vegetables, 2 tsp cooking oil.")
    }

    @Test func amountsWrittenInOtherWays() {
        func first(_ text: String) -> IngredientDish.Item? { IngredientParser.parse(text, database: db).items.first }
        #expect(first("2 eggs")?.grams == 100)
        #expect(first("2 eggs")?.foodID == "egg")
        #expect(first("rice 150 g")?.grams == 150)
        #expect(first("150g paneer")?.foodID == "paneer")
        #expect(first("150g paneer")?.grams == 150)
        #expect(first("½ katori boiled soya chunks")?.grams == 75)
        #expect(first("1 tbsp ghee")?.foodID == "ghee")
        // No amount: one serving.
        #expect(first("dal tadka")?.grams == db.food(id: "dal_tadka")?.servingGrams)
        #expect(IngredientParser.parse("150 g unobtainium", database: db).unmatched == ["150 g unobtainium"])
    }

    @Test func templateKeepsTheDishsValuesThenTakesYourChanges() throws {
        let pulao = try #require(db.food(id: "veg_biryani"))
        var dish = IngredientDish.template(for: pulao, database: db)
        #expect(dish.items.map(\.foodID) == ["white_rice", "mixed_veg_raw", "oil", nil])
        #expect(close(dish.nutrients.kilocalories, pulao.perServing.kilocalories, 1))
        #expect(close(dish.grams, pulao.servingGrams, 1))
        // Your version: 150 g rice and 65 g boiled soya chunks.
        dish.items[0].grams = 150
        dish.items += IngredientParser.parse("65 g soya chunks", database: db).items
        #expect(close(dish.nutrients.protein, pulao.perServing.protein - 0.54 + 11.05, 0.1))
    }

    @Test func dishWithoutRecipeStartsAsOneServing() throws {
        let biryani = try #require(db.food(id: "chicken_biryani"))
        let dish = IngredientDish.template(for: biryani, database: db)
        #expect(dish.items.count == 1)
        #expect(dish.grams == biryani.servingGrams)
    }

    @Test func recipeIngredientsBecomeEditable() throws {
        let recipe = try #require(ProteinRecipes.all.first { $0.id == "soya_chunks_masala" })
        let dish = IngredientDish.from(recipe, database: db)
        let n = recipe.nutrition(database: db)
        #expect(close(dish.nutrients.kilocalories, n.nutrients.kilocalories, 0.01))
        #expect(dish.items.contains { $0.foodID == "soya_chunks_boiled" && $0.grams == 120 })
    }

    @Test func proteinCanBeAddedToEveryCookedDish() throws {
        let subji = try #require(db.food(id: "mixed_veg"))
        let recipe = try #require(DishRecipes.recipe(for: subji))
        #expect(recipe.components.allSatisfy { $0.isAddIn })
        let plain = recipe.result(amounts: [:], dish: subji, database: db)
        #expect(plain.isTypical)
        #expect(plain.summary.isEmpty)
        let withSoya = recipe.result(amounts: ["add.soya": 65], dish: subji, database: db)
        #expect(withSoya.summary == "65 g soya chunks")
        #expect(close(withSoya.nutrients.protein, subji.perServing.protein + 11.05, 0.01))
        // Basic ingredients don't get add-ins; dishes that already have the food don't get it twice.
        let egg = try #require(db.food(id: "egg"))
        #expect(DishRecipes.recipe(for: egg) == nil)
        let palak = try #require(db.food(id: "palak_paneer"))
        let paneerDish = try #require(DishRecipes.recipe(for: palak))
        #expect(paneerDish.components.filter { $0.foodID == "paneer" }.count == 1)
    }

    @Test func eggHalfFryTakesYourEggsAndOil() throws {
        let fry = try #require(db.food(id: "egg_half_fry"))
        #expect(db.search("sunny side up").first?.id == "egg_half_fry")
        #expect(db.search("half fry").first?.id == "egg_half_fry")
        let recipe = try #require(DishRecipes.recipe(for: fry))
        let two = recipe.result(amounts: ["main": 2, "fat": 1], dish: fry, database: db)
        #expect(two.summary == "2 eggs, 1 tsp oil")
        #expect(close(two.nutrients.protein, 13, 0.05))
        #expect(close(two.nutrients.kilocalories, 143 + 44.2, 0.1))
    }

    @Test func soyaChunksAreBoiled() throws {
        #expect(db.food(id: "soya_chunks") == nil)
        let soya = try #require(db.search("soya chunks").first)
        #expect(soya.id == "soya_chunks_boiled")
        // A third of the dry values (51 g protein per 100 g dry).
        #expect(soya.per100g.protein == 17)
    }

    @Test func dictatedDishWithItsName() throws {
        let said = "Chicken keema with 250 grams of raw chicken, 2 eggs, 100 grams veggies and 2 teaspoons oil."
        let (name, result) = IngredientParser.parseDish(said, database: db)
        #expect(name == "Chicken keema")
        #expect(result.unmatched.isEmpty)
        #expect(result.items.map(\.foodID) == ["chicken_raw", "egg", "mixed_veg_raw", "oil"])
        #expect(result.items.map(\.grams) == [250, 100, 100, 10])
        let dish = IngredientDish(name: name ?? "", items: result.items)
        // 250 g raw chicken (67.5 g protein) + 2 eggs (13 g) + veggies (2.3 g).
        #expect(close(dish.nutrients.protein, 82.8, 0.05))
        #expect(dish.grams == 460)
    }

    @Test func otherWaysOfNamingTheDish() {
        #expect(IngredientParser.parseDish("The dish name is soya pulao. It has 150 g rice and 65 g soya chunks", database: db).name == "Soya pulao")
        #expect(IngredientParser.parseDish("Poha: 60 g poha, 1 tsp oil", database: db).name == "Poha")
        let unnamed = IngredientParser.parseDish("150 g rice, 2 eggs", database: db)
        #expect(unnamed.name == nil)
        #expect(unnamed.result.items.count == 2)
        let sentence = IngredientParser.parseDish("Egg bhurji contains 3 eggs. It also has 1.5 tsp oil", database: db)
        #expect(sentence.name == "Egg bhurji")
        #expect(sentence.result.items.map(\.grams) == [150, 7.5])
    }

    @Test func liquidsInMillilitres() throws {
        let milk = try #require(db.food(id: "buffalo_milk"))
        #expect(milk.millilitreGrams == 1)
        #expect(db.food(id: "oil")?.millilitreGrams == 0.92)
        #expect(db.food(id: "chai")?.millilitreGrams == 1)        // drinks are stored per 100 ml
        #expect(db.food(id: "paneer")?.millilitreGrams == nil)
        let parsed = IngredientParser.parse("200 ml buffalo milk, 10 ml oil, 0.5 l buttermilk", database: db).items
        #expect(parsed.map(\.foodID) == ["buffalo_milk", "oil", "buttermilk"])
        #expect(parsed.map { ($0.grams * 10).rounded() / 10 } == [200, 9.2, 500])
        #expect(IngredientDish(name: "x", items: [parsed[0]]).summary == "200 ml buffalo milk")
    }

    @Test func chitaleBuffaloMilkFollowsThePack() throws {
        let milk = try #require(db.food(id: "buffalo_milk"))
        // Chitale full cream (buffalo) milk, per 100 ml.
        #expect(milk.per100g == Nutrients(kilocalories: 94, protein: 3.8, carbohydrates: 5.2, fat: 6.4))
        #expect(db.search("chitale").first?.id == "buffalo_milk")
    }

    @Test func dailyCoffeeTakesTheMilkYouPour() throws {
        let coffee = try #require(db.food(id: "coffee_buffalo_milk"))
        #expect(coffee.name == "Coffee")
        #expect(db.search("coffee").first?.id == "coffee_buffalo_milk")
        let recipe = try #require(DishRecipes.recipe(for: coffee))
        #expect(recipe.components.map(\.id) == ["milk", "coffee"])
        let typical = recipe.result(amounts: [:], dish: coffee, database: db)
        #expect(typical.summary == "120 ml milk, 5 g coffee")
        // 120 ml milk (112.8 kcal, 4.56 g protein) + 5 g coffee powder (17.65 kcal, 0.61 g) + a spoon of water.
        #expect(close(typical.nutrients.kilocalories, 130.45, 0.2))
        #expect(close(typical.nutrients.protein, 5.17, 0.02))
        let small = recipe.result(amounts: ["milk": 80], dish: coffee, database: db)
        #expect(small.summary == "80 ml milk, 5 g coffee")
        #expect(close(small.nutrients.kilocalories, 130.45 - 37.6, 0.2))
        #expect(close(small.nutrients.fat, 7.705 - 2.56, 0.02))
    }
}
