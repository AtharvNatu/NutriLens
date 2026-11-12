import Charts
import NutriCore
import SwiftUI

/// What a body metric means, its healthy / low / high ranges for you, where your value sits, and its history.
struct MetricDetailView: View {
    let metric: BodyMetric
    /// Readings that include this metric, newest first.
    let readings: [BodyMeasurement]
    let profile: BodyProfile

    @Environment(\.dismiss) private var dismiss

    private var latest: BodyMeasurement? { readings.first { $0.value(metric) != nil } }
    private var value: Double? { latest?.value(metric) }
    private var guide: MetricGuide {
        MetricGuides.guide(for: metric, profile: profile, weightKg: readings.first(where: { $0.weightKg > 0 })?.weightKg)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                    if let value, !guide.bands.isEmpty {
                        RangeBar(bands: guide.bands, value: value)
                            .frame(height: 54)
                            .padding(.vertical, 4)
                    }
                }
                if !guide.bands.isEmpty {
                    Section("Ranges") {
                        ForEach(guide.bands) { band in
                            HStack {
                                Circle().fill(band.level.color).frame(width: 10, height: 10)
                                Text(band.label)
                                Spacer()
                                Text(band.rangeText(decimals: decimals, unit: metric.unit))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                if let value, band.contains(value) {
                                    Image(systemName: "arrowtriangle.left.fill").font(.caption).foregroundStyle(band.level.color)
                                        .accessibilityLabel("Your value")
                                }
                            }
                        }
                    }
                }
                Section("About") {
                    Text(guide.about)
                    if let personal = guide.personalNote {
                        Label(personal, systemImage: "person.crop.circle").foregroundStyle(.secondary)
                    }
                    Text(guide.rangeNote).font(.footnote).foregroundStyle(.secondary)
                    if profile.sex == .notSet || profile.age == nil || profile.heightCm == nil {
                        Text("Profile: \(profileText). Edit in Settings › Profile.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                historySection
            }
            .navigationTitle(metric.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var decimals: Int { metric == .bmr || metric == .metabolicAge ? 0 : 1 }

    private var profileText: String {
        [profile.sex == .notSet ? "sex not set" : profile.sex.rawValue,
         profile.age.map { "\($0) years" } ?? "age not set",
         profile.heightCm.map { "\(Int($0)) cm" } ?? "height not set"].joined(separator: ", ")
    }

    @ViewBuilder private var header: some View {
        if let value, let latest {
            let band = guide.band(for: value)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(metric.format(value)).font(.largeTitle.bold().monospacedDigit())
                    Spacer()
                    if let band {
                        Text(band.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(band.level.color.opacity(0.18), in: .capsule)
                            .foregroundStyle(band.level.color)
                    }
                }
                Text(latest.date.formatted(date: .abbreviated, time: .shortened)
                     + (latest.statuses[metric.rawValue].map { " · your scale app says \"\($0)\"" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("No readings with \(metric.displayName.lowercased()) yet.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var historySection: some View {
        let points = readings.compactMap { m in m.value(metric).map { (m.date, $0) } }.sorted { $0.0 < $1.0 }
        if points.count >= 2 {
            Section("History") {
                Chart {
                    ForEach(guide.bands) { band in
                        if let lo = band.lower, let hi = band.upper, band.level == .healthy {
                            RectangleMark(yStart: .value("From", lo), yEnd: .value("To", hi))
                                .foregroundStyle(.green.opacity(0.1))
                        }
                    }
                    ForEach(points, id: \.0) { point in
                        LineMark(x: .value("Date", point.0), y: .value(metric.displayName, point.1))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.0), y: .value(metric.displayName, point.1))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
                ForEach(points.reversed().prefix(10), id: \.0) { point in
                    LabeledContent(point.0.formatted(date: .abbreviated, time: .omitted), value: metric.format(point.1))
                }
            }
        }
    }
}

extension MetricBand.Level {
    var color: Color {
        switch self {
        case .low: .orange
        case .healthy: .green
        case .high: .orange
        case .veryHigh: .red
        }
    }
}

/// Coloured bands with a marker at the current value.
struct RangeBar: View {
    let bands: [MetricBand]
    let value: Double

    /// Visible span: the bounded bands plus a margin for open-ended ones.
    private var span: (Double, Double) {
        let bounds = bands.flatMap { [$0.lower, $0.upper] }.compactMap { $0 }
        guard let lo = bounds.min(), let hi = bounds.max() else { return (value - 1, value + 1) }
        let margin = max((hi - lo) * 0.25, abs(hi) * 0.05, 1)
        return (min(lo - margin, value), max(hi + margin, value))
    }

    /// Horizontal position of `v` in a bar `width` points wide.
    private func x(_ v: Double, width: CGFloat) -> CGFloat {
        let (lo, hi) = span
        return CGFloat((v - lo) / (hi - lo)) * width
    }

    private var boundaries: [Double] {
        Array(Set(bands.flatMap { [$0.lower, $0.upper] }.compactMap { $0 })).sorted()
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                ForEach(bands) { band in
                    let start = x(band.lower ?? span.0, width: width), end = x(band.upper ?? span.1, width: width)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(band.level.color.opacity(0.75))
                        .frame(width: max(0, end - start - 2), height: 10)
                        .offset(x: start, y: 30)
                }
                ForEach(boundaries, id: \.self) { b in
                    Text(b.formatted(.number.precision(.fractionLength(0...1))).replacingOccurrences(of: "-", with: "−"))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .position(x: x(b, width: width), y: 48)
                }
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .position(x: min(max(x(value, width: width), 6), width - 6), y: 20)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Your value \(value.formatted()) on the range scale")
    }
}
