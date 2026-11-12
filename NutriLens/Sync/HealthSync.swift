import Foundation
import NutriCore
import SwiftData

/// Keeps this device's records in step with what NutriLens wrote to Apple Health on your other devices.
///
/// Apple Health syncs through iCloud between your iPhone and iPad (Settings › your name › iCloud › Health),
/// which works with a free Apple ID. Every meal, scale reading and workout NutriLens saves to Health carries
/// its record ID and a JSON payload, so here we insert what's missing, update what's newer and remove
/// records whose Health entries were deleted on the other device.
@MainActor
enum HealthSync {
    struct Report: Equatable {
        var inserted = 0
        var updated = 0
        var removed = 0

        var summary: String {
            inserted + updated + removed == 0 ? "Everything is up to date."
                : "\(inserted) added, \(updated) updated, \(removed) removed from your other devices."
        }
    }

    /// Routine syncs look at the last 90 days, which covers anything changed on your other device.
    static let window: TimeInterval = 90 * 86_400

    /// - Parameter fullHistory: also bring back everything older than the routine window (used once after
    ///   installing, so a deleted and reinstalled app gets all its meals, readings and workouts back).
    ///   Records are only ever *removed* inside the routine window, so a full-history pass can't delete old logs.
    /// - Parameter removals: whether records missing from Health are deleted here. Off with iCloud sync, where a meal
    ///   can arrive from the other device before Health's own sync does, and must not be taken for a deletion.
    /// - Parameter defaults: where `WatchImport` lists Watch sessions whose Health workout hasn't arrived yet; those are
    ///   never taken for deletions.
    static func run(health: any HealthDataProviding, context: ModelContext, now: Date = .now, fullHistory: Bool = false,
                    removals: Bool = true, defaults: UserDefaults = .standard) async throws -> Report {
        guard health.isAvailable else { return Report() }
        let start = now.addingTimeInterval(-window)
        let fetchStart = fullHistory ? Date.distantPast : start
        let end = now.addingTimeInterval(86_400)
        let tombstones = Set(try context.fetch(FetchDescriptor<DeletedRecord>()).map(\.id))
        var report = Report()

        // Meals.
        let mealRecords = try await health.mealRecords(from: fetchStart, to: end)
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        var mealsByID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for record in mealRecords where !tombstones.contains(record.nutriLensID) {
            let payload = PayloadCoder.decode(MealPayload.self, from: record.payload)
            if let local = mealsByID[record.nutriLensID] {
                if let payload, payload.updatedAt > local.updatedAt {
                    local.date = record.date
                    local.name = record.name
                    local.grams = payload.grams
                    local.mealTypeRaw = payload.mealType
                    local.kilocalories = record.nutrients.kilocalories
                    local.protein = record.nutrients.protein
                    local.carbohydrates = record.nutrients.carbohydrates
                    local.fat = record.nutrients.fat
                    local.updatedAt = payload.updatedAt
                    report.updated += 1
                }
                // An edit on the other device replaces the Health sample, so follow it to the new one.
                if local.healthKitID != record.healthKitID { local.healthKitID = record.healthKitID }
            } else {
                let entry = MealEntry(date: record.date, name: record.name, foodID: payload?.foodID, grams: payload?.grams ?? 0,
                                      nutrients: record.nutrients, mealType: MealType(rawValue: payload?.mealType ?? "") ?? .suggested(for: record.date),
                                      source: MealSource(rawValue: payload?.source ?? "") ?? .search)
                entry.id = record.nutriLensID
                entry.healthKitID = record.healthKitID
                entry.updatedAt = payload?.updatedAt ?? record.date
                context.insert(entry)
                mealsByID[entry.id] = entry
                report.inserted += 1
            }
        }
        // Only trust absence when Health returned something (reading works and data has synced).
        if removals, !mealRecords.isEmpty {
            let present = Set(mealRecords.map(\.nutriLensID))
            for meal in meals where meal.healthKitID != nil && meal.date >= start && meal.date < end && !present.contains(meal.id) {
                context.delete(meal)
                report.removed += 1
            }
        }

        // Scale readings.
        let bodySamples = try await health.bodySamples(from: fetchStart, to: end).filter { $0.nutriLensID != nil }
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let measurementsByID = Dictionary(measurements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for sample in bodySamples {
            guard let id = sample.nutriLensID, !tombstones.contains(id),
                  let payload = PayloadCoder.decode(BodyPayload.self, from: sample.payload) else { continue }
            if let local = measurementsByID[id] {
                guard payload.updatedAt > local.updatedAt else { continue }
                local.apply(payload.reading)
                local.note = payload.note
                local.updatedAt = payload.updatedAt
                report.updated += 1
            } else {
                let m = BodyMeasurement(id: id, date: sample.date, source: BodyReadingSource(rawValue: payload.source) ?? .manual,
                                        reading: payload.reading, note: payload.note)
                m.healthKitID = sample.id
                m.updatedAt = payload.updatedAt
                context.insert(m)
                report.inserted += 1
            }
        }
        if removals, !bodySamples.isEmpty {
            let present = Set(bodySamples.compactMap(\.nutriLensID))
            for m in measurements where m.healthKitID != nil && m.date >= start && m.date < end && !present.contains(m.id) {
                context.delete(m)
                report.removed += 1
            }
        }

        // Workout logs.
        let workouts = try await health.nutriLensWorkouts(from: fetchStart, to: end)
        let logs = try context.fetch(FetchDescriptor<WorkoutLog>())
        let logsByID = Dictionary(logs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for workout in workouts {
            guard let id = workout.nutriLensID, !tombstones.contains(id),
                  let payload = PayloadCoder.decode(WorkoutPayload.self, from: workout.payload) else { continue }
            if let local = logsByID[id] {
                guard payload.updatedAt > local.updatedAt else { continue }
                local.apply(payload)
                report.updated += 1
            } else {
                let log = WorkoutLog(id: id, kind: WorkoutLogKind(rawValue: payload.kind) ?? .other, title: payload.title,
                                     start: workout.start, end: workout.end)
                log.apply(payload)
                log.energyKcal = workout.energyBurned ?? 0
                log.healthKitID = workout.id
                context.insert(log)
                report.inserted += 1
            }
        }
        let presentWorkouts = Set(workouts.compactMap(\.nutriLensID))
        WatchImport.healthHas(presentWorkouts, defaults: defaults)
        if removals, !workouts.isEmpty {
            // A session the Watch sent here may arrive before Health has synced its workout to this iPhone.
            let awaiting = WatchImport.awaitingHealth(defaults: defaults, now: now)
            for log in logs where log.healthKitID != nil && log.start >= start && log.start < end
                && !presentWorkouts.contains(log.id) && !awaiting.contains(log.id) {
                context.delete(log)
                report.removed += 1
            }
        }

        try context.save()
        return report
    }
}

/// Records a deletion so it can travel to other devices in a backup file.
@MainActor
enum Tombstone {
    static func record(_ id: UUID, type: String, in context: ModelContext) {
        context.insert(DeletedRecord(id: id, recordType: type))
    }
}
