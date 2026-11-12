import NutriCore
import SwiftData
import SwiftUI

/// A guided strength session: demo video, prescription, last time's numbers and advice,
/// set-by-set logging and a rest timer. Saved to the log and Apple Health at the end.
struct StrengthSessionView: View {
    let day: PlanDay
    let week: Int
    let readiness: Readiness

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutLog.start) private var logs: [WorkoutLog]

    @State private var startedAt = Date.now
    @State private var index = 0
    @State private var logged: [String: [LoggedSet]] = [:]
    @State private var skipped: Set<String> = []
    @State private var reps = 10
    @State private var load = 5.0
    @State private var rir = 2
    @State private var restUntil: Date?
    @State private var showingFinish = false
    @State private var confirmingCancel = false

    private var items: [(planned: PlannedExercise, prescription: Prescription)] {
        Training.adjusted(PlanEngine.session(for: day, week: week), readiness: readiness)
    }

    private var current: (planned: PlannedExercise, prescription: Prescription)? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    progressStrip
                    if let current, let exercise = env.plan.exercise(current.planned.exerciseID) {
                        exerciseSection(exercise, current.planned, current.prescription)
                    }
                }
                .padding()
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { restBanner }
            .navigationTitle(day.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if logged.isEmpty { dismiss() } else { confirmingCancel = true }
                    }
                }
                ToolbarItem(placement: .principal) {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(startedAt)).formatted(.time(pattern: .minuteSecond)))
                            .font(.headline.monospacedDigit())
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { showingFinish = true }
                        .disabled(logged.isEmpty)
                }
            }
            .confirmationDialog("Discard this session?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $showingFinish) {
                FinishStrengthSheet(day: day, week: week, readiness: readiness, startedAt: startedAt,
                                    exercises: items.map { LoggedExercise(exerciseID: $0.planned.exerciseID, sets: logged[$0.planned.exerciseID] ?? [], skipped: skipped.contains($0.planned.exerciseID)) }) {
                    dismiss()
                }
            }
            .onAppear { prepareInputs() }
            .onChange(of: index) { prepareInputs() }
        }
    }

    // MARK: Pieces

    private var progressStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    let done = (logged[item.planned.exerciseID]?.count ?? 0) >= item.prescription.sets
                    Button {
                        index = i
                    } label: {
                        Text(item.planned.exerciseID)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .frame(width: 40, height: 32)
                            .background(i == index ? Color.accentColor : (done ? Color.green.opacity(0.2) : Color.secondary.opacity(0.12)), in: .capsule)
                            .foregroundStyle(i == index ? Color.white : (done ? Color.green : Color.primary))
                    }
                    .accessibilityLabel("Exercise \(i + 1)\(done ? ", done" : "")")
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: Exercise, _ planned: PlannedExercise, _ rx: Prescription) -> some View {
        let sets = logged[exercise.id] ?? []
        let history = Training.history(of: exercise.id, in: logs, weekday: day.weekday)
        ExerciseVideoCard(exercise: exercise)
            .frame(maxHeight: 320)
            .frame(maxWidth: .infinity)
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.numberedName).font(.title2.bold())
            Text("\(rx.label) · rest \(planned.restLabel) · \(PlanPhase.forWeek(week).repsInReserve)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let note = planned.note { Text("Keep this \(note): it's practice, not a second hard session.").font(.caption).foregroundStyle(.orange) }
        }
        if let last = history.last {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last time: " + last.map { "\($0.reps)" }.joined(separator: ", ") + " reps @ " + ProgressionAdvice.kg(last.map(\.loadKg).max() ?? 0))
                    .font(.subheadline.weight(.medium))
                Text(ProgressionAdvisor.advice(history: history, prescription: rx).message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 12))
        }

        // Logged sets.
        VStack(spacing: 6) {
            ForEach(Array(sets.enumerated()), id: \.offset) { n, set in
                HStack {
                    Text("Set \(n + 1)").font(.subheadline.weight(.medium))
                    Spacer()
                    Text(WorkoutLogDetailView.describe(set, timed: rx.seconds) + (rx.perSide ? " / side" : ""))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Remove set", systemImage: "minus.circle") { logged[exercise.id]?.remove(at: n) }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.red)
                }
            }
        }

        // Input for the next set.
        if sets.count < rx.sets + 2 {
            VStack(spacing: 10) {
                Stepper(value: $reps, in: 1...120) {
                    LabeledContent(rx.seconds ? "Seconds\(rx.perSide ? " per side" : "")" : "Reps\(rx.perSide ? " per side" : "")") {
                        Text("\(reps)").font(.title3.bold().monospacedDigit())
                    }
                }
                if exercise.usesLoad {
                    Stepper(value: $load, in: 0...60, step: 0.5) {
                        LabeledContent(exercise.equipment.localizedCaseInsensitiveContains("total") ? "Load (total)" : "Load (each)") {
                            Text(ProgressionAdvice.kg(load)).font(.title3.bold().monospacedDigit())
                        }
                    }
                }
                Picker("Reps left", selection: $rir) {
                    ForEach(0...4, id: \.self) { Text($0 == 4 ? "4+" : "\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Reps left in reserve: finish while good reps remain; stop before form breaks.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    logSet(exercise: exercise, planned: planned, rx: rx)
                } label: {
                    Label(sets.count >= rx.sets ? "Log an extra set" : "Log set \(sets.count + 1) of \(rx.sets)", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }

        HStack {
            Button("Previous", systemImage: "chevron.left") { index -= 1 }
                .disabled(index == 0)
            Spacer()
            Button(skipped.contains(exercise.id) ? "Skipped" : "Skip exercise") {
                skipped.insert(exercise.id)
                if index < items.count - 1 { index += 1 }
            }
            .foregroundStyle(.secondary)
            Spacer()
            Button {
                if index < items.count - 1 { index += 1 } else { showingFinish = true }
            } label: {
                Label(index < items.count - 1 ? "Next" : "Finish", systemImage: "chevron.right").labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.bordered)

        DisclosureGroup("How to do it") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(exercise.steps.enumerated()), id: \.offset) { n, step in
                    Label(step, systemImage: "\(n + 1).circle")
                }
                Label(exercise.watchFor, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                Label(exercise.adjust, systemImage: "slider.horizontal.3").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.top, 6)
        }
    }

    @ViewBuilder private var restBanner: some View {
        if let restUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = restUntil.timeIntervalSince(context.date)
                HStack {
                    Image(systemName: "timer")
                    Text(remaining > 0 ? "Rest \(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))" : "Rest done: next set when breathing settles")
                        .font(.headline.monospacedDigit())
                    Spacer()
                    Button(remaining > 0 ? "Skip" : "OK") { self.restUntil = nil }
                        .buttonStyle(.bordered)
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 16).fill(remaining > 0 ? Color.orange.opacity(0.22) : Color.green.opacity(0.25)))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                .sensoryFeedback(.success, trigger: remaining <= 0)
            }
        }
    }

    private func prepareInputs() {
        guard let current, let exercise = env.plan.exercise(current.planned.exerciseID) else { return }
        let rx = current.prescription
        let last = logged[exercise.id]?.last ?? Training.history(of: exercise.id, in: logs, weekday: day.weekday).last?.last
        reps = last?.reps ?? (rx.seconds ? rx.low : (rx.low + rx.high) / 2)
        load = last?.loadKg ?? (exercise.usesLoad ? 5 : 0)
        rir = last?.repsInReserve ?? (PlanPhase.forWeek(week) == .build ? 2 : 3)
    }

    private func logSet(exercise: Exercise, planned: PlannedExercise, rx: Prescription) {
        logged[exercise.id, default: []].append(LoggedSet(reps: reps, loadKg: exercise.usesLoad ? load : 0, repsInReserve: rir))
        skipped.remove(exercise.id)
        restUntil = .now.addingTimeInterval(Double(planned.restSeconds.lowerBound))
        if (logged[exercise.id]?.count ?? 0) == rx.sets, index < items.count - 1 {
            index += 1
        }
    }
}

