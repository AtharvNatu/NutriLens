import NutriCore
import SwiftData
import SwiftUI

/// Confirm the dish, pick the portion and time, then save to the log and Apple Health.
struct MealEditorView: View {
    enum PortionUnit: String, CaseIterable, Identifiable {
        case servings = "Servings"
        case grams = "Grams"
        case millilitres = "ml"
        var id: String { rawValue }
    }

    let food: FoodItem
    let source: MealSource
    let photoData: Data?
    let onSaved: (SaveResult) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @State private var unit = PortionUnit.servings
    @State private var servings = 1.0
    @State private var grams: Double
    @State private var date = Date.now
    @State private var mealType = MealType.suggested(for: .now)
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Amounts for dishes you can make your way (eggs, paneer, oil…).
    @State private var amounts: [String: Double]
    @State private var usual: [String: Double]?

    private var recipe: DishRecipe? { DishRecipes.recipe(for: food) }

    /// The dish as you made it; the food itself when it has no recipe or uses the typical amounts.
    private var madeFood: FoodItem {
        recipe?.customized(food, amounts: amounts, database: env.database) ?? food
    }

    private var recipeResult: DishRecipe.Result? {
        recipe?.result(amounts: amounts, dish: food, database: env.database)
    }

    init(food: FoodItem, source: MealSource, photoData: Data?, onSaved: @escaping (SaveResult) -> Void) {
        self.food = food
        self.source = source
        self.photoData = photoData
        self.onSaved = onSaved
        let recipe = DishRecipes.recipe(for: food)
        let usual = recipe.flatMap { RecipePreferences.usual(for: $0) }
        _usual = State(initialValue: usual)
        _amounts = State(initialValue: usual ?? recipe?.typicalAmounts ?? [:])
        let start = recipe.map { $0.customized(food, amounts: usual ?? $0.typicalAmounts, database: .bundled) } ?? food
        _grams = State(initialValue: start.servingGrams.rounded())
        // Milk, buttermilk and oil are measured in ml; drinks and dishes keep servings (1 cup, 1 glass).
        if food.millilitreGrams != nil, recipe == nil, food.category != "drink" { _unit = State(initialValue: .millilitres) }
    }

    private var portion: Portion {
        unit == .servings ? .servings(servings) : .grams(grams)
    }

    private var nutrients: Nutrients { madeFood.nutrients(for: portion) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(.rect(cornerRadius: 10))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).font(.title3.bold())
                        Text("1 serving = \(madeFood.servingLabel) · \(Format.kcal(madeFood.perServing.kilocalories)) kcal · \(Format.grams(madeFood.perServing.protein)) protein")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let recipe { recipeSection(recipe) }

