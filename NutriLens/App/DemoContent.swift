import NutriCore
import SwiftData
import UIKit

/// Sample meals and a drawn sample photo for previews, tests and Simulator screenshots.
enum DemoContent {
    @MainActor
    static func seed(into context: ModelContext, database: NutritionDatabase, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        // (days ago, hour, minute, food id, servings, meal)
        let plan: [(Int, Int, Int, String, Double, MealType)] = [
            (0, 8, 10, "kande_pohe", 1, .breakfast),
            (0, 8, 15, "chai", 1, .breakfast),
            (0, 13, 5, "poli", 2, .lunch),
            (0, 13, 6, "matki_usal", 1, .lunch),
            (0, 13, 7, "varan_bhaat", 1, .lunch),
            (0, 16, 30, "moong_sprouts", 1, .snack),
            (1, 7, 50, "egg_bhurji", 1, .breakfast),
            (1, 7, 55, "poli", 1, .breakfast),
            (1, 12, 40, "dal_tadka", 1, .lunch),
            (1, 12, 41, "jeera_rice", 1, .lunch),
            (1, 19, 45, "chicken_rassa", 1, .dinner),
            (1, 19, 46, "jowar_bhakri", 2, .dinner),
            (2, 8, 20, "thalipeeth", 2, .breakfast),
            (2, 8, 21, "curd", 1, .breakfast),
            (2, 13, 15, "misal_pav", 1, .lunch),
            (2, 20, 0, "paneer_bhurji", 1, .dinner),
            (2, 20, 1, "poli", 2, .dinner),
            (3, 8, 0, "idli", 1.5, .breakfast),
            (3, 8, 1, "sambar", 1, .breakfast),
            (3, 13, 0, "varan_bhaat", 1, .lunch),
            (3, 13, 1, "bhendi_bhaji", 1, .lunch),
            (3, 20, 15, "palak_paneer", 1, .dinner),
            (3, 20, 16, "phulka", 3, .dinner),
            (4, 7, 45, "upma", 1, .breakfast),
            (4, 12, 30, "chole", 1, .lunch),
            (4, 12, 31, "poli", 2, .lunch),
            (4, 16, 0, "peanuts", 1, .snack),
            (4, 20, 10, "surmai_fry", 1, .dinner),
            (4, 20, 11, "white_rice", 1, .dinner),
            (5, 9, 0, "sabudana_khichdi", 1, .breakfast),
            (5, 14, 0, "vada_pav", 2, .lunch),
            (5, 19, 30, "pav_bhaji", 1, .dinner),
            (6, 8, 0, "dosa", 2, .breakfast),
            (6, 13, 20, "chicken_curry", 1, .lunch),
            (6, 13, 21, "white_rice", 1, .lunch),
            (6, 21, 0, "shrikhand", 1, .snack),
        ]
        for (daysAgo, hour, minute, id, servings, meal) in plan {
            guard let food = database.food(id: id),
                  let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  date <= now
            else { continue }
            let portion = Portion.servings(servings)
            context.insert(MealEntry(
                date: date,
                name: food.name,
                foodID: food.id,
                grams: portion.grams(for: food),
                nutrients: food.nutrients(for: portion),
                mealType: meal,
                source: .search
            ))
        }
        seedTraining(into: context, now: now, calendar: calendar)
        seedBody(into: context, now: now, calendar: calendar)
        try? context.save()
    }

