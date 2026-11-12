import Charts
import NutriCore
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Binding var section: FoodSection
    @State private var weekStart = DailyTotals.week(containing: .now).first ?? Calendar.current.startOfDay(for: .now)

    private var isCurrentWeek: Bool {
        weekStart == DailyTotals.week(containing: .now).first
    }

    var body: some View {
        NavigationStack {
            WeekHistoryView(weekStart: weekStart)
                .id(weekStart)
                .navigationTitle("Food history")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { FoodSectionPicker(section: $section) }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Previous week", systemImage: "chevron.left") { move(by: -1) }
                        Button("Next week", systemImage: "chevron.right") { move(by: 1) }
                            .disabled(isCurrentWeek)
                    }
                }
        }
    }

    private func move(by weeks: Int) {
        if let date = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: weekStart) {
            weekStart = DailyTotals.week(containing: date).first ?? date
        }
    }
}

/// One week: charts of calories in vs. out and macros, then the per-day log.
private struct WeekHistoryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.dailyCalorieTarget) private var target = SettingsDefault.dailyCalorieTarget

    @Query private var entries: [MealEntry]
    @State private var activity: [Date: ActivitySummary] = [:]
    @State private var deleteError: String?
    @State private var editingMeal: MealEntry?

    private let days: [Date]

    init(weekStart: Date) {
        let days = DailyTotals.week(containing: weekStart)
        self.days = days
        let start = days.first ?? weekStart
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        _entries = Query(filter: MealEntry.predicate(from: start, to: end), sort: \MealEntry.date, order: .reverse)
    }

    private var totals: [DayTotal] {
        DailyTotals.totals(of: entries.map(\.loggedAmount), for: days)
    }

    private var rangeTitle: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    var body: some View {
        List {
            Section {
                caloriesChart
            } header: {
                Text(rangeTitle)
            }
            Section("Macros (kcal from each)") {
                macrosChart
            }
            Section("Daily average") {
                averages
            }
            if let deleteError {
                Section {
                    Label(deleteError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            ForEach(days.reversed(), id: \.self) { day in
                let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                if !dayEntries.isEmpty {
                    Section {
                        ForEach(dayEntries) { entry in
                            Button { editingMeal = entry } label: {
                                MealRow(entry: entry).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button("Edit", systemImage: "pencil") { editingMeal = entry }.tint(.blue)
                            }
                        }
                        .onDelete { offsets in
                            let doomed = offsets.map { dayEntries[$0] }
                            Task { await delete(doomed) }
                        }
                    } header: {
                        HStack {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            Spacer()
                            Text("\(Format.kcal(dayEntries.map(\.kilocalories).reduce(0, +))) kcal")
                        }
                    }
                }
            }
            if entries.isEmpty {
                Section {
                    Text("No meals logged this week.").foregroundStyle(.secondary)
                }
            }
        }
        .task(id: env.healthRevision) {
            activity = (try? await env.health.activity(for: days)) ?? [:]
        }
        .sheet(item: $editingMeal) { LoggedMealEditor(entry: $0) }
    }

    private var caloriesChart: some View {
        Chart {
            ForEach(totals) { total in
                BarMark(
                    x: .value("Day", total.day, unit: .day),
                    y: .value("kcal", total.nutrients.kilocalories)
                )
                .foregroundStyle(by: .value("Series", "Eaten"))
                .position(by: .value("Series", "Eaten"))

                BarMark(
                    x: .value("Day", total.day, unit: .day),
                    y: .value("kcal", activity[total.day]?.totalEnergy ?? 0)
                )
                .foregroundStyle(by: .value("Series", "Burned"))
                .position(by: .value("Series", "Burned"))
            }
            RuleMark(y: .value("Target", target))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .trailing) {
                    Text("Target \(Format.kcal(target))").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale(["Eaten": Palette.eaten, "Burned": Palette.burned])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .frame(height: 220)
        .padding(.vertical, 6)
    }

    private var macrosChart: some View {
        Chart {
            ForEach(totals) { total in
                let n = total.nutrients
                BarMark(x: .value("Day", total.day, unit: .day), y: .value("kcal", n.protein * Nutrients.EnergyPerGram.protein))
                    .foregroundStyle(by: .value("Macro", "Protein"))
                BarMark(x: .value("Day", total.day, unit: .day), y: .value("kcal", n.carbohydrates * Nutrients.EnergyPerGram.carbohydrates))
                    .foregroundStyle(by: .value("Macro", "Carbs"))
                BarMark(x: .value("Day", total.day, unit: .day), y: .value("kcal", n.fat * Nutrients.EnergyPerGram.fat))
                    .foregroundStyle(by: .value("Macro", "Fat"))
            }
        }
        .chartForegroundStyleScale(["Protein": Palette.protein, "Carbs": Palette.carbohydrates, "Fat": Palette.fat])
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .frame(height: 180)
        .padding(.vertical, 6)
    }

    private var averages: some View {
        let loggedDays = totals.filter { $0.entryCount > 0 }
        let eaten = DailyTotals.averageKilocalories(of: totals)
        let burnedDays = loggedDays.compactMap { activity[$0.day]?.totalEnergy }.filter { $0 > 0 }
        let burned = burnedDays.isEmpty ? 0 : burnedDays.reduce(0, +) / Double(burnedDays.count)
        return HStack {
            StatTile(title: "Eaten", value: Format.kcal(eaten), unit: "kcal", systemImage: "fork.knife", tint: Palette.eaten)
            StatTile(title: "Burned", value: Format.kcal(burned), unit: "kcal", systemImage: "flame", tint: Palette.burned)
            StatTile(title: "Net", value: burned > 0 ? Format.signedKcal(eaten - burned) : "–", unit: burned > 0 ? "kcal" : "", systemImage: "plusminus", tint: Palette.net)
        }
    }

    private func delete(_ doomed: [MealEntry]) async {
        deleteError = await MealLog.delete(doomed, env: env, context: modelContext)
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    HistoryView(section: .constant(.history))
        .environment(environment)
        .modelContainer(environment.modelContainer)
}
