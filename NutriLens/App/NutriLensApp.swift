import NutriCore
import SwiftData
import SwiftUI

@main
struct NutriLensApp: App {
    @State private var environment = AppEnvironment.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
        }
        .modelContainer(environment.modelContainer)
    }
}

/// User preferences stored in `UserDefaults` via `@AppStorage` (included in backups).
enum SettingsKey {
    static let dailyCalorieTarget = "dailyCalorieTarget"
    static let proteinTarget = "proteinTarget"
    static let carbohydrateTarget = "carbohydrateTarget"
    static let fatTarget = "fatTarget"
    /// `ExerciseCreditPolicy.Source.rawValue`.
    static let creditSource = "creditSource"
    static let creditFraction = "creditFraction"
    /// Plan start, seconds since 1970.
    static let planStartDate = "planStartDate"
    static let goalWeightKg = "goalWeightKg"
    static let sleepGoalHours = "sleepGoalHours"
    static let stepLengthMeters = "stepLengthMeters"
    static let dailyStepGoal = "dailyStepGoal"
    static let lastHealthSync = "lastHealthSync"
    /// Set once this install has pulled its whole history back from Apple Health.
    static let fullHealthRestoreDone = "fullHealthRestoreDone"
    /// Set once records made before iCloud sync carry this device's stamp (see `CloudDeduplicator`).
    static let cloudOriginsStamped = "cloudOriginsStamped"
    /// "health" (use Apple Health), or a `Sex` raw value.
    static let profileSex = "profileSex"
    /// 0 = use Apple Health.
    static let profileAge = "profileAge"
    /// 0 = use Apple Health.
    static let profileHeightCm = "profileHeightCm"
    static let asianCutoffs = "asianCutoffs"
    /// Your usual amounts for dishes you make your way: JSON `{dishID: {componentID: amount}}`.
    static let dishRecipeDefaults = "dishRecipeDefaults"

    // Automatic backup to a folder (device-specific, not part of backups).
    /// Bookmark of the folder you chose (e.g. iCloud Drive/NutriLens Backups).
    static let autoBackupFolder = "autoBackupFolder"
    static let autoBackupFolderName = "autoBackupFolderName"
    /// `BackupFrequency.rawValue`.
    static let autoBackupFrequency = "autoBackupFrequency"
    static let autoBackupPhotos = "autoBackupPhotos"
    /// When this device last wrote / last considered writing a backup (seconds since 1970).
    static let autoBackupLastWrite = "autoBackupLastWrite"
    static let autoBackupLastCheck = "autoBackupLastCheck"
    static let autoBackupLastFile = "autoBackupLastFile"
    /// Fingerprint of the last backup written, to skip writing when nothing changed.
    static let autoBackupLastHash = "autoBackupLastHash"
    /// Other devices' files already merged: file name → modification time.
    static let autoBackupImported = "autoBackupImported"
    /// Settings as last agreed with the other devices, for a three-way merge.
    static let autoBackupSettingsBase = "autoBackupSettingsBase"
    /// Random ID of this installation, used in backup file names.
    static let deviceID = "deviceID"
}

enum SettingsDefault {
    static let dailyCalorieTarget = 2_000.0
    /// The plan suggests roughly 130–160 g protein a day.
    static let proteinTarget = 140.0
    static let carbohydrateTarget = 230.0
    static let fatTarget = 65.0
    static let creditSource = ExerciseCreditPolicy.Source.workoutsAndSteps.rawValue
    static let creditFraction = 0.5
    /// 21 October 2026, the plan's date.
    static var planStartDate: Double {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21)) ?? .now
        return date.timeIntervalSince1970
    }
    static let goalWeightKg = PlanContent.homeStrength12Week.goalWeightKg ?? 75
    /// The plan aims for 7–9 hours.
    static let sleepGoalHours = 8.0
    /// The plan's planning value; calibrate with measured distance ÷ steps.
    static let stepLengthMeters = StepEnergy.defaultStepLengthMeters
    static let dailyStepGoal = 7_500.0
}

extension UserDefaults {
    var creditPolicy: ExerciseCreditPolicy {
        let source = ExerciseCreditPolicy.Source(rawValue: string(forKey: SettingsKey.creditSource) ?? SettingsDefault.creditSource) ?? .workoutsAndSteps
        let fraction = object(forKey: SettingsKey.creditFraction) as? Double ?? SettingsDefault.creditFraction
        return ExerciseCreditPolicy(source: source, fraction: fraction)
    }
}
