import Foundation

/// A dish worked out from what went into it: "150 g cooked rice, 50 g vegetables, 65 g boiled soya chunks, 2 tsp oil".
///
/// Used when a photo guess is wrong or close (a soya pulao recognised as chicken biryani), to change a recipe's
/// ingredients, or to build any home dish. Nutrition is the sum of the ingredients.
public struct IngredientDish: Equatable, Sendable {
    public struct Item: Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var name: String
        /// Food in the table, or nil for "the rest of the dish" taken from a template.
        public var foodID: String?
        public var per100g: Nutrients
        public var grams: Double
        /// Grams in one counted unit (an egg, a teaspoon), for the stepper; 0 when weighed in grams.
        public var unitGrams: Double = 0
        public var unitName: String = ""
        /// Set for liquids (milk, oil), so the amount is shown and typed in ml.
        public var gramsPerMl: Double?

        public init(name: String, foodID: String?, per100g: Nutrients, grams: Double, unitGrams: Double = 0, unitName: String = "",
                    gramsPerMl: Double? = nil) {
            self.name = name
            self.foodID = foodID
            self.per100g = per100g
            self.grams = grams
            self.unitGrams = unitGrams
            self.unitName = unitName
            self.gramsPerMl = gramsPerMl
        }

        public init(food: FoodItem, grams: Double) {
            // Drinks are dishes in a cup; only plain liquids (milk, oil) are typed in ml here.
            self.init(name: food.name, foodID: food.id, per100g: food.per100g, grams: grams,
                      gramsPerMl: food.category == "drink" ? nil : food.gramsPerMl)
        }