    /// Made-up strength sessions for the last two weeks, following the plan's weekdays.
    @MainActor
    static func seedTraining(into context: ModelContext, now: Date, calendar: Calendar) {
        let plan = PlanContent.homeStrength12Week
        let today = calendar.startOfDay(for: now)
        for daysAgo in 1...13 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let planDay = plan.day(weekday: calendar.component(.weekday, from: day)),
                  planDay.kind == .strength,
                  let start = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day)
            else { continue }
            let week = daysAgo > 6 ? 3 : 4
            let log = WorkoutLog(kind: .strength, title: planDay.title, start: start, end: start.addingTimeInterval(52 * 60))
            log.planWeek = week
            log.planWeekday = planDay.weekday
            log.energyRating = 4
            log.energyKcal = 210
            log.exercises = PlanEngine.session(for: planDay, week: week).map { item in
                let ex = plan.exercise(item.planned.exerciseID)
                let load = (ex?.usesLoad ?? false) ? (item.prescription.high >= 15 ? 5.0 : 7.5) : 0
                let reps = item.prescription.seconds ? item.prescription.low + 5 : item.prescription.high - (daysAgo > 6 ? 2 : 0)
                return LoggedExercise(exerciseID: item.planned.exerciseID,
                                      sets: (0..<item.prescription.sets).map { _ in LoggedSet(reps: reps, loadKg: load, repsInReserve: 2) })
            }
            context.insert(log)
        }
    }

    /// Made-up smart-scale readings every few days (values are illustrative only).
    @MainActor
    static func seedBody(into context: ModelContext, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        for (i, daysAgo) in stride(from: 49, through: 1, by: -7).enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let date = calendar.date(bySettingHour: 7, minute: 5, second: 0, of: day) else { continue }
            let w = 86.2 - Double(i) * 0.25
            let fat = 25.4 - Double(i) * 0.2
            let values: [BodyMetric: Double] = [
                .weight: w, .bodyFat: fat, .muscleMass: (w * (1 - fat / 100) * 0.94 * 10).rounded() / 10,
                .muscleMassPercent: 70.4 + Double(i) * 0.18, .leanBodyMass: (w * (1 - fat / 100) * 10).rounded() / 10,
                .skeletalMuscle: 47.6 + Double(i) * 0.1, .subcutaneousFat: 22.6 - Double(i) * 0.18, .visceralFat: 9 - Double(i / 3),
                .bmi: (w / (1.83 * 1.83) * 10).rounded() / 10, .bmr: 1_790 - Double(i) * 3, .bodyWater: 54.1 + Double(i) * 0.12,
                .protein: 16.8 + Double(i) * 0.05, .boneMass: 3.1, .metabolicAge: 28 - Double(i / 2), .healthScore: 72 + Double(i),
                .obesityDegree: 18.5 - Double(i) * 0.4, .mineralSalt: 1.1, .bestVisualWeight: 77, .standardWeight: 74,
                .weightControl: -(w - 74).rounded(), .fatControl: -9.5 + Double(i) * 0.3, .muscleControl: 1.8,
            ]
            let statuses: [BodyMetric: String] = [.bodyFat: "High", .bmi: "High", .bodyWater: "Healthy", .protein: "Healthy", .muscleMassPercent: "Low"]
            let m = BodyMeasurement(date: date, source: .screenshot, reading: BodyReading(date: date, values: values, statuses: statuses))
            m.values[BodyMetric.waist.rawValue] = 94 - Double(i) * 0.5
            context.insert(m)
        }
    }

    /// A simple drawn "photo" of misal pav (a bowl of misal with farsan, two pav, onion and lemon),
    /// used in demo mode. No real photo is bundled.
    static func samplePhoto(size: CGFloat = 900) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            let cg = ctx.cgContext
            func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
            func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ c: UIColor) {
                c.setFill()
                cg.fillEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
            }
            // Steel thali on a wooden table.
            color(0.55, 0.38, 0.24).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            ellipse(size * 0.5, size * 0.5, size * 0.47, size * 0.47, color(0.82, 0.84, 0.86))
            ellipse(size * 0.5, size * 0.5, size * 0.43, size * 0.43, color(0.9, 0.91, 0.92))
            // Bowl of misal: orange-red tarri, matki, then farsan, onion and coriander on top.
            let bx = size * 0.4, by = size * 0.42
            ellipse(bx, by, size * 0.25, size * 0.25, color(0.75, 0.76, 0.78))
            ellipse(bx, by, size * 0.22, size * 0.22, color(0.78, 0.26, 0.08))
            var generator = SeededGenerator(seed: 42)
            func scatter(_ count: Int, radius: CGFloat, dot: CGFloat, _ c: UIColor) {
                for _ in 0..<count {
                    let angle = Double.random(in: 0..<(2 * .pi), using: &generator)
                    let r = radius * sqrt(Double.random(in: 0...1, using: &generator))
                    ellipse(bx + cos(angle) * r, by + sin(angle) * r, dot, dot * 0.7, c)
                }
            }
            scatter(40, radius: size * 0.19, dot: size * 0.012, color(0.55, 0.38, 0.12))   // matki
            scatter(160, radius: size * 0.17, dot: size * 0.009, color(0.95, 0.72, 0.22))  // farsan
            scatter(30, radius: size * 0.15, dot: size * 0.011, color(0.96, 0.92, 0.95))   // onion
            scatter(25, radius: size * 0.15, dot: size * 0.008, color(0.2, 0.55, 0.2))     // coriander
            // Two pav.
            for (dx, dy) in [(0.72, 0.62), (0.8, 0.45)] {
                let rect = CGRect(x: size * dx - size * 0.1, y: size * dy - size * 0.075, width: size * 0.2, height: size * 0.15)
                color(0.8, 0.52, 0.22).setFill()
                cg.addPath(CGPath(roundedRect: rect, cornerWidth: size * 0.06, cornerHeight: size * 0.06, transform: nil))
                cg.fillPath()
                color(0.93, 0.74, 0.45).setFill()
                cg.addPath(CGPath(roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02), cornerWidth: size * 0.05, cornerHeight: size * 0.05, transform: nil))
                cg.fillPath()
            }
            // Lemon wedge and chopped onion.
            ellipse(size * 0.3, size * 0.78, size * 0.06, size * 0.04, color(0.95, 0.88, 0.3))
            ellipse(size * 0.5, size * 0.8, size * 0.07, size * 0.045, color(0.92, 0.85, 0.9))
        }
    }
}

/// Deterministic random numbers so the demo image is identical every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
