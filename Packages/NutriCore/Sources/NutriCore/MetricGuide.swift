import Foundation

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female, notSet
}

/// What range lookups need to know about you. Any field may be unknown.
public struct BodyProfile: Equatable, Sendable {
    public var sex: Sex
    public var age: Int?
    public var heightCm: Double?
    /// Use the Asian-Indian BMI and waist cut-offs (consensus guidelines for India) instead of WHO's.
    public var asianCutoffs: Bool

    public init(sex: Sex = .notSet, age: Int? = nil, heightCm: Double? = nil, asianCutoffs: Bool = true) {
        self.sex = sex
        self.age = age
        self.heightCm = heightCm
        self.asianCutoffs = asianCutoffs
    }
}

/// One labelled range of a metric, e.g. "Healthy 18.0–22.9".
public struct MetricBand: Equatable, Sendable, Identifiable {
    public enum Level: String, Sendable {
        case low, healthy, high, veryHigh
    }

    public var label: String
    /// Inclusive lower bound (nil = no lower limit).
    public var lower: Double?
    /// Exclusive upper bound (nil = no upper limit).
    public var upper: Double?
    public var level: Level

    public var id: String { label }

    public init(_ label: String, _ lower: Double?, _ upper: Double?, _ level: Level) {
        self.label = label
        self.lower = lower
        self.upper = upper
        self.level = level
    }

    public func contains(_ value: Double) -> Bool {
        (lower.map { value >= $0 } ?? true) && (upper.map { value < $0 } ?? true)
    }

    /// "18.0–22.9 kg", "Under 18.0", "25.0 % or more", "−10.0 to 9.9 %". `unit` goes after each number group.
    public func rangeText(decimals: Int = 1, unit: String = "") -> String {
        func f(_ v: Double) -> String {
            v.formatted(.number.precision(.fractionLength(decimals))).replacingOccurrences(of: "-", with: "−")
        }
        let u = unit.isEmpty ? "" : " " + unit
        switch (lower, upper) {
        case let (l?, h?):
            let top = h - (decimals > 0 ? 0.1 : 1)
            return l < 0 ? "\(f(l)) to \(f(top))\(u)" : "\(f(l))–\(f(top))\(u)"
        case let (nil, h?): return "Under \(f(h))\(u)"
        case let (l?, nil): return "\(f(l))\(u) or more"
        default: return "Any"
        }
    }
}

/// Explanation and reference ranges for one body metric.
public struct MetricGuide: Sendable {
    public var metric: BodyMetric
    /// What the number is.
    public var about: String
    /// Recognised reference bands for this person, lowest first. Empty when there's no accepted range.
    public var bands: [MetricBand]
    /// Where the bands come from, or why there are none.
    public var rangeNote: String
    /// Extra context computed for this person (e.g. a BMR estimate, a healthy weight range).
    public var personalNote: String?

    public func band(for value: Double) -> MetricBand? {
        bands.first { $0.contains(value) }
    }
}

