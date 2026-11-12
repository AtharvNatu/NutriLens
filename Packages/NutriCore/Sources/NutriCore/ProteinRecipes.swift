import Foundation

/// A quick, protein-rich home recipe for one person, ready in 30 minutes or less.
///
/// Nutrition is the sum of the weighed ingredients from the food table (spices, lemon and herbs are left out:
/// they add next to nothing), so it stays in step with the table.
public struct ProteinRecipe: Identifiable, Hashable, Sendable {
    public enum Meal: String, CaseIterable, Sendable, Identifiable {
        case breakfast, lunch, snack, dinner
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
    }

    public enum Diet: String, CaseIterable, Sendable, Identifiable {
        case veg, egg, nonVeg
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .veg: "Veg"
            case .egg: "Egg"
            case .nonVeg: "Non-veg"
            }
        }
    }

    public struct Ingredient: Hashable, Sendable {
        /// As you'd measure it: "3 eggs", "1 small onion, chopped".
        public var text: String
        /// Food in the table, or nil for spices and other trace ingredients.
        public var foodID: String?
        public var grams: Double

        public init(_ text: String, _ foodID: String? = nil, grams: Double = 0) {
            self.text = text
            self.foodID = foodID
            self.grams = grams
        }
    }

    public var id: String
    public var name: String
    /// One line on what it is.
    public var summary: String
    public var meals: [Meal]
    public var diet: Diet
    /// Hands-on plus cooking time.
    public var minutes: Int
    /// Anything to do beforehand that isn't counted (soaking, boiling chana).
    public var ahead: String?
    public var ingredients: [Ingredient]
    public var steps: [String]
    public var tip: String?

    /// One serving's nutrition and weight.
    public func nutrition(database: NutritionDatabase) -> (nutrients: Nutrients, grams: Double) {
        var total = Nutrients.zero
        var grams = 0.0
        for item in ingredients {
            guard let id = item.foodID, let food = database.food(id: id) else { continue }
            total = total + food.nutrients(for: .grams(item.grams))
            grams += item.grams
        }
        return (total, grams)
    }

    /// The recipe as a food, so it can be logged with the usual portion maths (1 serving = the whole recipe).
    public func foodItem(database: NutritionDatabase) -> FoodItem {
        let (nutrients, grams) = nutrition(database: database)
        let g = max(grams, 1)
        return FoodItem(id: Self.foodPrefix + id, name: name, category: "main", per100g: nutrients.scaled(by: 100 / g),
                        servingGrams: g, servingDescription: "1 serving (this recipe)", region: "recipe",
                        notes: "Worked out from the recipe's ingredients.")
    }

    public static let foodPrefix = "recipe."
}

public enum ProteinRecipes {
    typealias I = ProteinRecipe.Ingredient