/// Summary, energy estimate and how-you-felt before saving the session.
private struct FinishStrengthSheet: View {
    let day: PlanDay
    let week: Int
    let readiness: Readiness
    let startedAt: Date
    let exercises: [LoggedExercise]
    let onSaved: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var endedAt = Date.now
    @State private var bodyMass: Double?
    @State private var energy: Double?
    @State private var rating = 3
    @State private var notes = ""
    @State private var walkMinutes = 0.0
    @State private var isSaving = false
    @State private var error: String?

    private var minutes: Double { endedAt.timeIntervalSince(startedAt) / 60 }
    private var estimate: Double {
        Training.estimatedEnergy(kind: .strength, minutes: minutes, bodyMassKg: bodyMass)
            + Training.estimatedEnergy(kind: .walk, minutes: walkMinutes, bodyMassKg: bodyMass)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Duration", value: Format.duration(endedAt.timeIntervalSince(startedAt)))
                    LabeledContent("Sets logged", value: "\(exercises.flatMap(\.sets).count)")
                    LabeledContent("Exercises", value: "\(exercises.filter { !$0.sets.isEmpty }.count) of \(exercises.count)")
                }
                Section {
                    HStack {
                        Text("Active energy")
                        Spacer()
                        TextField(Format.kcal(estimate), value: $energy, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                    Stepper(value: $walkMinutes, in: 0...60, step: 5) {
                        LabeledContent("Easy walk after", value: "\(Int(walkMinutes)) min")
                    }
                } footer: {
                    Text("Blank uses the estimate, ≈ \(Format.kcal(estimate)) kcal. If Apple Watch recorded it, type its value.")
                }
                Section("How did it feel?") {
                    Picker("Energy", selection: $rating) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Technique, discomfort or recovery notes", text: $notes, axis: .vertical)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Finish session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("Save") { Task { await save() } } }
                }
            }
            .task {
                bodyMass = try? await env.health.latestBodyMass()
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let log = WorkoutLog(kind: .strength, title: day.title, start: startedAt, end: endedAt)
        log.planWeek = week
        log.planWeekday = day.weekday
        log.readinessRaw = readiness.rawValue
        log.energyRating = rating
        log.notes = notes
        log.exercises = exercises
        log.energyKcal = energy ?? estimate
        log.cardioMinutes = walkMinutes
        if let message = await Training.save(log, env: env, context: modelContext) {
            error = message
            if message.hasPrefix("Couldn't") { return }
        }
        dismiss()
        onSaved()
    }
}
