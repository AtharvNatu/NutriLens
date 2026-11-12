import NutriCore
import SwiftUI

/// Quick protein-rich recipes (30 minutes or less), filtered by meal and diet.
struct RecipesView: View {
    @Binding var section: FoodSection
    @Environment(AppEnvironment.self) private var env
    @State private var meal: ProteinRecipe.Meal? = MealType.suggested(for: .now).recipeMeal
    @State private var diet: ProteinRecipe.Diet?
    @State private var path: [ProteinRecipe] = []
    @State private var savedMessage: SaveResult?

    private var recipes: [ProteinRecipe] {
        ProteinRecipes.filtered(meal: meal, diets: diet.map { [$0] } ?? Set(ProteinRecipe.Diet.allCases), database: env.database)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let savedMessage {
                    Section {
                        Label(savedMessage.text, systemImage: savedMessage.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(savedMessage.isWarning ? .orange : .green)
                    }
                }
                Section {
                    ForEach(recipes) { recipe in
                        NavigationLink(value: recipe) { RecipeRow(recipe: recipe) }
                    }
                } header: {
                    filters
                } footer: {
                    if recipes.isEmpty { Text("No recipe matches these filters.") }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { FoodSectionPicker(section: $section) }
            }
            .navigationDestination(for: ProteinRecipe.self) { recipe in
                RecipeDetailView(recipe: recipe) { result in
                    path = []
                    savedMessage = result
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("All", selected: meal == nil) { meal = nil }
                    ForEach(ProteinRecipe.Meal.allCases) { m in chip(m.title, selected: meal == m) { meal = m } }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Any diet", selected: diet == nil) { diet = nil }
                    ForEach(ProteinRecipe.Diet.allCases) { d in chip(d.title, selected: diet == d) { diet = d } }
                }
            }
            Text("≤ 30 min · most protein first").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .textCase(nil)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: .capsule)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .buttonStyle(.plain)
    }
}

private struct RecipeRow: View {
    let recipe: ProteinRecipe
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let n = recipe.nutrition(database: env.database).nutrients
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(recipe.name).font(.body.weight(.medium))
                Spacer(minLength: 4)
                DietTag(diet: recipe.diet)
            }
            HStack(spacing: 10) {
                Label("\(recipe.minutes) min", systemImage: "clock")
                Text("\(Format.grams(n.protein)) protein").foregroundStyle(Palette.protein)
                Text("\(Format.kcal(n.kilocalories)) kcal")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DietTag: View {
    let diet: ProteinRecipe.Diet

    var body: some View {
        let color: Color = switch diet {
        case .veg: .green
        case .egg: .orange
        case .nonVeg: .red
        }
        Text(diet.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }
}

/// Ingredients, steps and nutrition for one serving, with a button to log it.
struct RecipeDetailView: View {
    let recipe: ProteinRecipe
    let onSaved: (SaveResult) -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var logging = false
    @State private var changing = false
    /// Your version of the recipe, to log.
    @State private var changed: FoodItem?

    var body: some View {
        let (n, grams) = recipe.nutrition(database: env.database)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.summary).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Label("\(recipe.minutes) min", systemImage: "clock")
                        Label("1 serving", systemImage: "person")
                        DietTag(diet: recipe.diet)
                    }
                    .font(.subheadline)
                    Text("For " + ListFormatter.localizedString(byJoining: recipe.meals.map { $0.title.lowercased() }))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    StatTile(title: "Protein", value: Format.grams(n.protein), systemImage: "bolt.heart", tint: Palette.protein)
                    StatTile(title: "Energy", value: Format.kcal(n.kilocalories), unit: "kcal", systemImage: "flame", tint: Palette.eaten)
                }
                Text("Carbs \(Format.grams(n.carbohydrates)) · Fat \(Format.grams(n.fat)) · \(Format.grams(grams)) in all")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }

            if let ahead = recipe.ahead {
                Section {
                    Label(ahead, systemImage: "calendar.badge.clock").font(.subheadline)
                } header: {
                    Text("Ahead (not timed)")
                }
            }

            Section("Ingredients") {
                ForEach(recipe.ingredients, id: \.text) { item in
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.text)
                        Spacer()
                        if item.grams > 0 {
                            Text(Format.grams(item.grams)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Steps") {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(.tint)
                        Text(step)
                    }
                }
            }

            if let tip = recipe.tip {
                Section {
                    Label(tip, systemImage: "lightbulb").font(.subheadline)
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { changing = true } label: {
                    Label("Change", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    changed = nil
                    logging = true
                } label: {
                    Label("Log this meal", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationDestination(isPresented: $changing) {
            DishBuilderView(starts: [], initial: IngredientDish.from(recipe, database: env.database)) { food in
                changed = food
                changing = false
                logging = true
            }
        }
        .navigationDestination(isPresented: $logging) {
            MealEditorView(food: changed ?? recipe.foodItem(database: env.database), source: .search, photoData: nil) { result in
                logging = false
                changed = nil
                onSaved(result)
            }
        }
    }
}

extension MealType {
    /// The matching recipe filter.
    var recipeMeal: ProteinRecipe.Meal {
        switch self {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .snack: .snack
        case .dinner: .dinner
        }
    }
}
