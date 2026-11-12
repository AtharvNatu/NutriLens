import NutriCore
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(SettingsKey.dailyCalorieTarget) private var target = SettingsDefault.dailyCalorieTarget
    @AppStorage(SettingsKey.creditSource) private var creditSource = SettingsDefault.creditSource
    @AppStorage(SettingsKey.creditFraction) private var creditFraction = SettingsDefault.creditFraction
    @AppStorage(SettingsKey.sleepGoalHours) private var sleepGoal = SettingsDefault.sleepGoalHours
    @AppStorage(SettingsKey.goalWeightKg) private var goalWeight = SettingsDefault.goalWeightKg
    @AppStorage(SettingsKey.stepLengthMeters) private var stepLength = SettingsDefault.stepLengthMeters
    @AppStorage(SettingsKey.dailyStepGoal) private var stepGoal = SettingsDefault.dailyStepGoal

    @Query private var meals: [MealEntry]
    @Query private var todaysLogs: [WorkoutLog]
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @State private var activity = ActivitySummary.zero
    @State private var workouts: [WorkoutSummary] = []
    @State private var lastNight: SleepNight?
    @State private var sleepScore: SleepScore?
    /// Steps taken during today's workouts, so they aren't counted twice.
    @State private var workoutSteps: Double = 0
    @State private var healthWeights: [WeightPoint] = []
    @State private var needsAuthorization = false
    @State private var loadError: String?
    @State private var showingSettings = false
    /// The macro whose per-item breakdown is open.
    @State private var breakdownMacro: Macro?
    @State private var editingMeal: MealEntry?

    private let day: Date
    private let open: (AppTab) -> Void

    init(day: Date = .now, open: @escaping (AppTab) -> Void = { _ in }) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        self.day = start
        self.open = open
        _meals = Query(filter: MealEntry.predicate(from: start, to: end), sort: \MealEntry.date)
        _todaysLogs = Query(filter: WorkoutLog.predicate(from: start, to: end), sort: \WorkoutLog.start)
    }

    private var eaten: Nutrients { meals.map(\.nutrients).total() }

    /// Today's targets, from the plan's session for this day and your usual steps.
    private var macros: MacroTargets { env.macroTargets(on: day) }

    /// Today's Health workouts, a session the Watch also recorded counted once (with the Watch's energy).
    private var todaysWorkouts: [WorkoutSummary] {
        Training.displayedWorkouts(workouts.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }, logs: todaysLogs)
    }

    /// Sessions logged here that count on their own: not in Health and not recorded by the Watch.
    private var localOnlyLogs: [WorkoutLog] {
        Training.uncountedLogs(todaysLogs, workouts: workouts)
    }

    /// Workout energy today: Health workouts plus sessions logged here that aren't in Health.
    private var workoutEnergy: Double {
        todaysWorkouts.compactMap(\.energyBurned).reduce(0, +) + localOnlyLogs.map(\.energyKcal).reduce(0, +)
    }

    private var policy: ExerciseCreditPolicy {
        ExerciseCreditPolicy(source: ExerciseCreditPolicy.Source(rawValue: creditSource) ?? .workoutsAndSteps, fraction: creditFraction)
    }

    /// Steps walked outside workouts (workout steps are already in the workout's energy).
    private var everydaySteps: Double {
        max(0, activity.steps - workoutSteps - localOnlyLogs.map { Double($0.steps) }.reduce(0, +))
    }

    private var bodyMass: Double { weights.last?.kg ?? EnergyEstimator.defaultBodyMassKg }

    /// Walking energy from everyday steps.
    private var stepEnergy: Double {
        StepEnergy.kilocalories(steps: everydaySteps, bodyMassKg: bodyMass, stepLengthMeters: stepLength)
    }

    private var balance: CalorieBalance {
        CalorieBalance(eaten: eaten.kilocalories, activeEnergy: activity.activeEnergy, basalEnergy: activity.basalEnergy,
                       workoutEnergy: workoutEnergy, stepEnergy: stepEnergy, target: target, policy: policy)
    }

    private var weights: [WeightPoint] {
        let local = measurements.filter { $0.weightKg > 0 && $0.healthKitID == nil }.map { WeightPoint(date: $0.date, kg: $0.weightKg) }
        return WeightTrend.deduplicated(healthWeights + local)
    }


    var body: some View {
        NavigationStack {
            ScrollView {
                healthBanner
                    .padding(.horizontal)
                CardColumns(columns: sizeClass == .regular ? 2 : 1) {
                    balanceCard
                    planCard
                    macrosCard
                    sleepCard
                    weightCard
                    activityCard
                    if !todaysWorkouts.isEmpty || !localOnlyLogs.isEmpty { workoutsCard }
                    mealsCard
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CalendarView()
                    } label: {
                        Label("Calendar", systemImage: "calendar")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $editingMeal) { LoggedMealEditor(entry: $0) }
            .sheet(item: $breakdownMacro) { macro in
                MacroBreakdownView(meals: meals,
                                   targets: [.protein: macros.protein, .carbohydrates: macros.carbohydrates, .fat: macros.fat, .energy: balance.budget],
                                   macro: macro)
            }
            .refreshable {
                await env.syncFromHealth()
                await load()
            }
            .task(id: env.healthRevision) { await load() }
        }
    }

    /// Each query loads on its own, so one failure (say, a type you haven't allowed) doesn't hide the rest.
    private func load() async {
        needsAuthorization = await env.health.shouldRequestAuthorization()
        let calendar = Calendar.current
        var errors: [String] = []
        do { activity = try await env.health.activity(on: day) } catch { errors.append(error.localizedDescription) }
        do {
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: day) ?? day
            workouts = try await env.health.workouts(from: weekAgo, to: .now.addingTimeInterval(60))
            var steps = 0.0
            for workout in Training.countedWorkouts(workouts) where calendar.isDate(workout.start, inSameDayAs: day) {
                steps += (try? await env.health.stepCount(from: workout.start, to: workout.end)) ?? 0
            }
            workoutSteps = steps
        } catch { errors.append(error.localizedDescription) }
        do {
            // Two weeks of nights: last night plus the history its bedtime score compares with.
            let samples = try await env.health.sleepSamples(from: day.addingTimeInterval(-15 * 86_400), to: day.addingTimeInterval(14 * 3600))
            let nights = SleepAnalyzer.nights(from: samples)
            lastNight = nights.last { calendar.isDate($0.night, inSameDayAs: day) }
            sleepScore = lastNight.flatMap { SleepScore.score($0, previousNights: nights, goalHours: sleepGoal) }
        } catch { errors.append(error.localizedDescription) }
        do {
            let monthAgo = calendar.date(byAdding: .day, value: -35, to: day) ?? day
            healthWeights = try await env.health.bodySamples(from: monthAgo, to: .now.addingTimeInterval(60))
                .compactMap { s in s.values[.weight].map { WeightPoint(date: s.date, kg: $0) } }
        } catch { errors.append(error.localizedDescription) }
        loadError = errors.first
    }

    // MARK: Cards

    @ViewBuilder private var healthBanner: some View {
        if !env.health.isAvailable {
            Label("Apple Health isn't available here. Your logs are still saved.", systemImage: "heart.slash")
                .font(.subheadline)
                .card()
        } else if needsAuthorization {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(title: "Connect Apple Health", systemImage: "heart.fill", tint: .pink)
                Text("Allow access to activity, workouts, sleep and body data, and to save what you log.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Connect") {
                    Task {
                        try? await env.health.requestAuthorization()
                        await env.syncFromHealth()
                        env.healthDidChange()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }
            .card()
        } else if let loadError {
            Label(loadError, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .card()
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Calories", systemImage: "flame.fill", tint: Palette.eaten)
            HStack(spacing: 20) {
                ProgressRing(progress: balance.progress, tint: Palette.eaten) {
                    VStack(spacing: 0) {
                        Text(Format.kcal(abs(balance.remaining)))
                            .font(.title2.bold().monospacedDigit())
                            .minimumScaleFactor(0.6)
                        Text(balance.isOverBudget ? "kcal over" : "kcal left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(width: 130, height: 130)
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 10) {
                    StatTile(title: "Eaten", value: Format.kcal(balance.eaten), unit: "kcal", systemImage: "fork.knife", tint: Palette.eaten)
                    StatTile(title: "Burned", value: Format.kcal(balance.burned), unit: "kcal", systemImage: "flame", tint: Palette.burned)
                    StatTile(title: "Net", value: Format.signedKcal(balance.net), unit: "kcal", systemImage: "plusminus", tint: Palette.net)
                }
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var footnote: String {
        var budget = "Target \(Format.kcal(target)) kcal"
        if balance.exerciseCredit > 0 {
            let source = switch policy.source {
            case .workouts: "workouts (\(Format.kcal(workoutEnergy)))"
            case .workoutsAndSteps: "workouts + steps (\(Format.kcal(workoutEnergy + stepEnergy)))"
            default: "active energy (\(Format.kcal(balance.effectiveActiveEnergy)))"
            }
            budget += " + \(Int((policy.fraction * 100).rounded())) % of \(source) = \(Format.kcal(balance.budget)) kcal"
        }
        var burned = "Burned = \(Format.kcal(balance.effectiveActiveEnergy)) active + \(Format.kcal(activity.basalEnergy)) resting so far"
        if balance.effectiveActiveEnergy > activity.activeEnergy + 1 {
            burned += " (active includes \(Format.kcal(workoutEnergy)) workouts + \(Format.kcal(stepEnergy)) walking from steps)"
        }
        return "\(budget). \(burned)."
    }

    private var planCard: some View {
        let weekday = Calendar.current.component(.weekday, from: day)
        let planDay = env.plan.day(weekday: weekday)
        let week = env.planWeek(on: day)
        let done = !todaysLogs.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(title: "Training plan", systemImage: "dumbbell.fill", tint: .indigo)
                Spacer()
                if let week {
                    Text("Week \(week) · \(PlanPhase.forWeek(week).name)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.indigo.opacity(0.12), in: .capsule)
                        .foregroundStyle(.indigo)
                }
            }
            if let planDay {
                Text(planDay.title).font(.title3.bold())
                Text(week == nil ? "The plan starts \(env.planStartDate.formatted(date: .abbreviated, time: .omitted))." : planDay.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let week, planDay.kind != .rest {
                    Text("Walking today: \(PlanEngine.cardioMinutes(kind: planDay.kind, week: week)) moderate min · \(planDay.additional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                open(.train)
            } label: {
                Label(done ? "Done today · see plan" : "Open today's session", systemImage: done ? "checkmark.circle.fill" : "play.fill")
            }
            .buttonStyle(.bordered)
            .tint(done ? .green : .indigo)
        }
        .card()
    }

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(title: "Last night", systemImage: "bed.double.fill", tint: .purple)
                Spacer()
                Button("Sleep", systemImage: "chevron.right") { open(.sleep) }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            if let lastNight, lastNight.asleep > 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.duration(lastNight.asleep)).font(.title2.bold().monospacedDigit())
                    Text("asleep").foregroundStyle(.secondary)
                    Spacer()
                    if let sleepScore {
                        SleepScoreBadge(score: sleepScore)
                    }
                }
                ProgressView(value: min(lastNight.asleep / 3600, sleepGoal), total: sleepGoal)
                    .tint(lastNight.asleep >= 7 * 3600 ? .purple : .orange)
                Text("\(lastNight.start.formatted(date: .omitted, time: .shortened)) – \(lastNight.end.formatted(date: .omitted, time: .shortened)) · goal \(sleepGoal.formatted()) h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No sleep recorded last night.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var weightCard: some View {
        let weeks = WeightTrend.weeklyAverages(weights)
        let latest = weights.last
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(title: "Weight", systemImage: "scalemass.fill", tint: .teal)
                Spacer()
                Button("Body", systemImage: "chevron.right") { open(.body) }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            if let latest {
                HStack(alignment: .firstTextBaseline) {
                    Text(latest.kg.formatted(.number.precision(.fractionLength(1)))).font(.title2.bold().monospacedDigit())
                    Text("kg").foregroundStyle(.secondary)
                    Spacer()
                    Text(latest.kg > goalWeight ? "\((latest.kg - goalWeight).formatted(.number.precision(.fractionLength(1)))) kg to goal" : "Goal reached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if weeks.count >= 2 {
                    let change = weeks[weeks.count - 1].averageKg - weeks[weeks.count - 2].averageKg
                    Label("Weekly average \(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(1)))) kg vs last week",
                          systemImage: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No weight yet. Import a scale screenshot in Body.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { breakdownMacro = .protein } label: {
                HStack {
                    CardHeader(title: "Macros", systemImage: "chart.bar.fill", tint: .indigo)
                    Spacer()
                    Text("By item").font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .accessibilityLabel("Macros by item")
            macroButton(.protein, name: "Protein", grams: eaten.protein, target: macros.protein, tint: Palette.protein)
            macroButton(.carbohydrates, name: "Carbohydrates", grams: eaten.carbohydrates, target: macros.carbohydrates, tint: Palette.carbohydrates)
            macroButton(.fat, name: "Fat", grams: eaten.fat, target: macros.fat, tint: Palette.fat)
            Text("\(macros.dayTitle) targets for ≈ \(Format.kcal(macros.kilocalories)) kcal, with \(Int(macros.expectedSteps).formatted()) usual steps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .card()
    }

    /// Each bar opens the breakdown of that macro.
    private func macroButton(_ macro: Macro, name: String, grams: Double, target: Double, tint: Color) -> some View {
        Button { breakdownMacro = macro } label: {
            MacroBar(name: name, grams: grams, target: target, tint: tint).contentShape(.rect)
        }
        .accessibilityHint("Shows which items gave you this \(name.lowercased())")
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Activity", systemImage: "figure.walk", tint: Palette.steps)
            HStack {
                StatTile(title: "Steps", value: activity.steps.formatted(.number.precision(.fractionLength(0))), unit: "/ \(Int(stepGoal).formatted())",
                         systemImage: "shoeprints.fill", tint: Palette.steps)
                StatTile(title: "Active", value: Format.kcal(balance.effectiveActiveEnergy), unit: "kcal", systemImage: "flame", tint: Palette.burned)
            }
            ProgressView(value: min(activity.steps, max(stepGoal, 1)), total: max(stepGoal, 1)).tint(Palette.steps)
            HStack {
                StatTile(title: "Walking", value: Format.kcal(stepEnergy), unit: "kcal", systemImage: "figure.walk", tint: Palette.steps)
                StatTile(title: "Workouts", value: Format.kcal(workoutEnergy), unit: "kcal", systemImage: "dumbbell", tint: .indigo)
            }
            Text("Walking: \(Int(everydaySteps).formatted()) steps outside workouts ≈ \(StepEnergy.distanceKm(steps: everydaySteps, stepLengthMeters: stepLength).formatted(.number.precision(.fractionLength(1)))) km.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var workoutsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Today's workouts", systemImage: "figure.run", tint: Palette.burned)
            ForEach(todaysWorkouts) { WorkoutRow(workout: $0) }
            ForEach(localOnlyLogs) { log in
                WorkoutRow(workout: WorkoutSummary(id: log.id, name: log.title, symbolName: log.kind.symbolName, start: log.start, end: log.end,
                                                   energyBurned: log.energyKcal, sourceName: "NutriLens (not in Health)"))
            }
        }
        .card()
    }

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: "Meals today", systemImage: "fork.knife", tint: Palette.eaten)
                Spacer()
                Button("Log food", systemImage: "plus.circle.fill") { open(.food) }
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            if meals.isEmpty {
                Text("Nothing logged yet. Take a photo of your meal or search the food list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let groups = MealType.allCases.map { type in (type, meals.filter { $0.mealType == type }) }.filter { !$0.1.isEmpty }
                ForEach(groups, id: \.0) { type, entries in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(type.displayName, systemImage: type.symbolName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            let total = entries.map(\.nutrients).total()
                            Text("\(Format.kcal(total.kilocalories)) kcal · \(Format.grams(total.protein)) P")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ForEach(entries) { meal in
                            Button { editingMeal = meal } label: {
                                MealRow(entry: meal, showsMealType: false).contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Edit or delete")
                        }
                    }
                    if type != groups.last?.0 { Divider() }
                }
            }
        }
        .card()
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    TodayView()
        .environment(environment)
        .modelContainer(environment.modelContainer)
}