        public var nutrients: Nutrients { per100g.scaled(by: max(0, grams) / 100) }
    }

    public var name: String
    public var items: [Item]

    public init(name: String, items: [Item] = []) {
        self.name = name
        self.items = items
    }

    public var grams: Double { items.map { max(0, $0.grams) }.reduce(0, +) }

    public var nutrients: Nutrients { items.map(\.nutrients).reduce(.zero, +) }

    /// "150 g rice, 65 g soya chunks": the ingredients with a food, heaviest first, at most four.
    public var summary: String {
        let parts = items.filter { $0.foodID != nil && $0.grams > 0 }
            .sorted { $0.grams > $1.grams }
            .prefix(4)
            .map { item in
                item.unitGrams > 0 && !item.unitName.isEmpty
                    ? "\(Self.number(item.grams / item.unitGrams)) \(item.unitName) \(Self.shortName(item.name))"
                    : item.gramsPerMl.map { "\(Self.number(item.grams / $0)) ml \(Self.shortName(item.name))" }
                    ?? "\(Self.number(item.grams)) g \(Self.shortName(item.name))"
            }
        return parts.joined(separator: ", ")
    }

    /// The dish as a food whose one serving is everything listed.
    public func foodItem() -> FoodItem {
        let g = max(grams, 1)
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Home-made dish" : name
        return FoodItem(id: Self.foodPrefix + UUID().uuidString, name: title, category: "main", per100g: nutrients.scaled(by: 100 / g),
                        servingGrams: g, servingDescription: "1 dish", region: "custom",
                        notes: summary.isEmpty ? "Worked out from your ingredients." : "From your ingredients: \(summary).")
    }

    public static let foodPrefix = "dish."

    // MARK: Starting points

    /// A dish to start from: its adjustable ingredients at your amounts, plus the rest of the dish (masala, onion,
    /// water) as one item. A dish without a recipe starts as one serving of itself.
    public static func template(for dish: FoodItem, amounts: [String: Double]? = nil, database: NutritionDatabase) -> IngredientDish {
        guard let recipe = DishRecipes.recipe(for: dish), recipe.components.contains(where: { !$0.isAddIn }) else {
            return IngredientDish(name: dish.name, items: [Item(food: dish, grams: dish.servingGrams)])
        }
        var items: [Item] = []
        let base = recipe.base(dish: dish, database: database)
        for component in recipe.components {
            let amount = component.clamped(amounts?[component.id] ?? component.typical)
            guard amount > 0, let food = database.food(id: component.foodID) else { continue }
            var item = Item(food: food, grams: amount * component.gramsPerUnit)
            if component.gramsPerUnit != 1 {
                item.unitGrams = component.gramsPerUnit
                item.unitName = component.unit
            }
            items.append(item)
        }
        if base.grams >= 1 {
            items.append(Item(name: "Rest of the dish (masala, onion…)", foodID: nil,
                              per100g: base.nutrients.scaled(by: 100 / base.grams), grams: base.grams.rounded()))
        }
        return IngredientDish(name: dish.name, items: items)
    }

    /// A recipe's weighed ingredients (spices and other trace ingredients are left out).
    public static func from(_ recipe: ProteinRecipe, database: NutritionDatabase) -> IngredientDish {
        IngredientDish(name: recipe.name, items: recipe.ingredients.compactMap { ingredient in
            guard let id = ingredient.foodID, let food = database.food(id: id), ingredient.grams > 0 else { return nil }
            return Item(name: food.name, foodID: id, per100g: food.per100g, grams: ingredient.grams)
        })
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// "Rice, cooked (bhaat)" → "rice", "Soya chunks (boiled)" → "soya chunks".
    static func shortName(_ name: String) -> String {
        let cut = name.split(separator: "(").first.map(String.init) ?? name
        let first = cut.split(separator: ",").first.map(String.init) ?? cut
        return first.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// Reads a typed description such as "150 g cooked rice, 65 g soya chunks, 2 tsp oil, 2 eggs".
public enum IngredientParser {
    public struct Result: Equatable, Sendable {
        public var items: [IngredientDish.Item]
        /// Parts that didn't match a food in the table.
        public var unmatched: [String]
    }

    public static func parse(_ text: String, database: NutritionDatabase) -> Result {
        var items: [IngredientDish.Item] = []
        var unmatched: [String] = []
        for part in split(text) {
            let parsed = amount(in: part)
            guard let food = bestFood(for: parsed.name, database: database) else {
                unmatched.append(part)
                continue
            }
            let grams = parsed.grams(food)
            guard grams > 0 else {
                unmatched.append(part)
                continue
            }
            var item = IngredientDish.Item(food: food, grams: grams)
            switch parsed.unit {
            case .count where food.servingGrams > 0:
                item.unitGrams = food.servingGrams
                item.unitName = food.servingDescription.replacingOccurrences(of: "1 ", with: "")
            case .grams(5):
                (item.unitGrams, item.unitName) = (5, "tsp")
            case .grams(15):
                (item.unitGrams, item.unitName) = (15, "tbsp")
            default:
                break
            }
            items.append(item)
        }
        return Result(items: items, unmatched: unmatched)
    }

    /// A whole dish said or typed in one go: "Chicken keema with 250 grams raw chicken, 2 eggs, 100 grams veggies
    /// and 2 teaspoons oil", "Dish name is soya pulao. It has 150 g rice…", or "Poha: 60 g poha, 1 tsp oil".
    public static func parseDish(_ text: String, database: NutritionDatabase) -> (name: String?, result: Result) {
        let (name, rest) = splitName(text)
        return (name, parse(rest, database: database))
    }

    static func splitName(_ text: String) -> (name: String?, rest: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            // "The dish name is X. It has …", "Dish is X with …", "It's called X, …"
            #"^(?:the\s+)?(?:dish(?:'s|s)?\s+(?:name\s+)?is|dish\s+name\s*[:\-]?|name\s*(?:is|[:\-])|it'?s\s+called|called)\s+(.+?)(?:\s*[.:;,]\s+|\s+(?:with|which|that|and\s+it|it|made\s+with|containing|contains|has)\s+)(.*)$"#,
            // "X: …"
            #"^([^:\d]+?)\s*:\s*(.*)$"#,
            // "X with …", "X made with …", "X contains …"
            #"^([^\d,.]+?)\s+(?:made\s+with|made\s+of|consisting\s+of|consists\s+of|containing|contains|with|has)\s+(.*)$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let nameRange = Range(match.range(at: 1), in: trimmed), let restRange = Range(match.range(at: 2), in: trimmed) else { continue }
            let name = String(trimmed[nameRange]).trimmingCharacters(in: CharacterSet(charactersIn: " .,;:"))
            guard !name.isEmpty, name.split(separator: " ").count <= 6 else { continue }
            return (capitalized(name), String(trimmed[restRange]))
        }
        return (nil, trimmed)
    }

    /// "chicken keema" → "Chicken keema".
    static func capitalized(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }

    static func split(_ text: String) -> [String] {
        var t = " " + text.lowercased() + " "
        // Sentence ends (not decimal points): "… 2 eggs. It also has …"
        t = t.replacingOccurrences(of: #"\.(\s|$)"#, with: ",$1", options: .regularExpression)
        for joiner in [" and ", " with ", " plus ", " + ", "\n", ";"] { t = t.replacingOccurrences(of: joiner, with: ",") }
        return t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    enum Unit: Equatable {
        case grams(Double)
        /// Millilitres per unit; grams come from the food's density (1 for milk and drinks, 0.92 for oil).
        case millilitres(Double)
        case count
        /// No amount given: one serving.
        case serving
    }

    struct Parsed {
        var quantity: Double
        var unit: Unit
        var name: String

        func grams(_ food: FoodItem) -> Double {
            switch unit {
            case .grams(let perUnit): quantity * perUnit
            case .millilitres(let perUnit): quantity * perUnit * (food.millilitreGrams ?? 1)
            case .count: quantity * food.servingGrams
            case .serving: food.servingGrams
            }
        }
    }

    static let units: [(names: [String], unit: Unit)] = [
        (["kg", "kgs", "kilo", "kilos"], .grams(1_000)),
        (["g", "gm", "gms", "gram", "grams", "gr"], .grams(1)),
        (["ml", "millilitre", "millilitres", "milliliter", "milliliters"], .millilitres(1)),
        (["l", "litre", "litres", "liter", "liters"], .millilitres(1_000)),
        (["tsp", "teaspoon", "teaspoons"], .grams(5)),
        (["tbsp", "tablespoon", "tablespoons"], .grams(15)),
        (["cup", "cups"], .grams(150)),
        (["katori", "katoris", "bowl", "bowls"], .grams(150)),
        (["piece", "pieces", "pc", "pcs", "slice", "slices", "nos", "no"], .count),
    ]

    static func amount(in part: String) -> Parsed {
        var words = part.split(separator: " ").map(String.init)
        // "it has 250 grams chicken", "about 2 tsp oil": drop the words before the amount.
        if let index = words.firstIndex(where: { number($0) != nil || startsWithNumber($0) }), index > 0, index < words.count - 1,
           !["a", "an", "one", "half"].contains(words[index]), words[..<index].allSatisfy({ filler.contains($0) }) {
            words.removeFirst(index)
        }
        // "rice 150 g" → move a trailing amount to the front.
        if words.count >= 2, number(words[words.count - 1]) != nil {
            words = [words.removeLast()] + words
        } else if words.count >= 3, number(words[words.count - 2]) != nil, unit(words[words.count - 1]) != nil {
            let unitWord = words.removeLast()
            let numberWord = words.removeLast()
            words = [numberWord, unitWord] + words
        }
        guard let first = words.first else { return Parsed(quantity: 1, unit: .serving, name: part) }
        // "150g" written together.
        if number(first) == nil, let split = first.firstIndex(where: { !$0.isNumber && $0 != "." && $0 != "," }),
           split != first.startIndex, let value = number(String(first[..<split])) {
            let rest = String(first[split...])
            words.removeFirst()
            words = [String(value), rest] + words
        }
        guard let quantity = words.first.flatMap(number) else {
            return Parsed(quantity: 1, unit: .serving, name: words.joined(separator: " "))
        }
        words.removeFirst()
        if let next = words.first, let u = unit(next) {
            words.removeFirst()
            if words.first == "of" { words.removeFirst() }
            return Parsed(quantity: quantity, unit: u, name: words.joined(separator: " "))
        }
        if words.first == "of" { words.removeFirst() }
        return Parsed(quantity: quantity, unit: .count, name: words.joined(separator: " "))
    }

    static func startsWithNumber(_ word: String) -> Bool {
        word.first?.isNumber == true
    }

    static func unit(_ word: String) -> Unit? {
        units.first { $0.names.contains(word) }?.unit
    }

    static func number(_ word: String) -> Double? {
        let fractions: [String: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "1/2": 0.5, "1/4": 0.25, "3/4": 0.75, "half": 0.5,
                                           "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6]
        if let value = fractions[word] { return value }
        return Double(word.replacingOccurrences(of: ",", with: "."))
    }

    /// Words that describe how something was prepared, dropped when the full name doesn't match.
    static let filler: Set<String> = ["cooked", "boiled", "steamed", "white", "fresh", "chopped", "some", "the", "of", "plain",
                                      "home", "made", "homemade", "small", "medium", "large", "big", "little", "few", "soaked", "sliced",
                                      "it", "has", "also", "about", "around", "approximately", "roughly", "contains", "added", "some"]

    static func bestFood(for name: String, database: NutritionDatabase) -> FoodItem? {
        let cleaned = NutritionDatabase.normalize(name)
        guard !cleaned.isEmpty else { return nil }
        if let food = database.match(label: cleaned) ?? database.search(cleaned, limit: 1).first { return food }
        let words = cleaned.split(separator: " ").map(String.init).filter { !filler.contains($0) }
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        if let food = database.match(label: joined) ?? database.search(joined, limit: 1).first { return food }
        // Longest run of words that matches something.
        for length in stride(from: words.count - 1, through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let phrase = words[start..<(start + length)].joined(separator: " ")
                if phrase.count < 3 { continue }
                if let food = database.match(label: phrase) ?? database.search(phrase, limit: 1).first { return food }
            }
        }
        return nil
    }
}
