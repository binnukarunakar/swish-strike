import Foundation
import os

#if canImport(UIKit)
import CoreHaptics
import UIKit

/// Differentiated haptics, mirroring the web's vibration patterns: a clean swish
/// is one crisp tap, a rim make stutters, a miss thuds twice. CoreHaptics where
/// available, UIKit generators as the fallback — every path guarded.
@MainActor
final class Haptics {
    static let shared = Haptics()

    private let notify = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private var engine: CHHapticEngine?
    private let log = Logger(subsystem: Log.subsystem, category: "haptics")

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    func prepare() {
        notify.prepare()
        impact.prepare()
    }

    func swish() { notify.notificationOccurred(.success) }

    func rim() {
        // Two quick transients ~50ms apart — the rattle.
        if !playPattern(times: [0, 0.05], intensity: 0.8, sharpness: 0.6) {
            notify.notificationOccurred(.warning)
        }
    }

    func miss() {
        if !playPattern(times: [0, 0.09], intensity: 1.0, sharpness: 0.25) {
            impact.impactOccurred()
        }
    }

    func personalBest() { notify.notificationOccurred(.success) }

    private func playPattern(times: [TimeInterval], intensity: Float, sharpness: Float) -> Bool {
        guard let engine else { return false }
        let events = times.map { t in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ], relativeTime: t)
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: 0)
            return true
        } catch {
            log.debug("haptic pattern failed: \(error.localizedDescription)")
            return false
        }
    }
}

#else

/// No-op stand-in on platforms without UIKit so the logic layer typechecks on
/// a plain Mac (tools/typecheck-macos.sh). Never ships to a device.
@MainActor
final class Haptics {
    static let shared = Haptics()
    private init() {}
    func prepare() {}
    func swish() {}
    func rim() {}
    func miss() {}
    func personalBest() {}
}

#endif
