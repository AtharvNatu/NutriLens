import CoreData
import Foundation
import NutriCore
import Observation
import SwiftData

/// Shared services, injected into the SwiftUI environment.
@MainActor
@Observable
final class AppEnvironment {
    let health: any HealthDataProviding
    let recognizer: any FoodRecognizing
    let database: NutritionDatabase
    let modelContainer: ModelContainer
    /// Whether iCloud (CloudKit) keeps the data in step between devices (paid developer account builds).
    let usesCloudKit: Bool
    /// iCloud key-value sync of settings, with iCloud sync on.
    private var settingsSync: SettingsCloudSync?
    private var remoteChangeObserver: NSObjectProtocol?
    private var dedupeTask: Task<Void, Never>?
    /// True when running with sample data (`-demoMode YES`), e.g. for Simulator screenshots.
    let isDemo: Bool

    /// The training plan from Workout-Plan.pdf.
    let plan = PlanContent.homeStrength12Week

    /// Bumped whenever something is written to Health, so screens reload what they show.
    private(set) var healthRevision = 0
    /// Result of the last sync from Apple Health (meals, readings and workouts from your other devices).
    private(set) var lastSync: HealthSync.Report?
    private(set) var isSyncing = false
    private(set) var syncError: String?
    /// Last automatic-backup activity, for Settings ("Merged from your iPad…", "Saved …").
    private(set) var backupMessage: String?
    private(set) var backupError: String?
    private(set) var isBackingUp = false
    /// When the last automatic (launch / back-to-foreground) refresh started.
    private(set) var lastAutomaticRefresh: Date?
    /// Body weight and usual daily steps, for the day's macro targets (see `macroTargets(on:)`).
    private(set) var macroInputs = MacroInputs()

    struct MacroInputs: Equatable {
        var bodyMassKg: Double?
        var usualSteps = MacroPlanner.defaultSteps
    }

    /// Talks to the NutriLens Watch app (not used in tests or demo mode).
    @ObservationIgnored private var watchLink: WatchLink?

    /// Automatic refreshes closer together than this are skipped. Pull to refresh, saving and opening a
    /// calendar month always load at once.
    static let automaticRefreshInterval: TimeInterval = 15 * 60

    init(
        health: any HealthDataProviding,
        recognizer: any FoodRecognizing,
        database: NutritionDatabase,
        modelContainer: ModelContainer,
        isDemo: Bool = false,
        usesCloudKit: Bool = false
    ) {
        self.health = health
        self.recognizer = recognizer
        self.database = database
        self.modelContainer = modelContainer
        self.isDemo = isDemo
        self.usesCloudKit = usesCloudKit
    }

    func healthDidChange() {
        healthRevision += 1
        if let watchLink { Task { await watchLink.sendContext() } }
    }

    /// Starts the link to the Watch app: it gets the plan context, and sends back the sessions it records.
    func startWatchLink() {
        guard watchLink == nil else { return }
        let link = WatchLink()
        watchLink = link
        link.start(env: self)
    }

    /// Whether this build was made with iCloud sync (`ENABLE_CLOUDKIT_SYNC = YES`, paid developer account).
    static var cloudKitBuild: Bool {
        #if CLOUDKIT_SYNC
        true
        #else
        false
        #endif
    }

