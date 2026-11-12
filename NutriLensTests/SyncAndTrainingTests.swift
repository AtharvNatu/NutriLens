import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

/// Keeps every test store's container alive for the whole test run: a ModelContext whose
/// container has been released traps.
@MainActor
private var liveContainers: [ModelContainer] = []

@MainActor
private func freshContext() -> ModelContext {
    let container = AppEnvironment.makeContainer(inMemory: true)
    liveContainers.append(container)
    return container.mainContext
}

@Suite("Sync through Apple Health")
@MainActor
struct HealthSyncTests {
    let pizza = NutritionDatabase.bundled.food(id: "pizza")!

    func meal(on date: Date) -> MealEntry {
        MealEntry(date: date, name: pizza.name, foodID: pizza.id, grams: 214, nutrients: pizza.nutrients(for: .servings(2)), mealType: .dinner, source: .photo)
    }

    @Test func mealFromOtherDeviceIsImportedWithItsPayload() async throws {
        let health = MockHealthService()
        // "iPhone": a meal saved to Health with its payload.
        let phone = freshContext()
        let entry = meal(on: .now.addingTimeInterval(-3_600))
        phone.insert(entry)
        entry.healthKitID = try await health.saveMeal(entry.healthSample)

        // "iPad": empty store, same Health data.
        let pad = freshContext()
        let report = try await HealthSync.run(health: health, context: pad)
        #expect(report.inserted == 1)
        let imported = try #require(try pad.fetch(FetchDescriptor<MealEntry>()).first)
        #expect(imported.id == entry.id)
        #expect(imported.mealType == .dinner)
        #expect(imported.grams == 214)
        #expect(abs(imported.kilocalories - entry.kilocalories) < 0.001)

        // Running again changes nothing.
        #expect(try await HealthSync.run(health: health, context: pad) == HealthSync.Report())
    }

