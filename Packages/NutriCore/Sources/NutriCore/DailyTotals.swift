import Foundation

/// One logged item reduced to what the aggregations need.
public struct LoggedAmount: Sendable, Equatable {
    public var date: Date
    public var nutrients: Nutrients

    public init(date: Date, nutrients: Nutrients) {
        self.date = date
        self.nutrients = nutrients
    }
}

/// Nutrients eaten on one calendar day.
public struct DayTotal: Identifiable, Equatable, Sendable {
    /// Start of the day.
    public var day: Date
    public var nutrients: Nutrients
    public var entryCount: Int

    public var id: Date { day }

    public init(day: Date, nutrients: Nutrients, entryCount: Int) {
        self.day = day
        self.nutrients = nutrients
        self.entryCount = entryCount
    }
}

public enum DailyTotals {
    /// The seven start-of-day dates of the week containing `date`, using `calendar`'s first weekday.
    public static func week(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return [calendar.startOfDay(for: date)]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
            .map { calendar.startOfDay(for: $0) }
    }

    /// The `count` start-of-day dates ending with the day containing `date`, oldest first.
    public static func days(endingOn date: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        let end = calendar.startOfDay(for: date)
        return (0..<max(0, count)).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: end)
        }
    }

    /// Totals for each of `days` (start-of-day dates). Entries on other days are ignored;
    /// days without entries get zero totals, so charts show gaps as zero bars.
    public static func totals(
        of entries: [LoggedAmount],
        for days: [Date],
        calendar: Calendar = .current
    ) -> [DayTotal] {
        var sums: [Date: (Nutrients, Int)] = [:]
        let wanted = Set(days.map { calendar.startOfDay(for: $0) })
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            guard wanted.contains(day) else { continue }
            let current = sums[day] ?? (.zero, 0)
            sums[day] = (current.0 + entry.nutrients, current.1 + 1)
        }
        return days.map { raw in
            let day = calendar.startOfDay(for: raw)
            let (n, count) = sums[day] ?? (.zero, 0)
            return DayTotal(day: day, nutrients: n, entryCount: count)
        }
    }

    /// Mean kilocalories per day over the days that have at least one entry.
    public static func averageKilocalories(of totals: [DayTotal]) -> Double {
        let logged = totals.filter { $0.entryCount > 0 }
        guard !logged.isEmpty else { return 0 }
        return logged.map(\.nutrients.kilocalories).reduce(0, +) / Double(logged.count)
    }
}
