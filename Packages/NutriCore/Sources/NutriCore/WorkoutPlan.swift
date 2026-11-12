import Foundation

// MARK: - Exercise library

public enum ExerciseCategory: String, Codable, Sendable {
    case strength, core, yoga, cardio, warmUp
}

/// A movement in the technique library, with instructions and its looping demo video.
public struct Exercise: Identifiable, Codable, Hashable, Sendable {
    /// "01"…"20" for strength guides (as numbered in the plan), "Y1"…, "C1"… otherwise.
    public var id: String
    public var name: String
    public var category: ExerciseCategory
    /// Muscles, e.g. "Quads + glutes".
    public var focus: String
    /// e.g. "One dumbbell, total load".
    public var equipment: String
    public var steps: [String]
    public var watchFor: String
    public var adjust: String
    /// Done one side at a time (reps counted per side/arm).
    public var unilateral: Bool
    /// Prescribed in seconds rather than reps.
    public var timed: Bool
    /// Bundled looping video (without extension).
    public var videoName: String
    /// Loaded with dumbbells, so the log asks for a weight.
    public var usesLoad: Bool

    public init(id: String, name: String, category: ExerciseCategory, focus: String, equipment: String,
                steps: [String], watchFor: String, adjust: String, unilateral: Bool = false, timed: Bool = false,
                videoName: String, usesLoad: Bool = true) {
        self.id = id
        self.name = name
        self.category = category
        self.focus = focus
        self.equipment = equipment
        self.steps = steps
        self.watchFor = watchFor
        self.adjust = adjust
        self.unilateral = unilateral
        self.timed = timed
        self.videoName = videoName
        self.usesLoad = usesLoad
    }

    /// "01 · Goblet squat" for numbered strength guides.
    public var numberedName: String {
        id.first?.isNumber == true ? "\(id) · \(name)" : name
    }
}

// MARK: - Prescriptions

/// "2 × 8–12 / side" or "2 × 15–30 s / side".
public struct Prescription: Codable, Hashable, Sendable {
    public var sets: Int
    public var low: Int
    public var high: Int
    public var perSide: Bool
    public var seconds: Bool

    public init(sets: Int, _ low: Int, _ high: Int, perSide: Bool = false, seconds: Bool = false) {
        self.sets = sets
        self.low = low
        self.high = high
        self.perSide = perSide
        self.seconds = seconds
    }

    public var label: String {
        let range = low == high ? "\(low)" : "\(low)–\(high)"
        return "\(sets) × \(range)\(seconds ? " s" : "")\(perSide ? " / side" : "")"
    }

    func withSets(_ n: Int) -> Prescription {
        var copy = self
        copy.sets = n
        return copy
    }
}

public struct PlannedExercise: Codable, Hashable, Identifiable, Sendable {
    public var exerciseID: String
    /// Week-2 "Intro" prescription; nil means the exercise is omitted in the intro.
    public var intro: Prescription?
    /// Week-3+ "Build" prescription.
    public var build: Prescription
    public var restSeconds: ClosedRange<Int>
    public var optional: Bool
    /// First week the optional work may be added.
    public var optionalFromWeek: Int
    /// e.g. "light" for second-exposure leg practice.
    public var note: String?

    public var id: String { exerciseID + (note ?? "") }

    public init(_ exerciseID: String, intro: Prescription?, build: Prescription, rest: ClosedRange<Int>,
                optional: Bool = false, optionalFromWeek: Int = 1, note: String? = nil) {
        self.exerciseID = exerciseID
        self.intro = intro
        self.build = build
        self.restSeconds = rest
        self.optional = optional
        self.optionalFromWeek = optionalFromWeek
        self.note = note
    }

    public var restLabel: String {
        restSeconds.lowerBound == restSeconds.upperBound ? "\(restSeconds.lowerBound) s" : "\(restSeconds.lowerBound)–\(restSeconds.upperBound) s"
    }
}

