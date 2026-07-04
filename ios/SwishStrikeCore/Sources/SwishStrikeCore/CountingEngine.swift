import Foundation

// ----------------------------------------------------------------------------
// Swish Strike — CountingEngine (Swift)
//
// The Swift mirror of web-prototype/js/countingEngine.js. Same input sample
// sequence MUST produce the same count. This is the brain of the iOS app and it
// is intentionally pure — no camera, no Vision, no UI — so it unit-tests with
// `swift run SwishStrikeCoreCheck`. Parity with the JS engine is guarded by matched
// suites AND a shared golden trace (golden.fixtures.json) replayed through both.
//
// Robustness guards (see update()): out-of-order/duplicate frames are dropped,
// non-finite coordinates are treated as misses, a long detector gap resets the
// track so no phantom crossing is synthesized across an occlusion, and a
// degenerate (zero-area) zone never fires.
// ----------------------------------------------------------------------------

public enum RuleType: String, Sendable {
    case zoneCrossDown
    case zoneStreak
    case bounceReversal
}

/// A target zone in normalized coordinates (0...1, y pointing down).
public struct Zone: Sendable, Equatable {
    public var left, top, right, bottom: Double
    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}

public enum ReversalDirection: String, Sendable {
    case bottom // troughs (juggle touch, floor bounce)
    case top    // apexes
}

public struct CountRule: Sendable {
    public var type: RuleType
    public var zone: Zone?
    public var xTolerance: Double
    public var armWindow: Double
    public var cooldown: Double
    public var direction: ReversalDirection
    public var minAmplitude: Double
    public var missMargin: Double // zoneStreak: how far below the zone counts as a miss
    public var smoothingAlpha: Double
    public var minConfidence: Double
    public var maxGap: Double

    public static func zoneCrossDown(_ zone: Zone,
                                     xTolerance: Double = 0.05,
                                     armWindow: Double = 1.5,
                                     cooldown: Double = 1.0,
                                     smoothingAlpha: Double = 0.5,
                                     minConfidence: Double = 0.30,
                                     maxGap: Double = 1.5) -> CountRule {
        CountRule(type: .zoneCrossDown, zone: zone, xTolerance: xTolerance,
                  armWindow: armWindow, cooldown: cooldown, direction: .bottom,
                  minAmplitude: 0, missMargin: 0.18, smoothingAlpha: smoothingAlpha,
                  minConfidence: minConfidence, maxGap: maxGap)
    }

    /// zoneStreak rule. Detects makes exactly like zoneCrossDown, but the engine count
    /// tracks the CONSECUTIVE streak: a make increments it, and a miss (the ball, after
    /// being aimed at the target, falls more than `missMargin` past the zone without
    /// scoring) resets it to 0. Used by Free-Throw Streak.
    public static func zoneStreak(_ zone: Zone,
                                  xTolerance: Double = 0.05,
                                  armWindow: Double = 1.5,
                                  cooldown: Double = 1.0,
                                  missMargin: Double = 0.18,
                                  smoothingAlpha: Double = 0.5,
                                  minConfidence: Double = 0.30,
                                  maxGap: Double = 1.5) -> CountRule {
        CountRule(type: .zoneStreak, zone: zone, xTolerance: xTolerance,
                  armWindow: armWindow, cooldown: cooldown, direction: .bottom,
                  minAmplitude: 0, missMargin: missMargin, smoothingAlpha: smoothingAlpha,
                  minConfidence: minConfidence, maxGap: maxGap)
    }

    public static func bounceReversal(direction: ReversalDirection = .bottom,
                                      minAmplitude: Double = 0.12,
                                      cooldown: Double = 0.25,
                                      smoothingAlpha: Double = 0.5,
                                      minConfidence: Double = 0.30,
                                      maxGap: Double = 1.5) -> CountRule {
        CountRule(type: .bounceReversal, zone: nil, xTolerance: 0,
                  armWindow: 0, cooldown: cooldown, direction: direction,
                  minAmplitude: minAmplitude, missMargin: 0.18, smoothingAlpha: smoothingAlpha,
                  minConfidence: minConfidence, maxGap: maxGap)
    }
}

/// One detection sample. A missing detection = nil x/y, or confidence below floor.
public struct Sample: Sendable {
    public var t: Double
    public var x: Double?
    public var y: Double?
    public var confidence: Double?
    public init(t: Double, x: Double? = nil, y: Double? = nil, confidence: Double? = nil) {
        self.t = t; self.x = x; self.y = y; self.confidence = confidence
    }
}

