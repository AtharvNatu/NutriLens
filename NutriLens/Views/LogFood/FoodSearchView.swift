import NutriCore
import SwiftData
import SwiftUI

/// Searchable food list: the bundled Indian/Maharashtrian table plus your own foods.
struct FoodSearchView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \CustomFood.name) private var customFoods: [CustomFood]
    @State private var query = ""
    @State private var filter: FoodFilter = .all
    @State private var proteinFirst = false
    @State private var copyDraft: DraftBox?

    private var database: NutritionDatabase {
        env.database.adding(customFoods.map(\.foodItem))
    }

    private var results: [FoodItem] {
        database.search(query, filter: filter, sort: proteinFirst ? .proteinDensity : .relevance, limit: 300)
    }

    var body: some View {
        List {
            Section {
                ForEach(results) { food in
                    NavigationLink(value: LogRoute.editor(food, food.isCustom ? .custom : .search)) {
                        FoodRow(food: food, showProtein: proteinFirst)
                    }
                    .contextMenu {
                        Button("Copy to My foods and edit", systemImage: "doc.on.doc") {
                            copyDraft = DraftBox(draft: CustomFoodDraft(copying: food))
                        }
                    }
                }
            } header: {
                filterBar
            }
            Section {
                NavigationLink(value: LogRoute.custom) {
                    Label("Not listed? Add it to My foods", systemImage: "square.and.pencil")
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if results.isEmpty {
                if filter == .myFoods && query.isEmpty {
                    ContentUnavailableView("No foods of your own yet", systemImage: "fork.knife",
                                           description: Text("Add a family recipe or packaged food, or long-press any food to copy and adjust it."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Pohe, misal, bhakri, paneer…")
        .navigationTitle("Foods")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $proteinFirst) {
                    Label("Most protein first", systemImage: "bolt.heart")
                }
                .toggleStyle(.button)
                .accessibilityHint("Sorts foods by protein per 100 kcal")
            }
        }
        .sheet(item: $copyDraft) { box in
            NavigationStack { CustomFoodEditor(initial: box.draft) }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FoodFilter.allCases) { f in
                    Button(f.title) { filter = f }
                        .font(.subheadline.weight(filter == f ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(filter == f ? Color.accentColor : Color.secondary.opacity(0.12), in: .capsule)
                        .foregroundStyle(filter == f ? Color.white : Color.primary)
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        .textCase(nil)
    }
}

private struct DraftBox: Identifiable {
    let id = UUID()
    let draft: CustomFoodDraft
}

/// One food: name, energy and protein per serving, and where the protein figure comes from.
struct FoodRow: View {
    let food: FoodItem
    var showProtein = false

    var body: some View {
        // Dishes you've set your usual amounts for show your version.
        let shown = RecipePreferences.asUsual(food)
        let serving = shown.perServing
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(food.name).font(.body)
                Spacer(minLength: 4)
                if food.isCustom { Tag(text: "Mine", color: .purple) }
                if shown != food { Tag(text: "Your way", color: .orange) }
                if food.proteinSource != nil { Tag(text: "Protein list", color: .teal) }
            }
            Text("\(Format.kcal(serving.kilocalories)) kcal · \(Format.grams(serving.protein)) protein · \(shown.servingLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if showProtein {
                Text("\(food.proteinPer100Kcal.formatted(.number.precision(.fractionLength(1)))) g protein per 100 kcal")
                    .font(.caption2)
                    .foregroundStyle(.teal)
            }
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }
}
