import Foundation

/// Pure, deterministic shake gate shared by Core Motion and validation tests.
struct WristShakeDetector {
    private(set) var energeticSamples = 0
    private(set) var lastTrigger = Date.distantPast

    mutating func ingest(
        accelerationMagnitude: Double,
        rotationMagnitude: Double,
        at now: Date
    ) -> Bool {
        if accelerationMagnitude >= 0.55 || rotationMagnitude >= 3.2 {
            energeticSamples += 1
        } else {
            energeticSamples = max(0, energeticSamples - 1)
        }

        guard energeticSamples >= 2,
              now.timeIntervalSince(lastTrigger) >= 0.35 else {
            return false
        }

        energeticSamples = 0
        lastTrigger = now
        return true
    }

    mutating func reset() {
        energeticSamples = 0
    }
}
