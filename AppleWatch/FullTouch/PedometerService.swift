import Combine
import CoreMotion
import Foundation

final class PedometerService {
    private let pedometer = CMPedometer()

    func start(onUpdate: @escaping (Int) -> Void) {
        guard CMPedometer.isStepCountingAvailable() else { return }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, _ in
            let dayTotal = data?.numberOfSteps.intValue ?? 0
            DispatchQueue.main.async {
                onUpdate(dayTotal)
            }

            self.pedometer.startUpdates(from: Date()) { liveData, _ in
                guard let live = liveData?.numberOfSteps.intValue else { return }
                DispatchQueue.main.async {
                    onUpdate(dayTotal + live)
                }
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
    }
}

/// Converts a deliberate wrist shake into one detector walking pulse.
///
/// Both user acceleration and rotation are considered because a Watch worn
/// snugly on the wrist often produces more angular velocity than linear
/// travel. Requiring two energetic samples and applying a cooldown prevents a
/// normal tap or arm swing from advancing the game repeatedly.
final class WristShakeService: ObservableObject {
    private let motionManager = CMMotionManager()
    private var detector = WristShakeDetector()

    func start(onShake: @escaping () -> Void) {
        stop()
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) {
            [weak self] motion,
            _ in
            guard let self, let motion else { return }

            let acceleration = motion.userAcceleration
            let accelerationMagnitude = sqrt(
                acceleration.x * acceleration.x
                    + acceleration.y * acceleration.y
                    + acceleration.z * acceleration.z
            )
            let rotation = motion.rotationRate
            let rotationMagnitude = sqrt(
                rotation.x * rotation.x
                    + rotation.y * rotation.y
                    + rotation.z * rotation.z
            )

            let now = Date()
            guard self.detector.ingest(
                accelerationMagnitude: accelerationMagnitude,
                rotationMagnitude: rotationMagnitude,
                at: now
            ) else { return }
            onShake()
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        detector.reset()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}