/// Reference information for the smart-scale metrics.
///
/// Only widely used references are given as ranges: WHO and Indian consensus BMI and waist cut-offs,
/// body-fat ranges by age and sex (Gallagher et al., 2000), typical body-water ranges and conventions
/// for scale ratings. Many scale values (muscle %, protein, bone mass, health score…) are the scale
/// maker's own estimates with no agreed healthy range; for those the scale's own label is shown.
public enum MetricGuides {
    public static func guide(for metric: BodyMetric, profile: BodyProfile, weightKg: Double? = nil) -> MetricGuide {
        let noRange = "There's no agreed medical range for this scale estimate; the label (High, Low…) is your scale app's own rating. Watch the trend rather than one reading."
        switch metric {
        case .weight:
            var bands: [MetricBand] = []
            var note = "Set your height (Settings › Profile, or in Apple Health) to see a healthy weight range."
            if let h = profile.heightCm, h > 0 {
                let m2 = pow(h / 100, 2)
                let cut = bmiCutoffs(profile)
                bands = [
                    MetricBand("Underweight", nil, cut.healthy * m2, .low),
                    MetricBand("Healthy", cut.healthy * m2, cut.overweight * m2, .healthy),
                    MetricBand("Overweight", cut.overweight * m2, cut.obese * m2, .high),
                    MetricBand("Obese", cut.obese * m2, nil, .veryHigh),
                ]
                note = "Weight ranges from the \(profile.asianCutoffs ? "Asian-Indian" : "WHO") BMI cut-offs at your height (\(Int(h)) cm). Weight alone can't tell fat from muscle: compare weekly averages, waist and strength."
            }
            return MetricGuide(metric: metric, about: "Your total body weight. It moves by 0.5–2 kg through a day with food, water and salt, so the weekly average is the useful number.",
                               bands: bands, rangeNote: note)

        case .bmi:
            let cut = bmiCutoffs(profile)
            let bands = [
                MetricBand("Underweight", nil, cut.healthy, .low),
                MetricBand("Healthy", cut.healthy, cut.overweight, .healthy),
                MetricBand("Overweight", cut.overweight, cut.obese, .high),
                MetricBand("Obese", cut.obese, nil, .veryHigh),
            ]
            var personal: String?
            if let h = profile.heightCm, h > 0, let w = weightKg {
                personal = "Calculated from your weight and height: \((w / pow(h / 100, 2)).formatted(.number.precision(.fractionLength(1)))). If this differs from the scale's BMI, check the height in the scale app's profile."
            }
            return MetricGuide(metric: metric, about: "Body mass index: weight (kg) ÷ height (m)². A quick screen for weight relative to height; it can't distinguish fat from muscle.",
                               bands: bands,
                               rangeNote: profile.asianCutoffs
                                   ? "Asian-Indian cut-offs (Indian consensus guidelines, 2009): risk starts at a lower BMI for South Asians than WHO's general 25/30. Switch to WHO cut-offs in Settings › Profile."
                                   : "WHO cut-offs. For South Asians, Indian guidelines use 18.0 / 23 / 25 instead; turn them on in Settings › Profile.",
                               personalNote: personal)

        case .bodyFat:
            let note = "Healthy ranges by age and sex from Gallagher et al. (2000), used by most body-composition scales. Home scales estimate body fat from electrical impedance, so readings shift with hydration; use the trend."
            let about = "The share of your weight that is fat. Bioimpedance scales estimate it; it changes with water, meals and time of day."
            switch profile.sex {
            case .notSet:
                return MetricGuide(metric: metric, about: about, bands: [],
                                   rangeNote: "Ranges depend on sex and age. Set them in Settings › Profile, or allow NutriLens to read them from Apple Health.\n\nFor ages 20–39: men 8–19.9 % healthy, 20–24.9 % high, 25 %+ very high; women 21–32.9 % healthy, 33–38.9 % high, 39 %+ very high.")
            case .male, .female:
                let b = bodyFatBounds(sex: profile.sex, age: profile.age ?? 30)
                return MetricGuide(metric: metric, about: about, bands: [
                    MetricBand("Low", nil, b.0, .low),
                    MetricBand("Healthy", b.0, b.1, .healthy),
                    MetricBand("High", b.1, b.2, .high),
                    MetricBand("Very high", b.2, nil, .veryHigh),
                ], rangeNote: note + (profile.age == nil ? " Showing ages 20–39; set your age for an exact range." : ""))
            }

        case .bodyWater:
            let about = "Total body water as a share of weight. Muscle holds a lot of water and fat little, so it tends to rise as body fat falls."
            let (lo, hi): (Double, Double) = profile.sex == .female ? (45, 60) : (50, 65)
            return MetricGuide(metric: metric, about: about, bands: [
                MetricBand("Low", nil, lo, .low),
                MetricBand("Typical", lo, hi, .healthy),
                MetricBand("High", hi, nil, .high),
            ], rangeNote: "Typical ranges used by body-composition scales: men about 50–65 %, women about 45–60 %\(profile.sex == .notSet ? " (showing the men's range; set your sex in Settings › Profile)" : ""). Strongly affected by recent drinking, exercise and meals.")

        case .visceralFat:
            return MetricGuide(metric: metric, about: "An index of fat around the abdominal organs. Scales report it as a rating, not a measured percentage, even when the app shows \"%\".",
                               bands: [
                                   MetricBand("Healthy", nil, 13, .healthy),
                                   MetricBand("High", 13, nil, .high),
                               ],
                               rangeNote: "Many scales (e.g. Tanita) use a 1–59 rating where 1–12 is considered healthy and 13+ high. Your scale's method isn't published, so treat this as a rough guide. Waist measurement is a more reliable check.")

        case .waist:
            let female = profile.sex == .female
            let bands: [MetricBand]
            let note: String
            if profile.asianCutoffs {
                let cut: Double = female ? 80 : 90
                bands = [MetricBand("Healthy", nil, cut, .healthy), MetricBand("Increased risk", cut, nil, .high)]
                note = "South Asian cut-offs (International Diabetes Federation): \(female ? "women" : "men") \(Int(cut)) cm or more means increased risk."
            } else {
                let (a, b): (Double, Double) = female ? (80, 88) : (94, 102)
                bands = [MetricBand("Healthy", nil, a, .healthy), MetricBand("Increased risk", a, b, .high), MetricBand("High risk", b, nil, .veryHigh)]
                note = "WHO cut-offs for \(female ? "women" : "men")."
            }
            var personal: String?
            if let h = profile.heightCm, h > 0 {
                personal = "Waist-to-height guide: keep your waist under half your height, \(Int(h / 2)) cm."
            }
            return MetricGuide(metric: metric, about: "Waist circumference, measured with a tape at the navel after a normal breath out. Your plan's weekly measure of belly fat.",
                               bands: bands, rangeNote: note + (profile.sex == .notSet ? " Showing the men's cut-offs; set your sex in Settings › Profile." : ""),
                               personalNote: personal)

        case .bmr:
            var personal: String?
            if let h = profile.heightCm, let age = profile.age, let w = weightKg, profile.sex != .notSet {
                let estimate = 10 * w + 6.25 * h - 5 * Double(age) + (profile.sex == .male ? 5 : -161)
                personal = "Mifflin–St Jeor estimate for you: about \(Int(estimate.rounded())) kcal."
            }
            return MetricGuide(metric: metric, about: "Basal metabolic rate: an estimate of the energy you'd burn at complete rest in a day. It's not a calorie allowance: your daily needs are higher.",
                               bands: [], rangeNote: "There's no healthy or unhealthy BMR; it mainly reflects body size and lean mass. Your plan advises setting calories from your weight trend instead (Body › Calories from your trend).",
                               personalNote: personal)

        case .metabolicAge:
            var bands: [MetricBand] = []
            var note = "Set your age in Settings › Profile (or Apple Health) to compare."
            if let age = profile.age {
                bands = [MetricBand("At or below your age", nil, Double(age) + 1, .healthy), MetricBand("Above your age", Double(age) + 1, nil, .high)]
                note = "Scale apps compare it with your real age (\(age)): at or below is the usual target. It's a proprietary estimate based on BMR, not a medical measure."
            }
            return MetricGuide(metric: metric, about: "The age whose typical BMR matches yours, as estimated by the scale maker.", bands: bands, rangeNote: note)

        case .obesityDegree:
            return MetricGuide(metric: metric, about: "How far your weight is from the scale app's standard weight: (weight − standard weight) ÷ standard weight × 100.",
                               bands: [
                                   MetricBand("Underweight", nil, -10, .low),
                                   MetricBand("Normal", -10, 10, .healthy),
                                   MetricBand("Overweight", 10, 20, .high),
                                   MetricBand("Obese", 20, nil, .veryHigh),
                               ],
                               rangeNote: "The usual convention for this measure: within ±10 % normal, +10 to +20 % overweight, over +20 % obese. It depends entirely on the app's standard weight.")

        case .muscleMass:
            return MetricGuide(metric: metric, about: "Estimated weight of all muscle, including the water in it (and, for many scales, heart and gut muscle). Not the same as skeletal muscle.",
                               bands: [], rangeNote: noRange + " During fat loss, holding this steady while weight falls is a good sign.")
        case .muscleMassPercent:
            return MetricGuide(metric: metric, about: "Muscle mass as a share of your weight. It rises when you lose fat even if muscle doesn't change.", bands: [], rangeNote: noRange)
        case .leanBodyMass:
            var personal: String?
            if let w = weightKg { personal = "Fat-free mass is everything that isn't fat: muscle, bone, organs and water. With your weight of \(w.formatted(.number.precision(.fractionLength(1)))) kg, the rest is fat mass." }
            return MetricGuide(metric: metric, about: "Weight minus fat mass. Keeping it steady while weight drops means the loss is mostly fat.", bands: [], rangeNote: noRange, personalNote: personal)
        case .skeletalMuscle:
            return MetricGuide(metric: metric, about: "The scale's estimate of the muscle attached to your skeleton (the kind training builds), as a share of weight. Scale makers define it differently.", bands: [], rangeNote: noRange)
        case .subcutaneousFat:
            return MetricGuide(metric: metric, about: "The scale's estimate of fat just under the skin, as a share of weight. It falls along with overall body fat.", bands: [], rangeNote: noRange)
        case .protein:
            return MetricGuide(metric: metric, about: "The scale's estimate of protein (mostly in muscle) as a share of weight. It isn't your dietary protein.", bands: [], rangeNote: noRange)
        case .boneMass:
            return MetricGuide(metric: metric, about: "An estimate of bone mineral, worked out from your fat-free mass. Bioimpedance can't measure bone; it barely changes and isn't a bone-health test (that needs a DEXA scan).", bands: [], rangeNote: noRange)
        case .mineralSalt:
            return MetricGuide(metric: metric, about: "The scale's estimate of minerals in the body (largely bone mineral), in kg.", bands: [], rangeNote: noRange)
        case .healthScore:
            return MetricGuide(metric: metric, about: "The scale app's own 0–100 summary of your reading. Its formula isn't published.", bands: [], rangeNote: noRange)
        case .bestVisualWeight:
            return MetricGuide(metric: metric, about: "A target weight the scale app suggests for appearance, based on its own ideal body fat.", bands: [],
                               rangeNote: "An app suggestion, not a medical target. Your plan's goal and the weekly trend matter more.",
                               personalNote: weightKg.map { _ in "Compare with your goal weight in Settings." })
        case .standardWeight:
            return MetricGuide(metric: metric, about: "The scale app's reference weight for your height, used for obesity degree and the control values.", bands: [],
                               rangeNote: "An app reference, not a medical target. A healthy weight is a range (see Weight).")
        case .weightControl:
            return MetricGuide(metric: metric, about: "How much weight the app suggests changing to reach its standard (negative = lose).", bands: [], rangeNote: "An app suggestion based on its standard weight. Your plan aims for 0.2–0.4 kg a week.")
        case .fatControl:
            return MetricGuide(metric: metric, about: "How much fat the app suggests changing to reach its ideal body fat (negative = lose).", bands: [], rangeNote: "An app suggestion. Fat loss shows best in the weekly weight average and your waist.")
        case .muscleControl:
            return MetricGuide(metric: metric, about: "How much muscle the app suggests adding to reach its standard.", bands: [], rangeNote: "An app suggestion. Strength gains in your training log are the better measure.")
        }
    }

    /// BMI cut-offs: healthy from, overweight from, obese from.
    static func bmiCutoffs(_ profile: BodyProfile) -> (healthy: Double, overweight: Double, obese: Double) {
        profile.asianCutoffs ? (18.0, 23.0, 25.0) : (18.5, 25.0, 30.0)
    }

    /// Body-fat bounds (healthy from, high from, very high from) by sex and age (Gallagher et al., 2000).
    static func bodyFatBounds(sex: Sex, age: Int) -> (Double, Double, Double) {
        let group = age < 40 ? 0 : (age < 60 ? 1 : 2)
        if sex == .female {
            return [(21, 33, 39), (23, 34, 40), (24, 36, 42)][group]
        }
        return [(8, 20, 25), (11, 22, 28), (13, 25, 30)][group]
    }
}
