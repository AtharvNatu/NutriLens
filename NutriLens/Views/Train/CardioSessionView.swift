import NutriCore
import SwiftData
import SwiftUI

/// Indoor walk (count-up toward a target) or the walk/jog interval progression, with cues.
struct CardioSessionView: View {
    enum Mode {
        case walk(targetMinutes: Int)
        case intervals(JogStage)
    }

    let mode: Mode

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date?
    @State private var pausedTotal: TimeInterval = 0
    @State private var pausedAt: Date?
    @State private var bodyMass: Double?
    @State private var saving = false
    @State private var message: String?
    @State private var stepCounter = StepCounter()
    @AppStorage(SettingsKey.stepLengthMeters) private var stepLength = SettingsDefault.stepLengthMeters

    private var intervals: [TimedInterval] {
        if case .intervals(let stage) = mode { return PlanEngine.intervals(for: stage) }
        return []
    }

    private var exercise: Exercise? {
        switch mode {
        case .walk: env.plan.exercise("C1")
        case .intervals: env.plan.exercise("C2")
        }
    }

    private func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let pausedNow = pausedAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(startedAt) - pausedTotal - pausedNow)
    }

    /// Current interval and seconds left in it.
    private func phase(at elapsed: TimeInterval) -> (index: Int, interval: TimedInterval, remaining: TimeInterval)? {
        var t = elapsed
        for (i, interval) in intervals.enumerated() {
            if t < Double(interval.seconds) { return (i, interval, Double(interval.seconds) - t) }
            t -= Double(interval.seconds)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let exercise, phaseOrWalkShowsVideo {
                        ExerciseVideoCard(exercise: exercise).frame(maxHeight: 300)
                    }
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        timerContent(now: context.date)
                    }
                    stepsRow
                    controls
                    if let message {
                        Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                    }
                    guidance
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { bodyMass = try? await env.health.latestBodyMass() }
            .onDisappear { stepCounter.stop() }
        }
    }

    private var phaseOrWalkShowsVideo: Bool { true }

    private var title: String {
        switch mode {
        case .walk: "Indoor walk"
        case .intervals(let stage): "Walk/jog · stage \(stage.number)"
        }
    }

    @ViewBuilder private func timerContent(now: Date) -> some View {
        let seconds = elapsed(at: now)
        switch mode {
        case .walk(let target):
            VStack(spacing: 6) {
                Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                ProgressView(value: min(seconds / 60, Double(target)), total: Double(target)).tint(.green)
                Text("Target \(target) moderate minutes. Short bouts count: 3 × 10 minutes works too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .intervals:
            if let p = phase(at: seconds) {
                VStack(spacing: 6) {
                    Text(p.interval.kind.displayName)
                        .font(.title2.bold())
                        .foregroundStyle(p.interval.kind == .jog ? .orange : .green)
                    Text(Duration.seconds(p.remaining.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    Text("Interval \(p.index + 1) of \(intervals.count) · total \(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .sensoryFeedback(.impact(weight: .heavy), trigger: p.index)
            } else {
                Label(startedAt == nil ? "20 minutes: 5 min walk, 6 jog/walk rounds, 3 min walk" : "Session complete", systemImage: "flag.checkered")
                    .font(.title3.bold())
            }
        }
    }

    @ViewBuilder private var stepsRow: some View {
        if startedAt != nil {
            if stepCounter.isCounting {
                HStack {
                    StatTile(title: "Steps", value: stepCounter.steps.formatted(), systemImage: "shoeprints.fill", tint: Palette.steps)
                    StatTile(title: "Distance", value: StepEnergy.distanceKm(steps: Double(stepCounter.steps), stepLengthMeters: stepLength)
                        .formatted(.number.precision(.fractionLength(2))), unit: "km", systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: .teal)
                }
                .card()
            } else if let reason = stepCounter.unavailableReason {
                Label(reason, systemImage: "shoeprints.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack {
            if startedAt == nil {
                Button {
                    let now = Date.now
                    startedAt = now
                    stepCounter.start(from: now)
                } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    if let p = pausedAt { pausedTotal += Date.now.timeIntervalSince(p); pausedAt = nil } else { pausedAt = .now }
                } label: {
                    Label(pausedAt == nil ? "Pause" : "Resume", systemImage: pausedAt == nil ? "pause.fill" : "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await finish() }
                } label: {
                    Label("Finish & save", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(saving)
            }
        }
        .controlSize(.large)
    }

    @ViewBuilder private var guidance: some View {
        if let exercise {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(exercise.steps.enumerated()), id: \.offset) { n, step in
                    Label(step, systemImage: "\(n + 1).circle")
                }
                Label(exercise.adjust, systemImage: "slider.horizontal.3").foregroundStyle(.secondary)
                Text("Ventilate the room, keep water nearby and stop for joint, shin or Achilles pain.")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .card()
        }
    }

    private func finish() async {
        guard let startedAt else { return }
        saving = true
        defer { saving = false }
        let total = elapsed(at: .now)
        let minutes = total / 60
        let end = startedAt.addingTimeInterval(total + pausedTotal)
        stepCounter.stop()
        // Live pedometer steps, or what Apple Health recorded for the session (Simulator, no motion access).
        var steps = Double(stepCounter.steps)
        if steps == 0 { steps = (try? await env.health.stepCount(from: startedAt, to: end)) ?? 0 }
        let log: WorkoutLog
        switch mode {
        case .walk:
            log = WorkoutLog(kind: .walk, title: "Indoor walk", start: startedAt, end: end)
            log.cardioMinutes = minutes
            let fromTime = Training.estimatedEnergy(kind: .walk, minutes: minutes, bodyMassKg: bodyMass)
            let fromSteps = StepEnergy.kilocalories(steps: steps, bodyMassKg: bodyMass ?? EnergyEstimator.defaultBodyMassKg, stepLengthMeters: stepLength)
            // Steps measure the walking actually done; marching in place covers no distance, so keep the higher.
            log.energyKcal = max(fromTime, fromSteps).rounded()
        case .intervals(let stage):
            log = WorkoutLog(kind: .walkJog, title: "Walk/jog stage \(stage.number)", start: startedAt, end: end)
            // The plan counts the 12-minute interval block as moderate; warm-up and cool-down are extra.
            let block = Double(stage.repeats * (stage.jogSeconds + stage.walkSeconds)) / 60
            log.cardioMinutes = min(minutes, block)
            let jogShare = Double(stage.jogSeconds) / Double(stage.jogSeconds + stage.walkSeconds) * (block / 20)
            log.energyKcal = Training.estimatedEnergy(kind: .walkJog, minutes: minutes, bodyMassKg: bodyMass, jogShare: jogShare)
        }
        log.steps = Int(steps)
        log.distanceKm = StepEnergy.distanceKm(steps: steps, stepLengthMeters: stepLength)
        if let week = env.planWeek() { log.planWeek = week }
        log.planWeekday = Calendar.current.component(.weekday, from: startedAt)
        message = await Training.save(log, env: env, context: modelContext)
        if message == nil || message?.hasPrefix("Saved") == true { dismiss() }
    }
}

/// The plan's 10–12 minute recovery yoga: five poses with demos and timers.
struct YogaSessionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var poseStarted: Date?
    @State private var sessionStarted = Date.now
    @State private var before = 3
    @State private var after = 3
    @State private var saving = false

    private var steps: [YogaStep] { env.plan.yoga }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if steps.indices.contains(index), let exercise = env.plan.exercise(steps[index].exerciseID) {
                        let step = steps[index]
                        ExerciseVideoCard(exercise: exercise).frame(maxHeight: 320).frame(maxWidth: .infinity)
                        Text("\(index + 1) / \(steps.count) · \(exercise.name)").font(.title2.bold())
                        Text(step.dose).foregroundStyle(.secondary)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = poseStarted.map { Double(step.seconds) - context.date.timeIntervalSince($0) } ?? Double(step.seconds)
                            HStack {
                                Text(Duration.seconds(max(0, remaining).rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                                Spacer()
                                Button(poseStarted == nil ? "Start timer" : "Restart") { poseStarted = .now }
                                    .buttonStyle(.bordered)
                            }
                            .sensoryFeedback(.success, trigger: remaining <= 0)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(exercise.steps.enumerated()), id: \.offset) { n, s in Label(s, systemImage: "\(n + 1).circle") }
                            Label(exercise.adjust, systemImage: "slider.horizontal.3").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        HStack {
                            Button("Previous", systemImage: "chevron.left") { index -= 1; poseStarted = nil }
                                .disabled(index == 0)
                            Spacer()
                            Button(index == steps.count - 1 ? "Finish" : "Next pose") {
                                if index < steps.count - 1 { index += 1; poseStarted = .now } else { index = steps.count }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        finishSection
                    }
                }
                .padding()
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Gentle yoga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private var finishSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sequence complete", systemImage: "checkmark.seal.fill").font(.title2.bold()).foregroundStyle(.green)
            Text("Energy before and after (1–5), the plan's simple tracker:").font(.subheadline)
            Picker("Before", selection: $before) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
            Picker("After", selection: $after) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
            Button {
                Task { await save() }
            } label: {
                Label("Save yoga session", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(saving)
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let end = Date.now
        let log = WorkoutLog(kind: .yoga, title: "Gentle yoga", start: sessionStarted, end: end)
        let minutes = end.timeIntervalSince(sessionStarted) / 60
        log.energyKcal = Training.estimatedEnergy(kind: .yoga, minutes: minutes, bodyMassKg: try? await env.health.latestBodyMass())
        log.energyRating = after
        log.notes = "Energy before \(before), after \(after)."
        log.planWeek = env.planWeek()
        log.planWeekday = Calendar.current.component(.weekday, from: end)
        _ = await Training.save(log, env: env, context: modelContext)
        dismiss()
    }
}