    public static let all: [ProteinRecipe] = [
        // MARK: Breakfast
        ProteinRecipe(
            id: "egg_bhurji_toast", name: "Egg bhurji on toast",
            summary: "Soft scrambled masala eggs on brown bread.",
            meals: [.breakfast], diet: .egg, minutes: 15,
            ingredients: [
                I("3 eggs", "egg", grams: 150), I("1 small onion, chopped", "onion_raw", grams: 40),
                I("1 small tomato, chopped", "tomato_raw", grams: 40), I("1 tsp oil", "oil", grams: 5),
                I("2 slices brown bread", "brown_bread", grams: 64),
                I("1 green chilli, turmeric, salt, coriander"),
            ],
            steps: [
                "Heat the oil, fry the onion and chilli for 2–3 minutes until soft.",
                "Add the tomato, a pinch of turmeric and salt; cook 2 minutes until mushy.",
                "Pour in the beaten eggs and stir on low heat until just set, about 2 minutes.",
                "Finish with coriander and serve on toasted bread.",
            ],
            tip: "Swap one whole egg for two whites to cut fat and keep the protein."
        ),
        ProteinRecipe(
            id: "paneer_besan_chilla", name: "Besan chilla with paneer",
            summary: "Savoury gram-flour pancakes filled with crumbled paneer.",
            meals: [.breakfast, .dinner], diet: .veg, minutes: 20,
            ingredients: [
                I("5 tbsp besan", "besan", grams: 50), I("50 g paneer, crumbled", "paneer", grams: 50),
                I("2 tbsp chopped onion", "onion_raw", grams: 20), I("2 tbsp chopped tomato", "tomato_raw", grams: 20),
                I("1 tsp oil", "oil", grams: 5), I("Ajwain, chilli, turmeric, salt, about 1/3 cup water"),
            ],
            steps: [
                "Whisk the besan with the spices and water into a pouring batter; stir in the onion and tomato.",
                "Spread half the batter thin on a hot greased tawa; cook 2 minutes a side.",
                "Scatter half the paneer on top, fold and press. Repeat for the second chilla.",
            ],
            tip: "Eat with a katori of curd for another 3–4 g of protein."
        ),
        ProteinRecipe(
            id: "peanut_butter_oats", name: "Peanut butter banana oats",
            summary: "Creamy oats cooked in milk with chia, banana and peanut butter.",
            meals: [.breakfast], diet: .veg, minutes: 10,
            ingredients: [
                I("1/2 cup rolled oats", "oats_rolled", grams: 40), I("1 glass milk", "milk_cow", grams: 250),
                I("1 tbsp peanut butter", "peanut_butter", grams: 16), I("1 tbsp chia seeds", "chia_seeds", grams: 10),
                I("1/2 banana, sliced", "banana", grams: 60), I("Pinch of cinnamon"),
            ],
            steps: [
                "Simmer the oats in the milk for 4–5 minutes, stirring, until thick.",
                "Stir in the chia seeds and cinnamon; rest 1 minute.",
                "Top with the banana and peanut butter.",
            ],
            tip: "A scoop of whey stirred in off the heat adds about 23 g protein."
        ),
        ProteinRecipe(
            id: "egg_white_veg_omelette", name: "Egg-white veggie omelette",
            summary: "Two whole eggs plus three whites with spinach and capsicum.",
            meals: [.breakfast, .dinner], diet: .egg, minutes: 15,
            ingredients: [
                I("2 eggs", "egg", grams: 100), I("3 egg whites", "egg_white", grams: 99),
                I("A handful of spinach, chopped", "spinach_raw", grams: 30), I("2 tbsp chopped onion", "onion_raw", grams: 20),
                I("2 tbsp chopped capsicum", "capsicum_raw", grams: 20), I("1 tsp oil", "oil", grams: 5),
                I("1 slice brown bread", "brown_bread", grams: 32), I("Pepper, salt, chilli"),
            ],
            steps: [
                "Beat the eggs and whites with salt and pepper.",
                "Soften the onion, capsicum and spinach in the oil for 2 minutes.",
                "Pour the eggs over, cover and cook on low 3–4 minutes until set; fold and serve with toast.",
            ],
            tip: nil
        ),
        ProteinRecipe(
            id: "chakka_seed_bowl", name: "Hung curd seed bowl",
            summary: "Thick chakka with pumpkin seeds and banana; no cooking.",
            meals: [.breakfast, .snack], diet: .veg, minutes: 5,
            ingredients: [
                I("1 1/2 katori chakka (hung curd)", "chakka", grams: 150), I("1 tbsp pumpkin seeds", "pumpkin_seeds", grams: 10),
                I("1/2 banana, sliced", "banana", grams: 60), I("Cardamom or cinnamon"),
            ],
            steps: [
                "Whisk the chakka smooth with a pinch of cardamom.",
                "Top with the banana and pumpkin seeds.",
            ],
            tip: "No chakka? Hang 300 g curd in a cloth overnight in the fridge."
        ),
        ProteinRecipe(
            id: "moong_sprouts_chaat", name: "Moong sprouts chaat",
            summary: "Tangy sprouted moong with cucumber, tomato and peanuts.",
            meals: [.breakfast, .snack, .lunch], diet: .veg, minutes: 10,
            ahead: "Sprouted moong (or buy ready sprouts).",
            ingredients: [
                I("1 1/2 katori moong sprouts", "moong_sprouts", grams: 150), I("2 tbsp chopped onion", "onion_raw", grams: 30),
                I("1 small tomato, chopped", "tomato_raw", grams: 40), I("1/4 cucumber, chopped", "english_cucumber", grams: 40),
                I("1 tbsp roasted peanuts", "peanuts", grams: 15), I("Lemon, chaat masala, salt, coriander"),
            ],
            steps: [
                "Steam or boil the sprouts for 4–5 minutes until just tender; drain and cool.",
                "Toss with the vegetables, peanuts, lemon juice, chaat masala and salt.",
            ],
            tip: nil
        ),

        // MARK: Lunch and dinner
        ProteinRecipe(
            id: "soya_chunks_masala", name: "Soya chunks masala",
            summary: "Soya chunks in a quick onion-tomato masala.",
            meals: [.lunch, .dinner], diet: .veg, minutes: 25,
            ingredients: [
                I("120 g boiled soya chunks (40 g dry)", "soya_chunks_boiled", grams: 120), I("1 small onion, chopped", "onion_raw", grams: 50),
                I("1 tomato, chopped", "tomato_raw", grams: 60), I("2 tbsp curd", "curd", grams: 30),
                I("1 1/2 tsp oil", "oil", grams: 7), I("Ginger-garlic paste, garam masala, chilli, turmeric, salt"),
            ],
            steps: [
                "Boil the soya chunks in salted water for 5 minutes, then squeeze dry.",
                "Fry the onion in the oil for 4 minutes, add ginger-garlic and spices, then the tomato; cook 4 minutes.",
                "Add the chunks, the curd and a splash of water; simmer 5 minutes.",
            ],
            tip: "Have it with one poli for a balanced plate."
        ),
        ProteinRecipe(
            id: "tofu_palak", name: "Tofu palak",
            summary: "Tofu cubes in a quick spinach gravy.",
            meals: [.lunch, .dinner], diet: .veg, minutes: 25,
            ingredients: [
                I("150 g firm tofu, cubed", "tofu", grams: 150), I("3 cups spinach", "spinach_raw", grams: 150),
                I("1 small onion, chopped", "onion_raw", grams: 40), I("1 small tomato, chopped", "tomato_raw", grams: 40),
                I("1 1/2 tsp oil", "oil", grams: 7), I("Garlic, green chilli, cumin, garam masala, salt"),
            ],
            steps: [
                "Blanch the spinach for 2 minutes, cool and blend with the chilli.",
                "Fry cumin, garlic and onion in the oil for 4 minutes; add the tomato and cook 3 minutes.",
                "Add the spinach purée and spices, simmer 3 minutes, then fold in the tofu and heat through.",
            ],
            tip: "Paneer works the same way (more protein and fat)."
        ),
        ProteinRecipe(
            id: "chicken_capsicum", name: "Chicken capsicum stir-fry",
            summary: "Quick pepper chicken with capsicum and onion.",
            meals: [.lunch, .dinner], diet: .nonVeg, minutes: 20,
            ingredients: [
                I("150 g boneless chicken, sliced", "chicken_raw", grams: 150), I("1 capsicum, sliced", "capsicum_raw", grams: 80),
                I("1 small onion, sliced", "onion_raw", grams: 50), I("1 1/2 tsp oil", "oil", grams: 7),
                I("Ginger-garlic paste, soy sauce, black pepper, salt"),
            ],
            steps: [
                "Toss the chicken with ginger-garlic, pepper and salt.",
                "Sear it in the hot oil for 5–6 minutes until cooked through.",
                "Add the onion and capsicum and stir-fry 3 minutes; finish with a dash of soy sauce.",
            ],
            tip: nil
        ),
        ProteinRecipe(
            id: "kala_chana_salad", name: "Kala chana salad",
            summary: "Boiled black chana with cucumber, tomato and a curd dressing.",
            meals: [.lunch, .snack], diet: .veg, minutes: 10,
            ahead: "Soak and pressure-cook the chana (or use a tin).",
            ingredients: [
                I("1 1/2 katori boiled kala chana", "kala_chana_cooked", grams: 150), I("1/3 cucumber, chopped", "english_cucumber", grams: 60),
                I("1 small tomato, chopped", "tomato_raw", grams: 50), I("2 tbsp chopped onion", "onion_raw", grams: 30),
                I("1/2 katori curd", "curd", grams: 50), I("Lemon, roasted cumin, chaat masala, salt, coriander"),
            ],
            steps: [
                "Whisk the curd with cumin, salt and lemon.",
                "Toss the chana and vegetables in the dressing; top with coriander.",
            ],
            tip: nil
        ),
        ProteinRecipe(
            id: "quick_matar_paneer", name: "Quick matar paneer",
            summary: "Paneer and peas in a light tomato gravy.",
            meals: [.lunch, .dinner], diet: .veg, minutes: 25,
            ingredients: [
                I("100 g paneer, cubed", "paneer", grams: 100), I("1/2 cup green peas", "green_peas", grams: 80),
                I("1 tomato, puréed", "tomato_raw", grams: 80), I("1 small onion, chopped", "onion_raw", grams: 40),
                I("1 1/2 tsp oil", "oil", grams: 7), I("Ginger-garlic paste, cumin, kitchen king or garam masala, salt"),
            ],
            steps: [
                "Fry cumin and onion in the oil for 4 minutes; add ginger-garlic and the spices.",
                "Add the tomato purée and cook 5 minutes until the oil separates.",
                "Add the peas and 1/2 cup water, simmer 5 minutes, then the paneer for 2 minutes.",
            ],
            tip: nil
        ),
        ProteinRecipe(
            id: "moong_dal_khichdi", name: "Moong dal khichdi",
            summary: "One-pot dal and rice, more dal than rice, with curd on the side.",
            meals: [.lunch, .dinner], diet: .veg, minutes: 25,
            ingredients: [
                I("1/3 cup yellow moong dal", "moong_dal", grams: 60), I("3 tbsp rice", "brown_rice_raw", grams: 30),
                I("1 tsp ghee", "ghee", grams: 5), I("1 katori curd, on the side", "curd", grams: 100),
                I("Cumin, turmeric, hing, salt, 2 1/2 cups water"),
            ],
            steps: [
                "Rinse the dal and rice together.",
                "Heat the ghee in a pressure cooker, crackle the cumin and hing, add the dal, rice, turmeric, salt and water.",
                "Cook for 3–4 whistles (about 12 minutes), let the pressure drop and serve with the curd.",
            ],
            tip: "White rice cooks a little faster than brown; the nutrition is close."
        ),
        ProteinRecipe(
            id: "quick_egg_curry", name: "Quick egg curry",
            summary: "Boiled eggs in an onion-tomato gravy.",
            meals: [.lunch, .dinner], diet: .egg, minutes: 25,
            ingredients: [
                I("3 eggs", "egg", grams: 150), I("1 small onion, chopped", "onion_raw", grams: 50),
                I("1 tomato, chopped", "tomato_raw", grams: 80), I("1 1/2 tsp oil", "oil", grams: 7),
                I("Ginger-garlic paste, Kolhapuri or garam masala, turmeric, salt"),
            ],
            steps: [
                "Boil the eggs for 9 minutes, cool and peel; meanwhile fry the onion in the oil for 5 minutes.",
                "Add ginger-garlic, the spices and the tomato; cook 5 minutes until soft.",
                "Add 1/2 cup water and the halved eggs; simmer 4 minutes.",
            ],
            tip: nil
        ),
        ProteinRecipe(
            id: "matki_usal_quick", name: "Matki usal",
            summary: "Sprouted matki in a light Maharashtrian masala, with curd.",
            meals: [.breakfast, .lunch, .dinner], diet: .veg, minutes: 20,
            ahead: "Sprouted matki.",
            ingredients: [
                I("1 1/2 katori matki sprouts", "matki_sprouts", grams: 150), I("1 small onion, chopped", "onion_raw", grams: 40),
                I("1 small tomato, chopped", "tomato_raw", grams: 40), I("1 1/2 tsp oil", "oil", grams: 7),
                I("1 katori curd, on the side", "curd", grams: 100), I("Goda masala, mustard seeds, turmeric, salt, coriander"),
            ],
            steps: [
                "Crackle mustard seeds in the oil, fry the onion 3 minutes, add the tomato and spices.",
                "Add the sprouts and 1 cup water; cover and cook 10 minutes until tender.",
                "Top with coriander; have it with the curd.",
            ],
            tip: nil
        ),
        ProteinRecipe(
            id: "masoor_dal_tadka", name: "Masoor dal tadka",
            summary: "Red lentils pressure-cooked with a garlic-cumin tadka.",
            meals: [.lunch, .dinner], diet: .veg, minutes: 25,
            ingredients: [
                I("1/3 cup masoor dal", "masoor_dal", grams: 60), I("2 tbsp chopped onion", "onion_raw", grams: 30),
                I("1 small tomato, chopped", "tomato_raw", grams: 40), I("1 tsp ghee", "ghee", grams: 5),
                I("Garlic, cumin, red chilli, turmeric, salt"),
            ],
            steps: [
                "Pressure-cook the dal with turmeric, salt and 1 1/2 cups water for 2 whistles (about 8 minutes).",
                "Heat the ghee, crackle cumin and garlic, add the onion and tomato and cook 4 minutes.",
                "Pour the tadka into the dal and simmer 2 minutes.",
            ],
            tip: "Masoor needs no soaking, which keeps it under 30 minutes."
        ),
        ProteinRecipe(
            id: "pan_chicken_tikka", name: "Pan chicken tikka",
            summary: "Curd-marinated chicken seared with onion and capsicum.",
            meals: [.lunch, .dinner], diet: .nonVeg, minutes: 25,
            ahead: "Marinating for an hour or overnight makes it better, but 10 minutes works.",
            ingredients: [
                I("150 g boneless chicken, cubed", "chicken_raw", grams: 150), I("1/2 katori curd", "curd", grams: 50),
                I("1 small onion, in petals", "onion_raw", grams: 40), I("1/2 capsicum, in squares", "capsicum_raw", grams: 40),
                I("1 tsp oil", "oil", grams: 5), I("Ginger-garlic paste, tikka masala or chilli and garam masala, lemon, salt"),
            ],
            steps: [
                "Mix the chicken with the curd, ginger-garlic, spices, lemon and salt; rest 10 minutes.",
                "Sear in the hot oil on a pan for 8–10 minutes, turning, until charred and cooked through.",
                "Add the onion and capsicum for the last 3 minutes.",
            ],
            tip: nil
        ),
    ]

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func recipe(id: String) -> ProteinRecipe? { byID[id] }

    /// Recipes for `meal` (all when nil) and diet, most protein first.
    public static func filtered(meal: ProteinRecipe.Meal?, diets: Set<ProteinRecipe.Diet> = Set(ProteinRecipe.Diet.allCases),
                                database: NutritionDatabase = .bundled) -> [ProteinRecipe] {
        all.filter { (meal == nil || $0.meals.contains(meal!)) && diets.contains($0.diet) }
            .sorted { $0.nutrition(database: database).nutrients.protein > $1.nutrition(database: database).nutrients.protein }
    }
}
