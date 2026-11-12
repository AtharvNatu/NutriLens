import Foundation
import NutriCore
import Observation
import WatchConnectivity

/// The Watch's side of WatchConnectivity: keeps the iPhone's latest context and sends finished sessions back.
@MainActor
@Observable
final class PhoneLink: NSObject {
    /// Plan start, settings, readiness suggestion and recent sets from the iPhone (kept between launches).
    private(set) var context: WatchContext?
    @ObservationIgnored private let defaults: UserDefaults
    private static let storeKey = "phoneContext"
    /// Sessions finished before the connection was ready, kept until it is (JSON array of records).
    private static let pendingKey = "pendingWorkouts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        context = WatchMessage.context(from: defaults.data(forKey: Self.storeKey))
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// The plan's start date: the iPhone's setting, or the plan's own date until the iPhone has sent one.
    var planStart: Date { context?.planStart ?? Self.defaultPlanStart }

    static var defaultPlanStart: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 21)) ?? .now
    }

    /// Sends the session to the iPhone: at once when the iPhone app is reachable, otherwise (or if that fails)
    /// with `transferUserInfo`, which delivers it even if the iPhone app isn't running. The iPhone stores each
    /// session once, by its ID, however often it arrives.
    func send(_ record: WatchWorkoutRecord) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let message = try? WatchMessage.encode(record) else {
            var queued = pending
            queued.removeAll { $0.id == record.id }
            queued.append(record)
            pending = queued
            return
        }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: { _ in }, errorHandler: { _ in
                WCSession.default.transferUserInfo(message)
            })
        } else {
            session.transferUserInfo(message)
        }
    }

    /// Sessions waiting for the connection (survive the app quitting).
    private(set) var pending: [WatchWorkoutRecord] {
        get {
            (defaults.array(forKey: Self.pendingKey) as? [Data] ?? []).compactMap { WatchMessage.workout(from: $0) }
        }
        set {
            let data = newValue.compactMap { try? WatchMessage.encode($0)[WatchMessage.workoutKey] }
            defaults.set(data, forKey: Self.pendingKey)
        }
    }

    /// Demo data for Simulator screenshots.
    func useDemoContext(_ context: WatchContext) {
        self.context = context
    }

    fileprivate func store(_ data: Data) {
        guard let new = WatchMessage.context(from: data) else { return }
        if let context, context.sentAt > new.sentAt { return }
        context = new
        defaults.set(data, forKey: Self.storeKey)
    }

    fileprivate func flush() {
        let records = pending
        guard !records.isEmpty, WCSession.default.activationState == .activated else { return }
        pending = []
        records.forEach(send)
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        let data = session.receivedApplicationContext[WatchMessage.contextKey] as? Data
        Task { @MainActor in
            if let data { self.store(data) }
            self.flush()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchMessage.contextKey] as? Data else { return }
        Task { @MainActor in self.store(data) }
    }
}
