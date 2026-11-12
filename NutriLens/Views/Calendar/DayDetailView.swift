import NutriCore
import SwiftData
import SwiftUI

/// Everything recorded on one day, with buttons to step to the previous or next day.
struct DayDetailView: View {
    @State private var day: Date
    private let calendar = Calendar.current

    init(day: Date) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    private var isToday: Bool { calendar.isDateInToday(day) }

    var body: some View {
        DayDetailContent(day: day)
            .id(day)
            .navigationTitle(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Previous day", systemImage: "chevron.left") { step(-1) }
                    Button("Next day", systemImage: "chevron.right") { step(1) }
                        .disabled(isToday)
                }
            }
    }

    private func step(_ by: Int) {
        guard let next = calendar.date(byAdding: .day, value: by, to: day), next <= .now else { return }
        day = next
    }
}

private struct DayDetailContent: View {
    let day: Date

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKey.dailyStepGoal) private var stepGoal = SettingsDefault.dailyStepGoal

    @Query private var records: [DayRecord]
    @Query private var meals: [MealEntry]
    @Query private var logs: [WorkoutLog]
    @State private var loading = true
    @State private var editingMeal: MealEntry?

    init(day: Date) {
        self.day = day
        let key = DayRecord.key(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        _records = Query(filter: #Predicate<DayRecord> { $0.dayKey == key }, sort: \DayRecord.updatedAt, order: .reverse)
        _meals = Query(filter: MealEntry.predicate(from: day, to: end), sort: \MealEntry.date)
        _logs = Query(filter: WorkoutLog.predicate(from: day, to: end), sort: \WorkoutLog.start)
    }

    private var record: DayRecord? { records.first }

    var body: some View {
        ScrollView {
            if let record {
                CardColumns(columns: sizeClass == .regular ? 2 : 1) {
                    caloriesCard(record)
                    macrosCard(record)
                    workoutsCard(record)
                    activityCard(record)
                    sleepAndWeightCard(record)
                    mealsCard
                }
                .padding()
            } else if loading {
                ProgressView().padding(.top, 80)
            } else {
                ContentUnavailableView("Nothing recorded", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("No data for this day."))
            }
        }
        .background(Color(.systemGroupedBackground))
        .task(id: env.healthRevision) {
            await DayRecorder.record(days: [day], health: env.health, context: context)
            loading = false
        }
        .sheet(item: $editingMeal) { LoggedMealEditor(entry: $0) }
    }

    private func caloriesCard(_ r: DayRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Calories", systemImage: "flame.fill", tint: Palette.eaten)
            HStack(spacing: 20) {
                ProgressRing(progress: r.budgetKcal > 0 ? r.eatenKcal / r.budgetKcal : 0, tint: Palette.eaten) {
                    VStack(spacing: 0) {
                        Text(Format.kcal(r.eatenKcal)).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.6)
                        Text("kcal eaten").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Budget", value: "\(Format.kcal(r.budgetKcal)) kcal")
                    LabeledContent(r.eatenKcal > r.budgetKcal ? "Over" : "Under", value: "\(Format.kcal(abs(r.budgetKcal - r.eatenKcal))) kcal")
                    LabeledContent("Burned", value: "\(Format.kcal(r.burnedKcal)) kcal")
                    LabeledContent("Net", value: "\(Format.signedKcal(r.netKcal)) kcal")
                }
                .font(.subheadline.monospacedDigit())
            }
            Text("Budget = target \(Format.kcal(r.targetKcal)) + exercise credit \(Format.kcal(r.budgetKcal - r.targetKcal)). Burned = active \(Format.kcal(r.burnedKcal - r.basalEnergy)) + resting \(Format.kcal(r.basalEnergy)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func macrosCard(_ r: DayRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Macros", systemImage: "chart.bar.fill", tint: Palette.protein)
            let t = env.macroTargets(on: day)
            MacroBar(name: "Protein", grams: r.protein, target: t.protein, tint: Palette.protein)
            MacroBar(name: "Carbohydrates", grams: r.carbohydrates, target: t.carbohydrates, tint: Palette.carbohydrates)
            MacroBar(name: "Fat", grams: r.fat, target: t.fat, tint: Palette.fat)
            Text("\(t.dayTitle) targets.").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func workoutsCard(_ r: DayRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Workouts", systemImage: "dumbbell.fill", tint: Palette.burned)
            if r.workouts.isEmpty {
                Text("No workouts.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(r.workouts) { w in
                    HStack(spacing: 12) {
                        Image(systemName: w.symbolName)
                            .font(.title3)
                            .foregroundStyle(Palette.burned)
                            .frame(width: 40, height: 40)
                            .background(Palette.burned.opacity(0.15), in: .rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.body.weight(.medium))
                            Text([w.start.formatted(date: .omitted, time: .shortened), Format.duration(w.minutes * 60),
                                  w.steps > 0 ? "\(w.steps.formatted()) steps" : nil].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(w.source).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Format.kcal(w.kilocalories)).font(.body.bold().monospacedDigit())
                            Text("kcal").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(logs.filter { !$0.exercises.isEmpty }) { log in
                    DisclosureGroup("\(log.title.isEmpty ? log.kind.displayName : log.title): \(log.completedSets) sets") {
                        ForEach(log.exercises.filter { !$0.skipped }) { exercise in
                            LabeledContent(env.plan.exercise(exercise.exerciseID)?.name ?? exercise.exerciseID,
                                           value: "\(exercise.sets.count) sets")
                                .font(.subheadline)
                        }
                    }
                    .font(.subheadline)
                }
                if r.cardioMinutes > 0 {
                    Text("\(Int(r.cardioMinutes.rounded())) moderate cardio minutes").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func activityCard(_ r: DayRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Activity", systemImage: "figure.walk", tint: Palette.steps)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(title: "Steps", value: Format.kcal(r.steps), unit: "/ \(stepGoal.formatted())", systemImage: "shoeprints.fill", tint: Palette.steps)
                    StatTile(title: "Walking", value: Format.kcal(r.stepEnergy), unit: "kcal", systemImage: "figure.walk", tint: Palette.steps)
                }
                GridRow {
                    StatTile(title: "Active", value: Format.kcal(r.burnedKcal - r.basalEnergy), unit: "kcal", systemImage: "flame", tint: Palette.burned)
                    StatTile(title: "Resting", value: Format.kcal(r.basalEnergy), unit: "kcal", systemImage: "bed.double", tint: Palette.burned)
                }
            }
        }
        .card()
    }

    private func sleepAndWeightCard(_ r: DayRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Sleep and weight", systemImage: "moon.zzz.fill", tint: .indigo)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(title: "Asleep (night before)", value: r.asleepSeconds > 0 ? Format.duration(r.asleepSeconds) : "–",
                             systemImage: "bed.double.fill", tint: .indigo)
                    StatTile(title: "Sleep score", value: r.sleepScore.map { "\($0)" } ?? "–", unit: r.sleepScore == nil ? "" : "/ 100",
                             systemImage: "moon.stars.fill", tint: .indigo)
                }
                GridRow {
                    StatTile(title: "Weight", value: r.weightKg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–",
                             unit: r.weightKg == nil ? "" : "kg", systemImage: "scalemass.fill", tint: .purple)
                    Color.clear.frame(height: 1)
                }
            }
        }
        .card()
    }

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Meals", systemImage: "fork.knife", tint: Palette.eaten)
            if meals.isEmpty {
                Text("No meals logged.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(MealType.allCases, id: \.self) { type in
                    let entries = meals.filter { $0.mealType == type }
                    if !entries.isEmpty {
                        HStack {
                            Text(type.displayName).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Format.kcal(entries.map(\.kilocalories).reduce(0, +))) kcal")
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ForEach(entries) { entry in
                            Button { editingMeal = entry } label: {
                                MealRow(entry: entry, showsMealType: false).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit or delete")
                        }
                        Divider()
                    }
                }
            }
        }
        .card()
    }
}
