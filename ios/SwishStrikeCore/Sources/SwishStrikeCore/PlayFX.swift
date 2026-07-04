import Foundation

// ----------------------------------------------------------------------------
// Swish Strike — PlayFX (TrailBuffer + Heat)
//
// Play-phase effects that are deliberately NOT part of the pure counting engine.
// The Swift mirror of web-prototype/js/playfx.js, with times in SECONDS (the JS
// buffers use milliseconds: 850ms -> 0.85, 1400ms -> 1.4).
//   - TrailBuffer: a short, time-windowed history of ball positions, drawn as a
//     fading "comet" behind the ball and snapshotted as the made-shot arc for
//     the instant replay + share card.
//   - Heat: a decaying meter that rises with each score and cools over time, so
//     rapid scoring lights the screen up ("on fire").
// Both are pure data structures (no UI, no engine coupling) so they unit-test.
// ----------------------------------------------------------------------------

/// One renderable trail point; `fade` is 0..1 (1 = freshest).
public struct TrailPoint: Sendable {
    public var x, y, fade: Double
    public init(x: Double, y: Double, fade: Double) {
        self.x = x; self.y = y; self.fade = fade
    }
}

public final class TrailBuffer {
    private struct Entry { var t, x, y: Double }

    private let maxAge: Double
    private let maxCount: Int
    private var pts: [Entry] = []

    public init(maxAge: Double = 0.85, maxCount: Int = 64) {
        self.maxAge = maxAge
        self.maxCount = maxCount
    }

    public func push(now: Double, x: Double, y: Double) {
        guard x.isFinite, y.isFinite else { return }
        pts.append(Entry(t: now, x: x, y: y))
        if pts.count > maxCount { pts.removeFirst() }
    }

    /// Points within the fade window, oldest to newest, each with fade 0..1
    /// (1 = freshest).
    public func live(now: Double) -> [TrailPoint] {
        var out: [TrailPoint] = []
        for p in pts {
            let age = (now - p.t) / maxAge
            // Clamp so a point stamped ahead of `now` (clock skew) can't exceed
            // full freshness. Mirrors playfx.js exactly.
            if age <= 1 { out.append(TrailPoint(x: p.x, y: p.y, fade: min(1, 1 - age))) }
        }
        return out
    }

    /// Snapshot the recent arc (normalized points) for replay + share.
    public func snapshotArc(now: Double, span: Double = 1.4) -> [(x: Double, y: Double)] {
        pts.filter { now - $0.t <= span }.map { (x: $0.x, y: $0.y) }
    }

    public func clear() { pts.removeAll() }
}

public final class Heat {
    private let perScore: Double
    private let decayPerSec: Double
    private let maxValue: Double
    private var value = 0.0
    private var lastT: Double?

    public init(perScore: Double = 0.34, decayPerSec: Double = 0.5, max: Double = 1.4) {
        self.perScore = perScore
        self.decayPerSec = decayPerSec
        self.maxValue = max
    }

    public func bump() { value = min(maxValue, value + perScore) }

    /// Advance decay to `now` (seconds); returns the current 0..1 level.
    @discardableResult
    public func tick(now: Double) -> Double {
        if let lastT, now > lastT {
            value = max(0, value - (now - lastT) * decayPerSec)
        }
        lastT = now
        return level
    }

    /// 0..1 for rendering.
    public var level: Double { min(1, value) }

    public var onFire: Bool { value >= 1 }

    public func reset() {
        value = 0
        lastT = nil
    }
}
