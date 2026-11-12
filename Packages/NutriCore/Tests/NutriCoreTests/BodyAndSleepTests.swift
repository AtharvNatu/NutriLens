import Foundation
import Testing
@testable import NutriCore

/// Synthetic OCR output laid out like the Healthify Smart Scale result screens
/// (status tag, label, value stacked on cards in two columns). Values are made up.
enum FakeScreens {
    static func card(_ status: String?, _ label: String, _ value: String, column: Int, row: Int, top: Double = 0.30) -> [RecognizedLine] {
        let x = column == 0 ? 0.10 : 0.56
        let y = top + Double(row) * 0.115
        var lines = [
            RecognizedLine(label, x: x, y: y + 0.025, width: 0.25, height: 0.018),
            RecognizedLine(value, x: x, y: y + 0.050, width: 0.22, height: 0.032),
        ]
        if let status { lines.append(RecognizedLine(status, x: x + 0.01, y: y, width: 0.07, height: 0.014)) }
        return lines
    }

    static var main: [RecognizedLine] {
        [
            RecognizedLine("9:41", x: 0.08, y: 0.02, width: 0.1, height: 0.02),
            RecognizedLine("91.40 kg", x: 0.30, y: 0.08, width: 0.40, height: 0.06),
            RecognizedLine("High", x: 0.45, y: 0.15, width: 0.08, height: 0.015),
            RecognizedLine("5 Nov, 2026 • Smart Scale", x: 0.30, y: 0.18, width: 0.40, height: 0.02),
        ]
        + card("High", "Body Fat", "25.10 %", column: 0, row: 0)
        + card("Low", "Muscle Mass %", "70.20 %", column: 1, row: 0)
        + card("High", "BMI", "26.40", column: 0, row: 1)
        + card("Healthy", "BMR", "1810 Cal", column: 1, row: 1)
        + card("Healthy", "Bone Mass", "3.10 %", column: 0, row: 2)
        + card("Healthy", "Body Hydration", "54.20 %", column: 1, row: 2)
        + card(nil, "Metabolic Age", "27.00 years", column: 0, row: 3)
        + card("Healthy", "Protein", "16.90 %", column: 1, row: 3)
        + card("High", "Skeletal Muscle", "47.30 %", column: 0, row: 4)
        + card("High", "Subcutaneous Fat", "22.40 %", column: 1, row: 4)
    }

    static var continued: [RecognizedLine] {
        [RecognizedLine("12:16", x: 0.08, y: 0.02, width: 0.1, height: 0.02)]
        + card("Healthy", "Visceral Fat", "9.00 %", column: 0, row: 0, top: 0.12)
        + card(nil, "Muscle Mass", "64.20 kg", column: 1, row: 0, top: 0.12)
        + card("Low", "Lean Body Mass (kg)", "68.40 kg", column: 0, row: 1, top: 0.12)
        + card(nil, "Health Score", "0.00", column: 1, row: 1, top: 0.12)
        + card("High", "Obesity Degree (%)", "18.10 %", column: 0, row: 2, top: 0.12)
        + card(nil, "Mineral Salt (kg)", "1.10 kg", column: 1, row: 2, top: 0.12)
        + card(nil, "Best Visual Weight (kg)", "77.00 kg", column: 0, row: 3, top: 0.12)
        + card(nil, "Standard Weight (kg)", "74.00 kg", column: 1, row: 3, top: 0.12)
        + card("Low", "Weight Control (kg)", "-12.50 kg", column: 0, row: 4, top: 0.12)
        + card("Low", "Fat Control (kg)", "-9.80 kg", column: 1, row: 4, top: 0.12)
        + card("High", "Muscle Control (kg)", "1.70 kg", column: 0, row: 5, top: 0.12)
    }
}