    @Test func deletionOnOtherDeviceRemovesTheLocalCopy() async throws {
        let health = MockHealthService()
        let pad = freshContext()
        let keep = meal(on: .now.addingTimeInterval(-7_200))
        let gone = meal(on: .now.addingTimeInterval(-3_600))
        for m in [keep, gone] {
            pad.insert(m)
            m.healthKitID = try await health.saveMeal(m.healthSample)
        }
        // The phone deletes one meal from Health.
        try await health.deleteMeal(id: try #require(gone.healthKitID))
        let report = try await HealthSync.run(health: health, context: pad)
        #expect(report.removed == 1)
        #expect(try pad.fetch(FetchDescriptor<MealEntry>()).map(\.id) == [keep.id])
    }

    @Test func nothingIsDeletedWhenHealthReturnsNoRecords() async throws {
        // E.g. read permission not granted on this device: absence must not wipe local data.
        let pad = freshContext()
        let local = meal(on: .now)
        local.healthKitID = UUID()
        pad.insert(local)
        let report = try await HealthSync.run(health: MockHealthService(), context: pad)
        #expect(report.removed == 0)
        #expect(try pad.fetch(FetchDescriptor<MealEntry>()).count == 1)
    }

    @Test func scaleReadingTravelsWithAllValues() async throws {
        let health = MockHealthService()
        let reading = BodyReading(date: .now, values: [.weight: 82.8, .bodyFat: 22.7, .visceralFat: 7, .metabolicAge: 23, .waist: 92],
                                  statuses: [.bodyFat: "High"])
        let phone = freshContext()
        let m = BodyMeasurement(date: .now, source: .screenshot, reading: reading)
        phone.insert(m)
        m.healthKitID = try await health.saveBody(reading, date: m.date, nutriLensID: m.id, payload: PayloadCoder.encode(m.payload))
        // Health itself only stores the five supported values.
        let stored = try #require(health.snapshot.body.first)
        #expect(Set(stored.values.keys) == [.weight, .bodyFat, .waist])

        let pad = freshContext()
        #expect(try await HealthSync.run(health: health, context: pad).inserted == 1)
        let copy = try #require(try pad.fetch(FetchDescriptor<BodyMeasurement>()).first)
        #expect(copy.value(.visceralFat) == 7)
        #expect(copy.value(.metabolicAge) == 23)
        #expect(copy.statuses["bodyFat"] == "High")
        #expect(copy.weightKg == 82.8)
    }

    @Test func workoutLogTravelsWithItsSets() async throws {
        let health = MockHealthService()
        let log = WorkoutLog(kind: .strength, title: "Legs + core", start: .now.addingTimeInterval(-3_600), end: .now)
        log.exercises = [LoggedExercise(exerciseID: "01", sets: [LoggedSet(reps: 12, loadKg: 5, repsInReserve: 3)])]
        log.planWeek = 4
        log.energyKcal = 200
        log.healthKitID = try await health.saveWorkout(kind: .strength, start: log.start, end: log.end, kilocalories: 200,
                                                       nutriLensID: log.id, payload: PayloadCoder.encode(log.payload))
        let pad = freshContext()
        #expect(try await HealthSync.run(health: health, context: pad).inserted == 1)
        let copy = try #require(try pad.fetch(FetchDescriptor<WorkoutLog>()).first)
        #expect(copy.exercises.first?.sets.first?.reps == 12)
        #expect(copy.planWeek == 4)
        #expect(copy.kind == .strength)
    }

    @Test func tombstonedRecordsAreNotReimported() async throws {
        let health = MockHealthService()
        let entry = meal(on: .now)
        _ = try await health.saveMeal(entry.healthSample)
        let pad = freshContext()
        pad.insert(DeletedRecord(id: entry.id, recordType: SyncRecordType.meal))
        #expect(try await HealthSync.run(health: health, context: pad).inserted == 0)
    }
}

@Suite("Backup file")
@MainActor
struct BackupTests {
    @Test func roundTripAndMergeWithDeletions() throws {
        let phone = freshContext()
        let pizza = NutritionDatabase.bundled.food(id: "pizza")!
        let a = MealEntry(date: .now, name: "Pizza", foodID: "pizza", grams: 107, nutrients: pizza.perServing, mealType: .lunch, source: .search)
        let b = MealEntry(date: .now, name: "Pizza", foodID: "pizza", grams: 214, nutrients: pizza.nutrients(for: .servings(2)), mealType: .dinner, source: .search)
        phone.insert(a)
        phone.insert(b)
        phone.insert(BodyMeasurement(date: .now, source: .manual, reading: BodyReading(values: [.weight: 80])))
        let log = WorkoutLog(kind: .yoga, title: "Gentle yoga", start: .now, end: .now.addingTimeInterval(600))
        phone.insert(log)
        try phone.save()

        // First transfer to the iPad.
        let pad = freshContext()
        let first = try BackupService.decode(BackupService.encode(BackupService.makeBackup(context: phone, defaults: UserDefaults(suiteName: "test-\(UUID())")!)))
        let report = try BackupService.merge(first, into: pad, applySettings: false)
        #expect(report.inserted == 4)
        #expect(try pad.fetch(FetchDescriptor<MealEntry>()).count == 2)

        // The phone deletes a meal and edits the other; the next backup carries both.
        Tombstone.record(b.id, type: SyncRecordType.meal, in: phone)
        phone.delete(b)
        a.grams = 150
        a.updatedAt = .now.addingTimeInterval(5)
        try phone.save()
        let second = try BackupService.makeBackup(context: phone)
        let report2 = try BackupService.merge(second, into: pad, applySettings: false)
        #expect(report2.deleted == 1)
        #expect(report2.updated >= 1)
        let meals = try pad.fetch(FetchDescriptor<MealEntry>())
        #expect(meals.map(\.id) == [a.id])
        #expect(meals.first?.grams == 150)

        // Importing the same file again is a no-op.
        let report3 = try BackupService.merge(second, into: pad, applySettings: false)
        #expect(report3 == BackupService.ImportReport())
    }
}

@Suite("Training helpers")
@MainActor
struct TrainingTests {
    let plan = PlanContent.homeStrength12Week

    @Test func tiredVersionCapsSetsAndDropsOptionalWork() {
        let monday = plan.day(weekday: 2)!
        let normal = PlanEngine.session(for: monday, week: 5)
        let tired = Training.adjusted(normal, readiness: .tired)
        #expect(normal.contains { $0.planned.optional })
        #expect(!tired.contains { $0.planned.optional })
        #expect(tired.allSatisfy { $0.prescription.sets <= 2 })
        #expect(Training.adjusted(normal, readiness: .unwell).isEmpty)
        #expect(Training.adjusted(normal, readiness: .ready).count == normal.count)
    }

