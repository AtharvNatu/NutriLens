import NutriCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Your own foods: add, edit, delete, and import/export a list as CSV.
struct MyFoodsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomFood.name) private var foods: [CustomFood]
    @State private var editing: CustomFood?
    @State private var adding = false
    @State private var importing = false
    @State private var exportURL: URL?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                if foods.isEmpty {
                    Text("Add family recipes, packaged foods or anything missing from the list.")
                        .foregroundStyle(.secondary)
                }
                ForEach(foods) { food in
                    NavigationLink(value: LogRoute.editor(food.foodItem, .custom)) {
                        FoodRow(food: food.foodItem)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Edit", systemImage: "pencil") { editing = food }.tint(.blue)
                    }
                }
                .onDelete(perform: delete)
            } header: {
                Text("\(foods.count) food\(foods.count == 1 ? "" : "s")")
            } footer: {
                Text("Swipe right to edit, left to delete. Long-press any food in the list to copy it here.")
            }

            Section {
                NavigationLink(value: LogRoute.builder([])) {
                    Label("New dish: say what's in it", systemImage: "mic")
                }
                Button("Import a list (CSV)", systemImage: "square.and.arrow.down") { importing = true }
                Button("Export my foods (CSV)", systemImage: "square.and.arrow.up") { export() }
                    .disabled(foods.isEmpty)
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share \(exportURL.lastPathComponent)", systemImage: "paperplane") }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Lists")
            } footer: {
                Text("CSV columns (per serving): \(FoodListCSV.header).")
            }
        }
        .navigationTitle("My foods")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add food", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { CustomFoodEditor() }
        }
        .sheet(item: $editing) { food in
            NavigationStack { CustomFoodEditor(existing: food) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            importList(result)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let food = foods[index]
            Tombstone.record(food.id, type: SyncRecordType.customFood, in: modelContext)
            modelContext.delete(food)
        }
        try? modelContext.save()
    }

    private func export() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NutriLens-my-foods.csv")
        do {
            try FoodListCSV.export(foods.map(\.draft)).write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            message = nil
        } catch {
            message = "Couldn't export: \(error.localizedDescription)"
        }
    }

    private func importList(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let parsed = FoodListCSV.parse(try String(contentsOf: url, encoding: .utf8))
            // Same name replaces the existing entry, so re-importing an edited list updates it.
            var byName = Dictionary(foods.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
            var added = 0, updated = 0
            for draft in parsed.foods {
                if let existing = byName[draft.name.lowercased()] {
                    existing.apply(draft)
                    updated += 1
                } else {
                    let food = CustomFood(draft: draft)
                    modelContext.insert(food)
                    byName[draft.name.lowercased()] = food
                    added += 1
                }
            }
            try modelContext.save()
            var text = "Imported: \(added) added, \(updated) updated."
            if !parsed.errors.isEmpty { text += " Skipped \(parsed.errors.count): " + parsed.errors.prefix(3).joined(separator: "; ") }
            message = text
        } catch {
            message = "Couldn't import: \(error.localizedDescription)"
        }
    }
}

/// Add or edit one of your foods, entered per serving.
struct CustomFoodEditor: View {
    var existing: CustomFood?
    var initial: CustomFoodDraft?
    /// When set (logging flow), called with the saved food so it can be logged straight away.
    var onSaved: ((FoodItem) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = FoodCategory.main
    @State private var serving = "1 serving"
    @State private var grams: Double? = 100
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var notes = ""
    @State private var loaded = false

    private var draft: CustomFoodDraft {
        CustomFoodDraft(name: name, servingDescription: serving, servingGrams: (grams ?? 0) > 0 ? grams! : 100,
                        perServing: Nutrients(kilocalories: kcal ?? 0, protein: protein ?? 0, carbohydrates: carbs ?? 0, fat: fat ?? 0),
                        category: category.rawValue, notes: notes)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (kcal ?? 0) > 0 }

    var body: some View {
        Form {
            Section {
                TextField("Name (e.g. Aai's thalipeeth)", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(FoodCategory.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                TextField("Serving (e.g. 1 plate, 1 ladoo)", text: $serving)
                numberField("Serving weight", value: $grams, unit: "g")
                numberField("Energy", value: $kcal, unit: "kcal")
                numberField("Protein", value: $protein, unit: "g")
                numberField("Carbohydrates", value: $carbs, unit: "g")
                numberField("Fat", value: $fat, unit: "g")
            } header: {
                Text("One serving contains")
            } footer: {
                if canSave {
                    let n = draft.per100g
                    Text("Per 100 g: \(Format.kcal(n.kilocalories)) kcal, \(Format.grams(n.protein)) protein.")
                } else {
                    Text("A name and energy are needed. Protein, carbs and fat help the macro targets.")
                }
            }
            Section("Notes") {
                TextField("e.g. less oil, with peanuts", text: $notes, axis: .vertical)
            }
        }
        .navigationTitle(existing == nil ? "New food" : "Edit food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onSaved == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(onSaved == nil ? "Save" : "Save & log") { save() }.disabled(!canSave)
            }
        }
        .onAppear(perform: load)
    }

    private func numberField(_ title: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let d = existing?.draft ?? initial else { return }
        name = existing == nil ? "\(d.name) (mine)" : d.name
        category = FoodCategory(rawValue: d.category) ?? .main
        serving = d.servingDescription
        grams = d.servingGrams
        kcal = (d.perServing.kilocalories * 10).rounded() / 10
        protein = (d.perServing.protein * 10).rounded() / 10
        carbs = (d.perServing.carbohydrates * 10).rounded() / 10
        fat = (d.perServing.fat * 10).rounded() / 10
        notes = d.notes
    }

    private func save() {
        let food: CustomFood
        if let existing {
            existing.apply(draft)
            food = existing
        } else {
            food = CustomFood(draft: draft)
            modelContext.insert(food)
        }
        try? modelContext.save()
        if let onSaved { onSaved(food.foodItem) } else { dismiss() }
    }
}
