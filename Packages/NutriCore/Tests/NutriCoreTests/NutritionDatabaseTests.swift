import Foundation
import Testing
import Vision
@testable import NutriCore

@Suite("Nutrition table")
struct NutritionDatabaseTests {
    let db = try! NutritionDatabase.loadBundled()

    /// Protein per 100 g from Protein-Sources.pdf (midpoint of each range). Buffalo milk follows the Chitale
    /// pack instead (3.8 g per 100 ml; the PDF said 4–4.5 g).
    static let pdfProtein: [(String, Double)] = [
        ("egg", 13), ("chicken_raw", 27), ("chicken_cooked", 31), ("curd", 3.5), ("chakka", 9.5),
        ("paneer", 19), ("buttermilk", 1.5), ("tofu", 10), ("soya_chunks_boiled", 17), ("mushroom", 3.5), ("toor_dal", 22),
        ("moong_dal", 24), ("masoor_dal", 25), ("moong_whole", 24), ("matki_whole", 23), ("chickpeas_dry", 19),
        ("kala_chana_dry", 20), ("peanuts", 25.5), ("almonds", 21), ("cashews", 18), ("walnuts", 15), ("pistachios", 20),
        ("pumpkin_seeds", 30), ("sunflower_seeds", 20.5), ("flax_seeds", 18), ("chia_seeds", 16.5), ("sesame_seeds", 18),
        ("wheat_atta", 12), ("jowar_flour", 10.5), ("bajra_flour", 11.5), ("brown_rice_raw", 7.5),
    ]

    @Test func everyProteinSourceFromThePDFUsesItsProteinValue() throws {
        #expect(Self.pdfProtein.count == 31)
        for (id, protein) in Self.pdfProtein {
            let food = try #require(db.food(id: id), "missing \(id)")
            #expect(food.per100g.protein == protein, "\(id)")
            #expect(food.proteinSource == "Protein-Sources.pdf", "\(id)")
            #expect(food.notes?.isEmpty == false, "\(id) should carry the PDF's note")
        }
    }

    @Test func derivedCookedFormsAreLowerThanDry() throws {
        let pairs = [("toor_dal", "varan"), ("moong_dal", "moong_dal_cooked"), ("moong_whole", "moong_sprouts"),
                     ("matki_whole", "matki_sprouts"), ("chickpeas_dry", "chickpeas_cooked"), ("kala_chana_dry", "kala_chana_cooked"),
                     ("brown_rice_raw", "brown_rice_cooked")]
        for (dry, cooked) in pairs {
            let d = try #require(db.food(id: dry)), c = try #require(db.food(id: cooked))
            #expect(c.per100g.protein < d.per100g.protein / 2, "\(cooked) vs \(dry)")
        }
    }

