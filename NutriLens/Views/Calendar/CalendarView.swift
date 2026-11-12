import NutriCore
import SwiftData
import SwiftUI

/// What the calendar's day rings show.
enum CalendarMetric: String, CaseIterable, Identifiable {
    case calories = "Calories"
    case protein = "Protein"
    case steps = "Steps"
    case sleep = "Sleep"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .calories: Palette.eaten
        case .protein: Palette.protein
        case .steps: Palette.steps
        case .sleep: .indigo
        }
    }
}

/// Month calendar of everything recorded: calories and macros eaten, workouts, steps, sleep and weight.
/// Tap a day to see it in full. Days are stored on the device (`DayRecord`), so old months stay available.
struct CalendarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.dailyStepGoal) private var stepGoal = SettingsDefault.dailyStepGoal
    @AppStorage(SettingsKey.sleepGoalHours) private var sleepGoal = SettingsDefault.sleepGoalHours
    @AppStorage("calendarMetric") private var metric: CalendarMetric = .calories

    @Query(sort: \DayRecord.date) private var records: [DayRecord]
    @State private var month: Date
    @State private var isRecording = false
    @State private var selectedDay: Date?

    private let calendar = Calendar.current

    init(month: Date = .now) {
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: month)?.start ?? month)
    }

    private var byKey: [String: DayRecord] {
        Dictionary(records.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b })
    }

    private var days: [Date] { DayRecorder.days(inMonthOf: month, calendar: calendar) }
    private var monthRecords: [DayRecord] { days.compactMap { byKey[DayRecord.key(for: $0, calendar: calendar)] } }
    private var isCurrentMonth: Bool { calendar.isDate(month, equalTo: .now, toGranularity: .month) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 12) {
                    monthHeader
                    Picker("Show", selection: $metric) {
                        ForEach(CalendarMetric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    grid
                    legend
                }
                .card()
                summaryCard
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isCurrentMonth {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("This month") { withAnimation { month = calendar.dateInterval(of: .month, for: .now)?.start ?? .now } }
                }
            }
        }
        .navigationDestination(item: $selectedDay) { day in
            DayDetailView(day: day)
        }
        .task(id: "\(month.timeIntervalSince1970)-\(env.healthRevision)") {
            isRecording = true
            await DayRecorder.record(days: days, health: env.health, context: context)
            isRecording = false
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) else { return }
            shiftMonth(value.translation.width < 0 ? 1 : -1)
        })
    }

    private func shiftMonth(_ by: Int) {
        guard let next = calendar.date(byAdding: .month, value: by, to: month), next <= .now else { return }
        withAnimation { month = next }
    }

    private var monthHeader: some View {
        HStack {
            Button("Previous month", systemImage: "chevron.left") { shiftMonth(-1) }
                .labelStyle(.iconOnly)
            Spacer()
            HStack(spacing: 6) {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.bold())
                if isRecording { ProgressView().controlSize(.small) }
            }
            Spacer()
            Button("Next month", systemImage: "chevron.right") { shiftMonth(1) }
                .labelStyle(.iconOnly)
                .disabled(isCurrentMonth)
        }
        .font(.title3)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var leadingBlanks: Int {
        guard let first = days.first else { return 0 }
        return (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let today = calendar.startOfDay(for: .now)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 1) }
            ForEach(days, id: \.self) { day in
                let record = byKey[DayRecord.key(for: day, calendar: calendar)]
                Button { selectedDay = day } label: {
                    DayCell(day: day, record: record, metric: metric, progress: record.map(progress) ?? 0,
                            isToday: day == today, isFuture: day > today)
                }
                .buttonStyle(.plain)
                .disabled(day > today)
            }
        }
    }

    private func progress(_ record: DayRecord) -> Double {
        switch metric {
        case .calories: record.budgetKcal > 0 ? record.eatenKcal / record.budgetKcal : 0
        case .protein: record.protein / max(1, env.macroTargets(on: record.date).protein)
        case .steps: stepGoal > 0 ? record.steps / Double(stepGoal) : 0
        case .sleep: sleepGoal > 0 ? record.asleepSeconds / (sleepGoal * 3600) : 0
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label(legendText, systemImage: "circle.circle").foregroundStyle(metric.tint)
            Label("Workout", systemImage: "circle.fill").foregroundStyle(Palette.burned)
            Label("Weigh-in", systemImage: "circle.fill").foregroundStyle(.purple)
        }
        .font(.caption2)
        .labelStyle(LegendLabelStyle())
    }

    private var legendText: String {
        switch metric {
        case .calories: "Eaten vs budget"
        case .protein: "Protein vs the day's target"
        case .steps: "Steps vs \(stepGoal.formatted())"
        case .sleep: "Sleep vs \(sleepGoal.formatted()) h"
        }
    }

    // MARK: Month summary

    private var summaryCard: some View {
        let logged = monthRecords.filter(\.hasFood)
        let average: (KeyPath<DayRecord, Double>) -> Double = { path in
            logged.isEmpty ? 0 : logged.map { $0[keyPath: path] }.reduce(0, +) / Double(logged.count)
        }
        let workouts = monthRecords.flatMap(\.workouts)
        let stepDays = monthRecords.filter { $0.steps > 0 }
        let sleepDays = monthRecords.filter { $0.asleepSeconds > 0 }
        let weights = monthRecords.compactMap(\.weightKg)
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "\(month.formatted(.dateTime.month(.wide))) at a glance", systemImage: "calendar", tint: .accentColor)
            if monthRecords.allSatisfy({ !$0.hasAnything }) {
                Text("Nothing recorded this month.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatTile(title: "Days logged", value: "\(logged.count)", systemImage: "fork.knife", tint: Palette.eaten)
                        StatTile(title: "Avg eaten", value: Format.kcal(average(\.eatenKcal)), unit: "kcal", systemImage: "flame.fill", tint: Palette.eaten)
                    }
                    GridRow {
                        StatTile(title: "Avg protein", value: Format.kcal(average(\.protein)), unit: "g", systemImage: "p.circle", tint: Palette.protein)
                        StatTile(title: "Avg carbs · fat", value: "\(Format.kcal(average(\.carbohydrates))) · \(Format.kcal(average(\.fat)))", unit: "g",
                                 systemImage: "chart.pie", tint: Palette.carbohydrates)
                    }
                    GridRow {
                        StatTile(title: "Workouts", value: "\(workouts.count)", unit: Format.duration(workouts.map(\.minutes).reduce(0, +) * 60),
                                 systemImage: "dumbbell.fill", tint: Palette.burned)
                        StatTile(title: "Avg steps", value: stepDays.isEmpty ? "–" : Format.kcal(stepDays.map(\.steps).reduce(0, +) / Double(stepDays.count)),
                                 systemImage: "figure.walk", tint: Palette.steps)
                    }
                    GridRow {
                        StatTile(title: "Avg sleep", value: sleepDays.isEmpty ? "–" : Format.duration(sleepDays.map(\.asleepSeconds).reduce(0, +) / Double(sleepDays.count)),
                                 systemImage: "bed.double.fill", tint: .indigo)
                        StatTile(title: "Weight", value: weightText(weights), systemImage: "scalemass.fill", tint: .purple)
                    }
                }
            }
        }
        .card()
    }

    private func weightText(_ weights: [Double]) -> String {
        guard let first = weights.first, let last = weights.last else { return "–" }
        let change = last - first
        let latest = last.formatted(.number.precision(.fractionLength(1))) + " kg"
        guard weights.count > 1 else { return latest }
        return latest + " (" + (change >= 0 ? "+" : "−") + abs(change).formatted(.number.precision(.fractionLength(1))) + ")"
    }
}

private struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title.foregroundStyle(.secondary)
        }
    }
}

/// One day in the month grid: date inside a progress ring, with workout and weigh-in dots.
struct DayCell: View {
    let day: Date
    let record: DayRecord?
    let metric: CalendarMetric
    let progress: Double
    let isToday: Bool
    let isFuture: Bool

    private var hasValue: Bool {
        guard let record else { return false }
        switch metric {
        case .calories, .protein: return record.hasFood
        case .steps: return record.steps > 0
        case .sleep: return record.asleepSeconds > 0
        }
    }

    private var tint: Color { metric == .calories && progress > 1.1 ? .red : metric.tint }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(metric.tint.opacity(hasValue ? 0.18 : 0.07), lineWidth: 3.5)
                if hasValue {
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(day.formatted(.dateTime.day()))
                    .font(.callout.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? Color.accentColor : isFuture ? Color.secondary.opacity(0.5) : Color.primary)
            }
            .frame(width: 38, height: 38)
            HStack(spacing: 3) {
                Circle().fill(Palette.burned).frame(width: 5, height: 5).opacity(record?.workouts.isEmpty == false ? 1 : 0)
                Circle().fill(Color.purple).frame(width: 5, height: 5).opacity(record?.weightKg != nil ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [day.formatted(date: .complete, time: .omitted)]
        if let record {
            if record.hasFood { parts.append("\(Format.kcal(record.eatenKcal)) kilocalories eaten") }
            if !record.workouts.isEmpty { parts.append("\(record.workouts.count) workouts") }
            if record.steps > 0 { parts.append("\(Format.kcal(record.steps)) steps") }
            if record.asleepSeconds > 0 { parts.append("slept \(Format.duration(record.asleepSeconds))") }
        }
        return parts.joined(separator: ", ")
    }
}
