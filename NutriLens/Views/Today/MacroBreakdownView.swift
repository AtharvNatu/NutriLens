import NutriCore
import SwiftUI

/// Which number the breakdown splits up.
enum Macro: String, CaseIterable, Identifiable {
    case protein, carbohydrates, fat, energy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: "Protein"
        case .carbohydrates: "Carbs"
        case .fat: "Fat"
        case .energy: "Calories"
        }
    }

    var tint: Color {
        switch self {
        case .protein: Palette.protein
        case .carbohydrates: Palette.carbohydrates
        case .fat: Palette.fat
        case .energy: Palette.eaten
        }
    }

    func value(_ n: Nutrients) -> Double {
        switch self {
        case .protein: n.protein
        case .carbohydrates: n.carbohydrates
        case .fat: n.fat
        case .energy: n.kilocalories
        }
    }

    func format(_ value: Double) -> String {
        self == .energy ? "\(Format.kcal(value)) kcal" : Format.grams(value)
    }
}

/// How one macro splits across the day's meals and items.
struct MacroBreakdown {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let name: String
        let mealType: MealType
        let date: Date
        let grams: Double
        let value: Double
        /// Share of the day's total, 0…1.
        let share: Double
    }

    struct Group: Identifiable, Equatable {
        var id: MealType { mealType }
        let mealType: MealType
        let value: Double
        let share: Double
        let itemCount: Int
    }

    let total: Double
    /// Biggest contributor first.
    let items: [Item]
    /// Breakfast, lunch, snack, dinner; meals with nothing logged are left out.
    let groups: [Group]

    init(meals: [MealEntry], macro: Macro) {
        let values = meals.map { macro.value($0.nutrients) }
        let total = values.reduce(0, +)
        let share: (Double) -> Double = { total > 0 ? $0 / total : 0 }
        self.total = total
        items = zip(meals, values)
            .map { meal, value in
                Item(id: meal.id, name: meal.name, mealType: meal.mealType, date: meal.date, grams: meal.grams, value: value, share: share(value))
            }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.date < $1.date }
        groups = MealType.allCases.compactMap { type in
            let inGroup = zip(meals, values).filter { $0.0.mealType == type }
            guard !inGroup.isEmpty else { return nil }
            let value = inGroup.map(\.1).reduce(0, +)
            return Group(mealType: type, value: value, share: share(value), itemCount: inGroup.count)
        }
    }
}

/// Opened from the Macros card on Today: what each meal and item contributed.
struct MacroBreakdownView: View {
    let meals: [MealEntry]
    let targets: [Macro: Double]
    @State var macro: Macro
    @Environment(\.dismiss) private var dismiss

    private var breakdown: MacroBreakdown { MacroBreakdown(meals: meals, macro: macro) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $macro) {
                        ForEach(Macro.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    summary
                }

                if meals.isEmpty {
                    Section {
                        Text("Nothing logged yet today.").foregroundStyle(.secondary)
                    }
                } else {
                    Section("By meal") {
                        ForEach(breakdown.groups) { group in
                            ShareRow(title: group.mealType.displayName,
                                     subtitle: group.itemCount == 1 ? "1 item" : "\(group.itemCount) items",
                                     systemImage: group.mealType.symbolName,
                                     value: macro.format(group.value), share: group.share, tint: macro.tint)
                        }
                    }
                    Section {
                        ForEach(breakdown.items) { item in
                            ShareRow(title: item.name,
                                     subtitle: "\(item.mealType.displayName) · \(item.date.formatted(date: .omitted, time: .shortened)) · \(Format.grams(item.grams))",
                                     systemImage: nil,
                                     value: macro.format(item.value), share: item.share, tint: macro.tint)
                        }
                    } header: {
                        Text("By item")
                    } footer: {
                        Text("Biggest contributor first. Percentages are shares of today's \(macro.title.lowercased()).")
                    }
                }
            }
            .navigationTitle("Today's macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var summary: some View {
        let target = targets[macro] ?? 0
        let total = breakdown.total
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(macro.format(total)).font(.title2.bold().monospacedDigit())
                if target > 0 {
                    Text("of \(macro.format(target))").foregroundStyle(.secondary)
                    Spacer()
                    Text(total > target ? "\(macro.format(total - target)) over" : "\(macro.format(target - total)) left")
                        .font(.subheadline)
                        .foregroundStyle(total > target ? .red : .secondary)
                }
            }
            if target > 0 {
                ProgressView(value: min(total, target), total: target)
                    .tint(total > target ? .red : macro.tint)
            }
            if macro != .energy {
                let kcal = total * (macro == .fat ? 9 : 4)
                let allKcal = meals.map(\.kilocalories).reduce(0, +)
                if allKcal > 0 {
                    Text("\(Format.kcal(kcal)) kcal · \(Int((kcal / allKcal * 100).rounded())) % of today's calories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A name, its amount and its share of the total as a bar.
private struct ShareRow: View {
    let title: String
    let subtitle: String
    let systemImage: String?
    let value: String
    let share: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).foregroundStyle(Palette.eaten).frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value).font(.body.monospacedDigit())
                    Text("\(Int((share * 100).rounded())) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: share).tint(tint)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
