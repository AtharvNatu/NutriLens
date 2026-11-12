import NutriCore
import SwiftUI

/// Today's plan day and week phase, readiness, and the sessions you can start.
struct HomeView: View {
    @Environment(PhoneLink.self) private var link
    @Environment(WorkoutManager.self) private var workout
    @AppStorage("jogStage") private var jogStage = 1
    @State private var readiness: Readiness?
    @State private var today = Date.now

    private let plan = PlanContent.homeStrength12Week
    private var calendar: Calendar { .current }
    private var week: Int? { PlanEngine.week(for: today, startDate: link.planStart) }
    private var effectiveWeek: Int { week ?? 1 }
    private var weekday: Int { calendar.component(.weekday, from: today) }
    private var day: PlanDay? { plan.day(weekday: weekday) }
    private var currentReadiness: Readiness { readiness ?? link.context?.readiness(on: today) ?? .ready }
    private var walkMinutes: Int {
        let kind: SessionKind = day?.kind == .rest ? .cardioYoga : (day?.kind ?? .cardioYoga)
        let minutes = PlanEngine.cardioMinutes(kind: kind, week: effectiveWeek)
        return currentReadiness == .tired ? max(10, minutes / 2) : minutes
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                Section {
                    Picker("Today", selection: Binding(get: { currentReadiness }, set: { readiness = $0 })) {
                        Text("Ready").tag(Readiness.ready)
                        Text("Tired").tag(Readiness.tired)
                    }
                    .pickerStyle(.navigationLink)
                    if currentReadiness == .tired {
                        Text("Up to 2 sets, no optional work.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let day, day.kind == .strength {
                    Section {
                        strengthButton(day, title: "Start")
                    }
                }
                Section("Cardio and yoga") {
                    startButton("Walk \(walkMinutes) min", systemImage: "figure.walk", tint: .green) {
                        .walk(targetMinutes: walkMinutes)
                    }
                    if PlanEngine.jogAllowed(week: effectiveWeek, weekday: weekday), currentReadiness == .ready,
                       let stage = plan.jogStages.first(where: { $0.number == jogStage }) ?? plan.jogStages.first {
                        startButton("Walk/jog stage \(stage.number)", systemImage: "figure.run", tint: .orange) { .intervals(stage) }
                        Picker("Stage", selection: $jogStage) {
                            ForEach(plan.jogStages) { Text("Stage \($0.number)").tag($0.number) }
                        }
                    }
                    startButton("Yoga", systemImage: "figure.yoga", tint: .purple) { .yoga }
                }
                Section("Other days") {
                    ForEach(plan.days.filter { $0.kind == .strength && $0.weekday != weekday }) { other in
                        strengthButton(other, title: calendar.weekdaySymbols[other.weekday - 1])
                    }
                }
                Section {
                    syncStatus
                }
            }
            .navigationTitle("NutriLens")
            .alert("Workout", isPresented: Binding(get: { workout.errorMessage != nil && workout.phase == .idle },
                                                   set: { if !$0 { workout.errorMessage = nil } })) {
                Button("OK") { workout.errorMessage = nil }
            } message: {
                Text(workout.errorMessage ?? "")
            }
            .onAppear { today = .now }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let week {
                Text("Week \(week) · \(PlanPhase.forWeek(week).name)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.indigo)
            } else {
                Text("Starts \(link.planStart.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(day?.title ?? "Rest")
                .font(.headline)
            if let week {
                Text(PlanPhase.forWeek(week).repsInReserve)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.clear)
    }

    private func strengthButton(_ day: PlanDay, title: String) -> some View {
        let count = PlanEngine.adjusted(PlanEngine.session(for: day, week: effectiveWeek), readiness: currentReadiness).count
        return Button {
            let session = StrengthSession(day: day, week: effectiveWeek, readiness: currentReadiness, plan: plan, context: link.context)
            Task { await workout.start(.strength(session)) }
        } label: {
            HStack {
                Image(systemName: "dumbbell.fill").foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text(title == "Start" ? day.title : title).font(.body.weight(.semibold))
                    Text(title == "Start" ? "\(count) exercises" : day.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .disabled(workout.phase != .idle)
    }

    private func startButton(_ title: String, systemImage: String, tint: Color, _ make: @escaping () -> ActiveWorkout) -> some View {
        Button {
            Task { await workout.start(make()) }
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(tint)
        }
        .disabled(workout.phase != .idle)
    }

    @ViewBuilder private var syncStatus: some View {
        if let context = link.context {
            Text("From iPhone \(context.sentAt.formatted(.relative(presentation: .named)))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("Open NutriLens on iPhone to bring over your last sets.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
