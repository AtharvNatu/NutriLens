import Foundation
import Testing
@testable import NutriCore

@Suite("Raw vegetables and fruit")
struct ProduceTests {
    let db = NutritionDatabase.bundled

    static let requested: [(query: String, id: String)] = [
        ("English cucumber", "english_cucumber"), ("Tomato", "tomato_raw"), ("Carrot", "carrot_raw"), ("Beetroot", "beetroot_raw"),
        ("Mushrooms", "mushroom"), ("Onion", "onion_raw"), ("Banana", "banana"), ("Plum", "plum"),
        ("White dragon fruit", "dragon_fruit_white"), ("Chikoo", "chikoo"), ("Orange", "orange"), ("Mandarin", "mandarin"),
        ("Jackfruit", "jackfruit"), ("Mango", "mango"),
    ]

    @Test func everyRequestedItemIsFoundFirstBySearch() {
        for item in Self.requested {
            #expect(db.search(item.query).first?.id == item.id, "\(item.query) → \(db.search(item.query).prefix(3).map(\.id))")
        }
    }

    @Test func aliasesFindThem() {
        for (query, id) in [("kakdi", "english_cucumber"), ("gajar", "carrot_raw"), ("phanas", "jackfruit"),
                            ("kinnow", "mandarin"), ("pitaya", "dragon_fruit_white"), ("aloo bukhara", "plum"), ("chukandar", "beetroot_raw")] {
            #expect(db.search(query).contains { $0.id == id }, "\(query)")
        }
    }

    @Test func fruitAndVegFilter() {
        let produce = db.search("", filter: .fruit, limit: 500).map(\.id)
        for item in Self.requested where item.id != "mushroom" { #expect(produce.contains(item.id), "\(item.id)") }
        #expect(!produce.contains("ghee"))
        #expect(db.search("", filter: .basics, limit: 500).contains { $0.id == "ghee" })
    }

    @Test func valuesAreSensible() throws {
        for item in Self.requested {
            let food = try #require(db.food(id: item.id))
            let n = food.per100g
            // Energy roughly matches 4/4/9 kcal per gram (fibre makes produce read a little low).
            let fromMacros = 4 * n.protein + 4 * n.carbohydrates + 9 * n.fat
            #expect(abs(fromMacros - n.kilocalories) <= max(8, 0.2 * n.kilocalories), "\(item.id): \(fromMacros) vs \(n.kilocalories)")
            #expect(n.kilocalories < 100, "\(item.id)")
            #expect(food.servingGrams > 0)
        }
    }

    @Test func photosOfProduceSuggestTheRawFood() {
        #expect(db.visionLabels["cucumber"]?.first == "english_cucumber")
        #expect(db.visionLabels["tomato"]?.first == "tomato_raw")
        #expect(db.visionLabels["beet"]?.first == "beetroot_raw")
        #expect(db.visionLabels["mandarine"]?.first == "mandarin")
    }
}
