import NutriCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.dailyCalorieTarget) private var target = SettingsDefault.dailyCalorieTarget
    @AppStorage(SettingsKey.creditSource) private var creditSource = SettingsDefault.creditSource
    @AppStorage(SettingsKey.creditFraction) private var creditFraction = SettingsDefault.creditFraction
    @AppStorage(SettingsKey.planStartDate) private var planStart = SettingsDefault.planStartDate
    @AppStorage(SettingsKey.goalWeightKg) private var goalWeight = SettingsDefault.goalWeightKg
    @AppStorage(SettingsKey.sleepGoalHours) private var sleepGoal = SettingsDefault.sleepGoalHours
    @AppStorage(SettingsKey.lastHealthSync) private var lastHealthSync = 0.0
    @AppStorage(SettingsKey.stepLengthMeters) private var stepLength = SettingsDefault.stepLengthMeters
    @AppStorage(SettingsKey.dailyStepGoal) private var stepGoal = SettingsDefault.dailyStepGoal
    @AppStorage(SettingsKey.profileSex) private var profileSex = "health"
    @AppStorage(SettingsKey.profileAge) private var profileAge = 0
    @AppStorage(SettingsKey.profileHeightCm) private var profileHeight = 0.0
    @AppStorage(SettingsKey.asianCutoffs) private var asianCutoffs = true
    @State private var healthProfile = HealthProfile()
    @State private var healthMessage: String?
    @State private var backupURL: URL?
    @State private var backupMessage: String?
    @State private var pickerShown = false
    /// What the file picker is for. Kept after it closes: its result arrives after dismissal.
    @State private var pickerMode: PickerMode = .backupFile
    @AppStorage(SettingsKey.autoBackupFolderName) private var backupFolderName = ""
    @AppStorage(SettingsKey.autoBackupFrequency) private var backupFrequency: BackupFrequency = .everyOpen
    @AppStorage(SettingsKey.autoBackupPhotos) private var backupPhotos = true
    @AppStorage(SettingsKey.autoBackupLastWrite) private var lastBackup = 0.0
    @AppStorage(SettingsKey.autoBackupLastFile) private var lastBackupFile = ""
    @State private var hasBackupFolder = AutoBackup.folderName() != nil

    private enum PickerMode { case backupFile, folder }

    var body: some View {
        NavigationStack {
            Form {
                calorieSection
                stepsSection
                profileSection
                macroSection
                planSection
                syncSection
                autoBackupSection
                healthSection
                recognitionSection
                Section("Privacy") {
                    Text("Everything stays on your devices. No account, no analytics, no network requests.")
                        .font(.subheadline)
                }
                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    Text("\(env.database.foods.count) foods with typical per-100 g values (per 100 ml for drinks and milk). Training plan: 12-week Home Strength & Fat Loss.")
                        .font(.subheadline)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $pickerShown, allowedContentTypes: pickerMode == .folder ? [.folder] : [.json]) { result in
                switch pickerMode {
                case .folder: chooseBackupFolder(result)
                case .backupFile: importBackup(result)
                }
            }
        }
    }

    // MARK: Sections

    /// "1.1 (2)": the installed app's version and build.
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    /// Set each day from the plan; shown here, not set by hand.
    private var macroSection: some View {
        let t = env.macroTargets(on: env.now)
        return Section {
            LabeledContent("Today", value: t.dayTitle)
            LabeledContent("Protein", value: Format.grams(t.protein))
            LabeledContent("Carbohydrates", value: Format.grams(t.carbohydrates))
            LabeledContent("Fat", value: Format.grams(t.fat))
            LabeledContent("Usual steps", value: Int(t.expectedSteps).formatted())
            LabeledContent("Weight used", value: env.macroInputs.bodyMassKg.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kg" } ?? "70 kg (no weight yet)")
        } header: {
            Text("Macro targets")
        } footer: {
            Text("Set each day from that day's plan session and your usual steps (last 14 days, else 10,000). Protein 130–160 g, highest on strength days. Fat 25–30 %. Carbs are the rest, so they rise on training days.")
        }
    }

    private var calorieSection: some View {
        Section {
            Stepper(value: $target, in: 800...6_000, step: 50) {
                LabeledContent("Daily calories", value: "\(Format.kcal(target)) kcal")
            }
            Picker("Add back exercise", selection: $creditSource) {
                ForEach(ExerciseCreditPolicy.Source.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
            }
            if creditSource != ExerciseCreditPolicy.Source.none.rawValue {
                VStack(alignment: .leading) {
                    LabeledContent("Share added", value: creditFraction.formatted(.percent.precision(.fractionLength(0))))
                    Slider(value: $creditFraction, in: 0.25...1, step: 0.25)
                }
            }
        } header: {
            Text("Calorie target")
        } footer: {
            Text("Workouts (and walking, with \"Workouts + steps\") add to the day's budget. Adding back only part allows for trackers' overestimates.")
        }
    }

    private var profileSection: some View {
        Section {
            Picker("Sex", selection: $profileSex) {
                Text("From Apple Health" + (healthProfile.sex.map { " (\($0.rawValue))" } ?? "")).tag("health")
                Text("Male").tag(Sex.male.rawValue)
                Text("Female").tag(Sex.female.rawValue)
                Text("Not set").tag(Sex.notSet.rawValue)
            }
            Stepper(value: $profileAge, in: 0...100) {
                LabeledContent("Age", value: profileAge > 0 ? "\(profileAge)" : (healthAge.map { "\($0) (Apple Health)" } ?? "Not set"))
            }
            Stepper(value: $profileHeight, in: 0...230, step: 1) {
                LabeledContent("Height", value: profileHeight > 0 ? "\(Int(profileHeight)) cm" : (healthProfile.heightCm.map { "\(Int($0)) cm (Apple Health)" } ?? "Not set"))
            }
            Toggle("Asian-Indian BMI and waist cut-offs", isOn: $asianCutoffs)
        } header: {
            Text("Profile")
        } footer: {
            Text("Used for the healthy ranges in Body. 0 uses Apple Health's value. Indian cut-offs: BMI 18.0–22.9, waist under 90 cm (men) or 80 cm (women).")
        }
        .task { healthProfile = await env.health.healthProfile() }
    }

    private var healthAge: Int? {
        healthProfile.birthDate.flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year }
    }

    private var stepsSection: some View {
        Section {
            Stepper(value: $stepGoal, in: 2_000...20_000, step: 500) {
                LabeledContent("Daily step goal", value: Int(stepGoal).formatted())
            }
            Stepper(value: $stepLength, in: 0.4...1.2, step: 0.01) {
                LabeledContent("Step length", value: "\(stepLength.formatted(.number.precision(.fractionLength(2)))) m")
            }
        } header: {
            Text("Steps")
        } footer: {
            Text("Steps outside workouts count as walking energy (about 0.5 kcal per kg per km). Step length = a measured distance ÷ the steps it took.")
        }
    }

    private var planSection: some View {
        Section {
            DatePicker("Plan start", selection: Binding(get: { Date(timeIntervalSince1970: planStart) }, set: { planStart = $0.timeIntervalSince1970 }), displayedComponents: .date)
            if let week = env.planWeek() {
                LabeledContent("Current week", value: "\(week) · \(PlanPhase.forWeek(week).name)")
            }
            Stepper(value: $goalWeight, in: 40...200, step: 0.5) {
                LabeledContent("Goal weight", value: "\(goalWeight.formatted()) kg")
            }
            Stepper(value: $sleepGoal, in: 6...10, step: 0.5) {
                LabeledContent("Sleep goal", value: "\(sleepGoal.formatted()) h")
            }
        } header: {
            Text("Training plan")
        } footer: {
            Text("Weeks count from the start date. After a week or more off, restart or repeat a week.")
        }
    }

    private var syncSection: some View {
        Section {
            if env.usesCloudKit {
                Label("iCloud sync is on", systemImage: "icloud.fill")
            } else {
                Button {
                    Task { await env.syncFromHealth() }
                } label: {
                    HStack {
                        Label("Sync from Apple Health now", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if env.isSyncing { ProgressView() }
                    }
                }
                .disabled(!env.health.isAvailable || env.isSyncing)
            }
            Button {
                Task { await env.syncFromHealth(fullHistory: true) }
            } label: {
                HStack {
                    Label("Restore all history from Apple Health", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    if env.usesCloudKit && env.isSyncing { ProgressView() }
                }
            }
            .disabled(!env.health.isAvailable || env.isSyncing)
            if let report = env.lastSync {
                Text(report.summary).font(.footnote).foregroundStyle(.secondary)
            } else if lastHealthSync > 0 && !env.usesCloudKit {
                Text("Last synced \(Date(timeIntervalSince1970: lastHealthSync).formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = env.syncError { Text(error).font(.footnote).foregroundStyle(.orange) }
            Button("Create a backup file", systemImage: "doc.badge.arrow.up") {
                do {
                    backupURL = try BackupService.writeTemporaryFile(context: modelContext)
                    backupMessage = nil
                } catch {
                    backupMessage = "Couldn't create the backup: \(error.localizedDescription)"
                }
            }
            if let backupURL {
                ShareLink(item: backupURL) {
                    Label("Share \(backupURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                }
            }
            Button("Import a backup file", systemImage: "square.and.arrow.down") { openPicker(.backupFile) }
            if let backupMessage { Text(backupMessage).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Sync between your iPhone and iPad")
        } footer: {
            Text(env.usesCloudKit
                 ? "Everything, including photos, My foods and settings, syncs through your private iCloud. Both devices need the same Apple ID with iCloud on."
                 : "Meals, scale readings and workouts sync through Apple Health. Turn on iCloud › Health on both devices. Photos, My foods and settings travel with Automatic backup below.")
        }
    }

    private var autoBackupSection: some View {
        Section {
            if hasBackupFolder {
                LabeledContent("Folder", value: backupFolderName)
                Picker("Back up", selection: $backupFrequency) {
                    ForEach(BackupFrequency.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Include meal photos", isOn: $backupPhotos)
                Button {
                    Task {
                        await env.importFromBackupFolder()
                        await env.backUpToFolder(force: true)
                    }
                } label: {
                    HStack {
                        Label("Back up now", systemImage: "externaldrive.badge.checkmark")
                        Spacer()
                        if env.isBackingUp { ProgressView() }
                    }
                }
                .disabled(env.isBackingUp)
                Button("Choose another folder", systemImage: "folder") { openPicker(.folder) }
                Button("Stop automatic backup", systemImage: "folder.badge.minus") {
                    AutoBackup.forgetFolder()
                    hasBackupFolder = false
                }
                if lastBackup > 0 {
                    Text("Last backup \(Date(timeIntervalSince1970: lastBackup).formatted(.relative(presentation: .named))): \(lastBackupFile)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Button("Choose a backup folder", systemImage: "folder.badge.plus") { openPicker(.folder) }
            }
            if let message = env.backupMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
            if let error = env.backupError { Text(error).font(.footnote).foregroundStyle(.orange) }
        } header: {
            Text("Automatic backup")
        } footer: {
            Text(env.usesCloudKit
                 ? "A safety copy in a folder you choose (iCloud sync already keeps your devices in step). Keeps the last \(AutoBackup.keepCount) files."
                 : "Pick the same iCloud Drive folder on iPhone and iPad. On opening, NutriLens merges the other device's newest backup, then saves its own. Each device keeps its last \(AutoBackup.keepCount) files. After reinstalling, pick the folder again to restore.")
        }
    }

    private func openPicker(_ mode: PickerMode) {
        pickerMode = mode
        pickerShown = true
    }

    private func chooseBackupFolder(_ result: Result<URL, Error>) {
        do {
            try AutoBackup.chooseFolder(try result.get())
            hasBackupFolder = true
            Task {
                await env.importFromBackupFolder()
                await env.recordRecentDays()
                await env.backUpToFolder(force: true)
            }
        } catch {
            backupMessage = "Couldn't use that folder: \(error.localizedDescription)"
        }
    }

    private var healthSection: some View {
        Section {
            if env.health.isAvailable {
                Button("Request Apple Health access", systemImage: "heart.fill") {
                    Task {
                        do {
                            try await env.health.requestAuthorization()
                            healthMessage = "Done. To change access, open Settings › Health › Data Access & Devices › NutriLens."
                        } catch {
                            healthMessage = error.localizedDescription
                        }
                        env.healthDidChange()
                    }
                }
                if let healthMessage {
                    Text(healthMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Label("Apple Health isn't available on this device.", systemImage: "heart.slash")
            }
        } header: {
            Text("Apple Health")
        } footer: {
            Text("Reads activity, workouts, sleep and body measurements. Writes meals, workouts, sleep and scale readings.")
        }
    }

    private var recognitionSection: some View {
        Section {
            LabeledContent("Food photos", value: env.recognizer.engine.displayName)
            LabeledContent("Scale screenshots", value: "Apple Vision text recognition")
        } header: {
            Text("On-device recognition")
        } footer: {
            switch env.recognizer.engine {
            case .visionBuiltIn:
                Text("Apple's on-device image analysis only. You confirm the dish and portion.")
            case .mock:
                Text("Demo mode: recognition returns sample results.")
            }
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let backup = try BackupService.decode(Data(contentsOf: url))
            let report = try BackupService.merge(backup, into: modelContext)
            backupMessage = "Imported: \(report.summary)"
            env.healthDidChange()
        } catch {
            backupMessage = "Couldn't import: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview())
}
