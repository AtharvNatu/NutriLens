import Foundation
import NutriCore
import SwiftData

/// A food you added yourself ("My foods"): a family recipe, a packaged item, or a dish missing from the table.
/// Stored per 100 g like the table, entered per serving. Defaults on every property keep it CloudKit-ready.
@Model
final class CustomFood {
    var id: UUID = UUID()
    var name: String = ""
    var localName: String = ""
    var category: String = "main"
    var servingDescription: String = "1 serving"
    var servingGrams: Double = 100
    var kcalPer100g: Double = 0
    var proteinPer100g: Double = 0
    var carbsPer100g: Double = 0
    var fatPer100g: Double = 0
    var notes: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// Device that created this copy (see `CloudDeduplicator`); "" for records made before iCloud sync.
    var originDevice: String = ""

    init(id: UUID = UUID(), draft: CustomFoodDraft) {
        self.id = id
        originDevice = DeviceIdentity.id()
        apply(draft)
    }

    func apply(_ draft: CustomFoodDraft) {
        name = draft.name.trimmingCharacters(in: .whitespaces)
        localName = draft.localName.trimmingCharacters(in: .whitespaces)
        category = draft.category
        servingDescription = draft.servingDescription.isEmpty ? "1 serving" : draft.servingDescription
        servingGrams = max(draft.servingGrams, 1)
        let n = draft.per100g
        kcalPer100g = n.kilocalories
        proteinPer100g = n.protein
        carbsPer100g = n.carbohydrates
        fatPer100g = n.fat
        notes = draft.notes
        updatedAt = .now
    }

    var per100g: Nutrients {
        Nutrients(kilocalories: kcalPer100g, protein: proteinPer100g, carbohydrates: carbsPer100g, fat: fatPer100g)
    }

    var draft: CustomFoodDraft {
        CustomFoodDraft(name: name, localName: localName, servingDescription: servingDescription, servingGrams: servingGrams,
                        perServing: per100g.scaled(by: servingGrams / 100), category: category, notes: notes)
    }

    static func foodID(for id: UUID) -> String { FoodItem.customPrefix + id.uuidString }

    /// As a table entry, so it can be searched and logged like any other food.
    var foodItem: FoodItem {
        FoodItem(id: Self.foodID(for: id), name: name, category: category, per100g: per100g, servingGrams: servingGrams,
                 servingDescription: servingDescription, region: "custom",
                 notes: notes.isEmpty ? nil : notes)
    }
}

/// Categories offered when adding a food (keys match the bundled table).
enum FoodCategory: String, CaseIterable, Identifiable {
    case breakfast, main, dal, rice, bread, snack, sweet, nonveg, protein, dairy, drink, fruit, vegetable, side, nuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .main: "Bhaji / curry / usal"
        case .dal: "Dal / amti"
        case .rice: "Rice"
        case .bread: "Poli / bhakri / bread"
        case .snack: "Snack"
        case .sweet: "Sweet"
        case .nonveg: "Non-veg"
        case .protein: "Protein source"
        case .dairy: "Dairy"
        case .drink: "Drink"
        case .fruit: "Fruit"
        case .vegetable: "Vegetable (raw)"
        case .side: "Chutney / salad / side"
        case .nuts: "Nuts & seeds"
        }
    }
}
