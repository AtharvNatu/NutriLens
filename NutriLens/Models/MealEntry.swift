import Foundation
import NutriCore
import SwiftData

enum MealType: String, CaseIterable, Codable, Identifiable {
    // Listed in the order of the day (stored by name, so the order can change freely).
    case breakfast, lunch, snack, dinner

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }

    /// A sensible default for a meal logged at `date`.
    static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 17..<22: .dinner
        default: .snack
        }
    }
}

enum MealSource: String, Codable {
    case photo, search, custom
}

/// A logged meal, stored locally with SwiftData and mirrored to Apple Health.
@Model
final class MealEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var name: String = ""
    /// Id in the nutrition table, nil for custom foods.
    var foodID: String?
    var grams: Double = 0
    var kilocalories: Double = 0
    var protein: Double = 0
    var carbohydrates: Double = 0
    var fat: Double = 0
    var mealTypeRaw: String = MealType.snack.rawValue
    var sourceRaw: String = MealSource.search.rawValue
    /// UUID of the HKCorrelation saved to Apple Health, if the save succeeded.
    var healthKitID: UUID?
    /// Small JPEG of the meal photo, if one was taken.
    @Attribute(.externalStorage) var photoData: Data?
    /// Last change, used to merge data between devices.
    var updatedAt: Date = Date.now
    /// Device that created this copy (see `CloudDeduplicator`); "" for records made before iCloud sync.
    var originDevice: String = ""

    init(
        date: Date,
        name: String,
        foodID: String?,
        grams: Double,
        nutrients: Nutrients,
        mealType: MealType,
        source: MealSource,
        photoData: Data? = nil
    ) {
        self.date = date
        self.name = name
        self.foodID = foodID
        self.grams = grams
        self.kilocalories = nutrients.kilocalories
        self.protein = nutrients.protein
        self.carbohydrates = nutrients.carbohydrates
        self.fat = nutrients.fat
        self.mealTypeRaw = mealType.rawValue
        self.sourceRaw = source.rawValue
        self.photoData = photoData
        self.originDevice = DeviceIdentity.id()
    }

    var nutrients: Nutrients {
        Nutrients(kilocalories: kilocalories, protein: protein, carbohydrates: carbohydrates, fat: fat)
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var source: MealSource {
        MealSource(rawValue: sourceRaw) ?? .search
    }

    var loggedAmount: LoggedAmount {
        LoggedAmount(date: date, nutrients: nutrients)
    }

    /// Predicate for entries whose date falls in `[start, end)`.
    static func predicate(from start: Date, to end: Date) -> Predicate<MealEntry> {
        #Predicate<MealEntry> { $0.date >= start && $0.date < end }
    }
}
