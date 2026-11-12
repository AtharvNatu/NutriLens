import Foundation

/// Groups shown as filters in food search.
public enum FoodFilter: String, CaseIterable, Identifiable, Sendable {
    case all, maharashtrian, breakfast, meals, dalRice, breads, snacks, sweets, nonVeg, protein, drinks, fruit, basics, myFoods

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .maharashtrian: "Maharashtrian"
        case .breakfast: "Breakfast"
        case .meals: "Bhaji & curries"
        case .dalRice: "Dal & rice"
        case .breads: "Poli & bhakri"
        case .snacks: "Snacks"
        case .sweets: "Sweets"
        case .nonVeg: "Non-veg & eggs"
        case .protein: "Protein sources"
        case .drinks: "Drinks & dairy"
        case .fruit: "Fruit & veg"
        case .basics: "Basics"
        case .myFoods: "My foods"
        }
    }

    public func includes(_ food: FoodItem) -> Bool {
        switch self {
        case .all: true
        case .maharashtrian: food.region == "mh"
        case .breakfast: food.category == "breakfast"
        case .meals: food.category == "main"
        case .dalRice: food.category == "dal" || food.category == "rice"
        case .breads: food.category == "bread"
        case .snacks: food.category == "snack"
        case .sweets: food.category == "sweet"
        case .nonVeg: food.category == "nonveg" || food.id == "egg" || food.id.hasPrefix("chicken")
        case .protein: food.proteinSource != nil || food.category == "protein" || food.category == "nuts"
        case .drinks: food.category == "drink" || food.category == "dairy"
        case .fruit: food.category == "fruit" || food.category == "vegetable"
        case .basics: ["side", "staple", "grains", "international"].contains(food.category)
        case .myFoods: food.isCustom
        }
    }
}

/// The nutrition table (bundled plus your own foods), with lookup by id, Vision label and search.
public struct NutritionDatabase: Sendable {
    public enum LoadError: Error, Equatable {
        case resourceMissing
    }

    public let foods: [FoodItem]
    /// Apple Vision label → food ids, most likely first.
    public let visionLabels: [String: [String]]
    private let byID: [String: FoodItem]
    /// Normalised name/alias/id → food id. The first food to claim a key wins.
    private let byKey: [String: String]

    public init(foods: [FoodItem], visionLabels: [String: [String]] = [:]) {
        self.foods = foods.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.visionLabels = visionLabels
        var byID: [String: FoodItem] = [:]
        var byKey: [String: String] = [:]
        // Ids and names take priority over aliases, so an alias never shadows a real food.
        for food in foods {
            byID[food.id] = food
            for key in [food.id, food.name] + (food.localName.map { [$0] } ?? []) {
                let k = Self.normalize(key)
                if !k.isEmpty, byKey[k] == nil { byKey[k] = food.id }
            }
        }
        for food in foods {
            for alias in food.aliases {
                let k = Self.normalize(alias)
                if !k.isEmpty, byKey[k] == nil { byKey[k] = food.id }
            }
        }
        self.byID = byID
        self.byKey = byKey
    }

    public init(jsonData: Data) throws {
        struct File: Decodable {
            var foods: [FoodItem]
            var visionLabels: [String: [String]]?
        }
        let file = try JSONDecoder().decode(File.self, from: jsonData)
        self.init(foods: file.foods, visionLabels: file.visionLabels ?? [:])
    }

    /// Loads the table shipped inside this package.
    public static func loadBundled() throws -> NutritionDatabase {
        guard let url = Bundle.module.url(forResource: "foods", withExtension: "json") else {
            throw LoadError.resourceMissing
        }
        return try NutritionDatabase(jsonData: Data(contentsOf: url))
    }

    /// The bundled table, loaded once. Empty if the resource is somehow missing or corrupt.
    public static let bundled: NutritionDatabase = {
        do {
            return try loadBundled()
        } catch {
            assertionFailure("Bundled nutrition table failed to load: \(error)")
            return NutritionDatabase(foods: [])
        }
    }()