    /// Pulls in what NutriLens saved to Apple Health on your other devices.
    ///
    /// The first sync after installing looks at your whole history (not just the last 90 days), so if the app
    /// was deleted and reinstalled, every meal, scale reading and workout saved to Health comes back.
    /// `fullHistory: true` forces that again (Settings › Restore all history).
    ///
    /// With iCloud sync, iCloud carries the data between devices, so this only runs as a restore (the first time,
    /// or when asked) and never deletes anything.
    func syncFromHealth(fullHistory: Bool? = nil, defaults: UserDefaults = .standard) async {
        guard !isSyncing, health.isAvailable else { return }
        let full = fullHistory ?? !defaults.bool(forKey: SettingsKey.fullHealthRestoreDone)
        if usesCloudKit && !full { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let context = modelContainer.mainContext
            lastSync = try await HealthSync.run(health: health, context: context, fullHistory: full, removals: !usesCloudKit)
            if usesCloudKit { removeCloudDuplicates() }
            syncError = nil
            defaults.set(Date.now.timeIntervalSince1970, forKey: SettingsKey.lastHealthSync)
            // Before Health access is granted, reads come back empty without an error, and on a new device
            // Health's iCloud data may still be arriving: only stop doing full passes once something is here.
            if full, !(await health.shouldRequestAuthorization()), Self.hasLogs(in: context) {
                defaults.set(true, forKey: SettingsKey.fullHealthRestoreDone)
            }
            if let lastSync, lastSync.inserted + lastSync.updated + lastSync.removed > 0 { healthDidChange() }
        } catch {
            syncError = error.localizedDescription
        }
    }

