import Foundation

// ----------------------------------------------------------------------------
// Swish Strike — BallTracker
//
// An alpha-beta ("Kalman-lite") filter that turns noisy, gappy per-frame ball
// detections into a smooth position + velocity, and COASTS (predicts) through
// short detector dropouts/occlusions. The Swift mirror of web-prototype/js/
// tracker.js — pure and deterministic so it tests headlessly. It sits between
// the detector and the counting engine:
//   detection -> tracker.update() -> TrackedPoint -> engine
// The velocity it produces also drives the speed radar and the coach.
// ----------------------------------------------------------------------------

/// One filtered output frame. `coasting` means this frame was predicted through
/// a detector miss; `valid` goes false once the coast has gone stale.
public struct TrackedPoint: Sendable {
    public var t, x, y, vx, vy: Double
    public var valid, coasting: Bool
    public init(t: Double, x: Double, y: Double, vx: Double, vy: Double,
                valid: Bool, coasting: Bool) {
        self.t = t; self.x = x; self.y = y; self.vx = vx; self.vy = vy
        self.valid = valid; self.coasting = coasting
    }
}

public final class BallTracker {
    private let alpha: Double          // position correction gain
    private let beta: Double           // velocity correction gain
    private let maxCoastFrames: Int

    private var x: Double?
    private var y: Double?
    private var vx = 0.0
    private var vy = 0.0
    private var lastT: Double?
    private var coastCount = 0

    public init(alpha: Double = 0.5, beta: Double = 0.25, maxCoastFrames: Int = 6) {
        self.alpha = alpha
        self.beta = beta
        self.maxCoastFrames = maxCoastFrames
    }

    public func reset() {
        x = nil; y = nil
        vx = 0; vy = 0
        lastT = nil
        coastCount = 0
    }

    /// Feed one detection (nil x/y = a detector miss) at time `t`. Returns nil
    /// until the first fix; after that, misses coast on the prediction and the
    /// track resets once more than `maxCoastFrames` misses stack up.
    public func update(x mx: Double?, y my: Double?, t: Double) -> TrackedPoint? {
        // First fix.
        guard let px0 = x, let py0 = y else {
            guard let mx, let my else { return nil }
            x = mx; y = my; vx = 0; vy = 0
            lastT = t; coastCount = 0
            return TrackedPoint(t: t, x: mx, y: my, vx: 0, vy: 0, valid: true, coasting: false)
        }

        let dt = max(1e-3, t - (lastT ?? t))
        // Predict.
        let px = px0 + vx * dt
        let py = py0 + vy * dt

        if let mx, let my {
            let rx = mx - px, ry = my - py
            x = px + alpha * rx
            y = py + alpha * ry
            vx += (beta / dt) * rx
            vy += (beta / dt) * ry
            coastCount = 0
            lastT = t
            return TrackedPoint(t: t, x: x!, y: y!, vx: vx, vy: vy, valid: true, coasting: false)
        }

        // Miss: coast on the prediction.
        x = px; y = py
        coastCount += 1
        lastT = t
        let valid = coastCount <= maxCoastFrames
        if !valid { reset() } // track is stale — drop it so we don't bridge a long gap
        return TrackedPoint(t: t, x: px, y: py, vx: vx, vy: vy, valid: valid, coasting: true)
    }

    /// Current speed in normalized units/second.
    public var speed: Double { (vx * vx + vy * vy).squareRoot() }
}
