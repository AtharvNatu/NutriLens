import NutriCore
import SwiftUI

/// Indoor walk: counts up toward the plan's minutes, with a tap when the target is reached.
struct WalkView: View {
    let targetMinutes: Int
    @Environment(WorkoutManager.self) private var workout
    @State private var announced = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = workout.elapsed(at: context.date)
            let target = Double(targetMinutes * 60)
            VStack(spacing: 6) {
                Text("Walk").font(.headline).foregroundStyle(.green)
                Text(ElapsedTime.format(elapsed))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                ProgressView(value: min(elapsed, target), total: target)
                    .tint(.green)
                Text(elapsed >= target ? "Target reached" : "of \(targetMinutes) min · talk, don't sing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: elapsed >= target) { _, reached in
                if reached && !announced {
                    announced = true
                    Haptics.play(.success)
                }
            }
        }
    }
}

/// Walk/jog intervals: the current stage, time left in it, and a tap at every change.
struct IntervalsView: View {
    let stage: JogStage
    @Environment(WorkoutManager.self) private var workout

    private var intervals: [TimedInterval] { PlanEngine.intervals(for: stage) }

    private func phase(at elapsed: TimeInterval) -> (index: Int, interval: TimedInterval, remaining: TimeInterval)? {
        var t = elapsed
        for (i, interval) in intervals.enumerated() {
            if t < Double(interval.seconds) { return (i, interval, Double(interval.seconds) - t) }
            t -= Double(interval.seconds)
        }
        return nil
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let current = phase(at: workout.elapsed(at: context.date))
            VStack(spacing: 6) {
                if let current {
                    Text(current.interval.kind.displayName)
                        .font(.headline)
                        .foregroundStyle(current.interval.kind == .jog ? .orange : .green)
                    Text(ElapsedTime.format(current.remaining.rounded(.up)))
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("\(current.index + 1) of \(intervals.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let next = intervals.dropFirst(current.index + 1).first {
                        Text("Next: \(next.kind.displayName)").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Done").font(.title2.bold()).foregroundStyle(.green)
                    Text("Swipe right to end.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .onChange(of: current?.index) { _, index in
                guard let index else {
                    Haptics.play(.success)
                    return
                }
                Haptics.play(intervals[index].kind == .jog ? .start : .stop)
            }
        }
    }
}

/// The plan's recovery yoga: one pose at a time with its hold timer.
struct YogaView: View {
    @State private var index = 0
    @State private var poseStarted = Date.now

    private let plan = PlanContent.homeStrength12Week
    private var steps: [YogaStep] { plan.yoga }

    var body: some View {
        if steps.indices.contains(index), let exercise = plan.exercise(steps[index].exerciseID) {
            let step = steps[index]
            ScrollView {
                VStack(spacing: 6) {
                    Text("\(index + 1) of \(steps.count)").font(.footnote).foregroundStyle(.secondary)
                    Text(exercise.name).font(.headline).multilineTextAlignment(.center)
                    TimelineView(.periodic(from: poseStarted, by: 1)) { context in
                        let remaining = Double(step.seconds) - context.date.timeIntervalSince(poseStarted)
                        Text(remaining > 0 ? ElapsedTime.format(remaining.rounded(.up)) : "Done")
                            .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(remaining > 0 ? .purple : .green)
                    }
                    Text(step.dose).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(index == steps.count - 1 ? "Last pose done" : "Next pose") {
                        index += 1
                        poseStarted = .now
                    }
                    .tint(.purple)
                }
            }
            .task(id: index) {
                try? await Task.sleep(for: .seconds(step.seconds))
                guard !Task.isCancelled else { return }
                Haptics.play(.success)
            }
        } else {
            VStack(spacing: 6) {
                Text("All poses done").font(.headline).foregroundStyle(.green)
                Text("Swipe right to end.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
