import Foundation

/// A food you define yourself, entered per serving (as on a label or a family recipe).
public struct CustomFoodDraft: Equatable, Sendable {
    public var name: String
    public var localName: String
    public var servingDescription: String
    public var servingGrams: Double
    /// Nutrients in one serving.
    public var perServing: Nutrients
    public var category: String
    public var notes: String

    public init(name: String, localName: String = "", servingDescription: String = "1 serving", servingGrams: Double = 100,
                perServing: Nutrients, category: String = "main", notes: String = "") {
        self.name = name
        self.localName = localName
        self.servingDescription = servingDescription
        self.servingGrams = servingGrams
        self.perServing = perServing
        self.category = category
        self.notes = notes
    }

    /// Per-100 g values, as the table stores them.
    public var per100g: Nutrients {
        perServing.scaled(by: 100 / max(servingGrams, 1))
    }

    /// Starts from an existing food, e.g. to adjust a dish to your family's recipe.
    public init(copying food: FoodItem) {
        self.init(name: food.name, localName: food.localName ?? "", servingDescription: food.servingDescription,
                  servingGrams: food.servingGrams, perServing: food.perServing, category: food.category, notes: food.notes ?? "")
    }
}

/// Reads and writes a simple CSV of foods, per serving:
/// `name,serving,serving_grams,kcal,protein_g,carbs_g,fat_g,category,notes`
public enum FoodListCSV {
    public static let header = "name,serving,serving_grams,kcal,protein_g,carbs_g,fat_g,category,notes"
    /// Older files had a Marathi name column after the name; it's read past and ignored.
    static let legacyHeader = "name,marathi_name,serving,serving_grams,kcal,protein_g,carbs_g,fat_g,category,notes"

    public struct ParseResult: Equatable, Sendable {
        public var foods: [CustomFoodDraft]
        /// "Line 4: …" messages for rows that couldn't be read.
        public var errors: [String]
    }

    public static func parse(_ text: String) -> ParseResult {
        var foods: [CustomFoodDraft] = []
        var errors: [String] = []
        // Excel and Numbers often start UTF-8 CSVs with a byte-order mark.
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var columns: [String: Int] = [:]
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let fields = split(line)
            if columns.isEmpty {
                let names = fields.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                if names.contains("name") && names.contains("kcal") {
                    for (i, n) in names.enumerated() { columns[n] = i }
                    continue
                }
                // No header: assume the standard column order (or the older one with 10 columns).
                let order = fields.count >= 10 ? legacyHeader : header
                for (i, n) in order.split(separator: ",").enumerated() { columns[String(n)] = i }
            }
            func field(_ key: String) -> String {
                guard let i = columns[key], i < fields.count else { return "" }
                return fields[i].trimmingCharacters(in: .whitespaces)
            }
            func number(_ key: String) -> Double? {
                let v = field(key)
                return v.isEmpty ? 0 : Double(v.replacingOccurrences(of: ",", with: "."))
            }
            let name = field("name")
            guard !name.isEmpty else { errors.append("Line \(index + 1): missing name"); continue }
            guard let kcal = number("kcal"), let p = number("protein_g"), let c = number("carbs_g"), let f = number("fat_g"),
                  let gramsValue = number("serving_grams")
            else { errors.append("Line \(index + 1): a number couldn't be read"); continue }
            let grams = gramsValue > 0 ? gramsValue : 100
            guard kcal > 0, kcal < 5_000, [p, c, f].allSatisfy({ $0 >= 0 && $0 < 1_000 }) else {
                errors.append("Line \(index + 1): values out of range"); continue
            }
            let serving = field("serving")
            let category = field("category")
            foods.append(CustomFoodDraft(
                name: name,
                servingDescription: serving.isEmpty ? "1 serving" : serving, servingGrams: grams,
                perServing: Nutrients(kilocalories: kcal, protein: p, carbohydrates: c, fat: f),
                category: category.isEmpty ? "main" : category.lowercased(), notes: field("notes")
            ))
        }
        return ParseResult(foods: foods, errors: errors)
    }

    public static func export(_ foods: [CustomFoodDraft]) -> String {
        func n(_ v: Double) -> String { String(format: "%g", (v * 10).rounded() / 10) }
        var rows = [header]
        for food in foods {
            let s = food.perServing
            rows.append([food.name, food.servingDescription, n(food.servingGrams), n(s.kilocalories),
                         n(s.protein), n(s.carbohydrates), n(s.fat), food.category, food.notes].map(quote).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func quote(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Splits one CSV line, honouring double-quoted fields.
    static func split(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = Array(line)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { current.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i += 1
        }
        fields.append(current)
        chars.removeAll()
        return fields
    }
}
