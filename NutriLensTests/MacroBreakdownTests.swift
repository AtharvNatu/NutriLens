import Foundation
import NutriCore
import Testing
@testable import NutriLens

@Suite("Today's macros by item")
@MainActor
struct MacroBreakdownTests {
    func meal(_ name: String, _ type: MealType, protein: Double, kcal: Double, hour: Int) -> MealEntry {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return MealEntry(date: date, name: name, foodID: nil, grams: 100,
                         nutrients: Nutrients(kilocalories: kcal, protein: protein, carbohydrates: 10, fat: 5),
                         mealType: type, source: .custom)
    }

    @Test func splitsByItemAndByMeal() {
        let meals = [
            meal("Pohe", .breakfast, protein: 6, kcal: 250, hour: 8),
            meal("Seeds & nuts mix", .lunch, protein: 7, kcal: 173, hour: 13),
            meal("Chicken curry", .lunch, protein: 27, kcal: 300, hour: 13),
            meal("Seeds & nuts mix", .dinner, protein: 7, kcal: 173, hour: 20),
            meal("Banana", .snack, protein: 3, kcal: 105, hour: 17),
        ]
        let b = MacroBreakdown(meals: meals, macro: .protein)
        #expect(b.total == 50)
        #expect(b.items.first?.name == "Chicken curry")
        #expect(abs(b.items.first!.share - 0.54) < 0.001)
        #expect(abs(b.items.map(\.share).reduce(0, +) - 1) < 0.0001)
        // Order of the day, empty meals left out.
        #expect(b.groups.map(\.mealType) == [.breakfast, .lunch, .snack, .dinner])
        #expect(b.groups[1].value == 34)
        #expect(b.groups[1].itemCount == 2)

        let energy = MacroBreakdown(meals: meals, macro: .energy)
        #expect(energy.total == 1001)
        #expect(energy.items.first?.name == "Chicken curry")
        #expect(MacroBreakdown(meals: meals, macro: .carbohydrates).total == 50)
    }

    @Test func emptyDayHasNoShares() {
        let b = MacroBreakdown(meals: [], macro: .fat)
        #expect(b.total == 0 && b.items.isEmpty && b.groups.isEmpty)
        let zero = MacroBreakdown(meals: [meal("Black coffee", .breakfast, protein: 0, kcal: 2, hour: 7)], macro: .protein)
        #expect(zero.items.first?.share == 0)
    }

    @Test func mealsAreInTheOrderOfTheDay() {
        #expect(MealType.allCases == [.breakfast, .lunch, .snack, .dinner])
        #expect(MealType(rawValue: "dinner") == .dinner)
    }

    @Test func seedMixIsOneTapAwayOnLogFood() {
        #expect(LogFoodView.everyDayFoodIDs.allSatisfy { NutritionDatabase.bundled.food(id: $0) != nil })
    }
}