    /// This table plus your own foods. Your foods win if an id clashes.
    public func adding(_ custom: [FoodItem]) -> NutritionDatabase {
        guard !custom.isEmpty else { return self }
        let ids = Set(custom.map(\.id))
        return NutritionDatabase(foods: custom + foods.filter { !ids.contains($0.id) }, visionLabels: visionLabels)
    }

    public func food(id: String) -> FoodItem? {
        byID[id]
    }

    /// Finds the food for a name or label such as `"vada_pav"`, `"Kande Pohe"` or `"samosas"`.
    /// Labels with several comma-separated synonyms are tried in turn.
    public func match(label: String) -> FoodItem? {
        for part in label.split(separator: ",") {
            let key = Self.normalize(String(part))
            guard !key.isEmpty else { continue }
            for candidate in Self.variants(of: key) {
                if let id = byKey[candidate], let food = byID[id] { return food }
            }
        }
        return nil
    }

    /// Foods suggested for an Apple Vision label: the curated list for that label, else a name/alias match.
    public func foods(forVisionLabel label: String) -> [FoodItem] {
        if let ids = visionLabels[label] {
            return ids.compactMap { byID[$0] }
        }
        return match(label: label).map { [$0] } ?? []
    }

    public enum SortOrder: Sendable {
        /// Best text match first (alphabetical when there's no query).
        case relevance
        /// Most protein per 100 kcal first.
        case proteinDensity
    }

    /// Foods whose name, Marathi name or aliases contain every word of `query`, best matches first.
    public func search(_ query: String, filter: FoodFilter = .all, sort: SortOrder = .relevance, limit: Int = 50) -> [FoodItem] {
        let pool = foods.filter(filter.includes)
        let q = Self.normalize(query)
        var results: [FoodItem]
        if q.isEmpty {
            results = pool
        } else {
            let words = q.split(separator: " ").map(String.init)
            var scored: [(score: Int, food: FoodItem)] = []
            for food in pool {
                let name = Self.normalize(food.name)
                let haystacks = [name] + (food.localName.map { [Self.normalize($0)] } ?? []) + food.aliases.map(Self.normalize)
                guard words.allSatisfy({ w in haystacks.contains { $0.contains(w) } }) else { continue }
                let score: Int
                if name == q || haystacks.contains(q) {
                    score = 0
                } else if name.hasPrefix(q) {
                    score = 1
                } else if haystacks.contains(where: { $0.hasPrefix(q) }) {
                    score = 2
                } else if name.split(separator: " ").contains(where: { $0.hasPrefix(words[0]) }) {
                    score = 3
                } else {
                    score = 4
                }
                scored.append((score, food))
            }
            results = scored
                .sorted { $0.score != $1.score ? $0.score < $1.score : $0.food.name < $1.food.name }
                .map(\.food)
        }
        if sort == .proteinDensity {
            results = results.sorted { $0.proteinPer100Kcal > $1.proteinPer100Kcal }
        }
        return Array(results.prefix(limit))
    }

    /// Lower-cases, folds accents, turns `_`/`-` into spaces and collapses whitespace.
    /// Devanagari letters are kept, so Marathi names can be searched.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        let spaced = folded.map { ch -> Character in
            (ch == "_" || ch == "-" || ch == "/") ? " " : ch
        }
        let cleaned = String(spaced).filter { $0.isLetter || $0.isNumber || $0 == " " }
        return cleaned.split(separator: " ").joined(separator: " ")
    }

    /// The key itself, then simple singular/plural forms.
    private static func variants(of key: String) -> [String] {
        var out = [key]
        if key.hasSuffix("es") { out.append(String(key.dropLast(2))) }
        if key.hasSuffix("s") { out.append(String(key.dropLast())) }
        out.append(key + "s")
        return out
    }
}
