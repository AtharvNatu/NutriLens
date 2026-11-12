import NutriCore
import SwiftUI

/// A running session: controls on the left, the session in the middle, live metrics on the right.
struct SessionView: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var page = 1

    var body: some View {
        TabView(selection: $page) {
            ControlsView().tag(0)
            Group {
                switch workout.active {
                case .strength(let session): StrengthView(session: session)
                case .walk(let minutes): WalkView(targetMinutes: minutes)
                case .intervals(let stage): IntervalsView(stage: stage)
                case .yoga: YogaView()
                case nil: EmptyView()
                }
            }
            .tag(1)
            MetricsView().tag(2)
        }
        .tabViewStyle(.page)
        .navigationBarBackButtonHidden()
    }
}

/// End, pause and resume.
struct ControlsView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        VStack(spacing: 12) {
            Text(workout.active?.title ?? "")
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                VStack {
                    Button {
                        Task { await workout.end() }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .tint(.red)
                    .font(.title2)
                    Text("End").font(.footnote)
                }
                VStack {
                    Button {
                        workout.phase == .paused ? workout.resume() : workout.pause()
                    } label: {
                        Image(systemName: workout.phase == .paused ? "arrow.clockwise" : "pause")
                    }
                    .tint(.yellow)
                    .font(.title2)
                    Text(workout.phase == .paused ? "Resume" : "Pause").font(.footnote)
                }
            }
        }
    }
}

/// Time, heart rate and active energy.
struct MetricsView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(ElapsedTime.format(workout.elapsed(at: context.date)))
                    .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(.yellow)
                Label(workout.heartRate > 0 ? "\(Int(workout.heartRate)) bpm" : "-- bpm", systemImage: "heart.fill")
                    .foregroundStyle(.red)
                Label("\(Int(workout.activeEnergy)) kcal", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
                if workout.steps > 0 {
                    Label("\(Int(workout.steps)) steps", systemImage: "shoeprints.fill")
                        .foregroundStyle(.green)
                }
                if workout.phase == .paused {
                    Text("Paused").font(.footnote).foregroundStyle(.yellow)
                }
            }
            .font(.system(.title3, design: .rounded).monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum ElapsedTime {
    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
