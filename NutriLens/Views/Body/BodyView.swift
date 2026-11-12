import Charts
import NutriCore
import PhotosUI
import SwiftData
import SwiftUI

struct BodyView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKey.goalWeightKg) private var goalWeight = SettingsDefault.goalWeightKg
    @AppStorage(SettingsKey.dailyCalorieTarget) private var calorieTarget = SettingsDefault.dailyCalorieTarget
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @Query(sort: \MealEntry.date) private var meals: [MealEntry]

    @State private var healthSamples: [BodySample] = []
    @State private var rangeDays = 90
    @State private var metric = BodyMetric.bodyFat
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var draft: ReadingDraft?
    @State private var isReading = false
    @State private var readError: String?
    @State private var infoMetric: BodyMetric?
    @State private var profile = BodyProfile()

    struct ReadingDraft: Identifiable {
        let id = UUID()
        var reading: BodyReading
        var source: BodyReadingSource
        var existing: BodyMeasurement?
    }

    /// Weight from Apple Health (any source, including what NutriLens wrote) plus local readings not in Health.
    private var weights: [WeightPoint] {
        let fromHealth = healthSamples.compactMap { s in s.values[.weight].map { WeightPoint(date: s.date, kg: $0) } }
        let local = measurements.filter { $0.weightKg > 0 && $0.healthKitID == nil }.map { WeightPoint(date: $0.date, kg: $0.weightKg) }
        return WeightTrend.deduplicated(fromHealth + local)
    }

    private var shownWeights: [WeightPoint] {
        let start = Calendar.current.date(byAdding: .day, value: -rangeDays, to: .now) ?? .distantPast
        return weights.filter { $0.date >= start }
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    importCard
                    CardColumns(columns: sizeClass == .regular ? 2 : 1) {
                        progressCard
                        maintenanceCard
                    }
                    weightChartCard
                    latestReadingCard
                    metricTrendCard
                    readingsCard
                    Text("Scale body composition is an estimate. Weigh in the morning, same conditions, and compare weekly averages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Body")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Enter a reading", systemImage: "square.and.pencil") {
                            draft = ReadingDraft(reading: BodyReading(date: .now), source: .manual)
                        }
                        Button("Log waist", systemImage: "ruler") {
                            draft = ReadingDraft(reading: BodyReading(date: .now, values: [.waist: measurements.compactMap { $0.value(.waist) }.first ?? 90]), source: .manual)
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $infoMetric) { metric in
                MetricDetailView(metric: metric, readings: measurements.filter { $0.value(metric) != nil }, profile: profile)
            }
            .sheet(item: $draft) { draft in
                ReadingEditorView(reading: draft.reading, source: draft.source, existing: draft.existing)
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await read(items) }
            }
            .task(id: env.healthRevision) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        profile = await env.bodyProfile()
        let start = Calendar.current.date(byAdding: .year, value: -2, to: .now) ?? .now
        healthSamples = (try? await env.health.bodySamples(from: start, to: .now.addingTimeInterval(60))) ?? []
    }

    private func read(_ items: [PhotosPickerItem]) async {
        isReading = true
        readError = nil
        defer {
            isReading = false
            pickerItems = []
        }
        var images: [CGImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data)?.cgImage {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            readError = "Those screenshots couldn't be opened."
            return
        }
        do {
            var reading = try await TextRecognizer.reading(from: images)
            if reading.values.isEmpty {
                readError = "No values found. Use the scale's result screenshots, or enter the reading by hand."
                return
            }
            if reading.date == nil { reading.date = .now }
            draft = ReadingDraft(reading: reading, source: .screenshot)
        } catch {
            readError = "Text recognition failed: \(error.localizedDescription)"
        }
    }

    // MARK: Cards

    private var importCard: some View {
        let pickTitle = isReading ? "Reading…" : "Import"
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Add a smart-scale reading", systemImage: "camera.viewfinder", tint: .teal)
            Text("Import the scale's result screenshots. All 22 values are read on your device; you check them before saving.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 4, matching: .images) {
                    Label(pickTitle, systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isReading)
                Button {
                    draft = ReadingDraft(reading: BodyReading(date: .now), source: .manual)
                } label: {
                    Label("Enter", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            if isReading { ProgressView("Reading text on your device…") }
            if let readError { Label(readError, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange) }
        }
        .card()
    }

    private var progressCard: some View {
        let weeks = WeightTrend.weeklyAverages(weights)
        let recent = weights.filter { $0.date >= (Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now) }
        let slope = WeightTrend.slopePerWeek(recent)
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Weight", systemImage: "scalemass.fill", tint: .teal)
            if let latest = weights.last {
                HStack(alignment: .firstTextBaseline) {
                    Text(latest.kg.formatted(.number.precision(.fractionLength(1)))).font(.largeTitle.bold().monospacedDigit())
                    Text("kg").foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Goal \(goalWeight.formatted()) kg").font(.subheadline.weight(.medium))
                        Text("\((latest.kg - goalWeight).formatted(.number.precision(.fractionLength(1)))) kg to go").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let lastWeek = weeks.last {
                    Text("This week's average \(lastWeek.averageKg.formatted(.number.precision(.fractionLength(1)))) kg from \(lastWeek.readings) reading\(lastWeek.readings == 1 ? "" : "s").")
                        .font(.subheadline)
                }
                if let slope {
                    let pace = -slope
                    Label("Trend \(slope >= 0 ? "+" : "")\(slope.formatted(.number.precision(.fractionLength(2)))) kg/week over 4 weeks. Plan pace: 0.2–0.4 kg/week loss.",
                          systemImage: pace >= 0.2 && pace <= 0.5 ? "checkmark.circle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(pace > 0.5 ? .orange : .secondary)
                }
            } else {
                Text("No weight readings yet.").foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var maintenanceCard: some View {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -28, to: .now) ?? .now
        var intake: [Date: Double] = [:]
        for meal in meals where meal.date >= windowStart && !calendar.isDateInToday(meal.date) {
            intake[calendar.startOfDay(for: meal.date), default: 0] += meal.kilocalories
        }
        let estimate = MaintenanceEstimator.estimate(dailyIntake: intake, weights: weights.filter { $0.date >= windowStart })
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Calories from your trend", systemImage: "function", tint: .orange)
            if let estimate {
                Text("≈ \(Format.kcal(estimate.maintenanceKcal)) kcal/day maintenance")
                    .font(.title3.bold())
                Text("You averaged \(Format.kcal(estimate.averageIntakeKcal)) kcal over \(estimate.loggedDays) logged days while weight changed \(estimate.weightChangePerWeekKg.formatted(.number.precision(.fractionLength(2)))) kg/week. The plan suggests about \(Format.kcal(estimate.suggestedTarget.lowerBound))–\(Format.kcal(estimate.suggestedTarget.upperBound)) kcal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Use \(Format.kcal(estimate.suggestedTarget.upperBound.rounded(to: 50))) kcal as my target") {
                    calorieTarget = estimate.suggestedTarget.upperBound.rounded(to: 50)
                }
                .buttonStyle(.bordered)
            } else {
                Text("Log food on 10+ days and weigh in 5+ times over two weeks to estimate your maintenance calories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var weightChartCard: some View {
        let weekly = WeightTrend.weeklyAverages(shownWeights)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Weight history", systemImage: "chart.xyaxis.line", tint: .teal)
                Spacer()
                Picker("Range", selection: $rangeDays) {
                    Text("1M").tag(30)
                    Text("3M").tag(90)
                    Text("1Y").tag(365)
                    Text("All").tag(3650)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
            if shownWeights.isEmpty {
                Text("No readings in this range.").foregroundStyle(.secondary).frame(height: 120)
            } else {
                Chart {
                    ForEach(Array(shownWeights.enumerated()), id: \.offset) { _, point in
                        PointMark(x: .value("Date", point.date), y: .value("kg", point.kg))
                            .foregroundStyle(.teal.opacity(0.35))
                            .symbolSize(18)
                    }
                    ForEach(weekly) { week in
                        LineMark(x: .value("Date", week.weekStart.addingTimeInterval(3.5 * 86_400)), y: .value("kg", week.averageKg))
                            .foregroundStyle(.teal)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                    RuleMark(y: .value("Goal", goalWeight))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.green)
                        .annotation(position: .top, alignment: .leading) { Text("Goal").font(.caption2).foregroundStyle(.green) }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
                Text("Dots are single readings; the line is the weekly average.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    @ViewBuilder private var latestReadingCard: some View {
        let scaleReadings = measurements.filter { $0.values.count > 3 }
        if let latest = scaleReadings.first {
            let previous = scaleReadings.dropFirst().first
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardHeader(title: "Latest scale reading", systemImage: "list.bullet.rectangle", tint: .indigo)
                    Spacer()
                    Text(latest.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(BodyMetric.allCases) { metric in
                        if let value = latest.value(metric) {
                            Button {
                                infoMetric = metric
                            } label: {
                                MetricTile(metric: metric, value: value, status: latest.statuses[metric.rawValue], previous: previous?.value(metric),
                                           band: MetricGuides.guide(for: metric, profile: profile, weightKg: latest.weightKg > 0 ? latest.weightKg : nil).band(for: value))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows what this means and its healthy range")
                        }
                    }
                }
                if let previous {
                    Text("Changes vs \(previous.date.formatted(date: .abbreviated, time: .omitted)). Tap a value for details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    private var metricTrendCard: some View {
        let points = measurements.compactMap { m in m.value(metric).map { (m.date, $0) } }.sorted { $0.0 < $1.0 }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Trend", systemImage: metric.symbolName, tint: .indigo)
                Spacer()
                Picker("Value", selection: $metric) {
                    ForEach(BodyMetric.allCases) { Text($0.displayName).tag($0) }
                }
            }
            if points.count < 2 {
                Text("Two or more readings with \(metric.displayName.lowercased()) are needed for a trend.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(points, id: \.0) { point in
                    LineMark(x: .value("Date", point.0), y: .value(metric.displayName, point.1))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.0), y: .value(metric.displayName, point.1))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(metric.unit)
                .frame(height: 180)
            }
        }
        .card()
    }

    private var readingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Readings", systemImage: "clock", tint: .secondary)
            if measurements.isEmpty {
                Text("Readings you import or enter appear here.").foregroundStyle(.secondary)
            }
            ForEach(measurements.prefix(30)) { m in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.medium))
                        Text("\(m.source.displayName) · \(m.values.count) value\(m.values.count == 1 ? "" : "s")\(m.healthKitID == nil ? "" : " · in Health")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if m.weightKg > 0 { Text(BodyMetric.weight.format(m.weightKg)).monospacedDigit() }
                    Menu {
                        Button("Edit", systemImage: "pencil") { draft = ReadingDraft(reading: m.reading, source: m.source, existing: m) }
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await delete(m) } }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
        }
        .card()
    }

    private func delete(_ m: BodyMeasurement) async {
        if m.healthKitID != nil { try? await env.health.deleteBody(nutriLensID: m.id) }
        Tombstone.record(m.id, type: SyncRecordType.body, in: modelContext)
        modelContext.delete(m)
        try? modelContext.save()
        env.healthDidChange()
    }
}

private extension Double {
    func rounded(to step: Double) -> Double { (self / step).rounded() * step }
}

/// One metric with its scale status, change since the previous reading, and (where a reference range
/// exists) a coloured dot for where your value falls. Tapping opens `MetricDetailView`.
struct MetricTile: View {
    let metric: BodyMetric
    let value: Double
    let status: String?
    let previous: Double?
    var band: MetricBand?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let band {
                    Circle().fill(band.level.color).frame(width: 7, height: 7)
                }
                Text(metric.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 2)
                if let status {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(statusColor.opacity(0.15), in: .capsule)
                        .foregroundStyle(statusColor)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(metric.format(value)).font(.headline.monospacedDigit())
                Spacer()
                Image(systemName: "info.circle").font(.caption).foregroundStyle(.tertiary)
            }
            if let previous, abs(value - previous) > 0.0001 {
                let delta = value - previous
                let good = metric.lowerIsBetter.map { $0 ? delta < 0 : delta > 0 }
                Text("\(delta > 0 ? "▲" : "▼") \(abs(delta).formatted(.number.precision(.fractionLength(0...2))))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(good == nil ? Color.secondary : (good! ? Color.green : Color.orange))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch status?.lowercased() {
        case "healthy", "normal", "standard", "good", "excellent": .green
        case "high", "very high", "obese", "overweight": .red
        case "low", "very low", "underweight", "insufficient": .orange
        default: .secondary
        }
    }
}
