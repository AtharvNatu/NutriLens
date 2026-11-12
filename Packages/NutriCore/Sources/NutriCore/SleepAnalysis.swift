import Foundation

/// Sleep stages as Apple Health records them (`HKCategoryValueSleepAnalysis`).
public enum SleepStage: String, Codable, CaseIterable, Sendable {
    case inBed, awake, asleepUnspecified, core, deep, rem

    /// When samples from different sources overlap, the most specific stage wins.
    var priority: Int {
        switch self {
        case .inBed: 0
        case .awake: 1
        case .asleepUnspecified: 2
        case .core: 3
        case .rem: 4
        case .deep: 5
        }
    }

    public var isAsleep: Bool { self == .asleepUnspecified || self == .core || self == .deep || self == .rem }

    public var displayName: String {
        switch self {
        case .inBed: "In bed"
        case .awake: "Awake"
        case .asleepUnspecified: "Asleep"
        case .core: "Core"
        case .deep: "Deep"
        case .rem: "REM"
        }
    }
}

public struct SleepSample: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage

    public init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }
}

/// One night's sleep, after merging all sources.
public struct SleepNight: Identifiable, Equatable, Sendable {
    /// Start of the calendar day on which this sleep ended (the morning you woke up).
    public var night: Date
    /// Bedtime and wake time of the main sleep (the longest session ending that day).
    public var start: Date
    public var end: Date
    /// Seconds per stage in the main sleep. `inBed` counts only time in bed that no source marked as
    /// asleep or awake; gaps between sleep segments are counted as `awake`.
    public var durations: [SleepStage: TimeInterval]
    /// Times you woke up during the main sleep (awake spells between periods of sleep).
    public var awakenings: Int
    /// Sleep in other, shorter sessions ending the same day (naps), not part of the night.
    public var napAsleep: TimeInterval

    public var id: Date { night }

    public init(night: Date, start: Date, end: Date, durations: [SleepStage: TimeInterval], awakenings: Int = 0, napAsleep: TimeInterval = 0) {
        self.night = night
        self.start = start
        self.end = end
        self.durations = durations
        self.awakenings = awakenings
        self.napAsleep = napAsleep
    }

    public var asleep: TimeInterval {
        durations.filter { $0.key.isAsleep }.map(\.value).reduce(0, +)
    }
    public var awake: TimeInterval { durations[.awake] ?? 0 }
    /// Total time covered by the main sleep.
    public var timeInBed: TimeInterval { durations.values.reduce(0, +) }
    /// Asleep ÷ time in bed, 0...1.
    public var efficiency: Double { timeInBed > 0 ? asleep / timeInBed : 0 }
    /// Whether any source recorded stages (Apple Watch) rather than just "asleep".
    public var hasStages: Bool { (durations[.core] ?? 0) + (durations[.deep] ?? 0) + (durations[.rem] ?? 0) > 0 }
}

public enum SleepAnalyzer {
    /// Gap between samples that starts a new sleep session (a nap vs. the night, say).
    public static let sessionGap: TimeInterval = 3 * 3600

    /// Groups samples into nights and resolves overlaps, keeping the most specific stage at each moment.
    /// Sessions are assigned to the day they end on. The longest session that day is the night's sleep;
    /// the others are counted as naps.
    public static func nights(from samples: [SleepSample], calendar: Calendar = .current) -> [SleepNight] {
        let valid = samples.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !valid.isEmpty else { return [] }

        // Cluster into sessions.
        var sessions: [[SleepSample]] = []
        var currentEnd = Date.distantPast
        for sample in valid {
            if sessions.isEmpty || sample.start.timeIntervalSince(currentEnd) > sessionGap {
                sessions.append([sample])
                currentEnd = sample.end
            } else {
                sessions[sessions.count - 1].append(sample)
                currentEnd = max(currentEnd, sample.end)
            }
        }

        var byNight: [Date: [SleepNight]] = [:]
        for session in sessions {
            let (durations, awakenings) = resolve(session)
            let start = session.map(\.start).min()!
            let end = session.map(\.end).max()!
            let night = calendar.startOfDay(for: end)
            byNight[night, default: []].append(SleepNight(night: night, start: start, end: end, durations: durations, awakenings: awakenings))
        }
        return byNight.values.compactMap { sessions -> SleepNight? in
            guard var main = sessions.max(by: { $0.asleep < $1.asleep }) else { return nil }
            main.napAsleep = sessions.filter { $0.start != main.start }.map(\.asleep).reduce(0, +)
            return main
        }
        .sorted { $0.night < $1.night }
    }

    /// Sweep line over sample boundaries: each interval gets the highest-priority stage covering it.
    /// Uncovered gaps between sleep count as awake. Returns stage durations and the number of awakenings.
    static func resolve(_ samples: [SleepSample]) -> ([SleepStage: TimeInterval], Int) {
        let boundaries = Set(samples.flatMap { [$0.start, $0.end] }).sorted()
        var timeline: [(stage: SleepStage, seconds: TimeInterval)] = []
        for (a, b) in zip(boundaries, boundaries.dropFirst()) {
            let active = samples.filter { $0.start <= a && $0.end >= b }
            let stage = active.max(by: { $0.stage.priority < $1.stage.priority })?.stage ?? .awake
            if let last = timeline.last, last.stage == stage {
                timeline[timeline.count - 1].seconds += b.timeIntervalSince(a)
            } else {
                timeline.append((stage, b.timeIntervalSince(a)))
            }
        }
        var result: [SleepStage: TimeInterval] = [:]
        for part in timeline { result[part.stage, default: 0] += part.seconds }
        // An awakening is an awake spell of at least a minute with sleep both before and after it.
        var awakenings = 0
        var sleptBefore = false
        for (i, part) in timeline.enumerated() {
            if part.stage.isAsleep {
                sleptBefore = true
            } else if part.stage == .awake, part.seconds >= 60, sleptBefore,
                      timeline[(i + 1)...].contains(where: { $0.stage.isAsleep }) {
                awakenings += 1
            }
        }
        return (result, awakenings)
    }

