import Foundation

/// A food in the nutrition table. Nutrients are stored per 100 g as eaten.
public struct FoodItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var per100g: Nutrients
    /// Weight in grams of one typical serving.
    public var servingGrams: Double
    /// Human description of one serving, e.g. "1 slice".
    public var servingDescription: String
    /// Other names this food may be called (English, Hindi, Marathi transliterations).
    public var aliases: [String]
    /// No longer shown or collected (everything is in English); kept so older backups still decode.
    public var localName: String?
    /// "mh" Maharashtrian, "in" other Indian, "intl" international, "basic" ingredient/basic food, "custom" yours.
    public var region: String
    /// Short note, e.g. the guidance from Protein-Sources.pdf or how a value was derived.
    public var notes: String?
    /// Where the protein value comes from, when it isn't the general table (e.g. "Protein-Sources.pdf").
    public var proteinSource: String?
    /// For liquids, grams in one millilitre (milk and drinks are stored per 100 ml, so 1; oil 0.92). nil for solids.
    public var gramsPerMl: Double?

    public init(
        id: String,
        name: String,
        category: String = "other",
        per100g: Nutrients,
        servingGrams: Double,
        servingDescription: String,
        aliases: [String] = [],
        localName: String? = nil,
        region: String = "basic",
        notes: String? = nil,
        proteinSource: String? = nil,
        gramsPerMl: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.per100g = per100g
        self.servingGrams = servingGrams
        self.servingDescription = servingDescription
        self.aliases = aliases
        self.localName = localName
        self.region = region
        self.notes = notes
        self.proteinSource = proteinSource
        self.gramsPerMl = gramsPerMl
    }

    /// Grams in one millilitre when the food can be measured in ml: drinks (stored per 100 ml) and liquids the
    /// table marks (milk, buttermilk, oil, ghee). nil for solids.
    public var millilitreGrams: Double? {
        gramsPerMl ?? (category == "drink" ? 1 : nil)
    }

    /// Millilitres in `grams` of this liquid.
    public func millilitres(fromGrams grams: Double) -> Double? {
        millilitreGrams.map { grams / $0 }
    }

    public var isMaharashtrian: Bool { region == "mh" }
    public var isCustom: Bool { id.hasPrefix(Self.customPrefix) }
    public static let customPrefix = "custom."

    /// Grams of protein per 100 kcal, for ranking protein-dense foods.
    public var proteinPer100Kcal: Double {
        per100g.kilocalories > 0 ? per100g.protein / per100g.kilocalories * 100 : 0
    }

    /// Nutrients in one typical serving.
    public var perServing: Nutrients {
        nutrients(for: .servings(1))
    }

    /// "1 slice (107 g)"
    public var servingLabel: String {
        "\(servingDescription) (\(Int(servingGrams.rounded())) g)"
    }

    // The JSON is flat: {"id", "name", "kcal", "protein", "carbs", "fat", "servingGrams", "serving", ...}
    private enum CodingKeys: String, CodingKey {
        case id, name, category, kcal, protein, carbs, fat, servingGrams, serving, aliases, localName, region, notes, proteinSource, gramsPerMl
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "other"
        per100g = Nutrients(
            kilocalories: try c.decode(Double.self, forKey: .kcal),
            protein: try c.decode(Double.self, forKey: .protein),
            carbohydrates: try c.decode(Double.self, forKey: .carbs),
            fat: try c.decode(Double.self, forKey: .fat)
        )
        servingGrams = try c.decode(Double.self, forKey: .servingGrams)
        servingDescription = try c.decode(String.self, forKey: .serving)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        localName = try c.decodeIfPresent(String.self, forKey: .localName)
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? "basic"
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        proteinSource = try c.decodeIfPresent(String.self, forKey: .proteinSource)
        gramsPerMl = try c.decodeIfPresent(Double.self, forKey: .gramsPerMl)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(per100g.kilocalories, forKey: .kcal)
        try c.encode(per100g.protein, forKey: .protein)
        try c.encode(per100g.carbohydrates, forKey: .carbs)
        try c.encode(per100g.fat, forKey: .fat)
        try c.encode(servingGrams, forKey: .servingGrams)
        try c.encode(servingDescription, forKey: .serving)
        try c.encode(aliases, forKey: .aliases)
        try c.encodeIfPresent(localName, forKey: .localName)
        try c.encode(region, forKey: .region)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(proteinSource, forKey: .proteinSource)
        try c.encodeIfPresent(gramsPerMl, forKey: .gramsPerMl)
    }
}