    @Test func energyEstimatesAreActiveEnergy() {
        // Strength: (3.5 − 1) MET × 80 kg × 1 h = 200 kcal.
        #expect(Training.estimatedEnergy(kind: .strength, minutes: 60, bodyMassKg: 80) == 200)
        // Intervals with half jogging: (0.5 × 7 + 0.5 × 3.5 − 1) × 80 × 0.5 = 170.
        #expect(Training.estimatedEnergy(kind: .walkJog, minutes: 30, bodyMassKg: 80, jogShare: 0.5) == 170)
        // Unknown weight falls back to 70 kg: (2.5 − 1) × 70 = 105.
        #expect(Training.estimatedEnergy(kind: .yoga, minutes: 60, bodyMassKg: nil) == 105)
    }

    @Test func nutriLensSessionsCountTheirModerateMinutes() {
        let interval = DateInterval(start: .now.addingTimeInterval(-86_400), duration: 2 * 86_400)
        let log = WorkoutLog(kind: .walkJog, title: "Walk/jog stage 1", start: .now, end: .now.addingTimeInterval(20 * 60))
        log.cardioMinutes = 12
        let jog = WorkoutSummary(id: UUID(), name: "Running", symbolName: "figure.run", start: .now, end: .now.addingTimeInterval(20 * 60),
                                 energyBurned: 150, sourceName: "NutriLens", nutriLensID: log.id, payload: PayloadCoder.encode(log.payload), isCardio: true)
        let strength = WorkoutLog(kind: .strength, title: "Legs", start: .now, end: .now.addingTimeInterval(3_000))
        strength.cardioMinutes = 5  // easy walk after lifting
        let lift = WorkoutSummary(id: UUID(), name: "Strength", symbolName: "dumbbell", start: .now, end: .now.addingTimeInterval(3_000),
                                  energyBurned: 200, sourceName: "NutriLens", nutriLensID: strength.id, payload: PayloadCoder.encode(strength.payload))
        #expect(abs(Training.cardioMinutes(workouts: [jog, lift], logs: [], in: interval) - 17) < 0.001)
    }

