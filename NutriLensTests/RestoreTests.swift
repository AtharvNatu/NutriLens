import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@MainActor
private var restoreContainers: [ModelContainer] = []

@MainActor
private func restoreContainer() -> ModelContainer {
    let container = AppEnvironment.makeContainer(inMemory: true)
    restoreContainers.append(container)
    return container
}

@Suite("Restoring after a reinstall")
@MainActor
struct RestoreTests {
    let food = NutritionDatabase.bundled.foods.first!

    func meal(daysAgo: Double, name: String) -> MealEntry {
        MealEntry(date: .now.addingTimeInterval(-daysAgo * 86_400), name: name, foodID: food.id, grams: 150,
                  nutrients: Nutrients(kilocalories: 300, protein: 20, carbohydrates: 30, fat: 10), mealType: .lunch, source: .search)
    }

    func authorizedHealth() -> MockHealthService {
        MockHealthService(state: MockHealthService.State(authorized: true))
    }

    @Test func fullHistoryBringsBackMealsOlderThan90Days() async throws {
        let health = authorizedHealth()
        let original = restoreContainer().mainContext
        for m in [meal(daysAgo: 400, name: "Last year"), meal(daysAgo: 200, name: "Old"), meal(daysAgo: 2, name: "Recent")] {
            original.insert(m)
            m.healthKitID = try await health.saveMeal(m.healthSample)
        }

        // Reinstalled app: empty store. A routine sync only looks back 90 days…
        let routine = restoreContainer().mainContext
        #expect(try await HealthSync.run(health: health, context: routine).inserted == 1)
        // …a full-history sync gets everything.
        let restored = restoreContainer().mainContext
        #expect(try await HealthSync.run(health: health, context: restored, fullHistory: true).inserted == 3)
        #expect(Set(try restored.fetch(FetchDescriptor<MealEntry>()).map(\.name)) == ["Last year", "Old", "Recent"])
    }

    @Test func fullHistoryNeverRemovesOldRecords() async throws {
        let health = authorizedHealth()
        let context = restoreContainer().mainContext
        let recent = meal(daysAgo: 1, name: "Recent")
        context.insert(recent)
        recent.healthKitID = try await health.saveMeal(recent.healthSample)
        // An old meal whose Health copy is gone (say, Health data was trimmed): keep it.
        let old = meal(daysAgo: 300, name: "Old")
        old.healthKitID = UUID()
        context.insert(old)

        let report = try await HealthSync.run(health: health, context: context, fullHistory: true)
        #expect(report.removed == 0)
        #expect(try context.fetch(FetchDescriptor<MealEntry>()).count == 2)
    }

    @Test func firstSyncAfterInstallIsFullAndThenRoutine() async throws {
        let health = authorizedHealth()
        let original = restoreContainer().mainContext
        let old = meal(daysAgo: 200, name: "Old")
        original.insert(old)
        old.healthKitID = try await health.saveMeal(old.healthSample)

        let defaults = UserDefaults(suiteName: "restore-\(UUID())")!
        let env = AppEnvironment(health: health, recognizer: MockFoodRecognizer.demo(database: .bundled), database: .bundled,
                                 modelContainer: restoreContainer())
        await env.syncFromHealth(defaults: defaults)
        #expect(env.lastSync?.inserted == 1)
        #expect(defaults.bool(forKey: SettingsKey.fullHealthRestoreDone))
    }

    @Test func fullRestoreRepeatsUntilHealthAccessAndDataArrive() async throws {
        let health = MockHealthService()  // Not authorized yet: reads come back empty.
        let defaults = UserDefaults(suiteName: "restore-\(UUID())")!
        let env = AppEnvironment(health: health, recognizer: MockFoodRecognizer.demo(database: .bundled), database: .bundled,
                                 modelContainer: restoreContainer())
        await env.syncFromHealth(defaults: defaults)
        #expect(!defaults.bool(forKey: SettingsKey.fullHealthRestoreDone))

        // Access granted, but Health still has nothing from NutriLens (new device, iCloud still downloading).
        try await health.requestAuthorization()
        await env.syncFromHealth(defaults: defaults)
        #expect(!defaults.bool(forKey: SettingsKey.fullHealthRestoreDone))
    }