    @Test func tableIsMostlyIndianAndCoversMaharashtrianStaples() {
        #expect(db.foods.count >= 200)
        let international = db.foods.filter { $0.region == "intl" }.count
        #expect(Double(international) / Double(db.foods.count) < 0.1)
        let staples = ["kande_pohe", "upma", "sabudana_khichdi", "thalipeeth", "misal_pav", "vada_pav", "pav_bhaji", "matki_usal",
                       "zunka", "pithla", "jowar_bhakri", "bajra_bhakri", "poli", "puran_poli", "modak", "varan_bhaat", "amti",
                       "masale_bhaat", "bharli_vangi", "kothimbir_vadi", "sol_kadhi", "shrikhand", "aamras", "chicken_rassa", "surmai_fry"]
        for id in staples { #expect(db.food(id: id)?.region == "mh", "\(id)") }
        // Everything is in English: no Marathi script anywhere in the table.
        let devanagari = try! Regex("[\\u{0900}-\\u{097F}]")
        for food in db.foods {
            #expect(food.localName == nil, "\(food.id)")
            #expect(([food.name, food.servingDescription, food.notes ?? ""] + food.aliases).allSatisfy { !$0.contains(devanagari) }, "\(food.id)")
        }
    }

    @Test func idsAreUnique() {
        #expect(Set(db.foods.map(\.id)).count == db.foods.count)
    }

    /// Catches typos: stated energy should be close to 4/4/9 kcal per gram of macros.
    @Test func energyIsConsistentWithMacros() {
        for food in db.foods {
            let stated = food.per100g.kilocalories
            let relativeError = abs(stated - food.per100g.kilocaloriesFromMacros) / stated
            #expect(relativeError < 0.2, "\(food.id)")
        }
    }

    @Test func valuesArePlausible() {
        for food in db.foods {
            let n = food.per100g
            #expect(n.kilocalories > 0 && n.kilocalories <= 900, "\(food.id)")
            #expect(n.protein + n.carbohydrates + n.fat <= 100, "\(food.id)")
            #expect(food.servingGrams > 0 && food.servingGrams <= 800, "\(food.id)")
            #expect(!food.servingDescription.isEmpty)
            // servingLabel appends "(N g)", so the description itself must not contain a weight.
            #expect(food.servingDescription.range(of: #"\d\s*g\b"#, options: .regularExpression) == nil, "\(food.id)")
        }
    }

    @Test(arguments: [
        ("vada_pav", "vada_pav"), ("Vadapav", "vada_pav"), ("pohe", "kande_pohe"), ("kande pohe", "kande_pohe"),
        ("misal", "misal"), ("thalipeeth", "thalipeeth"), ("chapati", "poli"), ("roti", "poli"), ("bhakri", "jowar_bhakri"),
        ("biryani", "chicken_biryani"), ("dahi", "curd"), ("taak", "buttermilk"), ("shengdane", "peanuts"),
        ("cholebhature", "chole_bhature"), ("paani puri", "pani_puri"), ("samosas", "samosa"), ("Orange", "orange"),
    ])
    func matchesNamesAndAliases(label: String, expectedID: String) {
        #expect(db.match(label: label)?.id == expectedID)
    }

    @Test(arguments: ["", "   ", "spaceship", "keyboard", "foie gras"])
    func unknownLabelsDoNotMatch(label: String) {
        #expect(db.match(label: label) == nil)
    }

    @Test func searchFindsMarathiDishesTypedInEnglish() {
        #expect(db.search("pohe").first?.id == "kande_pohe")
        #expect(db.search("bhakri").count >= 3)
        #expect(db.search("chicken wing").map(\.id) == ["chicken_65"])
    }

    @Test func filtersAndProteinSort() {
        let mh = db.search("", filter: .maharashtrian, limit: 500)
        #expect(mh.count >= 60)
        #expect(mh.allSatisfy { $0.region == "mh" })
        let protein = db.search("", filter: .protein, limit: 500)
        #expect(Self.pdfProtein.allSatisfy { id, _ in protein.contains { $0.id == id } })
        let dense = db.search("", filter: .protein, sort: .proteinDensity, limit: 3).map(\.id)
        #expect(["whey_protein", "chicken_raw", "egg_white"].contains(dense.first ?? ""))
        #expect(db.search("", filter: .myFoods).isEmpty)
    }

    @Test func emptySearchReturnsAlphabeticalList() {
        let all = db.search("", limit: 500)
        #expect(all.count == db.foods.count)
        #expect(all.map(\.name) == all.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        #expect(db.search("", limit: 5).count == 5)
    }

    @Test func visionLabelsSuggestIndianDishes() {
        #expect(db.foods(forVisionLabel: "curry").first?.id == "chicken_curry")
        #expect(db.foods(forVisionLabel: "curry").count >= 5)
        #expect(db.foods(forVisionLabel: "crepe").first?.id == "dosa")
        #expect(db.foods(forVisionLabel: "dumpling").map(\.id).contains("modak"))
        #expect(db.foods(forVisionLabel: "samosa").first?.id == "samosa")
        #expect(db.foods(forVisionLabel: "keyboard").isEmpty)
        for (label, ids) in db.visionLabels {
            #expect(ids.allSatisfy { db.food(id: $0) != nil }, "\(label)")
        }
    }

    /// Every mapped label must be one Apple's classifier can actually return.
    @Test func visionLabelsExistInApplesClassifier() throws {
        let supported = ClassifyImageRequest().supportedIdentifiers
        guard !supported.isEmpty else { return }
        let known = Set(supported)
        for label in db.visionLabels.keys {
            #expect(known.contains(label), "\(label) isn't an Apple Vision label")
        }
    }

    @Test func customFoodsMergeAndWinOnClash() throws {
        let mine = FoodItem(id: FoodItem.customPrefix + "1", name: "Aai's pohe", per100g: Nutrients(kilocalories: 150, protein: 4, carbohydrates: 24, fat: 4),
                            servingGrams: 180, servingDescription: "1 plate", region: "custom")
        let merged = db.adding([mine])
        #expect(merged.foods.count == db.foods.count + 1)
        #expect(merged.search("aai").first?.id == mine.id)
        #expect(merged.search("", filter: .myFoods).map(\.id) == [mine.id])
        #expect(merged.visionLabels == db.visionLabels)
        #expect(mine.isCustom)
    }

    @Test func decodesMinimalJSON() throws {
        let json = """
        {"foods":[{"id":"x","name":"Thing","kcal":100,"protein":1,"carbs":2,"fat":3,"servingGrams":50,"serving":"1 piece"}]}
        """
        let custom = try NutritionDatabase(jsonData: Data(json.utf8))
        let food = try #require(custom.food(id: "x"))
        #expect(food.per100g == Nutrients(kilocalories: 100, protein: 1, carbohydrates: 2, fat: 3))
        #expect(food.region == "basic")
        #expect(custom.visionLabels.isEmpty)
    }

    @Test func normalisation() {
        #expect(NutritionDatabase.normalize("  Fish_and-Chips!! ") == "fish and chips")
        #expect(NutritionDatabase.normalize("Crème brûlée") == "creme brulee")
    }
}

@Suite("Food list CSV")
struct FoodListCSVTests {
    @Test func parsesWithHeaderAndQuotes() throws {
        let csv = """
        name,serving,serving_grams,kcal,protein_g,carbs_g,fat_g,category,notes
        Aai's pohe,1 plate,180,290,6,45,9,breakfast,"less oil, more peanuts"
        # a comment
        Protein ladoo,1 ladoo,35,150,8,14,7,sweet,
        ,,,,,,,,
        Bad row,1,abc,100,1,1,1,,
        """
        let result = FoodListCSV.parse(csv)
        #expect(result.foods.count == 2)
        let pohe = try #require(result.foods.first)
        #expect(pohe.localName.isEmpty)
        #expect(pohe.notes == "less oil, more peanuts")
        #expect(pohe.perServing.kilocalories == 290)
        #expect(abs(pohe.per100g.kilocalories - 161.11) < 0.01)
        #expect(result.errors.count == 2)
        #expect(result.errors.allSatisfy { $0.hasPrefix("Line ") })
    }

