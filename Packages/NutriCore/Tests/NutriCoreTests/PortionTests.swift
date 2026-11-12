import Testing
@testable import NutriCore

@Suite("Portion scaling")
struct PortionTests {
    /// 200 kcal, 10 g protein, 20 g carbs, 8 g fat per 100 g; a serving is 150 g.
    let food = FoodItem(
        id: "test",
        name: "Test food",
        per100g: Nutrients(kilocalories: 200, protein: 10, carbohydrates: 20, fat: 8),
        servingGrams: 150,
        servingDescription: "1 bowl"
    )

    @Test func hundredGramsEqualsTableValues() {
        #expect(food.nutrients(for: .grams(100)) == food.per100g)
    }

    @Test func gramsScaleLinearly() {
        let n = food.nutrients(for: .grams(250))
        #expect(n == Nutrients(kilocalories: 500, protein: 25, carbohydrates: 50, fat: 20))
    }

    @Test func oneServingUsesServingWeight() {
        let n = food.nutrients(for: .servings(1))
        #expect(n == Nutrients(kilocalories: 300, protein: 15, carbohydrates: 30, fat: 12))
        #expect(food.perServing == n)
    }

    @Test func fractionalServings() {
        let half = food.nutrients(for: .servings(0.5))
        #expect(half.kilocalories == 150)
        let oneAndHalf = food.nutrients(for: .servings(1.5))
        #expect(oneAndHalf.kilocalories == 450)
        #expect(oneAndHalf.fat == 18)
    }

    @Test func gramsAndServingsAgree() {
        #expect(food.nutrients(for: .servings(2)) == food.nutrients(for: .grams(300)))
        #expect(Portion.grams(300).servings(for: food) == 2)
        #expect(Portion.servings(2).grams(for: food) == 300)
    }

    @Test(arguments: [Portion.grams(0), .servings(0), .grams(-50), .servings(-1), .grams(.nan), .servings(.infinity)])
    func emptyOrInvalidPortionsGiveZero(portion: Portion) {
        #expect(food.nutrients(for: portion) == .zero)
    }

    @Test func zeroWeightServingIsZeroServings() {
        var weird = food
        weird.servingGrams = 0
        #expect(Portion.grams(100).servings(for: weird) == 0)
    }

    @Test func servingLabelShowsGrams() {
        #expect(food.servingLabel == "1 bowl (150 g)")
    }

    @Test func realTablePizzaSlice() throws {
        let db = try NutritionDatabase.loadBundled()
        let pizza = try #require(db.food(id: "pizza"))
        // 107 g slice at 266 kcal / 100 g = 284.62 kcal.
        let twoSlices = pizza.nutrients(for: .servings(2))
        #expect(abs(twoSlices.kilocalories - 569.24) < 0.001)
        #expect(abs(twoSlices.protein - 23.54) < 0.001)
    }

    @Test(arguments: [(0.1, 0.25), (0.6, 0.5), (0.63, 0.75), (1.1, 1.0), (2.9, 3.0), (Double.nan, 1.0)])
    func servingRounding(input: Double, expected: Double) {
        #expect(PortionPresets.roundedServings(input) == expected)
    }

    @Test func nutrientArithmetic() {
        let a = Nutrients(kilocalories: 100, protein: 1, carbohydrates: 2, fat: 3)
        let b = Nutrients(kilocalories: 50, protein: 4, carbohydrates: 5, fat: 6)
        #expect(a + b == Nutrients(kilocalories: 150, protein: 5, carbohydrates: 7, fat: 9))
        #expect([a, b, a].total().kilocalories == 250)
        #expect([Nutrients]().total() == .zero)
        #expect(a.scaled(by: -2) == .zero)
    }

    @Test func macroEnergySplit() {
        // 25 g protein (100 kcal), 25 g carbs (100 kcal), ~22.2 g fat (200 kcal) -> 25 / 25 / 50 %.
        let n = Nutrients(kilocalories: 400, protein: 25, carbohydrates: 25, fat: 200.0 / 9)
        let split = n.macroEnergySplit
        #expect(abs(split.protein - 0.25) < 1e-9)
        #expect(abs(split.carbohydrates - 0.25) < 1e-9)
        #expect(abs(split.fat - 0.5) < 1e-9)
        #expect(Nutrients.zero.macroEnergySplit == (0, 0, 0))
    }
}