    @Test func stepsTravelInTheWorkoutPayload() throws {
        let log = WorkoutLog(kind: .walk, title: "Indoor walk", start: .now, end: .now)
        log.steps = 3_120
        log.distanceKm = 2.34
        let copy = WorkoutLog(kind: .other, title: "", start: .now, end: .now)
        copy.apply(try #require(PayloadCoder.decode(WorkoutPayload.self, from: PayloadCoder.encode(log.payload))))
        #expect(copy.steps == 3_120)
        #expect(copy.distanceKm == 2.34)
        // Payloads written before steps existed still decode.
        let old = #"{"cardioMinutes":30,"energyRating":3,"exercises":[],"kind":"walk","notes":"","readiness":"ready","title":"Walk","updatedAt":"2026-11-01T08:00:00Z"}"#
        let decoded = try #require(PayloadCoder.decode(WorkoutPayload.self, from: old))
        #expect(decoded.steps == nil)
    }

    @Test func planWeekIntervalStartsOnThePlanWeekday() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!  // a Wednesday
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 9))!
        let interval = Training.planWeekInterval(containing: date, start: start)
        #expect(interval.start == calendar.date(from: DateComponents(year: 2026, month: 11, day: 11)))  // week 4 = 21 Oct + 21 days
        #expect(interval.contains(date))
        #expect(PlanEngine.week(for: date, startDate: start) == 4)
    }

    @Test func historyAndCardioMinutesAvoidDoubleCounting() {
        let interval = DateInterval(start: .now.addingTimeInterval(-86_400), duration: 2 * 86_400)
        let saved = WorkoutLog(kind: .walk, title: "Walk", start: .now, end: .now.addingTimeInterval(1_800))
        saved.cardioMinutes = 30
        saved.healthKitID = UUID()
        let localOnly = WorkoutLog(kind: .walk, title: "Walk", start: .now, end: .now.addingTimeInterval(1_200))
        localOnly.cardioMinutes = 20
        let healthWalk = WorkoutSummary(id: UUID(), name: "Walking", symbolName: "figure.walk", start: .now, end: .now.addingTimeInterval(1_800),
                                        energyBurned: 100, sourceName: "NutriLens", isCardio: true)
        let yoga = WorkoutSummary(id: UUID(), name: "Yoga", symbolName: "figure.yoga", start: .now, end: .now.addingTimeInterval(600),
                                  energyBurned: 30, sourceName: "NutriLens")
        // 30 min from Health (the saved walk) + 20 local-only; yoga isn't cardio.
        #expect(abs(Training.cardioMinutes(workouts: [healthWalk, yoga], logs: [saved, localOnly], in: interval) - 50) < 0.001)

        let older = WorkoutLog(kind: .strength, title: "A", start: .now.addingTimeInterval(-7 * 86_400), end: .now)
        older.exercises = [LoggedExercise(exerciseID: "02", sets: [LoggedSet(reps: 10, loadKg: 5)])]
        let newer = WorkoutLog(kind: .strength, title: "B", start: .now.addingTimeInterval(-86_400), end: .now)
        newer.exercises = [LoggedExercise(exerciseID: "02", sets: [LoggedSet(reps: 12, loadKg: 5)])]
        #expect(Training.history(of: "02", in: [newer, older]).map { $0[0].reps } == [10, 12])

        // Main-lift history is kept apart from practice on another plan day.
        older.planWeekday = 2
        newer.planWeekday = 7
        #expect(Training.history(of: "02", in: [newer, older], weekday: 2).map { $0[0].reps } == [10])
        #expect(Training.history(of: "02", in: [newer, older], weekday: 5).count == 2, "falls back when that day has none")
    }

    @Test func payloadsRoundTrip() throws {
        let log = WorkoutLog(kind: .walkJog, title: "Walk/jog stage 2", start: .now, end: .now)
        log.cardioMinutes = 12
        let decoded = try #require(PayloadCoder.decode(WorkoutPayload.self, from: PayloadCoder.encode(log.payload)))
        #expect(decoded.kind == "walkJog")
        #expect(decoded.cardioMinutes == 12)
        #expect(PayloadCoder.decode(WorkoutPayload.self, from: "not json") == nil)
    }

    @Test func everyExerciseVideoIsBundled() {
        for exercise in plan.exercises {
            #expect(Bundle.main.url(forResource: exercise.videoName, withExtension: "mp4") != nil, "missing \(exercise.videoName).mp4")
        }
    }
}

@Suite("My foods")
@MainActor
struct CustomFoodTests {
    @Test func customFoodBecomesASearchableTableEntry() throws {
        let context = freshContext()
        let food = CustomFood(draft: CustomFoodDraft(name: "Aai's thalipeeth", servingDescription: "1 piece",
                                                     servingGrams: 90, perServing: Nutrients(kilocalories: 225, protein: 8, carbohydrates: 30, fat: 8),
                                                     category: "breakfast"))
        context.insert(food)
        try context.save()
        let item = food.foodItem
        #expect(item.isCustom)
        #expect(item.region == "custom")
        #expect(abs(item.perServing.kilocalories - 225) < 0.001)
        #expect(abs(item.per100g.kilocalories - 250) < 0.001)
        let db = NutritionDatabase.bundled.adding([item])
        #expect(db.search("aai").first?.id == item.id)
        #expect(db.search("", filter: .myFoods).count == 1)
    }

    @Test func customFoodsTravelInBackups() throws {
        let phone = freshContext()
        let food = CustomFood(draft: CustomFoodDraft(name: "Protein ladoo", perServing: Nutrients(kilocalories: 150, protein: 8, carbohydrates: 14, fat: 7)))
        phone.insert(food)
        try phone.save()
        let pad = freshContext()
        let backup = try BackupService.decode(BackupService.encode(BackupService.makeBackup(context: phone)))
        #expect(try BackupService.merge(backup, into: pad, applySettings: false).inserted == 1)
        let copy = try #require(try pad.fetch(FetchDescriptor<CustomFood>()).first)
        #expect(copy.id == food.id)
        #expect(copy.name == "Protein ladoo")

        // Deleting on the phone removes it on the iPad at the next import.
        Tombstone.record(food.id, type: SyncRecordType.customFood, in: phone)
        phone.delete(food)
        try phone.save()
        #expect(try BackupService.merge(BackupService.makeBackup(context: phone), into: pad, applySettings: false).deleted == 1)
        #expect(try pad.fetch(FetchDescriptor<CustomFood>()).isEmpty)
    }
}