    @Test func backupCarriesCalendarDays() async throws {
        let phone = restoreContainer().mainContext
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let record = DayRecord(dayKey: "2026-01-15", date: day)
        record.eatenKcal = 1_850
        record.protein = 120
        record.steps = 9_000
        record.activeEnergy = 520
        record.basalEnergy = 1_780
        record.asleepSeconds = 7 * 3600
        record.sleepScore = 82
        record.weightKg = 83.4
        record.workouts = [DayWorkout(name: "Walking", symbolName: "figure.walk", start: day.addingTimeInterval(7 * 3600), minutes: 30,
                                      kilocalories: 140, steps: 3_200, cardioMinutes: 30, source: "Apple Watch")]
        phone.insert(record)

        let file = try BackupService.decode(BackupService.encode(BackupService.makeBackup(context: phone, defaults: UserDefaults(suiteName: "b-\(UUID())")!)))
        #expect(file.days?.count == 1)

        // A reinstalled phone: nothing stored.
        let fresh = restoreContainer().mainContext
        let report = try BackupService.merge(file, into: fresh, applySettings: false)
        #expect(report.inserted == 1)
        let restored = try #require(try fresh.fetch(FetchDescriptor<DayRecord>()).first)
        #expect(restored.eatenKcal == 1_850)
        #expect(restored.steps == 9_000)
        #expect(restored.sleepScore == 82)
        #expect(restored.weightKg == 83.4)
        #expect(restored.workouts.map(\.name) == ["Walking"])
        #expect(restored.cardioMinutes == 30)

        // A device that recorded the day later, but without Health data for it, keeps its own record and
        // gets the missing Health values filled in.
        let other = restoreContainer().mainContext
        let later = DayRecord(dayKey: "2026-01-15", date: day)
        later.eatenKcal = 1_900
        later.mealCount = 4
        later.updatedAt = .now
        other.insert(later)
        _ = try BackupService.merge(file, into: other, applySettings: false)
        let merged = try #require(try other.fetch(FetchDescriptor<DayRecord>()).first)
        #expect(merged.eatenKcal == 1_900)
        #expect(merged.steps == 9_000)
        #expect(merged.asleepSeconds == 7 * 3600)
        #expect(merged.weightKg == 83.4)
        #expect(merged.workouts.count == 1)
        #expect(try other.fetch(FetchDescriptor<DayRecord>()).count == 1)
    }

    @Test func automaticRefreshRunsAtMostEvery15MinutesPerDay() async throws {
        let env = AppEnvironment(health: authorizedHealth(), recognizer: MockFoodRecognizer.demo(database: .bundled), database: .bundled,
                                 modelContainer: restoreContainer())
        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 23, minute: 50, second: 0, of: .now)!
        #expect(await env.refreshIfStale(now: evening))                                   // launch
        #expect(await !env.refreshIfStale(now: evening.addingTimeInterval(10)))           // quick app switch
        #expect(await !env.refreshIfStale(now: evening.addingTimeInterval(5 * 60)))
        #expect(await env.refreshIfStale(now: evening.addingTimeInterval(11 * 60)))       // a new day, though < 15 min
        #expect(await !env.refreshIfStale(now: evening.addingTimeInterval(20 * 60)))
        #expect(await env.refreshIfStale(now: evening.addingTimeInterval(27 * 60)))       // 16 min after the last one
    }

    @Test func olderBackupWithoutDaysStillImports() throws {
        let json = #"{"format":"NutriLens backup","version":1,"exportedAt":"2026-10-01T10:00:00Z","meals":[],"body":[],"workouts":[],"deletions":[],"settings":{}}"#
        let file = try BackupService.decode(Data(json.utf8))
        #expect(file.days == nil)
        #expect(try BackupService.merge(file, into: restoreContainer().mainContext, applySettings: false) == BackupService.ImportReport())
    }
}

@Suite("Usual dish amounts")
@MainActor
struct RecipePreferencesTests {
    @Test func usualAmountsAreRememberedAndTravelInBackups() throws {
        let defaults = UserDefaults(suiteName: "recipes-\(UUID())")!
        let recipe = try #require(DishRecipes.recipe(for: "egg_bhurji"))
        #expect(RecipePreferences.usual(for: recipe, defaults: defaults) == nil)
        RecipePreferences.save(["main": 3, "fat": 1, "bogus": 9], for: recipe, defaults: defaults)
        #expect(RecipePreferences.usual(for: recipe, defaults: defaults) == ["main": 3, "fat": 1])

        // Through a backup to another device.
        let other = UserDefaults(suiteName: "recipes-\(UUID())")!
        let settings = BackupService.currentSettings(defaults)
        for (key, value) in settings { BackupService.applySetting(key, value, defaults: other) }
        #expect(RecipePreferences.usual(for: recipe, defaults: other) == ["main": 3, "fat": 1])

        let dish = try #require(NutritionDatabase.bundled.food(id: "egg_bhurji"))
        let shown = RecipePreferences.asUsual(dish, defaults: defaults)
        #expect(shown.servingDescription == "1 portion (3 eggs, 1 tsp oil)")
        #expect(shown.perServing.protein > dish.perServing.protein)
        let plain = try #require(NutritionDatabase.bundled.food(id: "kande_pohe"))
        #expect(RecipePreferences.asUsual(plain, defaults: defaults) == plain)

        RecipePreferences.forget(recipe, defaults: defaults)
        #expect(RecipePreferences.asUsual(dish, defaults: defaults) == dish)
        #expect(RecipePreferences.usual(for: recipe, defaults: defaults) == nil)
    }
}
