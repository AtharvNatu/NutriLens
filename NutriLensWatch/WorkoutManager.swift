import Foundation
import HealthKit
import NutriCore
import Observation
import WatchKit

/// What's being done on the wrist.
enum ActiveWorkout {
    case strength(StrengthSession)
    case walk(targetMinutes: Int)
    case intervals(JogStage)
    case yoga

    var kind: WorkoutLogKind {
        switch self {
        case .strength: .strength
        case .walk: .walk
        case .intervals: .walkJog
        case .yoga: .yoga
        }
    }

    var title: String {
        switch self {
        case .strength(let session): session.day.title
        case .walk: "Indoor walk"
        case .intervals(let stage): "Walk/jog stage \(stage.number)"
        case .yoga: "Gentle yoga"
        }
    }

    var activityType: HKWorkoutActivityType {
        switch self {
        case .strength: .traditionalStrengthTraining
        case .walk: .walking
        // Same type the iPhone uses for walk/jog sessions.
        case .intervals: .running
        case .yoga: .yoga
        }
    }
}

/// Runs the session with `HKWorkoutSession` + `HKLiveWorkoutBuilder`: heart rate and active energy are measured live,
/// the session counts toward the Activity rings, and the finished workout is saved to Apple Health with the same
/// NutriLens ID and payload the iPhone uses.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    enum Phase: Equatable {
        case idle, starting, running, paused
        /// Stopped; waiting for the finish screen (save or discard).
        case ended
        case saving
    }

    private(set) var phase: Phase = .idle
    private(set) var active: ActiveWorkout?
    private(set) var startDate: Date?
    private(set) var endDate: Date?
    private(set) var heartRate: Double = 0
    private(set) var averageHeartRate: Double = 0
    private(set) var activeEnergy: Double = 0
    private(set) var steps: Double = 0
    private(set) var distanceMeters: Double = 0
    var errorMessage: String?
    /// The NutriLens record ID for this session (Health metadata and the iPhone's log).
    private(set) var recordID = UUID()

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var pausedTotal: TimeInterval = 0
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var endedContinuation: CheckedContinuation<Void, Never>?
    /// Simulator screenshots: no HealthKit, sample numbers.
    @ObservationIgnored let simulated: Bool

    init(simulated: Bool = false) {
        self.simulated = simulated
        super.init()
    }

    // MARK: Time

    /// Active (unpaused) time.
    func elapsed(at date: Date) -> TimeInterval {
        guard let startDate else { return 0 }
        let until = endDate ?? date
        let pausedNow = pausedAt.map { until.timeIntervalSince($0) } ?? 0
        return max(0, until.timeIntervalSince(startDate) - pausedTotal - pausedNow)
    }

    // MARK: Control

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable(), !simulated else { return }
        let share: Set<HKSampleType> = [
            HKQuantityType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.stepCount),
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.stepCount), HKObjectType.activitySummaryType(),
        ]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start(_ workout: ActiveWorkout) async {
        guard phase == .idle else { return }
        reset()
        active = workout
        phase = .starting
        if simulated {
            startDate = .now.addingTimeInterval(-14 * 60 - 32)
            heartRate = 118
            averageHeartRate = 104
            activeEnergy = 96
            phase = .running
            return
        }
        await requestAuthorization()
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workout.activityType
        configuration.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let source = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            if workout.kind == .walk || workout.kind == .walkJog {
                source.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
            }
            builder.dataSource = source
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date.now
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            phase = .running
        } catch {
            errorMessage = "Couldn't start: \(error.localizedDescription)"
            session?.end()
            reset()
        }
    }

    func pause() {
        guard phase == .running else { return }
        pausedAt = .now
        phase = .paused
        session?.pause()
    }

    func resume() {
        guard phase == .paused else { return }
        if let pausedAt { pausedTotal += Date.now.timeIntervalSince(pausedAt) }
        pausedAt = nil
        phase = .running
        session?.resume()
    }

    /// Stops measuring and shows the finish screen.
    func end() async {
        guard phase == .running || phase == .paused else { return }
        let end = Date.now
        if let pausedAt { pausedTotal += end.timeIntervalSince(pausedAt) }
        pausedAt = nil
        endDate = end
        guard let session, let builder else {
            phase = .ended
            return
        }
        if session.state != .ended {
            await withCheckedContinuation { continuation in
                endedContinuation = continuation
                session.end()
            }
        }
        do {
            try await builder.endCollection(at: end)
        } catch {
            errorMessage = error.localizedDescription
        }
        updateStatistics(from: builder)
        phase = .ended
    }

    /// Saves the workout to Apple Health with NutriLens's ID and payload. Returns the Health workout's UUID.
    func save(payload: WorkoutPayload) async throws -> UUID? {
        guard phase == .ended else { return nil }
        phase = .saving
        defer { if phase == .saving { phase = .ended } }
        guard let builder else { return nil }
        var metadata: [String: Any] = [HKMetadataKeyIndoorWorkout: true, HealthSyncKey.recordID: recordID.uuidString]
        if let json = PayloadCoder.encode(payload) { metadata[HealthSyncKey.payload] = json }
        try await builder.addMetadata(metadata)
        let workout = try await builder.finishWorkout()
        return workout?.uuid
    }

    func discard() {
        builder?.discardWorkout()
        if let session, session.state != .ended { session.end() }
        reset()
    }

    /// Back to the start screen after saving.
    func close() {
        reset()
    }

    private func reset() {
        phase = .idle
        active = nil
        startDate = nil
        endDate = nil
        heartRate = 0
        averageHeartRate = 0
        activeEnergy = 0
        steps = 0
        distanceMeters = 0
        pausedTotal = 0
        pausedAt = nil
        session = nil
        builder = nil
        recordID = UUID()
    }

    // MARK: Statistics

    private func updateStatistics(from builder: HKLiveWorkoutBuilder) {
        let values = Self.statistics(builder)
        apply(values)
    }

    fileprivate func apply(_ values: Statistics) {
        if let hr = values.heartRate { heartRate = hr }
        if let avg = values.averageHeartRate { averageHeartRate = avg }
        if let kcal = values.activeEnergy { activeEnergy = kcal }
        if let steps = values.steps { self.steps = steps }
        if let meters = values.distance { distanceMeters = meters }
    }

    fileprivate struct Statistics: Sendable {
        var heartRate: Double?
        var averageHeartRate: Double?
        var activeEnergy: Double?
        var steps: Double?
        var distance: Double?
    }

    fileprivate nonisolated static func statistics(_ builder: HKLiveWorkoutBuilder) -> Statistics {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = builder.statistics(for: HKQuantityType(.heartRate))
        return Statistics(
            heartRate: hr?.mostRecentQuantity()?.doubleValue(for: bpm),
            averageHeartRate: hr?.averageQuantity()?.doubleValue(for: bpm),
            activeEnergy: builder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            steps: builder.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()?.doubleValue(for: .count()),
            distance: builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter())
        )
    }

    fileprivate func sessionEnded() {
        endedContinuation?.resume()
        endedContinuation = nil
    }

    fileprivate func sessionFailed(_ message: String) {
        errorMessage = message
        sessionEnded()
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        Task { @MainActor in self.sessionEnded() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.sessionFailed(message) }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let values = Self.statistics(workoutBuilder)
        Task { @MainActor in self.apply(values) }
    }
}

/// Wrist taps.
enum Haptics {
    static func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}