@Suite("Scale screenshot parser")
struct ScaleParserTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    @Test func readsTheMainScreen() {
        let r = ScaleScreenshotParser.parse(FakeScreens.main, calendar: calendar)
        #expect(r.values[.weight] == 91.4)
        #expect(r.values[.bodyFat] == 25.1)
        #expect(r.values[.muscleMassPercent] == 70.2)
        #expect(r.values[.bmi] == 26.4)
        #expect(r.values[.bmr] == 1810)
        #expect(r.values[.boneMass] == 3.1)
        #expect(r.values[.bodyWater] == 54.2)
        #expect(r.values[.metabolicAge] == 27)
        #expect(r.values[.protein] == 16.9)
        #expect(r.values[.skeletalMuscle] == 47.3)
        #expect(r.values[.subcutaneousFat] == 22.4)
        #expect(r.statuses[.bodyFat] == "High")
        #expect(r.statuses[.muscleMassPercent] == "Low")
        #expect(r.statuses[.metabolicAge] == nil)
        #expect(r.statuses[.weight] == "High")
        let day = calendar.dateComponents([.year, .month, .day], from: r.date!)
        #expect(day == DateComponents(year: 2026, month: 11, day: 5))
    }

    @Test func readsTheContinuedScreenIncludingNegativesAndKgMuscle() {
        let r = ScaleScreenshotParser.parse(FakeScreens.continued, calendar: calendar)
        #expect(r.values[.visceralFat] == 9)
        #expect(r.values[.muscleMass] == 64.2)
        #expect(r.values[.leanBodyMass] == 68.4)
        #expect(r.values[.healthScore] == 0)
        #expect(r.values[.obesityDegree] == 18.1)
        #expect(r.values[.mineralSalt] == 1.1)
        #expect(r.values[.bestVisualWeight] == 77)
        #expect(r.values[.standardWeight] == 74)
        #expect(r.values[.weightControl] == -12.5)
        #expect(r.values[.fatControl] == -9.8)
        #expect(r.values[.muscleControl] == 1.7)
        #expect(r.values[.weight] == nil, "no headline weight on the continued screen")
        #expect(r.date == nil)
    }

    @Test func bothScreensTogetherGiveAllTwentyTwoValues() {
        let combined = ScaleScreenshotParser.parse(FakeScreens.main, calendar: calendar)
            .merged(with: ScaleScreenshotParser.parse(FakeScreens.continued, calendar: calendar))
        #expect(combined.missingScaleMetrics.isEmpty, "missing \(combined.missingScaleMetrics)")
        #expect(combined.values.count == BodyMetric.scaleMetrics.count)
        #expect(BodyMetric.scaleMetrics.count == 22)
    }

    @Test func inlineLayoutAndOCRSlips() {
        let lines = [
            RecognizedLine("Weight 80.5 kg", x: 0.1, y: 0.1, width: 0.5, height: 0.02),
            RecognizedLine("Body fat rate: 21,4%", x: 0.1, y: 0.15, width: 0.5, height: 0.02),
            RecognizedLine("Subcutaneous Fal", x: 0.1, y: 0.2, width: 0.3, height: 0.02),
            RecognizedLine("19.0 %", x: 0.6, y: 0.2, width: 0.2, height: 0.02),
            RecognizedLine("BMR 99999 kcal", x: 0.1, y: 0.25, width: 0.5, height: 0.02),
        ]
        let r = ScaleScreenshotParser.parse(lines)
        #expect(r.values[.weight] == 80.5)
        #expect(r.values[.bodyFat] == 21.4)
        #expect(r.values[.subcutaneousFat] == 19)
        #expect(r.values[.bmr] == nil, "implausible values are dropped")
    }

    @Test(arguments: [("22.70 %", 22.7, "%"), ("1752 Cal", 1752, "cal"), ("-4.20 kg", -4.2, "kg"),
                      ("23.00 years", 23, "years"), ("0.00", 0, ""), ("−6,4 kg", -6.4, "kg")])
    func values(text: String, value: Double, unit: String) throws {
        let parsed = try #require(ScaleScreenshotParser.parseValue(text))
        #expect(abs(parsed.0 - value) < 1e-9)
        #expect(parsed.1 == unit)
    }

    @Test(arguments: ["12:16", "Smart Scale", "100%x", "Body Fat"])
    func nonValues(text: String) {
        #expect(ScaleScreenshotParser.parseValue(text) == nil)
    }

    @Test func labelNormalisation() {
        #expect(ScaleScreenshotParser.normalizeLabel("Lean Body Mass (kg)") == "lean body mass")
        #expect(ScaleScreenshotParser.normalizeLabel("Muscle Mass %") == "muscle mass %")
        #expect(ScaleScreenshotParser.metrics(forLabel: "Obesity Degree (%)") == [.obesityDegree])
    }

    @Test(arguments: ["20 Oct, 2026 • Smart Scale", "Oct 20, 2026", "20/10/2026", "2026-10-20"])
    func dates(text: String) throws {
        let date = try #require(ScaleScreenshotParser.parseDate(in: text, calendar: calendar))
        #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2026, month: 10, day: 20))
    }

    @Test func formatting() {
        #expect(BodyMetric.bodyFat.format(22.7) == "22.7 %")
        #expect(BodyMetric.weight.format(82.8) == "82.8 kg")
        #expect(BodyMetric.bmr.format(1752).contains("kcal"))
        #expect(BodyMetric.healthScore.format(0) == "0")
    }

    @Test func readingRoundTripsThroughJSON() throws {
        let r = BodyReading(date: Date(timeIntervalSince1970: 0), values: [.weight: 80, .bodyFat: 20], statuses: [.bodyFat: "High"])
        let data = try JSONEncoder().encode(r)
        #expect(String(decoding: data, as: UTF8.self).contains("\"bodyFat\""))
        #expect(try JSONDecoder().decode(BodyReading.self, from: data) == r)
    }
}

