import Foundation

// ----------------------------------------------------------------------------
// Swish Strike — SimSource
//
// On-device simulation source, the Swift mirror of web-prototype/js/sim.js (v2).
// It synthesizes the WHOLE experience — a calibration sequence (searching ->
// adjust -> locked) and realistic play (arced basketball shots launched from
// alternating players, or a bouncing ball) — and feeds it through the exact same
// coach / detector / tracker / engine pipeline the camera uses. This is why the
// app is runnable with zero network/model and why the full flow is testable
// headlessly: same clock in -> same result out.
//
// The free-throw trajectory is deliberately robust at ANY sampling rate: the
// ball hovers at the apex IN BAND long enough that some sample always arms the
// attempt, and a brick's entire fall happens far outside the band — so a
// lagging EMA can never read a miss as a make.
// ----------------------------------------------------------------------------

/// An axis-aligned box in normalized coordinates (0..1, y down).
public struct Box: Sendable {
    public var x, y, w, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// One simulated ball detection.
public struct SimBall: Sendable {
    public var x, y, confidence: Double
    public init(x: Double, y: Double, confidence: Double) {
        self.x = x; self.y = y; self.confidence = confidence
    }
}

/// Coach signals for the SETUP phase.
public struct CalibrationSignals: Sendable {
    public var targetVisible: Bool
    public var targetBox: Box?
    public var brightness: Double
    public var bodyVisible: Bool
    public init(targetVisible: Bool, targetBox: Box?, brightness: Double, bodyVisible: Bool) {
        self.targetVisible = targetVisible
        self.targetBox = targetBox
        self.brightness = brightness
        self.bodyVisible = bodyVisible
    }
}

/// One simulated PLAY frame. `launch` marks the frame a shot leaves the hand.
public struct SimFrame: Sendable {
    public var ball: SimBall?
    public var players: [Box]
    public var launch: (x: Double, y: Double)?
    public init(ball: SimBall?, players: [Box], launch: (x: Double, y: Double)?) {
        self.ball = ball
        self.players = players
        self.launch = launch
    }
}

public struct SimSource {
    public let label: String

    private let mode: CalibrationMode
    private let isHoop: Bool    // basketball rim games get swish/rattle variety
    private let isStreak: Bool  // free-throw: shots that can miss
    private let isZone: Bool
    private let zone: Zone?
    private let hoopCx: Double
    private let fallEnd: Double

    // Two players for zone games (left/right), one centered player for bounce games.
    private static let twoPlayers = [
        Box(x: 0.24, y: 0.45, w: 0.14, h: 0.50), // P1 ~ center 0.31
        Box(x: 0.62, y: 0.45, w: 0.14, h: 0.50), // P2 ~ center 0.69
    ]
    private static let onePlayer = [Box(x: 0.42, y: 0.34, w: 0.16, h: 0.60)]

    public init(game: Game) {
        let rule = game.buildRule()
        mode = game.calibrate
        isHoop = mode == .hoop
        isStreak = rule.type == .zoneStreak
        isZone = rule.type == .zoneCrossDown || rule.type == .zoneStreak
        zone = isZone ? rule.zone : nil
        hoopCx = zone.map { ($0.left + $0.right) / 2 } ?? 0.5
        // The sim ball must clearly clear the zone's bottom edge or low targets
        // (putting cup, cup rack) would never register a score.
        fallEnd = zone.map { min(0.95, $0.bottom + 0.18) } ?? 0.60
        label = isZone ? "arced shots from two players" : "a ball bouncing in rhythm"
    }

    // Coach signals for the SETUP phase: searching -> adjust (too small) -> locked.
    public func calibration(t: Double) -> CalibrationSignals {
        let bodyVisible = t > 0.8
        let brightness = 0.5
        if mode == .none {
            let targetBox: Box? = t > 0.6 ? Box(x: 0.30, y: 0.30, w: 0.40, h: 0.30) : nil
            return CalibrationSignals(targetVisible: targetBox != nil, targetBox: targetBox,
                                      brightness: brightness, bodyVisible: bodyVisible)
        }
        let z = zone ?? Zone(left: 0.4, top: 0.4, right: 0.6, bottom: 0.55)
        let box = Box(x: z.left, y: z.top, w: z.right - z.left, h: z.bottom - z.top)
        if t < 0.7 {
            return CalibrationSignals(targetVisible: false, targetBox: nil,
                                      brightness: brightness, bodyVisible: bodyVisible)
        }
        if t < 1.6 { // found but framed too small -> coach says "move closer"
            let small = Box(x: box.x + box.w * 0.25, y: box.y, w: box.w * 0.5, h: box.h * 0.5)
            return CalibrationSignals(targetVisible: true, targetBox: small,
                                      brightness: brightness, bodyVisible: bodyVisible)
        }
        return CalibrationSignals(targetVisible: true, targetBox: box,
                                  brightness: brightness, bodyVisible: bodyVisible) // locked
    }

