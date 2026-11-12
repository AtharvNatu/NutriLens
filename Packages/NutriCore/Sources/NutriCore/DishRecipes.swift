import Foundation

/// One adjustable ingredient of a dish, such as the eggs in egg bhurji or the oil it's cooked in.
public struct RecipeComponent: Hashable, Sendable, Identifiable {
    /// Key used when remembering your amounts ("main", "whites", "fat").
    public var id: String
    /// Food in the nutrition table that this ingredient is.
    public var foodID: String
    /// "Eggs", "Paneer", "Oil or ghee".
    public var label: String
    /// Unit names, e.g. "egg" / "eggs", "g" / "g", "tsp" / "tsp".
    public var unit: String
    public var unitPlural: String
    /// Grams in one unit (50 g per egg, 5 g per teaspoon of oil, 1 for grams).
    public var gramsPerUnit: Double
    /// Amount in the dish's typical serving.
    public var typical: Double
    public var range: ClosedRange<Double>
    public var step: Double
    /// Words after the amount in the dish name, e.g. "paneer" in "100 g paneer"; empty for counted units.
    public var noun: String
    /// Something you can add that the dish doesn't usually have (soya chunks in a veg pulao). Typical is 0,
    /// and it's offered under "Add protein" rather than shown as a row.
    public var isAddIn: Bool
    /// Amount filled in when you add it.
    public var addAmount: Double

    public init(id: String, foodID: String, label: String, unit: String, unitPlural: String, gramsPerUnit: Double,
                typical: Double, range: ClosedRange<Double>, step: Double, noun: String = "", isAddIn: Bool = false,
                addAmount: Double = 0) {
        self.id = id
        self.foodID = foodID
        self.label = label
        self.unit = unit
        self.unitPlural = unitPlural
        self.gramsPerUnit = gramsPerUnit
        self.typical = typical
        self.range = range
        self.step = step
        self.noun = noun
        self.isAddIn = isAddIn
        self.addAmount = addAmount
    }

    /// "3 eggs", "1.5 tsp oil", "100 g paneer".
    public func describe(_ amount: Double) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)))
        let unitText = amount == 1 ? unit : unitPlural
        return noun.isEmpty ? "\(number) \(unitText)" : "\(number) \(unitText) \(noun)"
    }

    /// "3 eggs", "5 g": the amount alone, for a row that already names the ingredient.
    public func amountText(_ amount: Double) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)))
        return "\(number) \(amount == 1 ? unit : unitPlural)"
    }

    public func clamped(_ amount: Double) -> Double {
        guard amount.isFinite else { return typical }
        return min(max(amount, range.lowerBound), range.upperBound)
    }
}

/// A dish whose main protein source and cooking fat you can set, e.g. egg bhurji with 3 eggs and 1 tsp oil.
///
/// The rest of the dish (onion, tomato, masala or gravy) is worked out from the dish's typical serving minus
/// its typical ingredients, and stays one portion's worth whatever amounts you choose. So the typical amounts
/// give exactly the dish's usual values, and each extra egg adds one egg's nutrition.
public struct DishRecipe: Hashable, Sendable {
    public var dishID: String
    public var components: [RecipeComponent]

    public init(dishID: String, components: [RecipeComponent]) {
        self.dishID = dishID
        self.components = components
    }

    /// True when the whole dish is made of the adjustable ingredients (a seed and nut mix), so there's no "rest of the dish".
    public func isOnlyComponents(dish: FoodItem, database: NutritionDatabase) -> Bool {
        base(dish: dish, database: database).grams < 0.5
    }

    public var typicalAmounts: [String: Double] {
        Dictionary(uniqueKeysWithValues: components.map { ($0.id, $0.typical) })
    }

    /// What one portion with these amounts contains.
    public struct Result: Equatable, Sendable {
        public var nutrients: Nutrients
        public var grams: Double
        /// "3 eggs, 1 tsp oil"
        public var summary: String
        /// Whether every amount is the typical one.
        public var isTypical: Bool
    }

    /// The dish apart from the adjustable ingredients, for one typical serving (never negative).
    public func base(dish: FoodItem, database: NutritionDatabase) -> (nutrients: Nutrients, grams: Double) {
        var nutrients = dish.perServing
        var grams = dish.servingGrams
        for component in components {
            guard let food = database.food(id: component.foodID) else { continue }
            let g = component.typical * component.gramsPerUnit
            let part = food.nutrients(for: .grams(g))
            nutrients = Nutrients(kilocalories: nutrients.kilocalories - part.kilocalories, protein: nutrients.protein - part.protein,
                                  carbohydrates: nutrients.carbohydrates - part.carbohydrates, fat: nutrients.fat - part.fat)
            grams -= g
        }
        return (Nutrients(kilocalories: max(0, nutrients.kilocalories), protein: max(0, nutrients.protein),
                          carbohydrates: max(0, nutrients.carbohydrates), fat: max(0, nutrients.fat)), max(0, grams))
    }