@Suite("Sleep analysis")
struct SleepTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    func t(_ day: Int, _ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m, second: s))!
    }

    @Test func overlappingSourcesUseTheMostSpecificStage() {
        // iPhone: in bed 23:00–07:00. Watch: core 23:30–02:00, deep 02:00–03:00, awake 03:00–03:15, REM 03:15–06:45.
        let samples = [
            SleepSample(start: t(10, 23), end: t(11, 7), stage: .inBed),
            SleepSample(start: t(10, 23, 30), end: t(11, 2), stage: .core),
            SleepSample(start: t(11, 2), end: t(11, 3), stage: .deep),
            SleepSample(start: t(11, 3), end: t(11, 3, 15), stage: .awake),
            SleepSample(start: t(11, 3, 15), end: t(11, 6, 45), stage: .rem),
        ]
        let nights = SleepAnalyzer.nights(from: samples, calendar: calendar)
        #expect(nights.count == 1)
        let n = nights[0]
        #expect(n.night == calendar.startOfDay(for: t(11, 7)))
        func close(_ a: Double?, _ b: Double) -> Bool { abs((a ?? -1) - b) < 0.001 }
        #expect(close(n.durations[.core], 2.5 * 3600))
        #expect(close(n.durations[.deep], 3600))
        #expect(close(n.durations[.awake], 15 * 60))
        #expect(close(n.durations[.rem], 3.5 * 3600))
        #expect(close(n.durations[.inBed], 45 * 60))  // 23:00–23:30 and 06:45–07:00
        #expect(close(n.asleep, 7 * 3600))
        #expect(close(n.timeInBed, 8 * 3600))
        #expect(abs(n.efficiency - 7.0 / 8.0) < 1e-9)
        #expect(n.hasStages)
    }

    @Test func duplicateSamplesAreNotDoubleCounted() {
        let samples = [
            SleepSample(start: t(10, 23), end: t(11, 6), stage: .asleepUnspecified),
            SleepSample(start: t(10, 23), end: t(11, 6), stage: .asleepUnspecified),
        ]
        let night = SleepAnalyzer.nights(from: samples, calendar: calendar)[0]
        #expect(night.asleep == 7 * 3600)
        #expect(!night.hasStages)
    }

    @Test func napsAreKeptOutOfTheNight() {
        let samples = [
            SleepSample(start: t(9, 23), end: t(10, 6), stage: .asleepUnspecified),
            SleepSample(start: t(10, 14), end: t(10, 14, 30), stage: .asleepUnspecified), // nap
            SleepSample(start: t(10, 23, 30), end: t(11, 6, 30), stage: .asleepUnspecified),
        ]
        let nights = SleepAnalyzer.nights(from: samples, calendar: calendar)
        #expect(nights.count == 2)
        #expect(abs(nights[0].asleep - 7 * 3600) < 0.001)
        #expect(abs(nights[0].napAsleep - 0.5 * 3600) < 0.001)
        #expect(nights[0].start == t(9, 23), "bedtime is the night's, not the nap's")
        #expect(abs(nights[1].asleep - 7 * 3600) < 0.001)
        #expect(abs(SleepAnalyzer.averageAsleep(nights) - 7 * 3600) < 0.001)
    }

    @Test func gapsBetweenSleepCountAsAwakeAndAwakenings() {
        // iPhone-style data: asleep 23:00–02:00 and 02:20–06:00, nothing recorded in between.
        let samples = [
            SleepSample(start: t(10, 23), end: t(11, 2), stage: .asleepUnspecified),
            SleepSample(start: t(11, 2, 20), end: t(11, 6), stage: .asleepUnspecified),
        ]
        let night = SleepAnalyzer.nights(from: samples, calendar: calendar)[0]
        #expect(abs(night.awake - 20 * 60) < 0.001)
        #expect(night.awakenings == 1)
        #expect(abs(night.asleep - 6.67 * 3600) < 60)
    }

    @Test func briefAwakeBlipsAndTrailingAwakeAreNotAwakenings() {
        let samples = [
            SleepSample(start: t(10, 23), end: t(11, 2), stage: .core),
            SleepSample(start: t(11, 2), end: t(11, 2, 0, 30), stage: .awake),   // 30 s
            SleepSample(start: t(11, 2, 0, 30), end: t(11, 6), stage: .core),
            SleepSample(start: t(11, 6), end: t(11, 6, 10), stage: .awake),      // woke up for the day
        ]
        #expect(SleepAnalyzer.nights(from: samples, calendar: calendar)[0].awakenings == 0)
    }

    @Test func emptyAndInvalidSamples() {
        #expect(SleepAnalyzer.nights(from: []).isEmpty)
        #expect(SleepAnalyzer.nights(from: [SleepSample(start: t(11, 2), end: t(11, 1), stage: .core)]).isEmpty)
        #expect(SleepAnalyzer.averageAsleep([]) == 0)
    }

    @Test func bedtimeAveragingWrapsAroundMidnight() throws {
        let stats = try #require(SleepAnalyzer.clockTimeStats([t(10, 23, 30), t(11, 0, 30)], calendar: calendar))
        #expect(abs(stats.meanMinutes - 0) < 1e-9 || abs(stats.meanMinutes - 1440) < 1e-9)
        #expect(abs(stats.sdMinutes - 30) < 1e-9)
    }
}

