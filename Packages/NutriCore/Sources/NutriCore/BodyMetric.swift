import Foundation

/// A body measurement, as shown by smart-scale apps such as HealthifyMe (Healthify Smart Scale).
///
/// Values are stored in the unit the scale app displays. Some are proprietary estimates
/// (health score, metabolic age, visceral fat) rather than clinical measurements.
public enum BodyMetric: String, CaseIterable, Codable, CodingKeyRepresentable, Identifiable, Sendable {
    case weight
    case bodyFat
    case muscleMass
    case muscleMassPercent
    case leanBodyMass
    case skeletalMuscle
    case subcutaneousFat
    case visceralFat
    case bmi
    case bmr
    case bodyWater
    case protein
    case boneMass
    case metabolicAge
    case healthScore
    case obesityDegree
    case mineralSalt
    case bestVisualWeight
    case standardWeight
    case weightControl
    case fatControl
    case muscleControl
    /// Not on the scale; measured with a tape, as the training plan recommends.
    case waist

    public var id: String { rawValue }

    /// The 22 values a Healthify Smart Scale reading shows (everything except waist).
    public static let scaleMetrics: [BodyMetric] = allCases.filter { $0 != .waist }

    public var displayName: String {
        switch self {
        case .weight: "Weight"
        case .bodyFat: "Body fat"
        case .muscleMass: "Muscle mass"
        case .muscleMassPercent: "Muscle mass %"
        case .leanBodyMass: "Lean body mass"
        case .skeletalMuscle: "Skeletal muscle"
        case .subcutaneousFat: "Subcutaneous fat"
        case .visceralFat: "Visceral fat"
        case .bmi: "BMI"
        case .bmr: "BMR"
        case .bodyWater: "Body hydration"
        case .protein: "Protein"
        case .boneMass: "Bone mass"
        case .metabolicAge: "Metabolic age"
        case .healthScore: "Health score"
        case .obesityDegree: "Obesity degree"
        case .mineralSalt: "Mineral salt"
        case .bestVisualWeight: "Best visual weight"
        case .standardWeight: "Standard weight"
        case .weightControl: "Weight control"
        case .fatControl: "Fat control"
        case .muscleControl: "Muscle control"
        case .waist: "Waist"
        }
    }

    /// Unit as the scale app displays it ("" for unitless scores).
    public var unit: String {
        switch self {
        case .weight, .muscleMass, .leanBodyMass, .mineralSalt, .bestVisualWeight, .standardWeight,
             .weightControl, .fatControl, .muscleControl: "kg"
        case .bodyFat, .muscleMassPercent, .skeletalMuscle, .subcutaneousFat, .visceralFat, .bodyWater,
             .protein, .boneMass, .obesityDegree: "%"
        case .bmr: "kcal"
        case .metabolicAge: "years"
        case .waist: "cm"
        case .bmi, .healthScore: ""
        }
    }

    public var symbolName: String {
        switch self {
        case .weight, .bestVisualWeight, .standardWeight, .weightControl: "scalemass"
        case .bodyFat, .subcutaneousFat, .visceralFat, .fatControl, .obesityDegree: "drop.halffull"
        case .muscleMass, .muscleMassPercent, .skeletalMuscle, .leanBodyMass, .muscleControl: "figure.strengthtraining.traditional"
        case .bmi: "figure.stand"
        case .bmr: "flame"
        case .bodyWater: "drop"
        case .protein: "fork.knife"
        case .boneMass, .mineralSalt: "circle.hexagongrid"
        case .metabolicAge: "hourglass"
        case .healthScore: "heart.text.square"
        case .waist: "ruler"
        }
    }

    /// Whether a falling value is generally the direction of progress during fat loss.
    /// `nil` when neither direction is clearly better (targets, control values, scores).
    public var lowerIsBetter: Bool? {
        switch self {
        case .weight, .bodyFat, .subcutaneousFat, .visceralFat, .bmi, .obesityDegree, .waist, .metabolicAge: true
        case .muscleMass, .leanBodyMass, .skeletalMuscle: false
        default: nil
        }
    }

