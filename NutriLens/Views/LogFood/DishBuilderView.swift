import NutriCore
import SwiftData
import SwiftUI

/// Build a dish from what went into it: start from a dish (the photo's guesses), type what you used
/// ("150 g rice, 65 g soya chunks") or pick foods, then confirm the portion as usual.
struct DishBuilderView: View {
    /// Dishes to start from (the photo's guesses); empty for a dish from scratch.
    let starts: [FoodItem]
    /// The ingredients to begin with (a recipe's), if any.
    let initial: IngredientDish?
    let onDone: (FoodItem) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomFood.name) private var customFoods: [CustomFood]
    @State private var dish = IngredientDish(name: "")
    @State private var description = ""
    @State private var unmatched: [String] = []
    @State private var startedFrom: String?
    /// Ingredients that came from the starting dish.
    @State private var templateItems: Set<UUID> = []
    /// The name last taken from what you said, so a new sentence can replace it.
    @State private var autoName: String?
    @State private var saveToMyFoods = true
    @State private var picking = false
    @State private var prepared = false
    @FocusState private var describing: Bool

    private var database: NutritionDatabase { env.database.adding(customFoods.map(\.foodItem)) }

    var body: some View {
        Form {
            Section {
                TextField("Dish name, e.g. Soya pulao", text: $dish.name)
                    .font(.headline)
            }

            if !starts.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(starts) { food in
                                Button(food.name) { start(from: food) }
                                    .buttonStyle(.bordered)
                                    .tint(startedFrom == food.id ? .accentColor : .secondary)
                            }
                        }
                    }
                } header: {
                    Text("Start from")
                } footer: {
                    Text("Fills in that dish's usual ingredients; change them below.")
                }
            }

            Section {
                TextField("Chicken keema with 250 g raw chicken, 2 eggs, 100 g veggies, 2 tsp oil", text: $description, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($describing)
                    .submitLabel(.done)
                    .onSubmit(addDescription)
                Button("Add these", systemImage: "text.badge.plus", action: addDescription)
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !unmatched.isEmpty {
                    Label("Not found: \(unmatched.joined(separator: "; ")). Try another name or pick the food.",
                          systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Say or type it")
            } footer: {
                Text("Dish name, then each ingredient with grams, tsp, katori or a count. Tap the keyboard's mic to dictate. Rice and soya chunks: cooked weight.")
            }

            Section("Ingredients") {
                if dish.items.isEmpty {
                    Text("Nothing yet.").foregroundStyle(.secondary)
                }
                ForEach($dish.items) { $item in
                    IngredientRow(item: $item)
                }
                .onDelete { dish.items.remove(atOffsets: $0) }
                Button("Add from food list", systemImage: "plus.circle") { picking = true }
            }

            if !dish.items.isEmpty {
                Section {
                    let n = dish.nutrients
                    LabeledContent("Energy") { Text("\(Format.kcal(n.kilocalories)) kcal").font(.headline.monospacedDigit()) }
                    LabeledContent("Protein", value: Format.grams(n.protein))
                    LabeledContent("Carbohydrates", value: Format.grams(n.carbohydrates))
                    LabeledContent("Fat", value: Format.grams(n.fat))
                    LabeledContent("Weight", value: Format.grams(dish.grams))
                    Toggle("Save to My foods", isOn: $saveToMyFoods)
                    Button("Save to My foods without logging", systemImage: "tray.and.arrow.down") {
                        saveCustomFood()
                        dismiss()
                    }
                } header: {
                    Text("Whole dish")
                } footer: {
                    Text("Next, choose how much of it you ate.")
                }
            }
        }
        .navigationTitle("Build a dish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next", action: finish)
                    .disabled(dish.items.isEmpty || dish.grams <= 0)
            }
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                FoodPicker(database: database) { food in
                    dish.items.append(IngredientDish.Item(food: food, grams: food.servingGrams))
                    picking = false
                }
            }
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            if let initial { dish = initial }
        }
    }

    private func start(from food: FoodItem) {
        let usual = DishRecipes.recipe(for: food).flatMap { RecipePreferences.usual(for: $0) }
        let template = IngredientDish.template(for: food, amounts: usual, database: env.database)
        // Replace the previous starting dish's ingredients; keep what you typed or picked.
        let kept = dish.items.filter { !templateItems.contains($0.id) }
        templateItems = Set(template.items.map(\.id))
        dish.items = template.items + kept
        if dish.name.isEmpty || dish.name == starts.first(where: { $0.id == startedFrom })?.name { dish.name = template.name }
        startedFrom = food.id
    }

    private func addDescription() {
        let (name, result) = IngredientParser.parseDish(description, database: database)
        if let name, dish.name.isEmpty || dish.name == autoName || dish.name == starts.first(where: { $0.id == startedFrom })?.name {
            dish.name = name
            autoName = name
        }
        for item in result.items {
            // Typing an ingredient that's already listed sets its amount.
            if let index = dish.items.firstIndex(where: { $0.foodID != nil && $0.foodID == item.foodID }) {
                dish.items[index].grams = item.grams
            } else {
                dish.items.append(item)
            }
        }
        unmatched = result.unmatched
        if result.unmatched.isEmpty { description = "" }
        describing = false
    }

    private func finish() {
        onDone(saveToMyFoods ? saveCustomFood() : dish.foodItem())
    }

    /// Adds the dish to My foods (one serving = the whole dish) and returns it as a food.
    @discardableResult
    private func saveCustomFood() -> FoodItem {
        let food = dish.foodItem()
        let draft = CustomFoodDraft(name: food.name, servingDescription: food.servingDescription, servingGrams: dish.grams.rounded(),
                                    perServing: dish.nutrients, category: "main", notes: food.notes ?? "")
        let custom = CustomFood(draft: draft)
        modelContext.insert(custom)
        try? modelContext.save()
        return custom.foodItem
    }
}

/// One ingredient: name, amount and what it adds.
private struct IngredientRow: View {
    @Binding var item: IngredientDish.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name).lineLimit(2)
                Spacer()
                if item.unitGrams > 0 {
                    Stepper(value: Binding(get: { (item.grams / item.unitGrams).rounded() }, set: { item.grams = max(0, $0) * item.unitGrams }),
                            in: 0...20) {
                        let count = Int((item.grams / item.unitGrams).rounded())
                        Text("\(count) \(count == 1 || item.unitName.hasSuffix("s") ? item.unitName : item.unitName + "s")")
                            .font(.subheadline.monospacedDigit())
                    }
                    .fixedSize()
                } else if let density = item.gramsPerMl {
                    TextField("ml", value: Binding(get: { (item.grams / density).rounded() }, set: { item.grams = max(0, $0) * density }),
                              format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .font(.body.monospacedDigit())
                    Text("ml").foregroundStyle(.secondary)
                } else {
                    TextField("g", value: $item.grams, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        .font(.body.monospacedDigit())
                    Text("g").foregroundStyle(.secondary)
                }
            }
            Text("\(Format.kcal(item.nutrients.kilocalories)) kcal · \(Format.grams(item.nutrients.protein)) protein")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Search the food list and pick one.
struct FoodPicker: View {
    let database: NutritionDatabase
    let onPick: (FoodItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List(database.search(query, limit: 80)) { food in
            Button { onPick(food) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name).foregroundStyle(.primary)
                    Text("\(Format.kcal(food.perServing.kilocalories)) kcal · \(Format.grams(food.perServing.protein)) protein · \(food.servingLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rice, soya chunks, paneer…")
        .navigationTitle("Add ingredient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }
}