@Suite("Weight trend and maintenance")
struct WeightTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400) }

    @Test func weeklyAveragesAndSlope() throws {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        // Losing 0.05 kg/day = 0.35 kg/week.
        let points = (0..<21).map { WeightPoint(date: day($0), kg: 85 - 0.05 * Double($0)) }
        let weeks = WeightTrend.weeklyAverages(points, calendar: c)
        #expect(weeks.count >= 3)
        #expect(weeks.map(\.readings).reduce(0, +) == 21)
        let slope = try #require(WeightTrend.slopePerWeek(points))
        #expect(abs(slope - -0.35) < 1e-9)
    }

    @Test func smoothingFollowsTheData() {
        let points = [WeightPoint(date: day(0), kg: 80), WeightPoint(date: day(1), kg: 82), WeightPoint(date: day(2), kg: 80)]
        let s = WeightTrend.smoothed(points)
        #expect(s.count == 3)
        #expect(s[0].kg == 80)
        #expect(s[1].kg > 80 && s[1].kg < 82)
        #expect(WeightTrend.smoothed([]).isEmpty)
        #expect(WeightTrend.slopePerWeek([points[0]]) == nil)
    }

    @Test func maintenanceFromIntakeAndWeightTrend() throws {
        // Eating 2,300 kcal/day while losing 0.35 kg/week → maintenance ≈ 2,300 + 0.05 × 7,700 = 2,685.
        var intake: [Date: Double] = [:]
        for n in 0..<14 { intake[day(n)] = 2_300 }
        let weights = stride(from: 0, to: 14, by: 2).map { WeightPoint(date: day($0), kg: 85 - 0.05 * Double($0)) }
        let estimate = try #require(MaintenanceEstimator.estimate(dailyIntake: intake, weights: weights))
        #expect(abs(estimate.maintenanceKcal - 2_685) < 0.5)
        #expect(abs(estimate.suggestedTarget.lowerBound - 2_335) < 0.5)
        #expect(estimate.loggedDays == 14)
    }

    @Test func partlyLoggedDaysAreIgnored() throws {
        var intake: [Date: Double] = [:]
        for n in 0..<16 { intake[day(n)] = n.isMultiple(of: 3) ? 450 : 2_300 }  // some days only breakfast logged
        let weights = stride(from: 0, to: 14, by: 2).map { WeightPoint(date: day($0), kg: 85 - 0.05 * Double($0)) }
        let estimate = try #require(MaintenanceEstimator.estimate(dailyIntake: intake, weights: weights))
        #expect(estimate.averageIntakeKcal == 2_300)
        #expect(estimate.loggedDays == 10)
    }

    @Test func duplicateWeighInsMerge() {
        let points = [
            WeightPoint(date: day(0), kg: 82.8),
            WeightPoint(date: day(0).addingTimeInterval(600), kg: 82.8),   // same reading via Apple Health
            WeightPoint(date: day(0).addingTimeInterval(3_600), kg: 82.5), // an hour later: kept
            WeightPoint(date: day(1), kg: 82.9),
        ]
        #expect(WeightTrend.deduplicated(points).map(\.kg) == [82.8, 82.5, 82.9])
    }

    @Test func maintenanceNeedsEnoughData() {
        let intake = [day(0): 2000.0, day(1): 2100]
        let weights = [WeightPoint(date: day(0), kg: 80), WeightPoint(date: day(1), kg: 80)]
        #expect(MaintenanceEstimator.estimate(dailyIntake: intake, weights: weights) == nil)
    }
}

