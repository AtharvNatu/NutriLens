import Foundation
import NutriCore
import SwiftData

/// A complete export of NutriLens's own data, for moving it between your devices
/// (AirDrop, Files/iCloud Drive) or keeping a copy. Importing merges: newer edits win and
/// deletions made on the other device are applied.
struct BackupFile: Codable {
    struct Meal: Codable {
        var id: UUID
        var date: Date
        var updatedAt: Date
        var name: String
        var foodID: String?
        var grams: Double
        var nutrients: Nutrients
        var mealType: String
        var source: String
        var healthKitID: UUID?
        var photo: Data?
    }

    struct Body: Codable {
        var id: UUID
        var date: Date
        var updatedAt: Date
        var source: String
        var reading: BodyReading
        var note: String
        var healthKitID: UUID?
    }

    struct Workout: Codable {
        var id: UUID
        var start: Date
        var end: Date
        var energyKcal: Double
        var healthKitID: UUID?
        var payload: WorkoutPayload
    }

    struct Food: Codable {
        var id: UUID
        var updatedAt: Date
        var name: String
        var localName: String
        var category: String
        var serving: String
        var servingGrams: Double
        var per100g: Nutrients
        var notes: String
    }

    /// One day of the calendar (see `DayRecord`).
    struct Day: Codable {
        var dayKey: String
        var date: Date
        var updatedAt: Date
        var eatenKcal: Double
        var protein: Double
        var carbohydrates: Double
        var fat: Double
        var mealCount: Int
        var activeEnergy: Double
        var basalEnergy: Double
        var workoutEnergy: Double
        var stepEnergy: Double
        var steps: Double
        var targetKcal: Double
        var budgetKcal: Double
        var workouts: [DayWorkout]
        var asleepSeconds: Double
        var sleepScore: Int?
        var weightKg: Double?
    }

    struct Deletion: Codable {
        var id: UUID
        var type: String
        var deletedAt: Date
    }

    var format = "NutriLens backup"
    var version = 1
    var exportedAt: Date
    /// Which installation wrote the file (automatic folder backups). Absent in older backups.
    var deviceID: String? = nil
    var deviceName: String? = nil
    var meals: [Meal]
    var body: [Body]
    var workouts: [Workout]
    /// Your own foods ("My foods"). Absent in backups from older versions.
    var customFoods: [Food]?
    /// The calendar's daily records. Absent in backups from older versions.
    var days: [Day]?
    var deletions: [Deletion]
    var settings: [String: String]
}

@MainActor
enum BackupService {
    struct ImportReport: Equatable {
        var inserted = 0
        var updated = 0
        var deleted = 0

        var summary: String { "\(inserted) added, \(updated) updated, \(deleted) removed." }
    }

    /// UserDefaults keys copied with the backup.
    static let settingKeys = [
        SettingsKey.dailyCalorieTarget, SettingsKey.proteinTarget, SettingsKey.carbohydrateTarget, SettingsKey.fatTarget,
        SettingsKey.creditSource, SettingsKey.creditFraction, SettingsKey.planStartDate, SettingsKey.goalWeightKg,
        SettingsKey.sleepGoalHours, SettingsKey.stepLengthMeters, SettingsKey.dailyStepGoal,
        SettingsKey.profileSex, SettingsKey.profileAge, SettingsKey.profileHeightCm, SettingsKey.asianCutoffs,
        SettingsKey.dishRecipeDefaults,
    ]

