import NutriCore
import SwiftUI

@main
struct NutriLensWatchApp: App {
    @State private var link: PhoneLink
    @State private var workout: WorkoutManager

    init() {
        let demo = WatchDemo.current
        let link = PhoneLink()
        let workout = WorkoutManager(simulated: demo != nil)
        if let demo { demo.prepare(link: link, workout: workout) } else { link.start() }
        _link = State(initialValue: link)
        _workout = State(initialValue: workout)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(link)
                .environment(workout)
        }
    }
}

struct RootView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        switch workout.phase {
        case .idle, .starting:
            HomeView()
        case .ended, .saving:
            FinishView()
        case .running, .paused:
            SessionView()
        }
    }
}

/// Launch arguments for Simulator screenshots: `-demoScreen home|strength|rest|walk|intervals|yoga|finish`.
/// No HealthKit is used and the iPhone context is sample data.
struct WatchDemo {
    var screen: String

    static var current: WatchDemo? {
        UserDefaults.standard.string(forKey: "demoScreen").map(WatchDemo.init)
    }

    @MainActor
    func prepare(link: PhoneLink, workout: WorkoutManager) {
        let calendar = Calendar.current
        let today = Date.now
        let history: [String: [[LoggedSet]]] = [
            WatchContext.historyKey("01", weekday: 0): [[LoggedSet(reps: 10, loadKg: 10, repsInReserve: 3), LoggedSet(reps: 10, loadKg: 10, repsInReserve: 2)]],
            WatchContext.historyKey("05", weekday: 0): [[LoggedSet(reps: 12, loadKg: 8, repsInReserve: 2)]],
        ]
        link.useDemoContext(WatchContext(sentAt: today, planStart: PhoneLink.defaultPlanStart, suggestedReadiness: .ready,
                                         readinessDay: calendar.startOfDay(for: today), stepLengthMeters: 0.7, history: history))
        let plan = PlanContent.homeStrength12Week
        let week = PlanEngine.week(for: today, startDate: link.planStart) ?? 1
        let active: ActiveWorkout?
        switch screen {
        case "strength", "rest", "finish":
            let day = plan.days.first { $0.weekday == 5 } ?? plan.days[0]
            let session = StrengthSession(day: day, week: week, readiness: .ready, plan: plan, context: link.context)
            if screen != "strength" { session.logSet() }
            if screen == "finish" { session.logSet() }
            active = .strength(session)
        case "walk": active = .walk(targetMinutes: PlanEngine.cardioMinutes(kind: .cardioYoga, week: week))
        case "intervals": active = plan.jogStages.first.map { .intervals($0) }
        case "yoga": active = .yoga
        default: active = nil
        }
        guard let active else { return }
        Task {
            await workout.start(active)
            if screen == "finish" { await workout.end() }
        }
    }
}
