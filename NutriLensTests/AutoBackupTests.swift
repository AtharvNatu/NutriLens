import Foundation
import NutriCore
import SwiftData
import Testing
@testable import NutriLens

@MainActor
private var autoBackupContainers: [ModelContainer] = []

/// One simulated device: its own store and settings, sharing a backup folder with the others.
@MainActor
private struct Device {
    let context: ModelContext
    let defaults: UserDefaults

    init(id: String, folder: URL) throws {
        let container = AppEnvironment.makeContainer(inMemory: true)
        autoBackupContainers.append(container)
        context = container.mainContext
        defaults = UserDefaults(suiteName: "auto-backup-\(UUID())")!
        defaults.set(id, forKey: SettingsKey.deviceID)
        try AutoBackup.chooseFolder(folder, defaults: defaults)
    }

    func backUp(now: Date = .now, force: Bool = false) async throws -> String? {
        try await AutoBackup.backUpIfDue(context: context, defaults: defaults, now: now, force: force)
    }

    func importNew() async throws -> AutoBackup.ImportResult {
        try await AutoBackup.importFromFolder(context: context, defaults: defaults)
    }
}

@Suite("Automatic backup folder (iCloud Drive)")
@MainActor
struct AutoBackupTests {
    let food = NutritionDatabase.bundled.foods.first!

    func newFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NutriLens Backups \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func meal(_ name: String, photo: Data? = nil, at date: Date = .now) -> MealEntry {
        MealEntry(date: date, name: name, foodID: food.id, grams: 200,
                  nutrients: Nutrients(kilocalories: 350, protein: 18, carbohydrates: 45, fat: 9), mealType: .lunch, source: .photo, photoData: photo)
    }

    @Test func fileNames() {
        let name = BackupFileName(day: "2026-11-12", deviceKind: "iPad", deviceID: "ab12cd34")
        #expect(name.fileName == "NutriLens backup 2026-11-12 iPad ab12cd34.json")
        #expect(BackupFileName(name.fileName) == name)
        for other in ["notes.txt", "NutriLens backup 2026-11-12 iPad AB12CD34.json", "NutriLens backup 2026-11-12 iPad ab12cd34.json.bak",
                      "NutriLens backup 26-11-12 iPad ab12cd34.json", "NutriLens-backup-2026-11-12.json", "NutriLens backup 2026-11-12 Phone ab12cd34.json"] {
            #expect(BackupFileName(other) == nil, "\(other)")
        }
    }

    @Test func iPhoneAndIPadStayInStep() async throws {
        let folder = try newFolder()
        let phone = try Device(id: "11111111", folder: folder)
        let pad = try Device(id: "22222222", folder: folder)

        // iPhone: a meal with its photo, and one of your own foods.
        let lunch = meal("Poha", photo: Data([1, 2, 3]))
        phone.context.insert(lunch)
        phone.context.insert(CustomFood(id: UUID(), draft: CustomFoodDraft(name: "Aai's thalipeeth", servingDescription: "1 piece",
                                                                             servingGrams: 80, perServing: Nutrients(kilocalories: 190, protein: 6, carbohydrates: 26, fat: 7),
                                                                             category: "Breakfast", notes: "")))
        let written = try #require(try await phone.backUp())
        #expect(try files(in: folder) == [written])

        // iPad opens: gets both, photo included.
        let result = try await pad.importNew()
        #expect(result.report.inserted == 2)
        #expect(result.from == ["iPhone"])
        let padMeal = try #require(try pad.context.fetch(FetchDescriptor<MealEntry>()).first)
        #expect(padMeal.id == lunch.id)
        #expect(padMeal.photoData == Data([1, 2, 3]))
        #expect(try pad.context.fetchCount(FetchDescriptor<CustomFood>()) == 1)
        // Opening again finds nothing new.
        #expect(try await pad.importNew() == AutoBackup.ImportResult())

        // iPad deletes the meal and backs up; the iPhone picks up the deletion.
        Tombstone.record(padMeal.id, type: SyncRecordType.meal, in: pad.context)
        pad.context.delete(padMeal)
        try #require(try await pad.backUp() != nil)
        #expect(try files(in: folder).count == 2)
        let back = try await phone.importNew()
        #expect(back.report.deleted == 1)
        #expect(try phone.context.fetchCount(FetchDescriptor<MealEntry>()) == 0)
        #expect(try phone.context.fetchCount(FetchDescriptor<CustomFood>()) == 1)
    }