// MARK: - Days and phases

public enum SessionKind: String, Codable, Sendable {
    case strength, cardioYoga, rest
}

public struct PlanDay: Codable, Hashable, Identifiable, Sendable {
    /// `Calendar` weekday: 1 = Sunday … 7 = Saturday.
    public var weekday: Int
    public var title: String
    public var kind: SessionKind
    public var summary: String
    public var additional: String
    public var exercises: [PlannedExercise]
    public var startingLoads: String
    public var priority: String
    public var duration: String

    public var id: Int { weekday }

    public init(weekday: Int, title: String, kind: SessionKind, summary: String, additional: String,
                exercises: [PlannedExercise] = [], startingLoads: String = "", priority: String = "", duration: String = "") {
        self.weekday = weekday
        self.title = title
        self.kind = kind
        self.summary = summary
        self.additional = additional
        self.exercises = exercises
        self.startingLoads = startingLoads
        self.priority = priority
        self.duration = duration
    }
}

public enum PlanPhase: String, Codable, CaseIterable, Sendable {
    case learn, settle, build, easeOff, rebuild, continueBuild, review

    public static func forWeek(_ week: Int) -> PlanPhase {
        switch week {
        case ...1: .learn
        case 2: .settle
        case 3...5: .build
        case 6: .easeOff
        case 7...8: .rebuild
        case 9...11: .continueBuild
        default: .review
        }
    }

    public var name: String {
        switch self {
        case .learn: "Learn"
        case .settle: "Settle"
        case .build: "Build"
        case .easeOff: "Ease off"
        case .rebuild: "Rebuild"
        case .continueBuild: "Continue"
        case .review: "Review"
        }
    }

    public var workSets: String {
        switch self {
        case .learn: "1 set per exercise; no optional push-ups"
        case .settle: "Intro sets on each strength day"
        case .build: "Build sets if recovered; optional chest sets from week 5"
        case .easeOff: "3 sets become 2, 2 become 1"
        case .rebuild: "Return to Build sets as tolerated"
        case .continueBuild: "Same Build sets; no automatic extra volume"
        case .review: "Repeat the week-6 reductions"
        }
    }

    /// Reps in reserve to finish each set with.
    public var repsInReserve: String {
        switch self {
        case .learn, .settle, .easeOff, .review: "3–4 reps left"
        case .build, .rebuild: "2–3 reps left"
        case .continueBuild: "About 2 reps left"
        }
    }

    public var focus: String {
        switch self {
        case .learn: "Light, repeatable technique."
        case .settle: "Assess next-day recovery."
        case .build: "Add reps before load."
        case .easeOff: "Omit optional push-ups; recover."
        case .rebuild: "Review at week 8."
        case .continueBuild: "Change one difficulty factor."
        case .review: "No maximum-lift testing."
        }
    }
}

// MARK: - Cardio

public struct JogStage: Codable, Hashable, Identifiable, Sendable {
    public var number: Int
    public var jogSeconds: Int
    public var walkSeconds: Int
    public var repeats: Int

    public var id: Int { number }

    public var label: String { "\(jogSeconds) s jog + \(walkSeconds) s walk × \(repeats)" }
}

public enum IntervalKind: String, Codable, Sendable {
    case warmUpWalk, jog, walk, coolDownWalk

    public var displayName: String {
        switch self {
        case .warmUpWalk: "Warm-up walk"
        case .jog: "Gentle jog"
        case .walk: "Walk / march"
        case .coolDownWalk: "Cool-down walk"
        }
    }
}

public struct TimedInterval: Codable, Hashable, Sendable {
    public var kind: IntervalKind
    public var seconds: Int
}

// MARK: - Plan

