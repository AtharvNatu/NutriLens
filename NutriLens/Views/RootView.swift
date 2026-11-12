import SwiftUI

enum AppTab: String, Hashable {
    case today, food, train, sleep, body

    /// Older launch-argument names still work ("log", "history", "exercise").
    init?(launchName: String) {
        switch launchName {
        case "log", "history", "recipes": self = .food
        case "exercise", "plan": self = .train
        default: self.init(rawValue: launchName)
        }
    }
}

enum FoodSection: String, CaseIterable, Identifiable {
    case log = "Log"
    case recipes = "Recipes"
    case history = "History"
    var id: String { rawValue }

    init(launchName: String?) {
        self = switch launchName {
        case "history": .history
        case "recipes": .recipes
        default: .log
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = AppTab(launchName: LaunchArguments.current.initialTab ?? "") ?? .today
    @State private var foodSection = FoodSection(launchName: LaunchArguments.current.initialTab)
    @State private var today = Calendar.current.startOfDay(for: .now)

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "chart.pie.fill", value: AppTab.today) {
                TodayView(day: today) { selection = $0 }
                    .id(today)
            }
            Tab("Food", systemImage: "fork.knife", value: AppTab.food) {
                FoodView(section: $foodSection)
            }
            Tab("Train", systemImage: "dumbbell.fill", value: AppTab.train) {
                TrainView()
            }
            Tab("Sleep", systemImage: "bed.double.fill", value: AppTab.sleep) {
                SleepView()
            }
            Tab("Body", systemImage: "scalemass.fill", value: AppTab.body) {
                BodyView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task { await env.refreshIfStale() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Roll the dashboard over to a new day when the app comes back after midnight,
            // and pick up anything logged on your other device (at most every 15 minutes).
            let now = Calendar.current.startOfDay(for: .now)
            if now != today { today = now }
            Task { await env.refreshIfStale() }
        }
    }
}

/// Food logging and the weekly food history, switched with a segmented control.
struct FoodView: View {
    @Binding var section: FoodSection

    var body: some View {
        switch section {
        case .log: LogFoodView(section: $section)
        case .recipes: RecipesView(section: $section)
        case .history: HistoryView(section: $section)
        }
    }
}

struct FoodSectionPicker: View {
    @Binding var section: FoodSection

    var body: some View {
        Picker("Food", selection: $section) {
            ForEach(FoodSection.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    RootView()
        .environment(environment)
        .modelContainer(environment.modelContainer)
}
