import Foundation

/// A line of text recognised in an image, with its bounding box in normalised image
/// coordinates (0...1, origin at the top-left, y growing downwards).
public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(_ text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var minX: Double { x }
    var maxX: Double { x + width }
    var minY: Double { y }
    var maxY: Double { y + height }
    var midY: Double { y + height / 2 }

    func horizontalOverlap(with other: RecognizedLine) -> Double {
        max(0, min(maxX, other.maxX) - max(minX, other.minX))
    }
}

/// Reads body-composition values from the text of a smart-scale app screenshot.
///
/// Built for the Healthify Smart Scale result screen, where each value sits on a card:
/// a status tag ("High", "Healthy"), the label ("Body Fat") and the value below it ("22.70 %").
/// It also handles "Label  value" on one line, as other scale apps show. The image itself is
/// read by Vision on the device; this type only interprets the recognised text, so it is testable.
public enum ScaleScreenshotParser {
    public static func parse(_ lines: [RecognizedLine], calendar: Calendar = .current) -> BodyReading {
        var reading = BodyReading()
        var labels: [(index: Int, line: RecognizedLine, metrics: [BodyMetric])] = []
        var values: [(index: Int, line: RecognizedLine, value: Double, unit: String)] = []
        var statuses: [(index: Int, line: RecognizedLine, text: String)] = []

        for (index, line) in lines.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if reading.date == nil, let date = parseDate(in: text, calendar: calendar) {
                reading.date = date
            }
            if let status = statusWord(text) {
                statuses.append((index, line, status))
            } else if let (value, unit) = parseValue(text) {
                values.append((index, line, value, unit))
            } else if let metrics = metrics(forLabel: text), !metrics.isEmpty {
                labels.append((index, line, metrics))
            } else if let (metrics, value, unit) = parseInline(text) {
                // "Body Fat  22.7 %" on a single line.
                if let metric = choose(metrics, unit: unit, taken: Set(reading.values.keys)),
                   metric.plausibleRange.contains(value) {
                    reading.values[metric] = value
                }
            }
        }

        // Pair each label with the closest value below it (card layout) or to its right (list layout).
        var candidates: [(score: Double, label: Int, value: Int)] = []
        for (li, label) in labels.enumerated() {
            let h = max(label.line.height, 0.005)
            for (vi, value) in values.enumerated() {
                let v = value.line
                let below = v.minY - label.line.maxY
                if below > -0.3 * h, below < 3.5 * h, v.horizontalOverlap(with: label.line) > 0 || abs(v.minX - label.line.minX) < 2 * h {
                    candidates.append((below / h + abs(v.minX - label.line.minX) / h * 0.5, li, vi))
                } else if abs(v.midY - label.line.midY) < 0.7 * h, v.minX >= label.line.maxX - h {
                    candidates.append((1 + (v.minX - label.line.maxX) / h * 0.2, li, vi))
                }
            }
        }
        candidates.sort { $0.score < $1.score }
        var usedLabels = Set<Int>(), usedValues = Set<Int>()
        var labelMetric: [Int: BodyMetric] = [:]
        for candidate in candidates where !usedLabels.contains(candidate.label) && !usedValues.contains(candidate.value) {
            let label = labels[candidate.label]
            let value = values[candidate.value]
            guard let metric = choose(label.metrics, unit: value.unit, taken: Set(reading.values.keys)),
                  metric.plausibleRange.contains(value.value)
            else { continue }
            reading.values[metric] = value.value
            labelMetric[candidate.label] = metric
            usedLabels.insert(candidate.label)
            usedValues.insert(candidate.value)
        }

        // The big headline number in kg is the weight when no "Weight" label exists.
        var weightLine: RecognizedLine?
        if reading.values[.weight] == nil {
            let unassigned = values.enumerated().filter { !usedValues.contains($0.offset) && $0.element.unit == "kg" }
            if let hero = unassigned.max(by: { $0.element.line.height < $1.element.line.height }),
               BodyMetric.weight.plausibleRange.contains(hero.element.value) {
                reading.values[.weight] = hero.element.value
                weightLine = hero.element.line
            }
        }

