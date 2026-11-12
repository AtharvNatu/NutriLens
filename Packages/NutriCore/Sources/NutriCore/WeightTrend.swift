import Foundation

public struct WeightPoint: Equatable, Sendable {
    public var date: Date
    public var kg: Double

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

public struct WeeklyWeight: Identifiable, Equatable, Sendable {
    /// Start of the week.
    public var weekStart: Date
    public var averageKg: Double
    public var readings: Int

    public var id: Date { weekStart }
}

public enum WeightTrend {
    /// Merges readings that are really the same weigh-in recorded twice (e.g. a screenshot import and the
    /// scale app's own Apple Health entry): within 30 minutes and 0.1 kg of each other. Sorted by date.
    public static func deduplicated(_ points: [WeightPoint]) -> [WeightPoint] {
        var result: [WeightPoint] = []
        for point in points.sorted(by: { $0.date < $1.date }) {
            if let last = result.last, point.date.timeIntervalSince(last.date) <= 30 * 60, abs(point.kg - last.kg) <= 0.1 {
                continue
            }
            result.append(point)
        }
        return result
    }

    /// Weekly averages ("compare weekly averages, not single days"), oldest first.
    public static func weeklyAverages(_ points: [WeightPoint], calendar: Calendar = .current) -> [WeeklyWeight] {
        var buckets: [Date: [Double]] = [:]
        for point in points {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: point.date)?.start else { continue }
            buckets[week, default: []].append(point.kg)
        }
        return buckets
            .map { WeeklyWeight(weekStart: $0.key, averageKg: $0.value.reduce(0, +) / Double($0.value.count), readings: $0.value.count) }
            .sorted { $0.weekStart < $1.weekStart }
    }

    /// Exponentially smoothed trend weight per reading (time-aware: about 10 % per day).
    public static func smoothed(_ points: [WeightPoint], dailyAlpha: Double = 0.1) -> [WeightPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        guard var trend = sorted.first?.kg, var last = sorted.first?.date else { return [] }
        var result: [WeightPoint] = []
        for point in sorted {
            let days = max(0, point.date.timeIntervalSince(last) / 86_400)
            let alpha = 1 - pow(1 - dailyAlpha, max(days, 1))
            trend += alpha * (point.kg - trend)
            result.append(WeightPoint(date: point.date, kg: trend))
            last = point.date
        }
        return result
    }

    /// Least-squares slope in kg per week, or nil with fewer than two readings on different days.
    public static func slopePerWeek(_ points: [WeightPoint]) -> Double? {
        guard points.count >= 2, let first = points.map(\.date).min() else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.kg)
        let n = Double(points.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        return sxy / sxx * 7
    }
}

/// Estimates maintenance calories from what you actually ate and how your weight moved.
public struct MaintenanceEstimate: Equatable, Sendable {
    public var maintenanceKcal: Double
    public var averageIntakeKcal: Double
    public var weightChangePerWeekKg: Double
    public var loggedDays: Int
    public var weighIns: Int

    /// The plan's suggestion: a modest 250–350 kcal/day below the observed maintenance.
    public var suggestedTarget: ClosedRange<Double> {
        (maintenanceKcal - 350)...(maintenanceKcal - 250)
    }
}

public enum MaintenanceEstimator {
    /// Energy in a kilogram of body-weight change, a common approximation.
    public static let kcalPerKg = 7_700.0

    /// Needs at least 10 logged days and 5 weigh-ins spanning 10+ days within the window.
    /// Days below `completeDayKcal` are treated as only partly logged and ignored, since counting them
    /// would make maintenance look far lower than it is.
    public static func estimate(dailyIntake: [Date: Double], weights: [WeightPoint],
                                minimumLoggedDays: Int = 10, minimumWeighIns: Int = 5,
                                completeDayKcal: Double = 1_000) -> MaintenanceEstimate? {
        let logged = dailyIntake.filter { $0.value >= completeDayKcal }
        guard logged.count >= minimumLoggedDays, weights.count >= minimumWeighIns,
              let first = weights.map(\.date).min(), let last = weights.map(\.date).max(),
              last.timeIntervalSince(first) >= 10 * 86_400,
              let slope = WeightTrend.slopePerWeek(weights)
        else { return nil }
        let intake = logged.values.reduce(0, +) / Double(logged.count)
        let maintenance = intake - slope / 7 * kcalPerKg
        return MaintenanceEstimate(
            maintenanceKcal: maintenance,
            averageIntakeKcal: intake,
            weightChangePerWeekKg: slope,
            loggedDays: logged.count,
            weighIns: weights.count
        )
    }
}
