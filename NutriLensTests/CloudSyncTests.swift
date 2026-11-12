import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@MainActor
private var cloudContainers: [ModelContainer] = []

@MainActor
private func cloudContext() -> ModelContext {
    let container = AppEnvironment.makeContainer(inMemory: true)
    cloudContainers.append(container)
    return container.mainContext
}

private final class MemoryStore: SettingsStore {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String?, forKey key: String) { values[key] = value }
    func synchronize() -> Bool { true }
}

@Suite("iCloud sync: duplicates")
@MainActor
struct CloudDeduplicatorTests {
    typealias Copy = CloudDeduplicator.Copy
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func bothDevicesKeepTheSameCopy() {
        // The same meal uploaded by the iPhone (aaaa…) and the iPad (bbbb…), listed in different orders.
        let phoneView = [Copy(key: "m", updatedAt: t0, origin: "aaaa1111"), Copy(key: "m", updatedAt: t0, origin: "bbbb2222")]
        let padView = Array(phoneView.reversed())
        #expect(CloudDeduplicator.doomed(phoneView, device: "aaaa1111") == [1])
        #expect(CloudDeduplicator.doomed(padView, device: "bbbb2222") == [0])
    }

    @Test func theNewestEditWins() {
        let copies = [Copy(key: "m", updatedAt: t0, origin: "aaaa1111"), Copy(key: "m", updatedAt: t0 + 60, origin: "bbbb2222")]
        #expect(CloudDeduplicator.doomed(copies, device: "aaaa1111") == [0])
        #expect(CloudDeduplicator.doomed(copies, device: "bbbb2222") == [0])
    }

    @Test func waitsForUnstampedCopiesAndLeavesSameDeviceTiesToThatDevice() {
        let unstamped = [Copy(key: "m", updatedAt: t0, origin: ""), Copy(key: "m", updatedAt: t0, origin: "aaaa1111")]
        #expect(CloudDeduplicator.doomed(unstamped, device: "aaaa1111").isEmpty)
        let sameDevice = [Copy(key: "m", updatedAt: t0, origin: "aaaa1111"), Copy(key: "m", updatedAt: t0, origin: "aaaa1111")]
        #expect(CloudDeduplicator.doomed(sameDevice, device: "bbbb2222").isEmpty)
        #expect(CloudDeduplicator.doomed(sameDevice, device: "aaaa1111") == [1])
        #expect(CloudDeduplicator.doomed([sameDevice[0]], device: "aaaa1111").isEmpty)
    }

    @Test func removesDuplicateMealsAndDaysFromTheStore() throws {
        let context = cloudContext()
        let id = UUID()
        func meal(origin: String, kcal: Double, updated: Date) -> MealEntry {
            let m = MealEntry(date: t0, name: "Pohe", foodID: "kande_pohe", grams: 200,
                              nutrients: Nutrients(kilocalories: kcal, protein: 6, carbohydrates: 50, fat: 11), mealType: .breakfast, source: .search)
            m.id = id
            m.originDevice = origin
            m.updatedAt = updated
            return m
        }
        context.insert(meal(origin: "bbbb2222", kcal: 320, updated: t0))
        context.insert(meal(origin: "aaaa1111", kcal: 320, updated: t0))
        context.insert(meal(origin: "bbbb2222", kcal: 350, updated: t0 + 30))  // edited on the iPad
        let unrelated = meal(origin: "aaaa1111", kcal: 100, updated: t0)
        unrelated.id = UUID()
        context.insert(unrelated)
        for origin in ["aaaa1111", "bbbb2222"] {
            let day = DayRecord(dayKey: "2026-11-12", date: t0)
            day.originDevice = origin
            context.insert(day)
        }
        try context.save()

        #expect(CloudDeduplicator.run(context: context, device: "aaaa1111") == 3)
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        #expect(meals.count == 2)
        #expect(meals.first { $0.id == id }?.kilocalories == 350)
        #expect(try context.fetchCount(FetchDescriptor<DayRecord>()) == 1)
        #expect(CloudDeduplicator.run(context: context, device: "aaaa1111") == 0)
    }

    @Test func recordsAreStampedWhenMadeAndOldOnesOnce() throws {
        let defaults = UserDefaults.standard
        let device = DeviceIdentity.id(defaults: defaults)
        let fresh = MealEntry(date: .now, name: "x", foodID: nil, grams: 1, nutrients: .zero, mealType: .snack, source: .custom)
        #expect(fresh.originDevice == device)

        let context = cloudContext()
        fresh.originDevice = ""
        context.insert(fresh)
        let reading = BodyMeasurement(date: .now, source: .manual, reading: BodyReading(date: .now, values: [.weight: 80]))
        reading.originDevice = ""
        context.insert(reading)
        CloudDeduplicator.stampUnclaimed(context: context, device: "cccc3333")
        #expect(fresh.originDevice == "cccc3333" && reading.originDevice == "cccc3333")
    }
}

