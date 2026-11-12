import Charts
import NutriCore
import SwiftUI

struct SleepView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKey.sleepGoalHours) private var goal = SettingsDefault.sleepGoalHours
    @State private var nights: [SleepNight] = []
    @State private var range = 14
    @State private var isLoading = true
    @State private var showingAdd = false

    private var shown: [SleepNight] { Array(nights.suffix(range)) }
    private var lastNight: SleepNight? {
        nights.last { Calendar.current.isDateInToday($0.night) || Calendar.current.isDateInYesterday($0.night) }
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !isLoading && nights.isEmpty {
                        emptyState
                    } else {
                        CardColumns(columns: sizeClass == .regular ? 2 : 1) {
                            scoreCard
                            lastNightCard
                            statsCard
                        }
                        chartCard
                        nightsCard
                    }
                    Text("From Apple Health. Aim for 7–9 hours at regular times.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sleep")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add sleep", systemImage: "plus") { showingAdd = true }
                        .disabled(!env.health.isAvailable)
                }
            }
            .sheet(isPresented: $showingAdd) { AddSleepView() }
            .task(id: env.healthRevision) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let start = Calendar.current.date(byAdding: .day, value: -32, to: .now) ?? .now
        let samples = (try? await env.health.sleepSamples(from: start, to: .now)) ?? []
        nights = SleepAnalyzer.nights(from: samples)
    }

    private func score(for night: SleepNight) -> SleepScore? {
        SleepScore.score(night, previousNights: nights, goalHours: goal)
    }

    @ViewBuilder private var scoreCard: some View {
        if let night = lastNight, let score = score(for: night) {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Sleep score", systemImage: "gauge.with.needle.fill", tint: .indigo)
                HStack(spacing: 18) {
                    ProgressRing(progress: Double(score.total) / 100, tint: score.rating.color, lineWidth: 12) {
                        VStack(spacing: 0) {
                            Text("\(score.total)").font(.largeTitle.bold().monospacedDigit())
                            Text(score.rating.rawValue).font(.caption.weight(.semibold)).foregroundStyle(score.rating.color)
                        }
                    }
                    .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 8) {
                        ScorePart(title: "Duration", value: score.duration, max: SleepScore.durationMax)
                        ScorePart(title: "Bedtime", value: score.bedtime, max: SleepScore.bedtimeMax)
                        ScorePart(title: "Interruptions", value: score.interruptions, max: SleepScore.interruptionsMax)
                    }
                }
                Text("Duration vs your \(goal.formatted()) h goal (50), bedtime \(score.bedtimeFromHistory ? "vs your usual" : "vs 9 pm–12:30 am") (30), interruptions (20). May differ from Apple Watch's score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No sleep data yet", systemImage: "bed.double")
        } description: {
            Text("Wear Apple Watch to bed or set up Sleep in Health, or add a night by hand.")
        } actions: {
            Button("Add a night") { showingAdd = true }.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var lastNightCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Last night", systemImage: "moon.stars.fill", tint: .purple)
            if let night = lastNight {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.duration(night.asleep)).font(.largeTitle.bold().monospacedDigit())
                    Text("asleep").foregroundStyle(.secondary)
                }
                Text("\(night.start.formatted(date: .omitted, time: .shortened)) – \(night.end.formatted(date: .omitted, time: .shortened)) · \(Format.duration(night.timeInBed)) in bed · \(night.efficiency.formatted(.percent.precision(.fractionLength(0)))) efficiency")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                StageBar(night: night)
                if night.napAsleep > 0 {
                    Label("Plus \(Format.duration(night.napAsleep)) of naps, not counted in the night", systemImage: "sun.max")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if night.hasStages {
                    HStack {
                        ForEach([SleepStage.deep, .core, .rem, .awake], id: \.self) { stage in
                            StatTile(title: stage.displayName, value: Format.duration(night.durations[stage] ?? 0), systemImage: "circle.fill", tint: stage.color)
                        }
                    }
                }
                let short = night.asleep < 7 * 3600
                Label(short ? "Under 7 hours: consider the tired version of today's session." : "Within your sleep range.",
                      systemImage: short ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(short ? .orange : .green)
            } else {
                Text("No sleep recorded for last night.").foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var statsCard: some View {
        let recent = Array(nights.suffix(7))
        let average = SleepAnalyzer.averageAsleep(recent)
        let bedtime = SleepAnalyzer.clockTimeStats(recent.map(\.start))
        let wake = SleepAnalyzer.clockTimeStats(recent.map(\.end))
        let goodNights = recent.filter { $0.asleep >= 7 * 3600 }.count
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Last 7 nights", systemImage: "chart.bar.doc.horizontal", tint: .indigo)
            HStack {
                StatTile(title: "Average", value: Format.duration(average), systemImage: "bed.double", tint: .purple)
                StatTile(title: "7 h or more", value: "\(goodNights) / \(recent.count)", systemImage: "checkmark.circle", tint: .green)
            }
            HStack {
                StatTile(title: "Bedtime", value: bedtime.map { clock($0.meanMinutes) } ?? "–", systemImage: "moon", tint: .indigo)
                StatTile(title: "Wake", value: wake.map { clock($0.meanMinutes) } ?? "–", systemImage: "sunrise", tint: .orange)
            }
            if let bedtime {
                Text("Bedtime varies by about ±\(Int(bedtime.sdMinutes.rounded())) min. A regular window helps recovery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func clock(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()) % 1440
        let date = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Nightly sleep", systemImage: "chart.bar.fill", tint: .purple)
                Spacer()
                Picker("Range", selection: $range) {
                    Text("7").tag(7)
                    Text("14").tag(14)
                    Text("30").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
            }
            Chart {
                RectangleMark(yStart: .value("Low", 7), yEnd: .value("High", 9))
                    .foregroundStyle(.green.opacity(0.08))
                ForEach(shown) { night in
                    ForEach([SleepStage.deep, .core, .rem, .asleepUnspecified, .awake], id: \.self) { stage in
                        if let seconds = night.durations[stage], seconds > 0 {
                            BarMark(x: .value("Night", night.night, unit: .day), y: .value("Hours", seconds / 3600))
                                .foregroundStyle(by: .value("Stage", stage.displayName))
                        }
                    }
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(goal.formatted()) h").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartForegroundStyleScale([
                "Deep": SleepStage.deep.color, "Core": SleepStage.core.color, "REM": SleepStage.rem.color,
                "Asleep": SleepStage.asleepUnspecified.color, "Awake": SleepStage.awake.color,
            ])
            .chartYAxisLabel("hours")
            .frame(height: 240)
        }
        .card()
    }

    private var nightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Nights", systemImage: "list.bullet", tint: .secondary)
            ForEach(shown.reversed()) { night in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(night.night.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.subheadline.weight(.medium))
                        Text("\(night.start.formatted(date: .omitted, time: .shortened)) – \(night.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Format.duration(night.asleep)).font(.body.bold().monospacedDigit())
                        .foregroundStyle(night.asleep >= 7 * 3600 ? Color.primary : Color.orange)
                    if let score = score(for: night) {
                        SleepScoreBadge(score: score)
                    }
                }
                if night.id != shown.first?.id { Divider() }
            }
        }
        .card()
    }
}

