import NutriCore
import SwiftData
import SwiftUI

/// The training plan: today's session, the week's progress, the exercise library and history.
struct TrainView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var date = Date.now
    @State private var readiness: Readiness?
    @State private var lastNightAsleep: TimeInterval?
    @State private var workouts: [WorkoutSummary] = []
    @State private var activeSession: ActiveSession?
    @State private var jogStage = 1
    /// Steps for the last 7 days, oldest first (today last).
    @State private var recentSteps: [Double] = []
    @AppStorage(SettingsKey.dailyStepGoal) private var stepGoal = SettingsDefault.dailyStepGoal

    enum ActiveSession: Identifiable {
        case strength(PlanDay, week: Int)
        case walk(minutes: Int)
        case intervals(JogStage)
        case yoga

        var id: String {
            switch self {
            case .strength(let day, let week): "strength-\(day.weekday)-\(week)"
            case .walk: "walk"
            case .intervals(let stage): "jog-\(stage.number)"
            case .yoga: "yoga"
            }
        }
    }

    private var calendar: Calendar { .current }
    private var plan: WorkoutPlan { env.plan }
    private var week: Int? { env.planWeek(on: date) }
    private var effectiveWeek: Int { week ?? 1 }
    private var planDay: PlanDay? { plan.day(weekday: calendar.component(.weekday, from: date)) }
    private var suggestedReadiness: Readiness { Readiness.suggested(lastNightAsleep: lastNightAsleep) }
    private var currentReadiness: Readiness { readiness ?? suggestedReadiness }

    private var weekInterval: DateInterval { Training.planWeekInterval(containing: date, start: env.planStartDate) }
    private var logsThisWeek: [WorkoutLog] { logs.filter { weekInterval.contains($0.start) } }


    var body: some View {
        NavigationStack {
            ScrollView {
                CardColumns(columns: sizeClass == .regular ? 2 : 1) {
                    phaseCard
                    todayCard
                    weekCard
                    stepsCard
                    readinessCard
                    warmUpCard
                    linksCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Exercise library", systemImage: "books.vertical")
                    }
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                switch session {
                case let .strength(day, week):
                    StrengthSessionView(day: day, week: week, readiness: currentReadiness)
                case let .walk(minutes):
                    CardioSessionView(mode: .walk(targetMinutes: minutes))
                case let .intervals(stage):
                    CardioSessionView(mode: .intervals(stage))
                case .yoga:
                    YogaSessionView()
                }
            }
            .task(id: env.healthRevision) { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        date = env.now
        let start = calendar.startOfDay(for: date).addingTimeInterval(-18 * 3600)
        let nights = SleepAnalyzer.nights(from: (try? await env.health.sleepSamples(from: start, to: .now)) ?? [])
        lastNightAsleep = nights.last { calendar.isDate($0.night, inSameDayAs: date) }?.asleep
        workouts = (try? await env.health.workouts(from: weekInterval.start, to: weekInterval.end)) ?? []
        let days = DailyTotals.days(endingOn: date, count: 7)
        let activity = (try? await env.health.activity(for: days)) ?? [:]
        recentSteps = days.map { activity[calendar.startOfDay(for: $0)]?.steps ?? 0 }
    }

    // MARK: Cards

    private var phaseCard: some View {
        let phase = PlanPhase.forWeek(effectiveWeek)
        return VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: plan.title, systemImage: "calendar", tint: .indigo)
            if let week {
                HStack(alignment: .firstTextBaseline) {
                    Text("Week \(week)").font(.title.bold())
                    Text(week <= plan.weeks ? "of \(plan.weeks)" : "· plan complete, keep going").foregroundStyle(.secondary)
                    Spacer()
                    Text(phase.name)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.indigo.opacity(0.12), in: .capsule)
                        .foregroundStyle(.indigo)
                }
                ProgressView(value: Double(min(week, plan.weeks)), total: Double(plan.weeks)).tint(.indigo)
                Text("\(phase.workSets). Finish sets with \(phase.repsInReserve). \(phase.focus)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Starts \(env.planStartDate.formatted(date: .complete, time: .omitted)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    @ViewBuilder private var todayCard: some View {
        if let planDay {
            let doneToday = logs.first { calendar.isDate($0.start, inSameDayAs: date) && ($0.planWeekday == planDay.weekday || planDay.kind != .strength) }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardHeader(title: date.formatted(.dateTime.weekday(.wide)), systemImage: "figure.strengthtraining.traditional", tint: Palette.burned)
                    Spacer()
                    if !planDay.duration.isEmpty { Text(planDay.duration).font(.caption).foregroundStyle(.secondary) }
                }
                Text(planDay.title).font(.title2.bold())
                Text(planDay.summary).font(.subheadline).foregroundStyle(.secondary)
                if let doneToday {
                    Label("\(doneToday.title) logged · \(Format.duration(doneToday.duration))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.medium))
                }
                switch planDay.kind {
                case .strength: strengthContent(planDay)
                case .cardioYoga: cardioContent(planDay)
                case .rest: restContent
                }
            }
            .card()
        }
    }

    @ViewBuilder private func strengthContent(_ day: PlanDay) -> some View {
        let session = Training.adjusted(PlanEngine.session(for: day, week: effectiveWeek), readiness: currentReadiness)
        if currentReadiness == .unwell {
            Text(Readiness.unwell.guidance).font(.subheadline)
        } else {
            VStack(spacing: 10) {
                ForEach(session, id: \.planned.id) { item in
                    if let exercise = plan.exercise(item.planned.exerciseID) {
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise, prescription: item.prescription, rest: item.planned.restLabel)
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseThumbnail(exercise: exercise)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.numberedName + (item.planned.note.map { " (\($0))" } ?? ""))
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("\(item.prescription.label) · rest \(item.planned.restLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Plus \(PlanEngine.cardioMinutes(kind: .strength, week: effectiveWeek)) min easy walking. \(planDay?.startingLoads ?? "")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                activeSession = .strength(day, week: effectiveWeek)
            } label: {
                Label(currentReadiness == .tired ? "Start the tired version" : "Start session", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder private func cardioContent(_ day: PlanDay) -> some View {
        let minutes = PlanEngine.cardioMinutes(kind: day.kind, week: effectiveWeek)
        let jogOK = PlanEngine.jogAllowed(week: effectiveWeek, weekday: day.weekday)
        Text("Walk \(minutes) min at a pace where you can talk but not sing, then 10–12 min yoga.")
            .font(.subheadline)
        HStack {
            Button {
                activeSession = .walk(minutes: currentReadiness == .tired ? max(10, minutes / 2) : minutes)
            } label: {
                Label("Walk", systemImage: "figure.walk").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button {
                activeSession = .yoga
            } label: {
                Label("Yoga", systemImage: "figure.yoga").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        if jogOK {
            VStack(alignment: .leading, spacing: 6) {
                Text("Optional walk/jog intervals").font(.subheadline.weight(.semibold))
                Picker("Stage", selection: $jogStage) {
                    ForEach(plan.jogStages) { Text("Stage \($0.number)").tag($0.number) }
                }
                .pickerStyle(.segmented)
                if let stage = plan.jogStages.first(where: { $0.number == jogStage }) {
                    Text("5 min walk, \(stage.label), 3 min walk. Move up after two easy sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        activeSession = .intervals(stage)
                    } label: {
                        Label("Start intervals", systemImage: "figure.run").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        } else {
            Text(effectiveWeek < 3 ? "Jogging is optional and starts no earlier than week 3." : "Jog intervals are planned for Friday (Wednesday optional).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var restContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep today free of demanding exercise. Gentle movement or the relaxed yoga sequence is fine.")
                .font(.subheadline)
            Button {
                activeSession = .yoga
            } label: {
                Label("Relaxed yoga (optional)", systemImage: "figure.yoga")
            }
            .buttonStyle(.bordered)
        }
    }

    private var stepsCard: some View {
        // The plan: record your 7-day average first, then add about 500 steps/day every 1–2 weeks.
        let completeDays = recentSteps.dropLast().filter { $0 > 0 }
        let average = completeDays.isEmpty ? 0 : completeDays.reduce(0, +) / Double(completeDays.count)
        let suggestion = StepEnergy.suggestedGoal(sevenDayAverage: average)
        let today = recentSteps.last ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Daily steps", systemImage: "shoeprints.fill", tint: Palette.steps)
            HStack {
                StatTile(title: "Today", value: Int(today).formatted(), unit: "/ \(Int(stepGoal).formatted())", systemImage: "figure.walk", tint: Palette.steps)
                StatTile(title: "6-day average", value: Int(average).formatted(), systemImage: "chart.bar", tint: .teal)
            }
            ProgressView(value: min(today, stepGoal), total: max(stepGoal, 1)).tint(Palette.steps)
            if average > 0, Double(suggestion) != stepGoal {
                HStack {
                    Text("Plan's next step: about \(suggestion.formatted()) a day (your average + 500).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use") { stepGoal = Double(suggestion) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            Text("Workout steps are already included. 6,000–9,000 is a range, not a quota.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Choose today's version", systemImage: "gauge.with.dots.needle.33percent", tint: .orange)
            Picker("Readiness", selection: Binding(get: { currentReadiness }, set: { readiness = $0 })) {
                ForEach(Readiness.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(currentReadiness.guidance).font(.subheadline).foregroundStyle(.secondary)
            if let lastNightAsleep, lastNightAsleep > 0 {
                Label("Last night: \(Format.duration(lastNightAsleep)) asleep\(suggestedReadiness == .tired ? ", so the tired version is suggested" : "")",
                      systemImage: "bed.double")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var weekCard: some View {
        let strengthDone = Set(logsThisWeek.filter { $0.kind == .strength }.compactMap { calendar.startOfDay(for: $0.start) }).count
        let cardio = Training.cardioMinutes(workouts: workouts, logs: logsThisWeek, in: weekInterval)
        let target = PlanEngine.weeklyCardioTarget(week: effectiveWeek)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekInterval.start) }
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "This plan week", systemImage: "calendar.badge.checkmark", tint: .green)
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { day in
                    let weekday = calendar.component(.weekday, from: day)
                    let kind = plan.day(weekday: weekday)?.kind ?? .rest
                    let done = logsThisWeek.contains { calendar.isDate($0.start, inSameDayAs: day) }
                        || workouts.contains { calendar.isDate($0.start, inSameDayAs: day) }
                    let isToday = calendar.isDate(day, inSameDayAs: date)
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                        ZStack {
                            Circle()
                                .fill(done ? Color.green : (kind == .rest ? Color.gray.opacity(0.15) : Color.indigo.opacity(0.12)))
                            Image(systemName: done ? "checkmark" : (kind == .strength ? "dumbbell.fill" : kind == .cardioYoga ? "figure.walk" : "moon.zzz"))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(done ? .white : (kind == .rest ? .secondary : Color.indigo))
                        }
                        .frame(width: 32, height: 32)
                        .overlay { if isToday { Circle().stroke(Color.accentColor, lineWidth: 2) } }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack {
                StatTile(title: "Strength", value: "\(strengthDone) / 4", systemImage: "dumbbell", tint: .indigo)
                StatTile(title: "Cardio", value: "\(Int(cardio))", unit: "/ \(target.lowerBound) min", systemImage: "figure.walk", tint: .green)
            }
            ProgressView(value: min(cardio, Double(target.lowerBound)), total: Double(target.lowerBound)).tint(.green)
            Text("Moderate minutes from walks, jogs and sessions logged here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var warmUpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Warm up before lifting · 6–8 min", systemImage: "flame", tint: .orange)
            ForEach(Array(plan.warmUp.enumerated()), id: \.offset) { index, step in
                Label(step, systemImage: "\(index + 1).circle")
                    .font(.subheadline)
            }
        }
        .card()
    }

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ExerciseLibraryView()
            } label: {
                linkRow("Exercise library", detail: "\(plan.exercises.count) looping demonstrations", symbol: "play.rectangle.on.rectangle")
            }
            .buttonStyle(.plain)
            Divider().padding(.vertical, 10)
            NavigationLink {
                WorkoutHistoryView()
            } label: {
                linkRow("Workout history", detail: "\(logs.count) logged sessions, plus Apple Health workouts", symbol: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            Divider().padding(.vertical, 10)
            NavigationLink {
                WeekScheduleView()
            } label: {
                linkRow("Weekly schedule", detail: "The four-day split with walking and yoga", symbol: "calendar")
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func linkRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// The seven-day split, with this week's prescriptions.
struct WeekScheduleView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let week = env.planWeek() ?? 1
        List {
            Section {
                Text("Week \(week) · \(PlanPhase.forWeek(week).name): \(PlanPhase.forWeek(week).workSets). Weekly cardio target \(PlanEngine.weeklyCardioTarget(week: week).lowerBound)–\(PlanEngine.weeklyCardioTarget(week: week).upperBound) moderate minutes.")
                    .font(.subheadline)
            }
            ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                if let day = env.plan.day(weekday: weekday) {
                    Section {
                        ForEach(PlanEngine.session(for: day, week: week), id: \.planned.id) { item in
                            if let exercise = env.plan.exercise(item.planned.exerciseID) {
                                NavigationLink {
                                    ExerciseDetailView(exercise: exercise, prescription: item.prescription, rest: item.planned.restLabel)
                                } label: {
                                    HStack {
                                        ExerciseThumbnail(exercise: exercise, size: 40)
                                        Text(exercise.numberedName)
                                        Spacer()
                                        Text(item.prescription.label).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if day.kind != .strength {
                            Text(day.summary).foregroundStyle(.secondary)
                        }
                        Label("\(day.additional)\(day.kind == .rest ? "" : " · \(PlanEngine.cardioMinutes(kind: day.kind, week: week)) min walking")", systemImage: "figure.walk")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("\(Calendar.current.weekdaySymbols[weekday - 1]) · \(day.title)")
                    }
                }
            }
            Section("Rules") {
                Text("Missed a day? Do the next session; don't double up. Keep the rest days.")
                    .font(.subheadline)
            }
        }
        .navigationTitle("Weekly schedule")
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    TrainView()
        .environment(environment)
        .modelContainer(environment.modelContainer)
}