    /// Mean of a set of clock times (e.g. bedtimes) as minutes after midnight, handling the wrap at midnight,
    /// plus the standard deviation in minutes, a simple sleep-regularity measure.
    public static func clockTimeStats(_ dates: [Date], calendar: Calendar = .current) -> (meanMinutes: Double, sdMinutes: Double)? {
        guard !dates.isEmpty else { return nil }
        // Shift so the day starts at noon: 23:30 and 00:30 are then an hour apart, not 23 hours.
        let minutes = dates.map { date -> Double in
            let c = calendar.dateComponents([.hour, .minute], from: date)
            let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            return m < 720 ? m + 1440 : m
        }
        let mean = minutes.reduce(0, +) / Double(minutes.count)
        let variance = minutes.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(minutes.count)
        return (mean.truncatingRemainder(dividingBy: 1440), variance.squareRoot())
    }

    /// Average nightly sleep over nights with data.
    public static func averageAsleep(_ nights: [SleepNight]) -> TimeInterval {
        let withSleep = nights.filter { $0.asleep > 0 }
        guard !withSleep.isEmpty else { return 0 }
        return withSleep.map(\.asleep).reduce(0, +) / Double(withSleep.count)
    }
}

/// A 0–100 nightly sleep score with the same three parts and weights Apple uses for its Apple Watch
/// Sleep Score: duration (50 points), bedtime consistency (30) and interruptions (20).
///
/// Apple doesn't publish its exact formula, and HealthKit doesn't expose Apple's score, so this is
/// NutriLens's own calculation from the same sleep data. It won't always match Apple's number.
public struct SleepScore: Equatable, Sendable {
    public var duration: Double
    public var bedtime: Double
    public var interruptions: Double
    /// Whether bedtime was compared with your own recent bedtimes (otherwise a 21:00–00:30 window).
    public var bedtimeFromHistory: Bool

    public static let durationMax = 50.0
    public static let bedtimeMax = 30.0
    public static let interruptionsMax = 20.0

    public var total: Int { Int((duration + bedtime + interruptions).rounded()) }

    public enum Rating: String, Sendable {
        case veryHigh = "Very high", high = "High", ok = "OK", low = "Low", veryLow = "Very low"
    }

    public var rating: Rating {
        switch total {
        case 90...: .veryHigh
        case 75..<90: .high
        case 60..<75: .ok
        case 40..<60: .low
        default: .veryLow
        }
    }

    /// - Parameters:
    ///   - night: the night to score.
    ///   - previousNights: earlier nights, used for bedtime consistency (needs 3 or more).
    ///   - goalHours: sleep goal; full duration points at or above it.
    public static func score(_ night: SleepNight, previousNights: [SleepNight], goalHours: Double = 8, calendar: Calendar = .current) -> SleepScore? {
        guard night.asleep > 0 else { return nil }
        let goal = max(goalHours, 4) * 3600
        // Duration: nothing below 3 h, full marks at the goal.
        let durationFraction = min(max((night.asleep - 3 * 3600) / (goal - 3 * 3600), 0), 1)

        // Bedtime: within 30 min of your usual bedtime scores fully, 2 h or more off scores nothing.
        let history = previousNights.filter { $0.night < night.night }.suffix(14)
        let deviation: Double
        let fromHistory: Bool
        if history.count >= 3, let usual = SleepAnalyzer.clockTimeStats(history.map(\.start), calendar: calendar) {
            let minutes = minutesAfterNoon(night.start, calendar: calendar)
            let usualAfterNoon = usual.meanMinutes < 720 ? usual.meanMinutes + 720 : usual.meanMinutes - 720
            deviation = abs(minutes - usualAfterNoon)
            fromHistory = true
        } else {
            // No history yet: 21:00–00:30 counts as a regular bedtime.
            let minutes = minutesAfterNoon(night.start, calendar: calendar)
            deviation = minutes < 540 ? 540 - minutes : max(0, minutes - 750)
            fromHistory = false
        }
        let bedtimeFraction = min(max(1 - (deviation - 30) / 90, 0), 1)

        // Interruptions: each awakening after the first costs 3 points, each awake minute 0.25.
        let penalty = Double(max(0, night.awakenings - 1)) * 3 + night.awake / 60 * 0.25
        let interruptions = max(0, interruptionsMax - penalty)

        return SleepScore(duration: durationFraction * durationMax, bedtime: bedtimeFraction * bedtimeMax,
                          interruptions: interruptions, bedtimeFromHistory: fromHistory)
    }

    /// Minutes since the previous noon, so 23:30 = 690 and 00:30 = 750.
    static func minutesAfterNoon(_ date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        return m >= 720 ? m - 720 : m + 720
    }
}