extension SleepStage {
    var color: Color {
        switch self {
        case .deep: .indigo
        case .core: .blue
        case .rem: .cyan
        case .asleepUnspecified: .purple
        case .awake: .orange
        case .inBed: .gray
        }
    }
}

/// A horizontal bar split by stage.
struct StageBar: View {
    let night: SleepNight

    var body: some View {
        let order: [SleepStage] = [.deep, .core, .rem, .asleepUnspecified, .awake, .inBed]
        let total = max(night.timeInBed, 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(order, id: \.self) { stage in
                    let share = (night.durations[stage] ?? 0) / total
                    if share > 0 {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stage.color.opacity(stage == .inBed ? 0.3 : 1))
                            .frame(width: max(2, geo.size.width * share - 2))
                    }
                }
            }
        }
        .frame(height: 14)
        .accessibilityLabel("Sleep stages")
    }
}

struct AddSleepView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var bedtime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: .now.addingTimeInterval(-86_400)) ?? .now
    @State private var wake = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Went to sleep", selection: $bedtime)
                DatePicker("Woke up", selection: $wake, in: bedtime...)
                LabeledContent("Duration", value: Format.duration(wake.timeIntervalSince(bedtime)))
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            .navigationTitle("Add sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await env.health.saveSleep(start: bedtime, end: wake)
                                env.healthDidChange()
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(wake <= bedtime || wake.timeIntervalSince(bedtime) > 16 * 3600)
                }
            }
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    SleepView()
        .environment(environment)
        .modelContainer(environment.modelContainer)
}

extension SleepScore.Rating {
    var color: Color {
        switch self {
        case .veryHigh: .green
        case .high: .teal
        case .ok: .yellow
        case .low: .orange
        case .veryLow: .red
        }
    }
}

/// "82" in a coloured capsule.
struct SleepScoreBadge: View {
    let score: SleepScore

    var body: some View {
        Text("\(score.total)")
            .font(.subheadline.bold().monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(score.rating.color.opacity(0.18), in: .capsule)
            .foregroundStyle(score.rating.color == .yellow ? Color.orange : score.rating.color)
            .accessibilityLabel("Sleep score \(score.total), \(score.rating.rawValue)")
    }
}

private struct ScorePart: View {
    let title: String
    let value: Double
    let max: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(max))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: value, total: max).tint(.indigo)
        }
    }
}