    /// Labels a scale app may use for this value, already normalised (see `ScaleScreenshotParser.normalizeLabel`).
    /// "Muscle mass" appears twice in Healthify: once in % and once in kg, told apart by the unit.
    public var labelAliases: [String] {
        switch self {
        case .weight: ["weight", "body weight"]
        case .bodyFat: ["body fat", "body fat rate", "fat", "bfr"]
        case .muscleMass: ["muscle mass", "muscle"]
        case .muscleMassPercent: ["muscle mass %", "muscle rate", "muscle mass rate"]
        case .leanBodyMass: ["lean body mass", "fat free mass", "fat free body weight", "lbm"]
        case .skeletalMuscle: ["skeletal muscle", "skeletal muscle rate", "skeletal muscle mass", "smm"]
        case .subcutaneousFat: ["subcutaneous fat", "subcutaneous fat rate"]
        case .visceralFat: ["visceral fat", "visceral fat level", "visceral fat index"]
        case .bmi: ["bmi", "body mass index"]
        case .bmr: ["bmr", "basal metabolic rate", "basal metabolism"]
        case .bodyWater: ["body hydration", "body water", "water", "hydration", "body water rate"]
        case .protein: ["protein", "protein rate"]
        case .boneMass: ["bone mass", "bone", "bone mineral"]
        case .metabolicAge: ["metabolic age", "body age"]
        case .healthScore: ["health score", "body score", "score"]
        case .obesityDegree: ["obesity degree", "obesity"]
        case .mineralSalt: ["mineral salt", "inorganic salt", "minerals"]
        case .bestVisualWeight: ["best visual weight"]
        case .standardWeight: ["standard weight", "ideal weight"]
        case .weightControl: ["weight control"]
        case .fatControl: ["fat control"]
        case .muscleControl: ["muscle control"]
        case .waist: ["waist", "waist circumference"]
        }
    }

    /// Units that may follow this metric's value on screen (lower-cased). Empty = unitless.
    var acceptedUnits: Set<String> {
        switch unit {
        case "kg": ["kg", ""]
        case "%": ["%", ""]
        case "kcal": ["kcal", "cal", ""]
        case "years": ["years", "year", "yrs", "yr", ""]
        case "cm": ["cm", ""]
        default: [""]
        }
    }

    /// Plausible range used to reject OCR misreads.
    var plausibleRange: ClosedRange<Double> {
        switch self {
        case .weight, .bestVisualWeight, .standardWeight: 20...350
        case .muscleMass, .leanBodyMass: 5...200
        case .weightControl, .fatControl, .muscleControl: -150...150
        case .mineralSalt: 0...20
        case .bmi: 8...90
        case .bmr: 500...5_000
        case .metabolicAge: 5...120
        case .healthScore: 0...100
        case .waist: 30...250
        default: 0...100
        }
    }

    /// Formats a value with this metric's unit, e.g. "22.7 %", "82.8 kg", "1,752 kcal".
    public func format(_ value: Double) -> String {
        let digits = (self == .bmr) ? 0...0 : 0...2
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        switch unit {
        case "": return number
        case "%": return "\(number) %"
        default: return "\(number) \(unit)"
        }
    }
}

/// One scale reading: any subset of body metrics, plus the app's status labels ("High", "Healthy", …).
public struct BodyReading: Codable, Equatable, Sendable {
    public var date: Date?
    public var values: [BodyMetric: Double]
    public var statuses: [BodyMetric: String]

    public init(date: Date? = nil, values: [BodyMetric: Double] = [:], statuses: [BodyMetric: String] = [:]) {
        self.date = date
        self.values = values
        self.statuses = statuses
    }

    /// Combines readings from several screenshots of the same measurement. Earlier readings win.
    public func merged(with other: BodyReading) -> BodyReading {
        BodyReading(
            date: date ?? other.date,
            values: values.merging(other.values) { first, _ in first },
            statuses: statuses.merging(other.statuses) { first, _ in first }
        )
    }

    /// Scale metrics that are still missing.
    public var missingScaleMetrics: [BodyMetric] {
        BodyMetric.scaleMetrics.filter { values[$0] == nil }
    }
}
