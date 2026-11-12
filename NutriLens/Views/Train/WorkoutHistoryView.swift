import NutriCore
import SwiftData
import SwiftUI

/// Sessions logged in NutriLens (with their sets) and other workouts from Apple Health.
struct WorkoutHistoryView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var healthWorkouts: [WorkoutSummary] = []
    @State private var showingAdd = false

    var body: some View {
        List {
            Section("Logged in NutriLens") {
                if logs.isEmpty {
                    Text("Sessions you log from the Train tab appear here.").foregroundStyle(.secondary)
                }
                ForEach(logs) { log in
                    let watch = Training.recording(of: log, in: healthWorkouts)
                    NavigationLink {
                        WorkoutLogDetailView(log: log, recording: watch)
                    } label: {
                        WorkoutRow(workout: WorkoutSummary(id: log.id, name: log.title, symbolName: log.kind.symbolName, start: log.start, end: log.end,
                                                           energyBurned: watch?.energyBurned ?? log.energyKcal,
                                                           sourceName: Self.detail(log) + (watch.map { " · \($0.sourceName)" } ?? "")))
                    }
                }
                .onDelete { offsets in
                    let doomed = offsets.map { logs[$0] }
                    Task { for log in doomed { await Training.delete(log, env: env, context: modelContext) } }
                }
            }
            Section {
                if otherWorkouts.isEmpty {
                    Text("Workouts from Apple Watch and other apps appear here.").foregroundStyle(.secondary)
                }
                ForEach(otherWorkouts) { WorkoutRow(workout: $0) }
            } header: {
                Text("Other workouts in Apple Health (30 days)")
            }
        }
        .navigationTitle("Workout history")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add workout", systemImage: "plus") { showingAdd = true }
            }
        }
        .sheet(isPresented: $showingAdd) { AddWorkoutView() }
        .task(id: env.healthRevision) {
            let start = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
            healthWorkouts = ((try? await env.health.workouts(from: start, to: .now.addingTimeInterval(60))) ?? []).filter { !Training.isFromNutriLens($0) }
        }
    }

    /// Workouts from the Watch and other apps, without those recorded during a session logged here (shown with it).
    private var otherWorkouts: [WorkoutSummary] {
        let recordings = Set(logs.compactMap { Training.recording(of: $0, in: healthWorkouts)?.id })
        return healthWorkouts.filter { !recordings.contains($0.id) }
    }

    static func detail(_ log: WorkoutLog) -> String {
        log.kind == .strength ? "\(log.completedSets) sets\(log.planWeek.map { " · week \($0)" } ?? "")" : log.kind.displayName
    }
}

struct WorkoutLogDetailView: View {
    let log: WorkoutLog
    /// The Watch's recording of this session, if any.
    var recording: WorkoutSummary? = nil
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: log.start.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Format.duration(log.duration))
                if let recording, let kcal = recording.energyBurned {
                    LabeledContent("Energy", value: "\(Format.kcal(kcal)) kcal")
                    LabeledContent("Recorded by", value: "\(recording.sourceName) · \(Format.duration(recording.duration))")
                } else {
                    LabeledContent("Energy", value: "\(Format.kcal(log.energyKcal)) kcal (estimate)")
                }
                if log.cardioMinutes > 0 { LabeledContent("Cardio", value: "\(Int(log.cardioMinutes)) min") }
                if log.steps > 0 {
                    LabeledContent("Steps", value: "\(log.steps.formatted()) · \(log.distanceKm.formatted(.number.precision(.fractionLength(2)))) km")
                }
                if let week = log.planWeek { LabeledContent("Plan week", value: "\(week) · \(PlanPhase.forWeek(week).name)") }
                if log.energyRating > 0 { LabeledContent("Energy (1–5)", value: "\(log.energyRating)") }
                LabeledContent("Version", value: log.readiness.title)
                LabeledContent("Apple Health", value: log.healthKitID == nil ? "Not saved" : "Saved")
            }
            ForEach(log.exercises) { item in
                if let exercise = env.plan.exercise(item.exerciseID) {
                    Section(exercise.numberedName) {
                        if item.sets.isEmpty {
                            Text(item.skipped ? "Skipped" : "No sets").foregroundStyle(.secondary)
                        }
                        ForEach(Array(item.sets.enumerated()), id: \.offset) { n, set in
                            LabeledContent("Set \(n + 1)") {
                                Text(Self.describe(set, timed: exercise.timed)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            if !log.notes.isEmpty {
                Section("Notes") { Text(log.notes) }
            }
        }
        .navigationTitle(log.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    static func describe(_ set: LoggedSet, timed: Bool) -> String {
        var text = "\(set.reps)" + (timed ? " s" : "") + " · " + ProgressionAdvice.kg(set.loadKg)
        if let rir = set.repsInReserve { text += " · \(rir) left" }
        return text
    }
}

/// Manual workout entry. Calories are estimated from MET × weight × time unless entered.
struct AddWorkoutView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ActivityKind.walking
    @State private var start = Date.now.addingTimeInterval(-30 * 60)
    @State private var minutes = 30.0
    @State private var enterCaloriesManually = false
    @State private var manualCalories: Double?
    @State private var bodyMass: Double?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var weight: Double { bodyMass ?? EnergyEstimator.defaultBodyMassKg }
    private var estimate: Double { EnergyEstimator.activityKilocalories(met: kind.met, bodyMassKg: weight, minutes: minutes).rounded() }
    private var calories: Double { enterCaloriesManually ? (manualCalories ?? 0) : estimate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Activity", selection: $kind) {
                        ForEach(ActivityKind.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                    }
                    DatePicker("Start", selection: $start, in: ...Date.now)
                    Stepper(value: $minutes, in: 5...600, step: 5) {
                        LabeledContent("Duration", value: Format.duration(minutes * 60))
                    }
                }
                Section {
                    Toggle("Enter calories myself", isOn: $enterCaloriesManually)
                    if enterCaloriesManually {
                        HStack {
                            TextField("Active energy", value: $manualCalories, format: .number)
                                .keyboardType(.numberPad)
                            Text("kcal").foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("Estimated active energy") {
                            Text("\(Format.kcal(calories)) kcal").monospacedDigit()
                        }
                    }
                } footer: {
                    if !enterCaloriesManually {
                        Text("Active energy estimate at \(weight.formatted(.number.precision(.fractionLength(0...1)))) kg\(bodyMass == nil ? " (assumed)" : "").")
                    }
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Save") { Task { await save() } } }
                }
            }
            .task { bodyMass = try? await env.health.latestBodyMass() }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let logKind: WorkoutLogKind = switch kind {
        case .walking, .hiking: .walk
        case .running: .walkJog
        case .strength: .strength
        case .yoga: .yoga
        default: .other
        }
        let log = WorkoutLog(kind: logKind, title: kind.displayName, start: start, end: start.addingTimeInterval(minutes * 60))
        log.energyKcal = calories
        if [.walking, .running, .hiking, .cycling, .swimming, .hiit, .dance].contains(kind) { log.cardioMinutes = minutes }
        log.planWeek = env.planWeek(on: start)
        let message = await Training.save(log, env: env, context: modelContext)
        if let message, message.hasPrefix("Couldn't") {
            errorMessage = message
        } else {
            dismiss()
        }
    }
}