@Suite("Sync merge")
struct SyncMergeTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    let t0 = Date(timeIntervalSince1970: 100), t1 = Date(timeIntervalSince1970: 200)

    @Test func newerRecordsWinAndTombstonesDelete() {
        let local = [SyncStamp(id: a, updatedAt: t0), SyncStamp(id: b, updatedAt: t1), SyncStamp(id: c, updatedAt: t0)]
        let incoming = [
            SyncStamp(id: a, updatedAt: t1),                 // newer → update
            SyncStamp(id: b, updatedAt: t0),                 // older → ignore
            SyncStamp(id: c, updatedAt: t1, deleted: true),  // deleted elsewhere → delete
            SyncStamp(id: d, updatedAt: t0),                 // new → insert
        ]
        let actions = SyncMerge.actions(local: local, incoming: incoming)
        #expect(Set(actions.map { "\($0)" }) == Set([SyncAction.update(a), .delete(c), .insert(d)].map { "\($0)" }))
    }

    @Test func tombstonesForUnknownRecordsAreIgnoredAndMergeIsIdempotent() {
        let incoming = [SyncStamp(id: a, updatedAt: t1, deleted: true), SyncStamp(id: b, updatedAt: t1)]
        #expect(SyncMerge.actions(local: [], incoming: incoming) == [.insert(b)])
        let local = [SyncStamp(id: b, updatedAt: t1)]
        #expect(SyncMerge.actions(local: local, incoming: incoming).isEmpty)
    }

    @Test func editAfterDeleteResurrects() {
        let local = [SyncStamp(id: a, updatedAt: t0, deleted: true)]
        #expect(SyncMerge.actions(local: local, incoming: [SyncStamp(id: a, updatedAt: t1)]) == [.insert(a)])
    }
}