    private static func hasLogs(in context: ModelContext) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<MealEntry>())) ?? 0) > 0
            || ((try? context.fetchCount(FetchDescriptor<BodyMeasurement>())) ?? 0) > 0
            || ((try? context.fetchCount(FetchDescriptor<WorkoutLog>())) ?? 0) > 0
    }

    /// Sync from Health and record the last week, unless that already happened in the last 15 minutes today.
    /// Called on launch and whenever the app returns to the foreground, so quick app switches cost nothing.
    /// Returns whether it ran.
    @discardableResult
    func refreshIfStale(now: Date = .now, calendar: Calendar = .current) async -> Bool {
        if let last = lastAutomaticRefresh, now.timeIntervalSince(last) < Self.automaticRefreshInterval,
           calendar.isDate(last, inSameDayAs: now) {
            return false
        }
        lastAutomaticRefresh = now
        await syncFromHealth()
        if usesCloudKit {
            removeCloudDuplicates()
            settingsSync?.pull()
        } else {
            // iCloud already brings the other device's records; merging its backups too would only race it.
            await importFromBackupFolder()
        }
        await refreshMacroInputs()
        await recordRecentDays()
        await backUpToFolder()
        await watchLink?.sendContext()
        return true
    }

    /// Merges new backups your other devices wrote to the backup folder (see `AutoBackup`).
    func importFromBackupFolder(defaults: UserDefaults = .standard) async {
        guard !isDemo, AutoBackup.folderName(defaults: defaults) != nil else { return }
        do {
            let result = try await AutoBackup.importFromFolder(context: modelContainer.mainContext, defaults: defaults)
            if result.changedAnything {
                let from = Set(result.from).sorted().joined(separator: " and ")
                backupMessage = "Merged from your \(from): \(result.report.summary)"
                    + (result.settingsChanged > 0 ? " \(result.settingsChanged) settings updated." : "")
                healthDidChange()
            }
            backupError = nil
        } catch {
            backupError = error.localizedDescription
        }
    }

    /// Writes this device's backup to the folder when one is due; `force` writes now.
    func backUpToFolder(force: Bool = false, defaults: UserDefaults = .standard) async {
        guard !isDemo, force || AutoBackup.folderName(defaults: defaults) != nil, !isBackingUp else { return }
        isBackingUp = true
        defer { isBackingUp = false }
        do {
            // Settings shows the last file written; backupMessage is kept for what was merged in.
            try await AutoBackup.backUpIfDue(context: modelContainer.mainContext, defaults: defaults, force: force)
            backupError = nil
        } catch {
            backupError = "Couldn't back up: \(error.localizedDescription)"
        }
    }

    /// Starts iCloud sync housekeeping: stamps records made before iCloud sync (first time only), syncs settings,
    /// and tidies duplicates whenever the other device's changes arrive.
    func startCloudSync(defaults: UserDefaults = .standard, settingsStore: SettingsStore = NSUbiquitousKeyValueStore.default) {
        guard usesCloudKit, settingsSync == nil else { return }
        let device = DeviceIdentity.id(defaults: defaults)
        if !defaults.bool(forKey: SettingsKey.cloudOriginsStamped) {
            CloudDeduplicator.stampUnclaimed(context: modelContainer.mainContext, device: device)
            defaults.set(true, forKey: SettingsKey.cloudOriginsStamped)
        }
        let sync = SettingsCloudSync(store: settingsStore, defaults: defaults)
        settingsSync = sync
        sync.start { [weak self] in self?.healthDidChange() }
        remoteChangeObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDedupe() }
        }
        removeCloudDuplicates()
    }

    /// Removes duplicate copies left by iCloud sync (see `CloudDeduplicator`).
    func removeCloudDuplicates(defaults: UserDefaults = .standard) {
        guard usesCloudKit else { return }
        if CloudDeduplicator.run(context: modelContainer.mainContext, device: DeviceIdentity.id(defaults: defaults)) > 0 {
            healthDidChange()
        }
    }

    /// Remote changes arrive in bursts; tidy up once they settle.
    private func scheduleDedupe() {
        dedupeTask?.cancel()
        dedupeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.removeCloudDuplicates()
        }
    }

    /// Stores the last week's day records, so the calendar keeps every day even if Health data goes away later.
    func recordRecentDays() async {
        await DayRecorder.record(days: DayRecorder.recentDays(7), health: health, context: modelContainer.mainContext)
    }

    /// The day's protein, carbohydrate and fat targets, from that day's planned training and your usual steps.
    func macroTargets(on date: Date, defaults: UserDefaults = .standard) -> MacroTargets {
        let target = defaults.object(forKey: SettingsKey.dailyCalorieTarget) as? Double ?? SettingsDefault.dailyCalorieTarget
        let stepLength = defaults.object(forKey: SettingsKey.stepLengthMeters) as? Double ?? SettingsDefault.stepLengthMeters
        return MacroPlanner.targets(day: plan.day(weekday: Calendar.current.component(.weekday, from: date)), week: planWeek(on: date),
                                    calorieTarget: target, policy: defaults.creditPolicy, bodyMassKg: macroInputs.bodyMassKg,
                                    expectedSteps: macroInputs.usualSteps, stepLengthMeters: stepLength)
    }

    /// Latest weight (Apple Health, else your last scale reading) and the median steps of the last 14 days.
    func refreshMacroInputs(now: Date = .now) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let days = (1...14).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let activity = (try? await health.activity(for: days)) ?? [:]
        let steps = days.map { activity[$0]?.steps ?? 0 }
        var mass = (try? await health.latestBodyMass()) ?? nil
        if mass == nil {
            var latest = FetchDescriptor<BodyMeasurement>(predicate: #Predicate { $0.weightKg > 0 }, sortBy: [SortDescriptor(\.date, order: .reverse)])
            latest.fetchLimit = 1
            mass = (try? modelContainer.mainContext.fetch(latest))?.first?.weightKg
        }
        let inputs = MacroInputs(bodyMassKg: mass, usualSteps: MacroPlanner.usualSteps(steps))
        if inputs != macroInputs { macroInputs = inputs }
    }

    /// "Now" for the plan screens; demo mode can shift it (`-demoDayOffset 1`) to show another weekday.
    var now: Date {
        guard isDemo else { return .now }
        let offset = UserDefaults.standard.double(forKey: "demoDayOffset")
        return Date.now.addingTimeInterval(offset * 86_400)
    }

    /// Your profile for reference ranges: values set in Settings win, otherwise Apple Health's.
    func bodyProfile(defaults: UserDefaults = .standard) async -> BodyProfile {
        let health = await self.health.healthProfile()
        let sexSetting = defaults.string(forKey: SettingsKey.profileSex) ?? "health"
        let sex: Sex = sexSetting == "health" ? (health.sex ?? .notSet) : (Sex(rawValue: sexSetting) ?? .notSet)
        let ageSetting = defaults.integer(forKey: SettingsKey.profileAge)
        let age: Int? = ageSetting > 0 ? ageSetting : health.birthDate.flatMap {
            Calendar.current.dateComponents([.year], from: $0, to: now).year
        }
        let heightSetting = defaults.double(forKey: SettingsKey.profileHeightCm)
        let height: Double? = heightSetting > 0 ? heightSetting : health.heightCm
        let asian = defaults.object(forKey: SettingsKey.asianCutoffs) as? Bool ?? true
        return BodyProfile(sex: sex, age: age, heightCm: height, asianCutoffs: asian)
    }

    /// Plan start from settings (defaults to the plan's date).
    var planStartDate: Date {
        let stored = UserDefaults.standard.object(forKey: SettingsKey.planStartDate) as? Double
        return Date(timeIntervalSince1970: stored ?? SettingsDefault.planStartDate)
    }

    /// Current plan week (nil before the start date).
    func planWeek(on date: Date = .now) -> Int? {
        PlanEngine.week(for: date, startDate: planStartDate)
    }

    /// Chooses real or mock services from the launch arguments and the device.
    static func makeDefault(arguments: LaunchArguments = .current) -> AppEnvironment {
        let database = NutritionDatabase.bundled
        if arguments.isDemo || arguments.isRunningTests {
            let container = makeContainer(inMemory: true)
            if arguments.isDemo {
                DemoContent.seed(into: container.mainContext, database: database)
            }
            return AppEnvironment(
                health: arguments.isDemo ? MockHealthService.sample() : MockHealthService(),
                recognizer: arguments.isDemo ? MockFoodRecognizer.demo(database: database) : MockFoodRecognizer(results: []),
                database: database,
                modelContainer: container,
                isDemo: arguments.isDemo
            )
        }
        let healthKit = HealthKitService()
        let health: any HealthDataProviding = healthKit.isAvailable ? healthKit : MockHealthService(isAvailable: false)
        let environment = AppEnvironment(
            health: health,
            recognizer: VisionFoodRecognizer(database: database),
            database: database,
            modelContainer: makeContainer(inMemory: false),
            usesCloudKit: cloudKitBuild
        )
        environment.startCloudSync()
        environment.startWatchLink()
        return environment
    }

    static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema(AppSchema.models)
        #if CLOUDKIT_SYNC
        let cloud: ModelConfiguration.CloudKitDatabase = inMemory ? .none : .automatic
        #else
        let cloud: ModelConfiguration.CloudKitDatabase = .none
        #endif
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: cloud)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // A broken on-disk store shouldn't stop the app opening; fall back to memory.
            assertionFailure("Failed to open the data store: \(error)")
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            } catch {
                fatalError("Unable to create even an in-memory store: \(error)")
            }
        }
    }

    /// A fully mocked environment for SwiftUI previews.
    static func preview() -> AppEnvironment {
        let database = NutritionDatabase.bundled
        let container = makeContainer(inMemory: true)
        DemoContent.seed(into: container.mainContext, database: database)
        return AppEnvironment(
            health: MockHealthService.sample(),
            recognizer: MockFoodRecognizer.demo(database: database),
            database: database,
            modelContainer: container,
            isDemo: true
        )
    }
}

/// Launch options read from the process arguments / user defaults.
struct LaunchArguments {
    var isDemo: Bool
    var isRunningTests: Bool
    /// Tab to open first: "today", "log", "exercise" or "history".
    var initialTab: String?
    /// In demo mode, pre-load a sample photo on the Log tab.
    var demoPhoto: Bool

    static var current: LaunchArguments {
        let defaults = UserDefaults.standard
        let env = ProcessInfo.processInfo.environment
        return LaunchArguments(
            isDemo: defaults.bool(forKey: "demoMode"),
            isRunningTests: env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil,
            initialTab: defaults.string(forKey: "initialTab"),
            demoPhoto: defaults.bool(forKey: "demoPhoto")
        )
    }
}