    /// One portion made with `amounts` (missing amounts use the typical ones).
    public func result(amounts: [String: Double], dish: FoodItem, database: NutritionDatabase) -> Result {
        var (nutrients, grams) = base(dish: dish, database: database)
        var parts: [String] = []
        var isTypical = true
        for component in components {
            let amount = component.clamped(amounts[component.id] ?? component.typical)
            if abs(amount - component.typical) > 0.001 { isTypical = false }
            if amount > 0 { parts.append(component.describe(amount)) }
            guard let food = database.food(id: component.foodID) else { continue }
            let g = amount * component.gramsPerUnit
            nutrients = nutrients + food.nutrients(for: .grams(g))
            grams += g
        }
        if parts.isEmpty, let main = components.first, !main.isAddIn { parts.append(main.describe(0)) }
        return Result(nutrients: nutrients, grams: grams, summary: parts.joined(separator: ", "), isTypical: isTypical)
    }

    /// The dish as a food whose one serving is your version, so the usual portion maths (servings, grams) apply.
    public func customized(_ dish: FoodItem, amounts: [String: Double], database: NutritionDatabase) -> FoodItem {
        let r = result(amounts: amounts, dish: dish, database: database)
        guard !r.isTypical, r.grams > 0 else { return dish }
        var food = dish
        food.per100g = r.nutrients.scaled(by: 100 / r.grams)
        food.servingGrams = r.grams
        food.servingDescription = "1 portion (\(r.summary))"
        return food
    }
}

/// The dishes you can make your way.
public enum DishRecipes {
    /// Protein you can add to a dish that doesn't usually have it (boiled soya chunks in a pulao or a subji).
    public static let proteinAddIns: [RecipeComponent] = [
        addIn("soya", "soya_chunks_boiled", "Soya chunks (boiled)", noun: "soya chunks", start: 50, upTo: 300, step: 5),
        addIn("paneer", "paneer", "Paneer", noun: "paneer", start: 50, upTo: 300, step: 10),
        addIn("tofu", "tofu", "Tofu", noun: "tofu", start: 75, upTo: 300, step: 25),
        RecipeComponent(id: "add.egg", foodID: "egg", label: "Eggs", unit: "egg", unitPlural: "eggs", gramsPerUnit: 50,
                        typical: 0, range: 0...6, step: 1, isAddIn: true, addAmount: 1),
        addIn("chicken", "chicken_cooked", "Chicken (cooked)", noun: "chicken", start: 75, upTo: 400, step: 25),
        addIn("peas", "green_peas", "Green peas", noun: "peas", start: 40, upTo: 200, step: 10),
    ]

    static func addIn(_ key: String, _ foodID: String, _ label: String, noun: String, start: Double, upTo: Double, step: Double) -> RecipeComponent {
        RecipeComponent(id: "add." + key, foodID: foodID, label: label, unit: "g", unitPlural: "g", gramsPerUnit: 1,
                        typical: 0, range: 0...upTo, step: step, noun: noun, isAddIn: true, addAmount: start)
    }

    /// Dish categories that take protein add-ins.
    static let addInCategories: Set<String> = ["main", "rice", "breakfast", "dal", "nonveg"]

    /// The recipe for a food: its own adjustable ingredients plus protein add-ins, or add-ins alone for other
    /// cooked dishes (a subji, upma or khichdi). nil for single ingredients and packaged foods.
    public static func recipe(for food: FoodItem) -> DishRecipe? {
        let own = byDish[food.id]
        // Your own dishes already list what's in them.
        guard addInCategories.contains(food.category), own?.dishID != "seed_nut_mix", food.region != "custom", !food.isCustom else { return own }
        var recipe = own ?? DishRecipe(dishID: food.id, components: [])
        let existing = Set(recipe.components.map(\.foodID))
        recipe.components += proteinAddIns.filter { !existing.contains($0.foodID) }
        return recipe
    }

    static func eggs(_ typical: Double) -> RecipeComponent {
        RecipeComponent(id: "main", foodID: "egg", label: "Whole eggs", unit: "egg", unitPlural: "eggs", gramsPerUnit: 50,
                        typical: typical, range: 0...12, step: 1)
    }

    static let whites = RecipeComponent(id: "whites", foodID: "egg_white", label: "Extra egg whites", unit: "egg white", unitPlural: "egg whites",
                                        gramsPerUnit: 33, typical: 0, range: 0...12, step: 1)

    static func rice(_ typical: Double) -> RecipeComponent {
        grams("white_rice", "Rice (cooked)", noun: "rice", typical: typical, upTo: 500, step: 10, id: "rice")
    }

    static func vegetables(_ typical: Double) -> RecipeComponent {
        grams("mixed_veg_raw", "Vegetables", noun: "vegetables", typical: typical, upTo: 300, step: 10, id: "veg")
    }