public struct ScoreEvent: Sendable, Equatable {
    public var t: Double
    public var count: Int
    public var quality: String?     // "swish" | "rim" — shot-quality metadata (zoneCrossDown)
    public var centerError: Double? // 0 = dead center, 1 = at the zone edge
    public var type: String?        // "miss" on a streak-reset event; nil for a make
    public init(t: Double, count: Int, quality: String? = nil, centerError: Double? = nil, type: String? = nil) {
        self.t = t; self.count = count; self.quality = quality; self.centerError = centerError; self.type = type
    }
}

public final class CountingEngine {
    public let rule: CountRule
    public private(set) var count: Int = 0
    public private(set) var events: [ScoreEvent] = []
    public private(set) var lastEvent: ScoreEvent?  // most recent score event (incl. shot quality)
    public private(set) var justMissed = false      // true only on the update where a streak miss resolved

    private var sx: Double?
    private var sy: Double?
    private var py: Double?
    private var lastT: Double = -.infinity
    private var lastValidT: Double = -.infinity
    private var lastCountT: Double = -.infinity
    private var lastQuality: (quality: String, centerError: Double)? // computed at fire, consumed on append
    // zoneCrossDown
    private var armed = false
    private var armedT: Double = -.infinity
    // zoneStreak: a shot is in flight (armed once, awaiting make-or-miss resolution)
    private var attemptActive = false
    // shot-quality (swish vs rim)
    private var descentReversals = 0
    private var lastDySign = 0
    // bounceReversal
    private var extremeVal: Double?
    private var sawApproach = false

    public init(rule: CountRule) { self.rule = rule }

    public func reset() {
        count = 0
        events.removeAll()
        lastEvent = nil
        justMissed = false
        lastT = -.infinity
        lastValidT = -.infinity
        lastCountT = -.infinity
        lastQuality = nil
        resetTrack()
    }

    /// Clears only the per-frame tracking state (not the count/history).
    private func resetTrack() {
        sx = nil; sy = nil; py = nil
        armed = false; armedT = -.infinity
        attemptActive = false
        descentReversals = 0; lastDySign = 0
        extremeVal = nil; sawApproach = false
    }

    /// Smoothed position, or nil if nothing has been seen yet.
    public var position: (x: Double, y: Double)? {
        guard let sx, let sy else { return nil }
        return (sx, sy)
    }

    /// Feed one sample. Returns true iff a score event fired.
    @discardableResult
    public func update(_ s: Sample) -> Bool {
        let t = s.t
        justMissed = false // reset every accepted/rejected frame (before any early return below)

        // Order guard: drop out-of-order/duplicate frames (also rejects NaN t).
        guard t > lastT else { return false }
        lastT = t

        // Long-gap discontinuity: reset the track so no crossing is synthesized
        // across a long detector silence. Count/history preserved.
        if lastValidT != -.infinity, t - lastValidT > rule.maxGap {
            resetTrack()
        }

        // Validity gate: finite x/y and (if provided) finite confidence ≥ floor.
        let confOK = s.confidence == nil || (s.confidence!.isFinite && s.confidence! >= rule.minConfidence)
        guard let x = s.x, let y = s.y, x.isFinite, y.isFinite, confOK else {
            return false // a miss — state held, time advanced
        }
        lastValidT = t

        let a = rule.smoothingAlpha
        sx = (sx == nil) ? x : a * x + (1 - a) * sx!
        sy = (sy == nil) ? y : a * y + (1 - a) * sy!

        var fired = false, missed = false
        switch rule.type {
        case .zoneCrossDown:  fired = detectMake(t)
        case .zoneStreak:
            let res = zoneStreak(t)
            fired = (res == .make); missed = (res == .miss)
        case .bounceReversal: fired = bounceReversal(t)
        }

        py = sy
        if fired {
            count += 1
            lastCountT = t
            let ev = ScoreEvent(t: t, count: count,
                                quality: lastQuality?.quality,
                                centerError: lastQuality?.centerError)
            lastQuality = nil
            events.append(ev)
            lastEvent = ev
        } else if missed {
            count = 0 // streak broken — reset, but do NOT set a cooldown (next shot is fair)
            let ev = ScoreEvent(t: t, count: 0, type: "miss")
            events.append(ev)
            lastEvent = ev
            justMissed = true
        }
        return fired
    }