    @Test func calendarDaysOnlyFillGapsSoDevicesDontFightOverThem() async throws {
        let folder = try newFolder()
        let phone = try Device(id: "11111111", folder: folder)
        let pad = try Device(id: "22222222", folder: folder)
        let day = Calendar.current.startOfDay(for: .now)

        let phoneDay = DayRecord(dayKey: DayRecord.key(for: day), date: day)
        phoneDay.steps = 9_000
        phoneDay.updatedAt = .now
        phone.context.insert(phoneDay)
        let oldDay = DayRecord(dayKey: "2026-01-02", date: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 2))!)
        oldDay.eatenKcal = 1_700
        phone.context.insert(oldDay)
        _ = try await phone.backUp()

        let padDay = DayRecord(dayKey: DayRecord.key(for: day), date: day)
        padDay.steps = 8_800
        padDay.updatedAt = .distantPast
        pad.context.insert(padDay)
        _ = try await pad.importNew()
        let days = try pad.context.fetch(FetchDescriptor<DayRecord>(sortBy: [SortDescriptor(\.date)]))
        #expect(days.map(\.dayKey) == ["2026-01-02", DayRecord.key(for: day)])
        #expect(days[0].eatenKcal == 1_700)
        #expect(days[1].steps == 8_800)  // its own value stays, though the iPhone's is newer
    }

    @Test func writesOnlyWhenSomethingChangedAndWhenDue() async throws {
        let folder = try newFolder()
        let phone = try Device(id: "11111111", folder: folder)
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now)!

        #expect(try await phone.backUp(now: morning) != nil)
        #expect(try await phone.backUp(now: morning.addingTimeInterval(600)) == nil)  // nothing changed
        phone.context.insert(meal("Misal pav"))
        #expect(try await phone.backUp(now: morning.addingTimeInterval(1_200)) != nil)

        phone.defaults.set(BackupFrequency.daily.rawValue, forKey: SettingsKey.autoBackupFrequency)
        phone.context.insert(meal("Varan bhaat"))
        #expect(try await phone.backUp(now: morning.addingTimeInterval(3_600)) == nil)    // already checked today
        #expect(try await phone.backUp(now: morning.addingTimeInterval(86_400)) != nil)   // next day
        #expect(try await phone.backUp(now: morning.addingTimeInterval(86_500), force: true) != nil)  // Back up now

        phone.defaults.set(BackupFrequency.off.rawValue, forKey: SettingsKey.autoBackupFrequency)
        phone.context.insert(meal("Sabudana khichdi"))
        #expect(try await phone.backUp(now: morning.addingTimeInterval(3 * 86_400)) == nil)
        #expect(try await phone.importNew() == AutoBackup.ImportResult())
    }

    @Test func keepsOnlyItsOwnLast14FilesAndNeverTouchesOthers() async throws {
        let folder = try newFolder()
        let others = ["notes.txt", "NutriLens backup 2026-01-01 iPad 99999999.json", "NutriLens backup 2026-01-01 iPhone ABCDEFGH.json"]
        for name in others { try Data("keep".utf8).write(to: folder.appendingPathComponent(name)) }
        let phone = try Device(id: "11111111", folder: folder)
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        for offset in 0..<20 {
            phone.context.insert(meal("Meal \(offset)", at: start.addingTimeInterval(Double(offset) * 86_400)))
            _ = try await phone.backUp(now: start.addingTimeInterval(Double(offset) * 86_400))
        }
        let names = try files(in: folder)
        let mine = names.compactMap(BackupFileName.init).filter { $0.deviceID == "11111111" }
        #expect(mine.count == AutoBackup.keepCount)
        #expect(mine.map(\.day).min() == "2026-10-07")
        #expect(mine.map(\.day).max() == "2026-10-20")
        for name in others { #expect(names.contains(name), "\(name) must not be deleted") }
    }

    @Test func settingsMergeKeepsLocalChanges() async throws {
        let folder = try newFolder()
        let phone = try Device(id: "11111111", folder: folder)
        let pad = try Device(id: "22222222", folder: folder)
        phone.defaults.set(1_800.0, forKey: SettingsKey.dailyCalorieTarget)
        phone.defaults.set(140.0, forKey: SettingsKey.proteinTarget)
        _ = try await phone.backUp()

        // iPad: protein changed here, target never set.
        pad.defaults.set(150.0, forKey: SettingsKey.proteinTarget)
        let result = try await pad.importNew()
        #expect(result.settingsChanged == 1)
        #expect(pad.defaults.double(forKey: SettingsKey.dailyCalorieTarget) == 1_800)
        #expect(pad.defaults.double(forKey: SettingsKey.proteinTarget) == 150)
        _ = try await pad.backUp()

        // iPhone didn't change protein since its backup, so it takes the iPad's.
        _ = try await phone.importNew()
        #expect(phone.defaults.double(forKey: SettingsKey.proteinTarget) == 150)
        #expect(phone.defaults.double(forKey: SettingsKey.dailyCalorieTarget) == 1_800)
    }

    @Test func reinstallRestoresFromTheFolder() async throws {
        let folder = try newFolder()
        let old = try Device(id: "11111111", folder: folder)
        old.context.insert(meal("Puran poli", photo: Data([9])))
        old.defaults.set(1_900.0, forKey: SettingsKey.dailyCalorieTarget)
        _ = try await old.backUp()

        // Reinstalled: new ID, empty store and settings; folder chosen again.
        let fresh = try Device(id: "33333333", folder: folder)
        let result = try await fresh.importNew()
        #expect(result.report.inserted == 1)
        #expect(try fresh.context.fetch(FetchDescriptor<MealEntry>()).first?.photoData == Data([9]))
        #expect(fresh.defaults.double(forKey: SettingsKey.dailyCalorieTarget) == 1_900)
    }
}
