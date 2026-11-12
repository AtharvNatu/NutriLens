import NutriCore
import SwiftData
import SwiftUI

/// Changing or removing a meal that's already logged, here and in Apple Health.
@MainActor
enum MealLog {
    /// Writes the edited entry to Health (a new sample with the same NutriLens id, then the old one removed, so the
    /// other device picks up the change) and saves. Returns a warning to show, or nil.
    static func saveChanges(to entry: MealEntry, env: AppEnvironment, context: ModelContext, now: Date = .now) async -> String? {
        entry.updatedAt = now
        var warning: String?
        if env.health.isAvailable {
            do {
                let old = entry.healthKitID
                entry.healthKitID = try await env.health.saveMeal(entry.healthSample)
                if let old {
                    do { try await env.health.deleteMeal(id: old) } catch HealthDataError.notFound {}
                }
            } catch {
                warning = "Changed in NutriLens, but Apple Health still has the old values: \(error.localizedDescription)"
            }
        }
        do {
            try context.save()
        } catch {
            return "Couldn't save the change: \(error.localizedDescription)"
        }
        env.healthDidChange()
        return warning
    }

    /// Removes the entries here and in Health, leaving a tombstone so backups and the other device drop them too.
    /// Returns a warning to show, or nil.
    static func delete(_ entries: [MealEntry], env: AppEnvironment, context: ModelContext) async -> String? {
        var warning: String?
        for entry in entries {
            if let id = entry.healthKitID, env.health.isAvailable {
                do {
                    try await env.health.deleteMeal(id: id)
                } catch HealthDataError.notFound {
                    // Already removed in the Health app; nothing to do.
                } catch {
                    warning = "Removed from NutriLens, but not from Apple Health: \(error.localizedDescription)"
                }
            }
            Tombstone.record(entry.id, type: SyncRecordType.meal, in: context)
            context.delete(entry)
        }
        try? context.save()
        env.healthDidChange()
        return warning
    }
}

/// What can be changed about a logged meal. Changing the amount scales the nutrition with it;
/// the nutrition can also be typed in directly.
struct MealEdit: Equatable {
    var name: String
    var mealType: MealType
    var date: Date
    var grams: Double
    var nutrients: Nutrients
    /// Nutrition per gram as logged, so a new amount scales it.
    let perGram: Nutrients?

    init(_ entry: MealEntry) {
        name = entry.name
        mealType = entry.mealType
        date = entry.date
        grams = entry.grams
        nutrients = entry.nutrients
        perGram = entry.grams > 0 ? entry.nutrients.scaled(by: 1 / entry.grams) : nil
    }

    /// Sets a new amount and scales the nutrition to match.
    mutating func setGrams(_ value: Double) {
        let value = max(0, value.isFinite ? value : 0)
        grams = value
        if let perGram { nutrients = perGram.scaled(by: value) }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && nutrients.kilocalories >= 0 && grams >= 0
    }

    func apply(to entry: MealEntry) {
        entry.name = name.trimmingCharacters(in: .whitespaces)
        entry.mealType = mealType
        entry.date = date
        entry.grams = grams
        entry.kilocalories = nutrients.kilocalories
        entry.protein = nutrients.protein
        entry.carbohydrates = nutrients.carbohydrates
        entry.fat = nutrients.fat
    }
}

/// Opened by tapping a logged meal: change its amount, nutrition, meal, time or name, or delete it.
struct LoggedMealEditor: View {
    let entry: MealEntry
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var edit: MealEdit
    @State private var original: MealEdit
    @State private var isSaving = false
    @State private var confirmingDelete = false
    @State private var message: String?

    init(entry: MealEntry) {
        self.entry = entry
        let edit = MealEdit(entry)
        _edit = State(initialValue: edit)
        _original = State(initialValue: edit)
    }

    private var gramsBinding: Binding<Double> {
        Binding(get: { edit.grams }, set: { edit.setGrams($0) })
    }

    private func nutrient(_ keyPath: WritableKeyPath<Nutrients, Double>) -> Binding<Double> {
        Binding(get: { edit.nutrients[keyPath: keyPath] }, set: { edit.nutrients[keyPath: keyPath] = max(0, $0.isFinite ? $0 : 0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $edit.name)
                    Picker("Meal", selection: $edit.mealType) {
                        ForEach(MealType.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                    }
                    DatePicker("Time", selection: $edit.date, in: ...Date.now.addingTimeInterval(3_600))
                }

                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Grams", value: gramsBinding, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                            .font(.body.monospacedDigit())
                        Text("g").foregroundStyle(.secondary)
                    }
                    if original.grams > 0 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2], id: \.self) { factor in
                                    let grams = (original.grams * factor).rounded()
                                    Button(factor == 1 ? "As logged" : "\(Format.servings(factor))×") { edit.setGrams(grams) }
                                        .buttonStyle(.bordered)
                                        .tint(abs(edit.grams - grams) < 0.5 ? .accentColor : .secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Portion")
                } footer: {
                    Text(original.grams > 0
                         ? "Nutrition scales with the amount. Logged: \(Format.grams(original.grams)), \(Format.kcal(original.nutrients.kilocalories)) kcal."
                         : "Logged without a weight: edit the nutrition below.")
                }

                Section {
                    numberRow("Energy", value: nutrient(\.kilocalories), unit: "kcal")
                    numberRow("Protein", value: nutrient(\.protein), unit: "g")
                    numberRow("Carbohydrates", value: nutrient(\.carbohydrates), unit: "g")
                    numberRow("Fat", value: nutrient(\.fat), unit: "g")
                } header: {
                    Text("Nutrition")
                }

                if let message {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                }

                Section {
                    Button("Delete meal", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .tint(.red)
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!edit.isValid || edit == original)
                    }
                }
            }
            .confirmationDialog("Delete \(entry.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete meal", role: .destructive) { Task { await delete() } }
            } message: {
                Text("Also removed from Apple Health and your other device.")
            }
            .interactiveDismissDisabled(edit != original)
        }
    }

    private func numberRow(_ title: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .font(.body.monospacedDigit())
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        edit.apply(to: entry)
        message = await MealLog.saveChanges(to: entry, env: env, context: modelContext)
        original = edit
        if message == nil { dismiss() }
    }

    private func delete() async {
        message = await MealLog.delete([entry], env: env, context: modelContext)
        dismiss()
    }
}