    @discardableResult
    public func feed(_ samples: [Sample]) -> Int {
        for s in samples { _ = update(s) }
        return count
    }

    // Detects a single make through the zone (shared by zoneCrossDown and zoneStreak).
    // Returns true on a make and stashes its swish/rim quality. Behavior is unchanged
    // from the original zoneCrossDown, so the golden parity stays exact.
    private func detectMake(_ t: Double) -> Bool {
        guard let z = rule.zone, let sx = sx, let sy = sy else { return false }
        if z.right <= z.left || z.bottom <= z.top { return false } // degenerate zone never fires

        let inBand = sx >= z.left - rule.xTolerance && sx <= z.right + rule.xTolerance

        // Arm when first seen above the zone and aligned; reset shot-quality
        // tracking on the rising edge so each attempt is classified independently.
        if inBand && sy < z.top {
            if !armed { descentReversals = 0; lastDySign = 0 }
            armed = true; armedT = t
        }
        if armed && t - armedT > rule.armWindow { armed = false }

        // Shot-quality signal: while tracking a descent, count vertical reversals.
        // A clean swish falls monotonically; a rim rattle pops the ball back up
        // before it drops, so a down→up flip is evidence of a rim contact.
        if armed, let py = py {
            let dy = sy - py
            let sign = dy > 1e-4 ? 1 : (dy < -1e-4 ? -1 : 0)
            if sign != 0 {
                if lastDySign == 1 && sign == -1 { descentReversals += 1 }
                lastDySign = sign
            }
        }

        let movingDown = (py == nil) ? true : (sy > py!)
        let crossedBelow = sy > z.bottom
        let cooledDown = t - lastCountT > rule.cooldown

        if armed && inBand && crossedBelow && movingDown && cooledDown && t - armedT <= rule.armWindow {
            armed = false
            lastQuality = classifyShot(z)
            return true
        }
        return false
    }

    private enum StreakResult { case make, miss, none }

    // zoneStreak: detect a make (via detectMake) and, otherwise, a miss — a shot that
    // armed (was aimed at the rim) but then fell more than `missMargin` past the zone
    // without scoring. Returns .make | .miss | .none.
    private func zoneStreak(_ t: Double) -> StreakResult {
        guard let z = rule.zone, let sy = sy else { return .none }
        if z.right <= z.left || z.bottom <= z.top { return .none }
        let wasArmed = armed
        let made = detectMake(t)
        if armed && !wasArmed { attemptActive = true } // a shot just went up at the rim
        if made { attemptActive = false; return .make }
        if attemptActive && sy > z.bottom + rule.missMargin {
            attemptActive = false // the ball fell past the rim without going in
            return .miss
        }
        return .none
    }

    /// Classify a made basket at the crossing point as a clean "swish" or a "rim"
    /// rattle. Pure metadata — it does NOT affect whether/when a score fires, so
    /// the count (and cross-language golden parity) is unchanged. A make is a swish
    /// when it crosses through the central half of the zone with no rim pop-up.
    private func classifyShot(_ z: Zone) -> (quality: String, centerError: Double) {
        let cx = (z.left + z.right) / 2
        let halfW = ((z.right - z.left) / 2 != 0) ? (z.right - z.left) / 2 : 1e-6
        let centerError = abs((sx ?? cx) - cx) / halfW // 0 = dead center, 1 = at the edge
        let clean = centerError <= 0.5 && descentReversals == 0
        return (clean ? "swish" : "rim", centerError)
    }

    private func bounceReversal(_ t: Double) -> Bool {
        guard let sy = sy else { return false }
        let dirSign: Double = (rule.direction == .bottom) ? 1 : -1
        let val = dirSign * sy

        if extremeVal == nil || val > extremeVal! { extremeVal = val }
        if let py = py {
            let towardExtreme = (sy - py) * dirSign
            if towardExtreme > 0 { sawApproach = true }
        }

        let retreat = (extremeVal == nil) ? 0 : extremeVal! - val
        let cooledDown = t - lastCountT > rule.cooldown
        if sawApproach && retreat >= rule.minAmplitude && cooledDown {
            extremeVal = val
            return true
        }
        return false
    }
}
