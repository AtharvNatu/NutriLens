import CoreMotion
import Foundation
import Observation

/// Live step count during a walk or jog, from the iPhone's motion coprocessor (on device, no network).
/// Not available in the Simulator or when Motion & Fitness access is off; sessions then use
/// Apple Health's step count for the session afterwards.
@MainActor
@Observable
final class StepCounter {
    private(set) var steps = 0
    private(set) var isCounting = false
    private(set) var unavailableReason: String?
    @ObservationIgnored private let pedometer = CMPedometer()

    var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func start(from date: Date) {
        guard isAvailable else {
            unavailableReason = "Live steps aren't available here; NutriLens uses Apple Health's step count when you finish."
            return
        }
        guard CMPedometer.authorizationStatus() != .denied, CMPedometer.authorizationStatus() != .restricted else {
            unavailableReason = "Motion & Fitness access is off for NutriLens (Settings › Privacy & Security › Motion & Fitness)."
            return
        }
        isCounting = true
        pedometer.startUpdates(from: date) { [weak self] data, _ in
            let count = data?.numberOfSteps.intValue
            Task { @MainActor in
                if let count { self?.steps = count }
            }
        }
    }

    func stop() {
        guard isCounting else { return }
        pedometer.stopUpdates()
        isCounting = false
    }
}
