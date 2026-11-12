import Foundation
import NutriCore
import SwiftData
import WatchConnectivity

/// The iPhone's side of the NutriLens Watch app: sends the plan context, receives finished sessions.
@MainActor
final class WatchLink: NSObject {
    private weak var env: AppEnvironment?
    private var session: WCSession?
    private var lastSent: Data?

    func start(env: AppEnvironment) {
        guard WCSession.isSupported(), session == nil else { return }
        self.env = env
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
    }

    /// Sends the current context when the Watch app is installed and something changed.
    func sendContext() async {
        guard let env, let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let logs = (try? env.modelContainer.mainContext.fetch(FetchDescriptor<WorkoutLog>(sortBy: [SortDescriptor(\.start)]))) ?? []
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now).addingTimeInterval(-18 * 3600)
        let nights = SleepAnalyzer.nights(from: (try? await env.health.sleepSamples(from: start, to: .now)) ?? [])
        let asleep = nights.last { calendar.isDate($0.night, inSameDayAs: .now) }?.asleep
        let stored = UserDefaults.standard.object(forKey: SettingsKey.stepLengthMeters) as? Double
        let context = WatchImport.context(logs: logs, planStart: env.planStartDate, lastNightAsleep: asleep,
                                          stepLengthMeters: stored ?? SettingsDefault.stepLengthMeters)
        guard let message = try? WatchMessage.encode(context) else { return }
        // Compare without the timestamp, so an unchanged context isn't sent again.
        var unstamped = context
        unstamped.sentAt = .distantPast
        let fingerprint = try? WatchMessage.encode(unstamped)[WatchMessage.contextKey]
        guard fingerprint != lastSent else { return }
        do {
            try session.updateApplicationContext(message)
            lastSent = fingerprint
        } catch {
            // Tried again on the next refresh.
        }
    }

    private func receive(_ data: Data) {
        guard let env, let record = WatchMessage.workout(from: data) else { return }
        do {
            if try WatchImport.receive(record, context: env.modelContainer.mainContext) != .unchanged {
                env.healthDidChange()
            }
        } catch {
            // Health's copy of the workout brings the log in on the next sync.
        }
        Task { await sendContext() }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in await self.sendContext() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another Watch: activate again for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.lastSent = nil
            await self.sendContext()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchMessage.workoutKey] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message[WatchMessage.workoutKey] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message[WatchMessage.workoutKey] as? Data else {
            replyHandler([:])
            return
        }
        Task { @MainActor in self.receive(data) }
        replyHandler(["received": true])
    }
}