        // Status tags sit just above their label (or just below the headline weight).
        var usedStatuses = Set<Int>()
        for (li, metric) in labelMetric {
            let label = labels[li].line
            let h = max(label.height, 0.005)
            let match = statuses.enumerated()
                .filter { !usedStatuses.contains($0.offset) }
                .filter { s in
                    let gap = label.minY - s.element.line.maxY
                    return gap > -0.2 * h && gap < 2.5 * h && (s.element.line.horizontalOverlap(with: label) > 0 || abs(s.element.line.minX - label.minX) < 2 * h)
                }
                .min { (label.minY - $0.element.line.maxY) < (label.minY - $1.element.line.maxY) }
            if let match {
                reading.statuses[metric] = match.element.text
                usedStatuses.insert(match.offset)
            }
        }
        if let weightLine {
            let h = weightLine.height
            if let status = statuses.enumerated().first(where: { s in
                !usedStatuses.contains(s.offset) && s.element.line.minY > weightLine.maxY - 0.1 * h && s.element.line.minY - weightLine.maxY < 1.5 * h
            }) {
                reading.statuses[.weight] = status.element.text
            }
        }
        return reading
    }

    // MARK: Pieces (internal for tests)

    /// Lower-cases, drops parenthesised units such as "(kg)", keeps a bare "%" as a word.
    public static func normalizeLabel(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "%", with: " % ")
        s = s.map { $0.isLetter || $0.isNumber || $0 == "%" ? String($0) : " " }.joined()
        return s.split(separator: " ").joined(separator: " ")
    }

    static func metrics(forLabel text: String) -> [BodyMetric]? {
        let key = normalizeLabel(text)
        guard !key.isEmpty, key.count <= 40, key.contains(where: \.isLetter) else { return nil }
        let exact = BodyMetric.allCases.filter { $0.labelAliases.contains(key) }
        if !exact.isEmpty { return exact }
        // Tolerate one or two OCR slips in longer labels ("Subcutaneous Fal").
        guard key.count >= 6 else { return nil }
        let allowed = key.count >= 12 ? 2 : 1
        let fuzzy = BodyMetric.allCases.filter { metric in
            metric.labelAliases.contains { $0.count >= 6 && editDistance($0, key) <= allowed }
        }
        return fuzzy.isEmpty ? nil : fuzzy
    }

    private static let valuePattern = #"^([+\-−–]?\d{1,4}(?:[.,]\d{1,3})?)\s*(kg|%|kcal|cal|years|year|yrs|yr|cm)?\.?$"#

    /// "22.70 %" → (22.7, "%"); "1752 Cal" → (1752, "cal"); "-4.20 kg" → (-4.2, "kg").
    public static func parseValue(_ text: String) -> (Double, String)? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let match = t.range(of: valuePattern, options: [.regularExpression, .caseInsensitive]), match == t.startIndex..<t.endIndex else { return nil }
        let regex = try? NSRegularExpression(pattern: valuePattern, options: [.caseInsensitive])
        let ns = t as NSString
        guard let m = regex?.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var number = ns.substring(with: m.range(at: 1))
        number = number.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        guard let value = Double(number) else { return nil }
        let unit = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2)).lowercased()
        return (value, unit)
    }

    static func parseInline(_ text: String) -> ([BodyMetric], Double, String)? {
        let pattern = #"^(.*?[A-Za-z%)])[\s:]+([+\-−–]?\d{1,4}(?:[.,]\d{1,3})?\s*(?:kg|%|kcal|cal|years|year|yrs|yr|cm)?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              let metrics = metrics(forLabel: ns.substring(with: m.range(at: 1))),
              let (value, unit) = parseValue(ns.substring(with: m.range(at: 2)))
        else { return nil }
        return (metrics, value, unit)
    }

    private static let statusWords: Set<String> = [
        "high", "low", "healthy", "normal", "standard", "excellent", "good", "obese",
        "overweight", "underweight", "insufficient", "sufficient", "very high", "very low",
    ]

    static func statusWord(_ text: String) -> String? {
        let key = normalizeLabel(text)
        guard statusWords.contains(key) else { return nil }
        return key.capitalized
    }

    /// Picks the metric that fits the displayed unit, e.g. "Muscle Mass" + "%" → muscle mass %.
    static func choose(_ metrics: [BodyMetric], unit: String, taken: Set<BodyMetric>) -> BodyMetric? {
        var options = metrics
        if options.contains(.muscleMass), !options.contains(.muscleMassPercent) { options.append(.muscleMassPercent) }
        if options.contains(.muscleMassPercent), !options.contains(.muscleMass) { options.append(.muscleMass) }
        let fitting = options.filter { $0.acceptedUnits.contains(unit) && !taken.contains($0) }
        // Prefer a metric whose unit is the displayed one over one that merely tolerates no unit.
        return fitting.first { $0.unit == unit || ($0.unit == "kcal" && unit == "cal") } ?? fitting.first
    }

    private static let dateFormats = [
        "d MMM, yyyy", "d MMM yyyy", "MMM d, yyyy", "d MMMM yyyy", "d MMMM, yyyy", "MMMM d, yyyy",
        "dd/MM/yyyy", "d/M/yyyy", "yyyy-MM-dd", "dd-MM-yyyy", "d MMM, yyyy h:mm a", "d MMM yyyy, HH:mm",
    ]

    /// Finds a date such as "20 Oct, 2026" in a line like "20 Oct, 2026 • Smart Scale".
    public static func parseDate(in text: String, calendar: Calendar = .current) -> Date? {
        let patterns = [
            #"\b\d{1,2}\s+[A-Za-z]{3,9},?\s+\d{4}\b"#,
            #"\b[A-Za-z]{3,9}\s+\d{1,2},\s*\d{4}\b"#,
            #"\b\d{1,2}[/-]\d{1,2}[/-]\d{4}\b"#,
            #"\b\d{4}-\d{2}-\d{2}\b"#,
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for pattern in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let candidate = String(text[range])
            for format in dateFormats {
                formatter.dateFormat = format
                if let date = formatter.date(from: candidate) {
                    return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: date) ?? date
                }
            }
        }
        return nil
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