public struct WorkoutPlan: Codable, Sendable {
    public var title: String
    public var weeks: Int
    public var exercises: [Exercise]
    public var days: [PlanDay]
    public var jogStages: [JogStage]
    /// Yoga sequence with target seconds per pose (per side where applicable).
    public var yoga: [YogaStep]
    public var warmUp: [String]
    public var goalWeightKg: Double?

    public func exercise(_ id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    public func day(weekday: Int) -> PlanDay? {
        days.first { $0.weekday == weekday }
    }
}

public struct YogaStep: Codable, Hashable, Identifiable, Sendable {
    public var exerciseID: String
    public var dose: String
    public var seconds: Int

    public var id: String { exerciseID }
}

// MARK: - Engine

/// Works out what the plan asks for on a given date.
public enum PlanEngine {
    /// Plan week (1-based) for `date`, counting from the week containing `startDate`.
    /// nil before the plan starts. Weeks past the plan's end keep counting (13, 14, …).
    public static func week(for date: Date, startDate: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: date)
        guard day >= start, let days = calendar.dateComponents([.day], from: start, to: day).day else { return nil }
        return days / 7 + 1
    }

    /// The prescription for this week, or nil when the exercise is left out this week.
    public static func prescription(for planned: PlannedExercise, week: Int) -> Prescription? {
        let phase = PlanPhase.forWeek(week)
        if planned.optional && (week < planned.optionalFromWeek || phase == .learn || phase == .easeOff || phase == .review) {
            return nil
        }
        switch phase {
        case .learn:
            return (planned.intro ?? planned.build).withSets(1)
        case .settle:
            return planned.intro
        case .build, .rebuild, .continueBuild:
            return planned.build
        case .easeOff, .review:
            // "3 sets become 2; 2 become 1."
            return planned.build.withSets(max(1, planned.build.sets - 1))
        }
    }

    /// Exercises for a day with this week's prescriptions (omitted ones removed).
    public static func session(for day: PlanDay, week: Int) -> [(planned: PlannedExercise, prescription: Prescription)] {
        day.exercises.compactMap { planned in
            prescription(for: planned, week: week).map { (planned, $0) }
        }
    }

    /// Moderate walking minutes suggested for a day of the week in this plan week.
    public static func cardioMinutes(kind: SessionKind, week: Int) -> Int {
        switch (kind, PlanPhase.forWeek(week)) {
        case (.rest, _): 0
        case (.cardioYoga, .learn), (.cardioYoga, .settle): 20
        case (.strength, .learn), (.strength, .settle): 10
        case (.cardioYoga, .build): week >= 5 ? 40 : 30
        case (.strength, .build): 15
        case (.cardioYoga, .easeOff): 30
        case (.strength, .easeOff): 10
        case (.cardioYoga, .rebuild), (.cardioYoga, .continueBuild): 45
        case (.strength, .rebuild), (.strength, .continueBuild): 15
        case (.cardioYoga, .review): 30
        case (.strength, .review): 15
        }
    }

    /// Weekly moderate cardio target in minutes.
    public static func weeklyCardioTarget(week: Int) -> ClosedRange<Int> {
        switch PlanPhase.forWeek(week) {
        case .learn, .settle: 80...80
        case .build: 120...150
        case .easeOff: 100...120
        case .rebuild, .continueBuild: 150...180
        case .review: 120...150
        }
    }

    /// Walk/jog intervals are optional and start no earlier than week 3, on Fridays.
    public static func jogAllowed(week: Int, weekday: Int) -> Bool {
        week >= 3 && (weekday == 6 || weekday == 4)
    }

    /// Full interval session: 5 min warm-up walk, 6 × (jog + walk), 3 min cool-down (20 minutes).
    public static func intervals(for stage: JogStage) -> [TimedInterval] {
        var result = [TimedInterval(kind: .warmUpWalk, seconds: 300)]
        for _ in 0..<stage.repeats {
            result.append(TimedInterval(kind: .jog, seconds: stage.jogSeconds))
            result.append(TimedInterval(kind: .walk, seconds: stage.walkSeconds))
        }
        result.append(TimedInterval(kind: .coolDownWalk, seconds: 180))
        return result
    }
}