            Section("Portion") {
                Picker("Unit", selection: $unit) {
                    ForEach(PortionUnit.allCases.filter { $0 != .millilitres || madeFood.millilitreGrams != nil }) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: unit) { old, new in convert(from: old, to: new) }

                if unit == .servings {
                    Stepper(value: $servings, in: 0.25...20, step: 0.25) {
                        Text("\(Format.servings(servings)) × \(madeFood.servingDescription)")
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(PortionPresets.servingMultipliers, id: \.self) { value in
                                Button(Format.servings(value) + "×") { servings = value }
                                    .buttonStyle(.bordered)
                                    .tint(value == servings ? .accentColor : .secondary)
                            }
                        }
                    }
                } else if unit == .millilitres, let density = madeFood.millilitreGrams {
                    let ml = Binding(get: { (grams / density).rounded() }, set: { grams = max(0, $0) * density })
                    HStack {
                        TextField("ml", value: ml, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                        Text("ml").foregroundStyle(.secondary)
                        Stepper("Millilitres", value: ml, in: 0...5_000, step: 10)
                            .labelsHidden()
                    }
                } else {
                    HStack {
                        TextField("Grams", value: $grams, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                        Text("g").foregroundStyle(.secondary)
                        Stepper("Grams", value: $grams, in: 0...5_000, step: 10)
                            .labelsHidden()
                    }
                }
            }

            Section("Nutrition") {
                LabeledContent("Energy") {
                    Text("\(Format.kcal(nutrients.kilocalories)) kcal").font(.headline.monospacedDigit())
                }
                LabeledContent("Protein", value: Format.grams(nutrients.protein))
                LabeledContent("Carbohydrates", value: Format.grams(nutrients.carbohydrates))
                LabeledContent("Fat", value: Format.grams(nutrients.fat))
                if let ml = madeFood.millilitres(fromGrams: portion.grams(for: madeFood)) {
                    LabeledContent("Amount", value: "\(Int(ml.rounded())) ml")
                } else {
                    LabeledContent("Weight", value: Format.grams(portion.grams(for: madeFood)))
                }
            }

            Section {
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                }
                DatePicker("Time", selection: $date, in: ...Date.now.addingTimeInterval(3_600))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let source = food.proteinSource {
                        Text("Protein from \(source)." + (food.notes.map { " \($0)" } ?? ""))
                    } else if let notes = food.notes {
                        Text(notes)
                    }
                    if !food.isCustom {
                        Text("Typical home-recipe values.")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Confirm meal")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: date) { _, newDate in mealType = MealType.suggested(for: newDate) }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(portion.grams(for: madeFood) <= 0)
                }
            }
        }
    }

    private func convert(from old: PortionUnit, to new: PortionUnit) {
        guard old != new else { return }
        switch new {
        case .grams, .millilitres:
            // Grams and ml share the same amount underneath; only leaving servings needs converting.
            if old == .servings { grams = Portion.servings(servings).grams(for: madeFood).rounded() }
        case .servings: servings = PortionPresets.roundedServings(Portion.grams(grams).servings(for: madeFood))
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let amount = nutrients
        let name = recipeResult.map { $0.isTypical ? food.name : "\(food.name) (\($0.summary))" } ?? food.name
        let entry = MealEntry(
            date: date,
            name: name,
            foodID: food.id,
            grams: portion.grams(for: madeFood),
            nutrients: amount,
            mealType: mealType,
            source: source,
            photoData: photoData
        )
        modelContext.insert(entry)

        var note = ""
        if env.health.isAvailable {
            do {
                entry.healthKitID = try await env.health.saveMeal(entry.healthSample)
            } catch {
                note = " Not saved to Apple Health (\(error.localizedDescription))."
            }
        }
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Couldn't save the meal: \(error.localizedDescription)"
            return
        }
        env.healthDidChange()
        onSaved(SaveResult(text: "Logged \(name), \(Format.kcal(amount.kilocalories)) kcal.\(note)", isWarning: !note.isEmpty))
    }

    // MARK: Make it your way

    private func recipeSection(_ recipe: DishRecipe) -> some View {
        Section {
            ForEach(recipe.components.filter { !$0.isAddIn || (amounts[$0.id] ?? 0) > 0 }) { component in
                Stepper(value: Binding(get: { amounts[component.id] ?? component.typical },
                                       set: { amounts[component.id] = component.clamped($0) }),
                        in: component.range, step: component.step) {
                    LabeledContent(component.label, value: component.amountText(amounts[component.id] ?? component.typical))
                }
                .swipeActions {
                    if component.isAddIn {
                        Button("Remove", role: .destructive) { amounts[component.id] = 0 }
                    }
                }
            }
            let addable = recipe.components.filter { $0.isAddIn && (amounts[$0.id] ?? 0) == 0 }
            if !addable.isEmpty {
                Menu {
                    ForEach(addable) { component in
                        Button(component.label) { amounts[component.id] = component.addAmount }
                    }
                } label: {
                    Label("Add protein", systemImage: "plus.circle")
                }
            }
            if let result = recipeResult {
                LabeledContent("One portion", value: "\(Format.kcal(result.nutrients.kilocalories)) kcal · \(Format.grams(result.nutrients.protein)) protein")
                    .font(.subheadline)
            }
            let isUsual = usual.map { recipe.result(amounts: $0, dish: food, database: env.database).summary == recipeResult?.summary } ?? false
            if !isUsual, usual != nil || recipeResult?.isTypical == false {
                Button("Make this my usual", systemImage: "star") {
                    RecipePreferences.save(amounts, for: recipe)
                    usual = amounts
                }
            }
            if recipeResult?.isTypical == false {
                Button("Back to typical", systemImage: "arrow.uturn.backward") { amounts = recipe.typicalAmounts }
            }
            if usual != nil {
                Button("Forget my usual", systemImage: "star.slash") {
                    RecipePreferences.forget(recipe)
                    usual = nil
                }
            }
        } header: {
            Text("Make it your way")
        } footer: {
            recipeFooter(recipe)
        }
    }

    private func recipeFooter(_ recipe: DishRecipe) -> Text {
        let typical = recipe.result(amounts: recipe.typicalAmounts, dish: food, database: env.database).summary
        var parts: [String] = []
        if !typical.isEmpty { parts.append("Typical: \(typical).") }
        if usual != nil { parts.append("Your usual amounts are used by default.") }
        if recipe.components.contains(where: { $0.isAddIn && (amounts[$0.id] ?? 0) > 0 }) { parts.append("Swipe an added item to remove it.") }
        return Text(parts.joined(separator: " "))
    }
}

/// Your usual amounts per dish (e.g. 3 eggs and 1 tsp oil in egg bhurji). Included in backups.
enum RecipePreferences {
    static func all(defaults: UserDefaults = .standard) -> [String: [String: Double]] {
        guard let text = defaults.string(forKey: SettingsKey.dishRecipeDefaults),
              let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else { return [:] }
        return value
    }

    static func usual(for recipe: DishRecipe, defaults: UserDefaults = .standard) -> [String: Double]? {
        all(defaults: defaults)[recipe.dishID]
    }

    /// `food` as you usually make it, or `food` itself.
    static func asUsual(_ food: FoodItem, database: NutritionDatabase = .bundled, defaults: UserDefaults = .standard) -> FoodItem {
        guard let recipe = DishRecipes.recipe(for: food), let usual = usual(for: recipe, defaults: defaults) else { return food }
        return recipe.customized(food, amounts: usual, database: database)
    }

    static func save(_ amounts: [String: Double], for recipe: DishRecipe, defaults: UserDefaults = .standard) {
        var value = all(defaults: defaults)
        value[recipe.dishID] = amounts.filter { key, _ in recipe.components.contains { $0.id == key } }
        store(value, defaults: defaults)
    }

    static func forget(_ recipe: DishRecipe, defaults: UserDefaults = .standard) {
        var value = all(defaults: defaults)
        value[recipe.dishID] = nil
        store(value, defaults: defaults)
    }

    private static func store(_ value: [String: [String: Double]], defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            defaults.set(text, forKey: SettingsKey.dishRecipeDefaults)
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    NavigationStack {
        MealEditorView(food: environment.database.food(id: "pizza")!, source: .photo, photoData: nil) { _ in }
    }
    .environment(environment)
    .modelContainer(environment.modelContainer)
}
