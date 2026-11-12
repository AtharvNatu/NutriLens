import NutriCore
import SwiftData
import SwiftUI

/// All demonstrations, grouped by type.
struct ExerciseLibraryView: View {
    @Environment(AppEnvironment.self) private var env

    private let groups: [(String, [ExerciseCategory])] = [
        ("Strength (technique library 01–20)", [.strength, .core]),
        ("Gentle yoga", [.yoga]),
        ("Cardio", [.cardio]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(groups, id: \.0) { title, categories in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(.title3.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(env.plan.exercises.filter { categories.contains($0.category) }) { exercise in
                                NavigationLink {
                                    ExerciseDetailView(exercise: exercise)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ExerciseThumbnail(exercise: exercise, size: 150)
                                            .frame(maxWidth: .infinity)
                                        Text(exercise.numberedName).font(.subheadline.weight(.semibold)).lineLimit(2)
                                            .foregroundStyle(.primary)
                                        Text(exercise.focus).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text("Use the comfortable version in each guide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Exercise library")
    }
}

/// One exercise: looping demo, technique, cautions and your history.
struct ExerciseDetailView: View {
    let exercise: Exercise
    var prescription: Prescription?
    var rest: String?

    @Query(sort: \WorkoutLog.start) private var logs: [WorkoutLog]

    private var history: [[LoggedSet]] { Training.history(of: exercise.id, in: logs) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExerciseVideoCard(exercise: exercise)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.focus.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                    Text(exercise.numberedName).font(.title.bold())
                    Text(exercise.equipment).foregroundStyle(.secondary)
                    if let prescription {
                        Label("This week: \(prescription.label)\(rest.map { " · rest \($0)" } ?? "")", systemImage: "list.number")
                            .font(.subheadline.weight(.medium))
                            .padding(.top, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(exercise.steps.enumerated()), id: \.offset) { n, step in
                        Label(step, systemImage: "\(n + 1).circle.fill")
                    }
                }
                .card()
                VStack(alignment: .leading, spacing: 8) {
                    Label("Watch for", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.orange)
                    Text(exercise.watchFor)
                    Label("Adjust", systemImage: "slider.horizontal.3").font(.headline).foregroundStyle(.tint).padding(.top, 4)
                    Text(exercise.adjust)
                }
                .card()
                if exercise.category == .strength || exercise.category == .core {
                    historySection
                }
                Text("Controlled, pain-free range. Exhale on effort. Stop for sharp or joint pain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Your history", systemImage: "chart.line.uptrend.xyaxis", tint: .indigo)
            if history.isEmpty {
                Text("No sets logged yet.").foregroundStyle(.secondary)
            } else {
                let sessions = logs.filter { log in log.exercises.contains { $0.exerciseID == exercise.id && !$0.sets.isEmpty } }.suffix(6).reversed()
                ForEach(Array(sessions), id: \.id) { log in
                    if let sets = log.exercises.first(where: { $0.exerciseID == exercise.id })?.sets {
                        HStack {
                            Text(log.start.formatted(.dateTime.day().month(.abbreviated)))
                            Spacer()
                            Text(sets.map { "\($0.reps)" }.joined(separator: " · ") + " @ " + ProgressionAdvice.kg(sets.map(\.loadKg).max() ?? 0))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                if let prescription {
                    Text(ProgressionAdvisor.advice(history: history, prescription: prescription).message)
                        .font(.caption)
                        .padding(.top, 4)
                }
            }
        }
        .card()
    }
}