// MARK: - Readiness and progression

/// The plan's "choose the right version today" check.
public enum Readiness: String, Codable, CaseIterable, Sendable {
    case ready, tired, unwell

    public var title: String {
        switch self {
        case .ready: "Ready"
        case .tired: "Tired"
        case .unwell: "Unwell or in pain"
        }
    }

    public var guidance: String {
        switch self {
        case .ready: "Normal energy, manageable soreness and no pain. Do the planned session."
        case .tired: "Use 1–2 sets, lighter loads and 3–4 reps left; skip optional work and shorten cardio."
        case .unwell: "Rest. Stop provoking movements and seek care when symptoms warrant it. Don't exercise to make up for food."
        }
    }

    /// Suggestion from last night's sleep: under 6 hours suggests the tired version.
    public static func suggested(lastNightAsleep: TimeInterval?) -> Readiness {
        guard let asleep = lastNightAsleep, asleep > 0 else { return .ready }
        return asleep < 6 * 3600 ? .tired : .ready
    }
}

/// One logged set.
public struct LoggedSet: Codable, Hashable, Sendable {
    public var reps: Int
    /// kg per dumbbell (or total for one dumbbell); 0 = bodyweight.
    public var loadKg: Double
    /// Reps in reserve the user reported, if any.
    public var repsInReserve: Int?

    public init(reps: Int, loadKg: Double, repsInReserve: Int? = nil) {
        self.reps = reps
        self.loadKg = loadKg
        self.repsInReserve = repsInReserve
    }
}

public enum ProgressionAdvice: Equatable, Sendable {
    /// No history yet.
    case firstTime
    /// Reached the top of the range on every set twice in a row: add the smallest safe load.
    case increaseLoad(from: Double)
    /// Keep the load and add reps toward the top of the range.
    case addReps(load: Double)
    /// Fell below the bottom of the range: stay or go lighter.
    case holdOrReduce(load: Double)

    public var message: String {
        switch self {
        case .firstTime:
            "First time: rehearse unloaded, then pick a load that leaves 3–4 good reps."
        case .increaseLoad(let load):
            "Earned an increase: add the smallest safe load above \(Self.kg(load)) and return to the low end of the range."
        case .addReps(let load):
            "Stay at \(Self.kg(load)) and add reps until every set reaches the top of the range."
        case .holdOrReduce(let load):
            "Some sets fell short of the range at \(Self.kg(load)). Repeat this load or go lighter."
        }
    }

    public static func kg(_ value: Double) -> String {
        value <= 0 ? "bodyweight" : "\(value.formatted(.number.precision(.fractionLength(0...1)))) kg"
    }
}

public enum ProgressionAdvisor {
    /// The plan's rule: "Reach the top of the rep range on every set for two comparable sessions …
    /// then add the smallest available safe load and return to the low end of the range."
    /// `history` holds previous sessions of this exercise, oldest first.
    public static func advice(history: [[LoggedSet]], prescription: Prescription) -> ProgressionAdvice {
        let sessions = history.filter { !$0.isEmpty }
        guard let last = sessions.last else { return .firstTime }
        let load = last.map(\.loadKg).max() ?? 0
        if last.contains(where: { $0.reps < prescription.low }) {
            return .holdOrReduce(load: load)
        }
        let toped: ([LoggedSet]) -> Bool = { sets in
            sets.count >= prescription.sets && sets.allSatisfy { $0.reps >= prescription.high }
        }
        if sessions.count >= 2 {
            let previous = sessions[sessions.count - 2]
            let sameLoad = (previous.map(\.loadKg).max() ?? 0) == load
            if sameLoad && toped(previous) && toped(last) {
                return .increaseLoad(from: load)
            }
        }
        return .addReps(load: load)
    }
}