    static func grams(_ foodID: String, _ label: String, noun: String, typical: Double, upTo: Double, step: Double,
                      id: String = "main") -> RecipeComponent {
        RecipeComponent(id: id, foodID: foodID, label: label, unit: "g", unitPlural: "g", gramsPerUnit: 1,
                        typical: typical, range: 0...upTo, step: step, noun: noun)
    }

    static func oil(_ typical: Double) -> RecipeComponent {
        RecipeComponent(id: "fat", foodID: "oil", label: "Oil or ghee", unit: "tsp", unitPlural: "tsp", gramsPerUnit: 5,
                        typical: typical, range: 0...8, step: 0.5, noun: "oil")
    }

    public static let all: [DishRecipe] = [
        DishRecipe(dishID: "egg_bhurji", components: [eggs(2), whites, oil(1.5)]),
        DishRecipe(dishID: "masala_omelette", components: [eggs(2), whites, oil(1.5)]),
        DishRecipe(dishID: "egg_curry", components: [eggs(2), oil(2)]),
        DishRecipe(dishID: "paneer_bhurji", components: [grams("paneer", "Paneer", noun: "paneer", typical: 75, upTo: 400, step: 25), oil(1)]),
        DishRecipe(dishID: "tofu_bhurji", components: [grams("tofu", "Tofu", noun: "tofu", typical: 100, upTo: 400, step: 25), oil(1)]),
        DishRecipe(dishID: "palak_paneer", components: [grams("paneer", "Paneer", noun: "paneer", typical: 50, upTo: 400, step: 25), oil(1)]),
        DishRecipe(dishID: "kadai_paneer", components: [grams("paneer", "Paneer", noun: "paneer", typical: 60, upTo: 400, step: 10), oil(1.5)]),
        DishRecipe(dishID: "paneer_butter_masala", components: [grams("paneer", "Paneer", noun: "paneer", typical: 50, upTo: 400, step: 25), oil(2)]),
        DishRecipe(dishID: "soya_chunk_curry", components: [grams("soya_chunks_boiled", "Soya chunks (boiled)", noun: "soya chunks",
                                                                  typical: 75, upTo: 300, step: 5), oil(1.5)]),
        DishRecipe(dishID: "chicken_curry", components: [grams("chicken_cooked", "Chicken (cooked weight)", noun: "chicken",
                                                               typical: 100, upTo: 500, step: 25), oil(3)]),
        DishRecipe(dishID: "chicken_rassa", components: [grams("chicken_cooked", "Chicken (cooked weight)", noun: "chicken",
                                                               typical: 100, upTo: 500, step: 25), oil(3)]),
        DishRecipe(dishID: "egg_half_fry", components: [eggs(1), oil(0.5)]),
        // Your daily coffee: 5 g powder in a spoon of water, topped with Chitale buffalo milk (set each cup).
        DishRecipe(dishID: "coffee_buffalo_milk", components: [
            RecipeComponent(id: "milk", foodID: "buffalo_milk", label: "Buffalo milk", unit: "ml", unitPlural: "ml", gramsPerUnit: 1,
                            typical: 120, range: 0...400, step: 10, noun: "milk"),
            grams("instant_coffee_powder", "Coffee powder", noun: "coffee", typical: 5, upTo: 20, step: 1, id: "coffee"),
        ]),
        DishRecipe(dishID: "egg_full_fry", components: [eggs(1), oil(0.5)]),
        // Rice dishes: set the rice, vegetables and oil, and add protein (a soya pulao is veg pulao + boiled soya chunks).
        DishRecipe(dishID: "veg_biryani", components: [rice(170), vegetables(50), oil(2)]),
        DishRecipe(dishID: "veg_fried_rice", components: [rice(170), vegetables(50), oil(2.5)]),
        DishRecipe(dishID: "jeera_rice", components: [rice(145), oil(1)]),
        // Your daily seeds and nuts, every part adjustable to the gram.
        DishRecipe(dishID: "seed_nut_mix", components: [
            grams("pumpkin_seeds", "Pumpkin seeds", noun: "pumpkin", typical: 5, upTo: 50, step: 1, id: "pumpkin"),
            grams("sunflower_seeds", "Sunflower seeds", noun: "sunflower", typical: 5, upTo: 50, step: 1, id: "sunflower"),
            grams("watermelon_seeds", "Watermelon seeds", noun: "watermelon", typical: 5, upTo: 50, step: 1, id: "watermelon"),
            grams("almonds", "Almonds", noun: "almonds", typical: 5, upTo: 50, step: 1, id: "almonds"),
            grams("pistachios", "Pista", noun: "pista", typical: 1, upTo: 50, step: 1, id: "pista"),
            grams("walnuts", "Walnuts", noun: "walnuts", typical: 4, upTo: 50, step: 1, id: "walnuts"),
            grams("cashews", "Cashews", noun: "cashews", typical: 5, upTo: 50, step: 1, id: "cashews"),
        ]),
    ]

    private static let byDish = Dictionary(uniqueKeysWithValues: all.map { ($0.dishID, $0) })

    public static func recipe(for dishID: String) -> DishRecipe? { byDish[dishID] }
}