    @Test func byteOrderMarkFromExcelIsIgnored() {
        let csv = "\u{FEFF}name,serving,serving_grams,kcal,protein_g,carbs_g,fat_g,category,notes\nPoha,1 plate,180,290,6,45,9,breakfast,\n"
        let result = FoodListCSV.parse(csv)
        #expect(result.errors.isEmpty)
        #expect(result.foods.map(\.name) == ["Poha"])
    }

    @Test func headerlessUsesStandardOrder() {
        let result = FoodListCSV.parse("Dal dhokli,1 bowl,300,360,14,52,10,main,")
        #expect(result.foods.first?.servingGrams == 300)
        #expect(result.foods.first?.category == "main")
    }

    /// Files exported before the Marathi name column was dropped still import; that column is skipped.
    @Test func olderFilesWithAMarathiColumnStillImport() {
        let withHeader = FoodListCSV.parse("name,marathi_name,serving,serving_grams,kcal,protein_g,carbs_g,fat_g,category,notes\nPoha,x,1 plate,180,290,6,45,9,breakfast,\n")
        let headerless = FoodListCSV.parse("Dal dhokli,x,1 bowl,300,360,14,52,10,main,")
        for result in [withHeader, headerless] {
            #expect(result.errors.isEmpty)
            #expect(result.foods.first?.localName.isEmpty == true)
        }
        #expect(withHeader.foods.first?.servingGrams == 180)
        #expect(headerless.foods.first?.servingGrams == 300)
        #expect(headerless.foods.first?.servingDescription == "1 bowl")
    }

    @Test func exportRoundTrips() {
        let foods = [CustomFoodDraft(name: "Thalipeeth, Aai style", servingDescription: "1 piece", servingGrams: 90,
                                     perServing: Nutrients(kilocalories: 220, protein: 7.5, carbohydrates: 30, fat: 8), category: "breakfast",
                                     notes: "with \"loni\"")]
        let text = FoodListCSV.export(foods)
        #expect(text.hasPrefix(FoodListCSV.header))
        #expect(FoodListCSV.parse(text).foods == foods)
    }

    @Test func copyingAnExistingFoodKeepsServingValues() throws {
        let db = try NutritionDatabase.loadBundled()
        let misal = try #require(db.food(id: "misal_pav"))
        let draft = CustomFoodDraft(copying: misal)
        #expect(draft.servingGrams == misal.servingGrams)
        #expect(abs(draft.per100g.kilocalories - misal.per100g.kilocalories) < 0.001)
        #expect(draft.localName.isEmpty)
    }
}
