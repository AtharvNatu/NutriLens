import NutriCore
import SwiftUI

/// Summary and the plan's 1–5 energy rating, then save to Apple Health and send to the iPhone.
struct FinishView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(PhoneLink.self) private var link
    @State private var rating = 3
    @State private var confirmingDiscard = false
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(workout.active?.title ?? "Session").font(.headline)
                summary
                Text("How did it feel?").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { n in
                        Button("\(n)") { rating = n }
                            .buttonStyle(.plain)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(Circle().fill(n == rating ? Color.green : Color.white.opacity(0.12)))
                            .foregroundStyle(n == rating ? .black : .white)
                            .accessibilityAddTraits(n == rating ? .isSelected : [])
                    }
                }
                Text("1 drained · 5 great").font(.caption2).foregroundStyle(.secondary)
                if let saveError {
                    Text(saveError).font(.footnote).foregroundStyle(.orange)
                    Button("Send to iPhone only") { Task { await save(toHealth: false) } }
                }
                Button {
                    Task { await save() }
                } label: {
                    if workout.phase == .saving { ProgressView() } else { Text("Save").frame(maxWidth: .infinity) }
                }
                .tint(.green)
                .disabled(workout.phase == .saving)
                Button("Discard", role: .destructive) { confirmingDiscard = true }
                    .disabled(workout.phase == .saving)
            }
        }
        .confirmationDialog("Discard this session?", isPresented: $confirmingDiscard) {
            Button("Discard", role: .destructive) { workout.discard() }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(ElapsedTime.format(workout.elapsed(at: .now)), systemImage: "timer").foregroundStyle(.yellow)
            Label("\(Int(workout.activeEnergy)) kcal", systemImage: "flame.fill").foregroundStyle(.orange)
            if workout.averageHeartRate > 0 {
                Label("\(Int(workout.averageHeartRate)) bpm avg", systemImage: "heart.fill").foregroundStyle(.red)
            }
            if case .strength(let session) = workout.active {
                Label(session.completedSets == 1 ? "1 set" : "\(session.completedSets) sets", systemImage: "dumbbell.fill").foregroundStyle(.green)
            }
        }
        .font(.body.monospacedDigit())
    }

    private func save(toHealth: Bool = true) async {
        guard let active = workout.active, let start = workout.startDate else { return }
        let end = workout.endDate ?? .now
        let calendar = Calendar.current
        let week = PlanEngine.week(for: start, startDate: link.planStart)
        var exercises: [LoggedExercise] = []
        var weekday = calendar.component(.weekday, from: start)
        var readiness = link.context?.readiness(on: start) ?? .ready
        var stage: JogStage?
        switch active {
        case .strength(let session):
            exercises = session.exercises
            weekday = session.day.weekday
            readiness = session.readiness
        case .intervals(let s):
            stage = s
        case .walk, .yoga:
            break
        }
        let payload = WorkoutPayload.watchSession(
            kind: active.kind, title: active.title, end: end, activeSeconds: workout.elapsed(at: end),
            planWeek: week, planWeekday: weekday, readiness: readiness, energyRating: rating, exercises: exercises,
            jogStage: stage, steps: workout.steps, distanceMeters: workout.distanceMeters,
            stepLengthMeters: link.context?.stepLengthMeters ?? StepEnergy.defaultStepLengthMeters
        )
        do {
            let id = workout.recordID
            let energy = workout.activeEnergy
            let healthID = toHealth ? try await workout.save(payload: payload) : nil
            link.send(WatchWorkoutRecord(id: id, healthKitID: healthID, start: start, end: end, energyKcal: energy, payload: payload))
            Haptics.play(.success)
            if toHealth { workout.close() } else { workout.discard() }
        } catch {
            saveError = "Couldn't save to Health: \(error.localizedDescription)"
        }
    }
}
