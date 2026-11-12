import Foundation
import Testing
@testable import NutriCore

@Suite("Body metric reference ranges")
struct MetricGuideTests {
    let man30 = BodyProfile(sex: .male, age: 30, heightCm: 183)

    @Test func bmiUsesAsianIndianCutoffsByDefault() {
        let guide = MetricGuides.guide(for: .bmi, profile: man30)
        #expect(guide.band(for: 17.9)?.level == .low)
        #expect(guide.band(for: 18.0)?.level == .healthy)
        #expect(guide.band(for: 22.9)?.level == .healthy)
        #expect(guide.band(for: 23.0)?.label == "Overweight")
        #expect(guide.band(for: 25.0)?.level == .veryHigh)
    }

    @Test func bmiWhoCutoffs() {
        var profile = man30
        profile.asianCutoffs = false
        let guide = MetricGuides.guide(for: .bmi, profile: profile)
        #expect(guide.band(for: 18.2)?.level == .low)
        #expect(guide.band(for: 24.9)?.level == .healthy)
        #expect(guide.band(for: 25.0)?.level == .high)
        #expect(guide.band(for: 30.0)?.level == .veryHigh)
    }

    @Test func bmiPersonalNoteFromWeightAndHeight() throws {
        let guide = MetricGuides.guide(for: .bmi, profile: man30, weightKg: 84.6)
        // 84.6 / 1.83² = 25.26…
        #expect(try #require(guide.personalNote).contains("25.3"))
    }

    @Test func healthyWeightRangeFollowsHeight() throws {
        let guide = MetricGuides.guide(for: .weight, profile: man30)
        let healthy = try #require(guide.bands.first { $0.level == .healthy })
        #expect(abs(try #require(healthy.lower) - 18.0 * 1.83 * 1.83) < 0.001)
        #expect(abs(try #require(healthy.upper) - 23.0 * 1.83 * 1.83) < 0.001)
        #expect(guide.band(for: 84.6)?.label == "Obese") // BMI 25.3 ≥ 25 (Asian-Indian)
        #expect(guide.band(for: 80)?.label == "Overweight")

        // No height, no range.
        #expect(MetricGuides.guide(for: .weight, profile: BodyProfile(sex: .male)).bands.isEmpty)
    }

    @Test func bodyFatBySexAndAge() {
        #expect(MetricGuides.guide(for: .bodyFat, profile: man30).band(for: 19.9)?.level == .healthy)
        #expect(MetricGuides.guide(for: .bodyFat, profile: man30).band(for: 20)?.level == .high)
        #expect(MetricGuides.guide(for: .bodyFat, profile: man30).band(for: 25)?.level == .veryHigh)
        #expect(MetricGuides.guide(for: .bodyFat, profile: man30).band(for: 7)?.level == .low)

        let man50 = BodyProfile(sex: .male, age: 50)
        #expect(MetricGuides.guide(for: .bodyFat, profile: man50).band(for: 21)?.level == .healthy)
        let woman65 = BodyProfile(sex: .female, age: 65)
        #expect(MetricGuides.guide(for: .bodyFat, profile: woman65).band(for: 35)?.level == .healthy)
        #expect(MetricGuides.guide(for: .bodyFat, profile: woman65).band(for: 42)?.level == .veryHigh)

        // Without sex there's no single range.
        #expect(MetricGuides.guide(for: .bodyFat, profile: BodyProfile()).bands.isEmpty)
    }

    @Test func waistCutoffs() {
        #expect(MetricGuides.guide(for: .waist, profile: man30).band(for: 89.9)?.level == .healthy)
        #expect(MetricGuides.guide(for: .waist, profile: man30).band(for: 90)?.level == .high)
        let woman = BodyProfile(sex: .female, age: 30, asianCutoffs: true)
        #expect(MetricGuides.guide(for: .waist, profile: woman).band(for: 80)?.level == .high)

        var who = man30
        who.asianCutoffs = false
        #expect(MetricGuides.guide(for: .waist, profile: who).band(for: 93)?.level == .healthy)
        #expect(MetricGuides.guide(for: .waist, profile: who).band(for: 95)?.level == .high)
        #expect(MetricGuides.guide(for: .waist, profile: who).band(for: 102)?.level == .veryHigh)
    }

    @Test func scaleRatings() {
        let obesity = MetricGuides.guide(for: .obesityDegree, profile: man30)
        #expect(obesity.band(for: -10.5)?.level == .low)
        #expect(obesity.band(for: 9.9)?.level == .healthy)
        #expect(obesity.band(for: 15)?.level == .high)
        #expect(obesity.band(for: 20)?.level == .veryHigh)

        let visceral = MetricGuides.guide(for: .visceralFat, profile: man30)
        #expect(visceral.band(for: 12)?.level == .healthy)
        #expect(visceral.band(for: 13)?.level == .high)

        #expect(MetricGuides.guide(for: .metabolicAge, profile: man30).band(for: 30)?.level == .healthy)
        #expect(MetricGuides.guide(for: .metabolicAge, profile: man30).band(for: 31)?.level == .high)
    }

    @Test func bodyWaterDependsOnSex() {
        #expect(MetricGuides.guide(for: .bodyWater, profile: man30).band(for: 48)?.level == .low)
        #expect(MetricGuides.guide(for: .bodyWater, profile: BodyProfile(sex: .female)).band(for: 48)?.level == .healthy)
    }

    @Test func bmrHasEstimateButNoRange() throws {
        let guide = MetricGuides.guide(for: .bmr, profile: man30, weightKg: 84.6)
        #expect(guide.bands.isEmpty)
        // 10×84.6 + 6.25×183 − 5×30 + 5 = 1844.75
        #expect(try #require(guide.personalNote).contains("1845"))
    }

    @Test func everyMetricHasAGuideWithContiguousBands() {
        for metric in BodyMetric.allCases {
            let guide = MetricGuides.guide(for: metric, profile: man30, weightKg: 84.6)
            #expect(!guide.about.isEmpty, "\(metric)")
            #expect(!guide.rangeNote.isEmpty, "\(metric)")
            // Each band starts where the previous one ends, so every value falls in exactly one band.
            for (a, b) in zip(guide.bands, guide.bands.dropFirst()) {
                #expect(a.upper != nil && a.upper == b.lower, "\(metric): \(a.label) → \(b.label)")
            }
            if let first = guide.bands.first { #expect(first.lower == nil, "\(metric)") }
            if let last = guide.bands.last { #expect(last.upper == nil, "\(metric)") }
        }
    }

    @Test func rangeText() {
        #expect(MetricBand("Healthy", 18, 23, .healthy).rangeText() == "18.0–22.9")
        #expect(MetricBand("Low", nil, 18, .low).rangeText() == "Under 18.0")
        #expect(MetricBand("Obese", 25, nil, .veryHigh).rangeText() == "25.0 or more")
        #expect(MetricBand("Normal", 10, 20, .healthy).rangeText(decimals: 0) == "10–19")
        #expect(MetricBand("Healthy", 60.3, 77, .healthy).rangeText(unit: "kg") == "60.3–76.9 kg")
        #expect(MetricBand("Normal", -10, 10, .healthy).rangeText(unit: "%") == "−10.0 to 9.9 %")
        #expect(MetricBand("Obese", 20, nil, .veryHigh).rangeText(unit: "%") == "20.0 % or more")
    }
}