@Suite("Sleep score")
struct SleepScoreTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    func t(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    /// A night ending on `day`: bedtime the evening before (or after midnight for hours < 12),
    /// `hours` asleep, with awake spells (hour, minute, length) carved out of the sleep.
    func night(_ day: Int, bed: (Int, Int), hours: Double, awake: [(Int, Int, Int)] = []) -> SleepNight {
        let start = bed.0 < 12 ? t(day, bed.0, bed.1) : t(day - 1, bed.0, bed.1)
        let spells = awake.map { (t(day, $0.0, $0.1), Double($0.2) * 60) }.sorted { $0.0 < $1.0 }
        let end = start.addingTimeInterval(hours * 3600 + spells.map(\.1).reduce(0, +))
        var samples: [SleepSample] = []
        var cursor = start
        for (begin, length) in spells {
            samples.append(SleepSample(start: cursor, end: begin, stage: .core))
            samples.append(SleepSample(start: begin, end: begin.addingTimeInterval(length), stage: .awake))
            cursor = begin.addingTimeInterval(length)
        }
        samples.append(SleepSample(start: cursor, end: end, stage: .core))
        return SleepAnalyzer.nights(from: samples, calendar: calendar).last!
    }

    @Test func perfectNightScores100() throws {
        let history = (3...9).map { night($0, bed: (23, 0), hours: 8) }
        let score = try #require(SleepScore.score(night(10, bed: (23, 10), hours: 8), previousNights: history, goalHours: 8, calendar: calendar))
        #expect(score.total == 100)
        #expect(score.rating == .veryHigh)
        #expect(score.bedtimeFromHistory)
    }

    @Test func partsFollowAppleWeights() throws {
        let history = (3...9).map { night($0, bed: (23, 0), hours: 8) }
        // 5.5 h asleep, in bed 75 min late, woken twice for 10 min each.
        let n = night(10, bed: (0, 15), hours: 5.5, awake: [(2, 0, 10), (4, 0, 10)])
        let score = try #require(SleepScore.score(n, previousNights: history, goalHours: 8, calendar: calendar))
        #expect(abs(score.duration - 25) < 0.5)        // (5.5 − 3) / (8 − 3) × 50
        #expect(abs(score.bedtime - 15) < 0.5)         // 75 min off: 1 − 45/90 → half of 30
        #expect(abs(score.interruptions - 12) < 0.01)  // 20 − 3 (second awakening) − 20 min × 0.25
        #expect(score.total == 52)
        #expect(score.rating == .low)
    }

    @Test func withoutHistoryBedtimeUsesAWindow() throws {
        let inWindow = try #require(SleepScore.score(night(10, bed: (22, 30), hours: 8), previousNights: [], calendar: calendar))
        #expect(inWindow.bedtime == 30)
        #expect(!inWindow.bedtimeFromHistory)
        let late = try #require(SleepScore.score(night(10, bed: (2, 30), hours: 8), previousNights: [], calendar: calendar))
        #expect(late.bedtime == 0)
    }

    @Test func bedtimeAcrossMidnightIsHandled() throws {
        // Usually asleep around 23:45–00:15; tonight 00:05 is on time.
        let history = (3...9).map { night($0, bed: $0.isMultiple(of: 2) ? (23, 45) : (0, 15), hours: 8) }
        let score = try #require(SleepScore.score(night(10, bed: (0, 5), hours: 8), previousNights: history, calendar: calendar))
        #expect(score.bedtime == 30)
    }

    @Test func noSleepNoScore() {
        let empty = SleepNight(night: t(10, 0), start: t(9, 23), end: t(10, 7), durations: [.inBed: 8 * 3600])
        #expect(SleepScore.score(empty, previousNights: []) == nil)
    }
}