    static func makeBackup(context: ModelContext, includePhotos: Bool = true, defaults: UserDefaults = .standard,
                           exportedAt: Date = .now) throws -> BackupFile {
        // Stable order, so an unchanged store produces an identical file (automatic backup compares them).
        let meals = try context.fetch(FetchDescriptor<MealEntry>()).sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }.map {
            BackupFile.Meal(id: $0.id, date: $0.date, updatedAt: $0.updatedAt, name: $0.name, foodID: $0.foodID, grams: $0.grams,
                            nutrients: $0.nutrients, mealType: $0.mealTypeRaw, source: $0.sourceRaw, healthKitID: $0.healthKitID,
                            photo: includePhotos ? $0.photoData : nil)
        }
        let body = try context.fetch(FetchDescriptor<BodyMeasurement>()).sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }.map {
            BackupFile.Body(id: $0.id, date: $0.date, updatedAt: $0.updatedAt, source: $0.sourceRaw, reading: $0.reading,
                            note: $0.note, healthKitID: $0.healthKitID)
        }
        let workouts = try context.fetch(FetchDescriptor<WorkoutLog>()).sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }.map {
            BackupFile.Workout(id: $0.id, start: $0.start, end: $0.end, energyKcal: $0.energyKcal, healthKitID: $0.healthKitID, payload: $0.payload)
        }
        let customFoods = try context.fetch(FetchDescriptor<CustomFood>()).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            BackupFile.Food(id: $0.id, updatedAt: $0.updatedAt, name: $0.name, localName: $0.localName, category: $0.category,
                            serving: $0.servingDescription, servingGrams: $0.servingGrams, per100g: $0.per100g, notes: $0.notes)
        }
        let days = try context.fetch(FetchDescriptor<DayRecord>()).sorted { $0.dayKey < $1.dayKey }.map {
            BackupFile.Day(dayKey: $0.dayKey, date: $0.date, updatedAt: $0.updatedAt, eatenKcal: $0.eatenKcal, protein: $0.protein,
                           carbohydrates: $0.carbohydrates, fat: $0.fat, mealCount: $0.mealCount, activeEnergy: $0.activeEnergy,
                           basalEnergy: $0.basalEnergy, workoutEnergy: $0.workoutEnergy, stepEnergy: $0.stepEnergy, steps: $0.steps,
                           targetKcal: $0.targetKcal, budgetKcal: $0.budgetKcal, workouts: $0.workouts, asleepSeconds: $0.asleepSeconds,
                           sleepScore: $0.sleepScore, weightKg: $0.weightKg)
        }
        let deletions = try context.fetch(FetchDescriptor<DeletedRecord>()).sorted { $0.id.uuidString < $1.id.uuidString }.map {
            BackupFile.Deletion(id: $0.id, type: $0.recordType, deletedAt: $0.deletedAt)
        }
        return BackupFile(exportedAt: exportedAt, meals: meals, body: body, workouts: workouts, customFoods: customFoods,
                          days: days, deletions: deletions, settings: currentSettings(defaults))
    }

    /// The backed-up settings as strings.
    static func currentSettings(_ defaults: UserDefaults) -> [String: String] {
        var settings: [String: String] = [:]
        for key in settingKeys {
            if let value = defaults.object(forKey: key) { settings[key] = "\(value)" }
        }
        return settings
    }

    static func applySetting(_ key: String, _ value: String, defaults: UserDefaults) {
        guard settingKeys.contains(key) else { return }
        if let number = Double(value) { defaults.set(number, forKey: key) } else { defaults.set(value, forKey: key) }
    }

    static func encode(_ backup: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        // Milliseconds, so an edit and a deletion in the same second still merge in the right order.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        // Accepts milliseconds and older backups' whole seconds.
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) { return date }
            if let date = try? Date(text, strategy: .iso8601) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date \(text)"))
        }
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// Writes a backup to a temporary file for sharing.
    static func writeTemporaryFile(context: ModelContext) throws -> URL {
        let data = try encode(makeBackup(context: context))
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NutriLens-backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// - Parameter replaceNewerDays: whether a newer calendar day in the file replaces this device's copy. Automatic
    ///   folder sync passes false: each device works out recent days from its own Health data, and the file only
    ///   adds days (or values) this device lacks, so two devices never keep overwriting each other.
    static func merge(_ backup: BackupFile, into context: ModelContext, applySettings: Bool = true, defaults: UserDefaults = .standard,
                      replaceNewerDays: Bool = true) throws -> ImportReport {
        var report = ImportReport()
        let localDeletions = try context.fetch(FetchDescriptor<DeletedRecord>())
        let deletedAt = Dictionary(localDeletions.map { ($0.id, $0.deletedAt) }, uniquingKeysWith: max)
        let incomingDeletions = Dictionary(backup.deletions.map { ($0.id, $0.deletedAt) }, uniquingKeysWith: max)

        func stamps(local: [(UUID, Date)], incoming: [(UUID, Date)]) -> [SyncAction] {
            let localStamps = local.map { SyncStamp(id: $0.0, updatedAt: $0.1) }
                + deletedAt.map { SyncStamp(id: $0.key, updatedAt: $0.value, deleted: true) }
            let incomingStamps = incoming.map { SyncStamp(id: $0.0, updatedAt: $0.1) }
                + incomingDeletions.map { SyncStamp(id: $0.key, updatedAt: $0.value, deleted: true) }
            return SyncMerge.actions(local: localStamps, incoming: incomingStamps)
        }

        // Meals.
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        let mealsByID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let incomingMeals = Dictionary(backup.meals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for action in stamps(local: meals.map { ($0.id, $0.updatedAt) }, incoming: backup.meals.map { ($0.id, $0.updatedAt) }) {
            switch action {
            case .delete(let id):
                if let m = mealsByID[id] { context.delete(m); report.deleted += 1 }
            case .insert(let id), .update(let id):
                guard let m = incomingMeals[id] else { continue }
                let entry = mealsByID[id] ?? {
                    let e = MealEntry(date: m.date, name: m.name, foodID: m.foodID, grams: m.grams, nutrients: m.nutrients,
                                      mealType: .snack, source: .search)
                    e.id = id
                    context.insert(e)
                    return e
                }()
                if mealsByID[id] == nil { report.inserted += 1 } else { report.updated += 1 }
                entry.date = m.date
                entry.name = m.name
                entry.foodID = m.foodID
                entry.grams = m.grams
                entry.kilocalories = m.nutrients.kilocalories
                entry.protein = m.nutrients.protein
                entry.carbohydrates = m.nutrients.carbohydrates
                entry.fat = m.nutrients.fat
                entry.mealTypeRaw = m.mealType
                entry.sourceRaw = m.source
                entry.healthKitID = entry.healthKitID ?? m.healthKitID
                if let photo = m.photo { entry.photoData = photo }
                entry.updatedAt = m.updatedAt
            }
        }

        // Body readings.
        let bodies = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let bodiesByID = Dictionary(bodies.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let incomingBodies = Dictionary(backup.body.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for action in stamps(local: bodies.map { ($0.id, $0.updatedAt) }, incoming: backup.body.map { ($0.id, $0.updatedAt) }) {
            switch action {
            case .delete(let id):
                if let b = bodiesByID[id] { context.delete(b); report.deleted += 1 }
            case .insert(let id), .update(let id):
                guard let b = incomingBodies[id] else { continue }
                if let existing = bodiesByID[id] {
                    existing.date = b.date
                    existing.apply(b.reading)
                    existing.note = b.note
                    existing.updatedAt = b.updatedAt
                    report.updated += 1
                } else {
                    let m = BodyMeasurement(id: id, date: b.date, source: BodyReadingSource(rawValue: b.source) ?? .manual, reading: b.reading, note: b.note)
                    m.healthKitID = b.healthKitID
                    m.updatedAt = b.updatedAt
                    context.insert(m)
                    report.inserted += 1
                }
            }
        }

        // Workouts.
        let logs = try context.fetch(FetchDescriptor<WorkoutLog>())
        let logsByID = Dictionary(logs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let incomingLogs = Dictionary(backup.workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for action in stamps(local: logs.map { ($0.id, $0.updatedAt) }, incoming: backup.workouts.map { ($0.id, $0.payload.updatedAt) }) {
            switch action {
            case .delete(let id):
                if let l = logsByID[id] { context.delete(l); report.deleted += 1 }
            case .insert(let id), .update(let id):
                guard let w = incomingLogs[id] else { continue }
                let log = logsByID[id] ?? {
                    let l = WorkoutLog(id: id, kind: .other, title: w.payload.title, start: w.start, end: w.end)
                    context.insert(l)
                    return l
                }()
                if logsByID[id] == nil { report.inserted += 1 } else { report.updated += 1 }
                log.start = w.start
                log.end = w.end
                log.energyKcal = w.energyKcal
                log.healthKitID = log.healthKitID ?? w.healthKitID
                log.apply(w.payload)
            }
        }

        // Your own foods.
        let foods = try context.fetch(FetchDescriptor<CustomFood>())
        let foodsByID = Dictionary(foods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let incomingFoods = Dictionary((backup.customFoods ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for action in stamps(local: foods.map { ($0.id, $0.updatedAt) }, incoming: (backup.customFoods ?? []).map { ($0.id, $0.updatedAt) }) {
            switch action {
            case .delete(let id):
                if let f = foodsByID[id] { context.delete(f); report.deleted += 1 }
            case .insert(let id), .update(let id):
                guard let f = incomingFoods[id] else { continue }
                let draft = CustomFoodDraft(name: f.name, localName: f.localName, servingDescription: f.serving, servingGrams: f.servingGrams,
                                            perServing: f.per100g.scaled(by: f.servingGrams / 100), category: f.category, notes: f.notes)
                if let existing = foodsByID[id] {
                    existing.apply(draft)
                    existing.updatedAt = f.updatedAt
                    report.updated += 1
                } else {
                    let food = CustomFood(id: id, draft: draft)
                    food.updatedAt = f.updatedAt
                    context.insert(food)
                    report.inserted += 1
                }
            }
        }

        // Calendar days: a newer record replaces the local one; otherwise the backup only fills in what this
        // device is missing (say, steps or sleep that Apple Health no longer has for that day).
        let dayRecords = try context.fetch(FetchDescriptor<DayRecord>())
        var daysByKey = Dictionary(dayRecords.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.updatedAt > b.updatedAt ? a : b })
        for d in backup.days ?? [] {
            if let local = daysByKey[d.dayKey] {
                if replaceNewerDays, d.updatedAt > local.updatedAt {
                    apply(d, to: local)
                    report.updated += 1
                } else if fillGaps(of: local, from: d) {
                    report.updated += 1
                }
            } else {
                let record = DayRecord(dayKey: d.dayKey, date: d.date)
                apply(d, to: record)
                context.insert(record)
                daysByKey[d.dayKey] = record
                report.inserted += 1
            }
        }

        // Keep the incoming tombstones so later merges stay consistent.
        for deletion in backup.deletions where deletedAt[deletion.id] == nil {
            let record = DeletedRecord(id: deletion.id, recordType: deletion.type)
            record.deletedAt = deletion.deletedAt
            context.insert(record)
        }

        if applySettings {
            for (key, value) in backup.settings { applySetting(key, value, defaults: defaults) }
        }
        try context.save()
        return report
    }

    private static func apply(_ d: BackupFile.Day, to r: DayRecord) {
        r.date = d.date
        r.updatedAt = d.updatedAt
        r.eatenKcal = d.eatenKcal
        r.protein = d.protein
        r.carbohydrates = d.carbohydrates
        r.fat = d.fat
        r.mealCount = d.mealCount
        r.activeEnergy = d.activeEnergy
        r.basalEnergy = d.basalEnergy
        r.workoutEnergy = d.workoutEnergy
        r.stepEnergy = d.stepEnergy
        r.steps = d.steps
        r.targetKcal = d.targetKcal
        r.budgetKcal = d.budgetKcal
        r.workouts = d.workouts
        r.asleepSeconds = d.asleepSeconds
        r.sleepScore = d.sleepScore
        r.weightKg = d.weightKg
    }

    /// Copies Apple Health values the local record lacks. Returns whether anything changed.
    private static func fillGaps(of r: DayRecord, from d: BackupFile.Day) -> Bool {
        var changed = false
        func fill(_ local: ReferenceWritableKeyPath<DayRecord, Double>, _ incoming: Double) {
            if r[keyPath: local] == 0, incoming > 0 { r[keyPath: local] = incoming; changed = true }
        }
        fill(\.steps, d.steps)
        fill(\.activeEnergy, d.activeEnergy)
        fill(\.basalEnergy, d.basalEnergy)
        fill(\.stepEnergy, d.stepEnergy)
        if r.asleepSeconds == 0, d.asleepSeconds > 0 {
            r.asleepSeconds = d.asleepSeconds
            r.sleepScore = d.sleepScore
            changed = true
        }
        if r.weightKg == nil, let w = d.weightKg { r.weightKg = w; changed = true }
        let healthWorkouts = d.workouts.filter(\.fromHealth)
        if !r.workouts.contains(where: \.fromHealth), !healthWorkouts.isEmpty {
            r.workouts = (r.workouts + healthWorkouts).sorted { $0.start < $1.start }
            r.workoutEnergy = r.workouts.map(\.kilocalories).reduce(0, +)
            changed = true
        }
        return changed
    }
}