@Suite("iCloud sync: settings")
@MainActor
struct SettingsCloudSyncTests {
    func defaults() -> UserDefaults { UserDefaults(suiteName: "kvs-\(UUID())")! }

    @Test func settingsTravelBetweenDevices() {
        let cloud = MemoryStore()
        let phone = defaults(), pad = defaults()
        phone.set(160.0, forKey: SettingsKey.proteinTarget)
        phone.set(2_100.0, forKey: SettingsKey.dailyCalorieTarget)
        phone.set("/private/phone-only", forKey: SettingsKey.autoBackupFolderName)

        let phoneSync = SettingsCloudSync(store: cloud, defaults: phone)
        #expect(phoneSync.push() == 2)
        #expect(cloud.values[SettingsKey.autoBackupFolderName] == nil)

        let padSync = SettingsCloudSync(store: cloud, defaults: pad)
        #expect(padSync.pull() == 2)
        #expect(pad.double(forKey: SettingsKey.proteinTarget) == 160)
        #expect(padSync.push() == 0)

        // A change on the iPad comes back to the iPhone; nothing else moves.
        pad.set(150.0, forKey: SettingsKey.proteinTarget)
        #expect(padSync.push() == 1)
        #expect(phoneSync.pull() == 1)
        #expect(phone.double(forKey: SettingsKey.proteinTarget) == 150)
        #expect(phone.double(forKey: SettingsKey.dailyCalorieTarget) == 2_100)
        #expect(phoneSync.push() == 0)
    }

    @Test func whenBothChangedTheOtherDeviceWins() {
        let cloud = MemoryStore()
        let phone = defaults(), pad = defaults()
        let phoneSync = SettingsCloudSync(store: cloud, defaults: phone)
        let padSync = SettingsCloudSync(store: cloud, defaults: pad)
        phone.set(8.0, forKey: SettingsKey.sleepGoalHours)
        phoneSync.push()
        padSync.pull()
        phone.set(7.5, forKey: SettingsKey.sleepGoalHours)
        pad.set(9.0, forKey: SettingsKey.sleepGoalHours)
        padSync.push()
        // The iPhone opens: pulls first, so the iPad's newer value replaces its unsent one.
        phoneSync.pull()
        #expect(phone.double(forKey: SettingsKey.sleepGoalHours) == 9)
        #expect(phoneSync.push() == 0)
    }
}

@Suite("iCloud sync: Apple Health only restores")
@MainActor
struct CloudHealthTests {
    @Test func healthSyncNeverDeletesWithICloudOn() async throws {
        let health = MockHealthService(state: MockHealthService.State(authorized: true))
        let container = AppEnvironment.makeContainer(inMemory: true)
        cloudContainers.append(container)
        let env = AppEnvironment(health: health, recognizer: MockFoodRecognizer.demo(database: .bundled), database: .bundled,
                                 modelContainer: container, usesCloudKit: true)
        let defaults = UserDefaults(suiteName: "ck-\(UUID())")!

        // Saved on the other device: its Health entry hasn't synced here yet, but iCloud already brought the meal.
        let meal = MealEntry(date: .now.addingTimeInterval(-600), name: "Egg bhurji", foodID: "egg_bhurji", grams: 200,
                             nutrients: Nutrients(kilocalories: 300, protein: 20, carbohydrates: 5, fat: 22), mealType: .breakfast, source: .search)
        meal.healthKitID = UUID()
        container.mainContext.insert(meal)
        let other = MealEntry(date: .now.addingTimeInterval(-7_200), name: "Poha", foodID: "kande_pohe", grams: 200,
                              nutrients: Nutrients(kilocalories: 320, protein: 6, carbohydrates: 50, fat: 11), mealType: .breakfast, source: .search)
        _ = try await health.saveMeal(other.healthSample)

        await env.syncFromHealth(defaults: defaults)  // first launch: a one-time restore
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealEntry>()) == 2)
        #expect(defaults.bool(forKey: SettingsKey.fullHealthRestoreDone))

        // Routine syncs are iCloud's job now: a later Health entry isn't pulled in from Health.
        let later = MealEntry(date: .now.addingTimeInterval(-300), name: "Banana", foodID: "banana", grams: 120,
                              nutrients: Nutrients(kilocalories: 107, protein: 1.3, carbohydrates: 28, fat: 0.4), mealType: .snack, source: .search)
        _ = try await health.saveMeal(later.healthSample)
        await env.syncFromHealth(defaults: defaults)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<MealEntry>()) == 2)
    }
}