    // PLAY phase: the frame at simulated time t.
    public func play(t: Double) -> SimFrame {
        if isStreak { return playFreeThrow(t) }
        if !isZone {
            let period = 0.62, amp = 0.27
            let y = 0.5 + amp * cos((t / period) * .pi * 2)
            return SimFrame(ball: SimBall(x: 0.5 + sin(t * 1.7) * 0.05, y: y, confidence: 0.95),
                            players: Self.onePlayer, launch: nil)
        }
        let P = 2.2                             // seconds per shot
        let cycle = Int(t / P)
        let phase = t.truncatingRemainder(dividingBy: P) / P
        let active = cycle % 2 != 0             // alternate shooters
        let px = active ? 0.69 : 0.31           // launch column = that player
        // Basketball only: every third make rattles in off the rim instead of a
        // clean swish, so the differentiated feedback is visible in the demo. The
        // ball still drops through the zone, so the COUNT is unchanged either way.
        let rattle = isHoop && cycle % 3 == 2
        var ball: SimBall?
        var launch: (x: Double, y: Double)?
        if phase < 0.12 {                       // ball in hands, low, by the shooter
            ball = SimBall(x: px, y: 0.82, confidence: 0.9)
            launch = (x: px, y: 0.82)
        } else if phase < 0.5 {                 // rise: shooter -> apex above the hoop
            let k = (phase - 0.12) / 0.38
            ball = SimBall(x: px + (hoopCx - px) * k, y: 0.82 + (0.10 - 0.82) * k, confidence: 0.9)
        } else if phase < 0.82 {                // fall: apex -> down through the target
            let k = (phase - 0.5) / 0.32
            // A rattle reaches the rim edge early and holds (off-center cross -> the
            // engine reads it as a rim make); a swish falls straight through center.
            // Reaching the edge before the crossing lets the EMA settle there.
            let fx = rattle ? hoopCx + 0.12 * min(1, k / 0.35) : hoopCx
            ball = SimBall(x: fx, y: 0.10 + (fallEnd - 0.10) * k, confidence: 0.95)
        } // else: ball gone, engine re-arms for the next shot
        return SimFrame(ball: ball, players: Self.twoPlayers, launch: launch)
    }

    // Free-throw streak: one shooter at the line. Most shots drop clean; every
    // fourth bricks out wide (a miss the engine must reset the streak on), and
    // some makes rattle in off the rim.
    private func playFreeThrow(_ t: Double) -> SimFrame {
        let P = 2.4
        let cycle = Int(t / P)
        let phase = t.truncatingRemainder(dividingBy: P) / P
        let willMiss = cycle % 4 == 3
        let rattle = !willMiss && cycle % 3 == 2
        let sx = 0.5, apexY = 0.08 // free-throw line, centered; apex above the rim
        if phase < 0.10 {
            return SimFrame(ball: SimBall(x: sx, y: 0.84, confidence: 0.9),
                            players: Self.onePlayer, launch: (x: sx, y: 0.84))
        }
        if phase < 0.42 { // rise, centered — the top of the rise is already in-band above the rim
            let k = (phase - 0.10) / 0.32
            return SimFrame(ball: SimBall(x: sx, y: 0.84 + (apexY - 0.84) * k, confidence: 0.9),
                            players: Self.onePlayer, launch: nil)
        }
        if phase < 0.52 { // hover at the apex, centered — guarantees arming at any fps
            return SimFrame(ball: SimBall(x: sx, y: apexY, confidence: 0.95),
                            players: Self.onePlayer, launch: nil)
        }
        if willMiss {
            if phase < 0.62 { // slide wide while still high — leaves the band before falling
                let k = (phase - 0.52) / 0.10
                return SimFrame(ball: SimBall(x: sx + 0.40 * k, y: apexY + 0.04 * k, confidence: 0.95),
                                players: Self.onePlayer, launch: nil)
            }
            if phase < 0.88 { // the WHOLE fall happens at x=0.90, far outside the band
                let k = (phase - 0.62) / 0.26
                return SimFrame(ball: SimBall(x: 0.90, y: 0.12 + (0.95 - 0.12) * k, confidence: 0.95),
                                players: Self.onePlayer, launch: nil)
            }
            return SimFrame(ball: nil, players: Self.onePlayer, launch: nil)
        }
        if phase < 0.88 { // make: fall through the rim (a rattle drifts onto the iron)
            let k = (phase - 0.52) / 0.36
            let x = rattle ? hoopCx + 0.12 * min(1, k / 0.35) : hoopCx
            return SimFrame(ball: SimBall(x: x, y: apexY + (fallEnd - apexY) * k, confidence: 0.95),
                            players: Self.onePlayer, launch: nil)
        }
        return SimFrame(ball: nil, players: Self.onePlayer, launch: nil)
    }
}
