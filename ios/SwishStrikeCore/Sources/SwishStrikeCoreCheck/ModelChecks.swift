import SwishStrikeCore
import Foundation

// Checks for the modules ported from the web prototype: BallTracker (tracker.js),
// TrailBuffer + Heat (playfx.js, mirrored from playfx.test.mjs), the GameCatalog
// (games.js), and the file-backed PersistenceStore. Uses the same check() style
// as main.swift.

func runTrackerChecks() {
    // first fix
    do {
        let tr = BallTracker()
        let before = tr.update(x: nil, y: nil, t: 0)
        let p = tr.update(x: 0.5, y: 0.6, t: 0.1)
        check("tracker: nil before any fix returns nil; first fix echoes the measurement",
              before == nil && p != nil && p!.valid && !p!.coasting
              && p!.x == 0.5 && p!.y == 0.6 && p!.vx == 0 && p!.vy == 0)
    }
    // tracks a moving point
    do {
        let tr = BallTracker()
        var last: TrackedPoint?
        for i in 0...20 {
            let t = Double(i) / 30
            last = tr.update(x: 0.1 + 0.02 * Double(i), y: 0.5, t: t)
        }
        check("tracker: follows a constant-velocity point (converges, speed > 0)",
              last != nil && abs(last!.x - 0.5) < 0.05 && abs(last!.y - 0.5) < 1e-9 && tr.speed > 0)
    }
    // coasts, then resets after maxCoastFrames
    do {
        let tr = BallTracker() // maxCoastFrames = 6
        _ = tr.update(x: 0.50, y: 0.5, t: 0.0)
        _ = tr.update(x: 0.52, y: 0.5, t: 1.0 / 30)
        var coastValid = true
        for i in 2...7 { // 6 misses: all coast, all still valid
            let p = tr.update(x: nil, y: nil, t: Double(i) / 30)
            coastValid = coastValid && (p != nil) && p!.coasting && p!.valid
        }
        let stale = tr.update(x: nil, y: nil, t: 8.0 / 30)   // 7th miss -> invalid + reset
        let fresh = tr.update(x: nil, y: nil, t: 9.0 / 30)   // reset track: no fix -> nil
        check("tracker: coasts through 6 misses then resets (7th is invalid, then nil)",
              coastValid && stale != nil && !stale!.valid && stale!.coasting && fresh == nil)
    }
}

func runPlayFXChecks() {
    // mirrors playfx.test.mjs (times converted ms -> seconds)
    do {
        let tb = TrailBuffer(maxAge: 0.8, maxCount: 64)
        tb.push(now: 0.0, x: 0.5, y: 0.5) // age 0.8s at now=0.8 -> exactly on the edge
        tb.push(now: 0.4, x: 0.5, y: 0.4)
        tb.push(now: 0.8, x: 0.5, y: 0.3) // freshest
        let live = tb.live(now: 0.8)
        check("trail: keeps points inside the fade window, freshest fade highest",
              live.count == 3 && live[2].fade > live[0].fade && live[2].fade > 0.99)
    }
    do {
        let tb = TrailBuffer(maxAge: 0.5)
        tb.push(now: 0.0, x: 0.5, y: 0.5)
        tb.push(now: 1.0, x: 0.5, y: 0.5)
        check("trail: drops points older than the window", tb.live(now: 1.0).count == 1)
    }
    do {
        let tb = TrailBuffer()
        tb.push(now: 0.00, x: Double.nan, y: 0.5)
        tb.push(now: 0.01, x: 0.5, y: Double.infinity)
        check("trail: ignores non-finite coordinates (engine misses)",
              tb.live(now: 0.01).isEmpty && tb.snapshotArc(now: 0.01).isEmpty)
    }
    do {
        let tb = TrailBuffer()
        tb.push(now: 0.0, x: 0.5, y: 0.9)
        tb.push(now: 0.1, x: 0.5, y: 0.5)
        tb.push(now: 0.2, x: 0.5, y: 0.2)
        let arc = tb.snapshotArc(now: 0.2, span: 1.4)
        check("trail: snapshotArc returns the recent arc as plain points",
              arc.count == 3 && arc[0] == (x: 0.5, y: 0.9)
              && arc[1] == (x: 0.5, y: 0.5) && arc[2] == (x: 0.5, y: 0.2))
    }
    do {
        let h = Heat(perScore: 0.34, decayPerSec: 0.5)
        h.tick(now: 0)
        h.bump(); h.bump(); h.bump()            // ~1.02 internal
        check("heat: rises on score, level clamps at 1, reports on-fire",
              h.tick(now: 0) == 1 && h.onFire)
    }
    do {
        let h = Heat(perScore: 0.34, decayPerSec: 0.5)
        h.tick(now: 0); h.bump()                // value ~0.34
        h.tick(now: 1)                          // -0.5 -> 0 (clamped)
        check("heat: decays toward zero over a quiet second", h.level == 0 && !h.onFire)
    }
}

func runCatalogChecks() {
    let expectedSlugs = ["hoop-count", "ping-pong-rally", "soccer-goal", "free-throw-streak",
                         "dribble-counter", "cornhole", "bottle-flip", "tennis-rally",
                         "catch-counter", "keepie-uppie", "golf-putt", "cup-pong",
                         "volley-bumps", "hacky-sack"]
    check("catalog: exactly 14 games", GameCatalog.games.count == 14)
    check("catalog: slugs match the JS catalog in order",
          GameCatalog.games.map(\.slug) == expectedSlugs)
    do {
        let ft = GameCatalog.game(slug: "free-throw-streak")!
        let r = ft.buildRule()
        check("catalog: free-throw-streak is zoneStreak(cooldown 1.0, missMargin 0.18)",
              r.type == .zoneStreak && r.cooldown == 1.0 && r.missMargin == 0.18
              && r.zone == Zone(left: 0.36, top: 0.26, right: 0.64, bottom: 0.38))
    }
    do {
        let hc = GameCatalog.game(slug: "hoop-count")!
        let r = hc.buildRule()
        check("catalog: hoop-count is the flagship (zoneCrossDown, cooldown 0.9, hoop/orange/body)",
              hc.flagship && r.type == .zoneCrossDown && r.cooldown == 0.9
              && hc.calibrate == .hoop && hc.ballHue == .orange && hc.needsBody)
    }
    do {
        let ch = GameCatalog.game(slug: "cornhole")!
        let vb = GameCatalog.game(slug: "volley-bumps")!
        check("catalog: META mirrors games.js (cornhole board/red/no-body, volley yellow/body)",
              ch.calibrate == .board && ch.ballHue == .red && !ch.needsBody
              && vb.calibrate == CalibrationMode.none && vb.ballHue == .yellow && vb.needsBody)
    }
    do {
        let custom = Zone(left: 0.1, top: 0.1, right: 0.3, bottom: 0.2)
        let zoned = GameCatalog.game(slug: "soccer-goal")!.buildRule(zoneOverride: custom)
        let bounce = GameCatalog.game(slug: "keepie-uppie")!.buildRule(zoneOverride: custom)
        check("catalog: buildRule honors a zone override (and bounce games ignore it)",
              zoned.zone == custom && bounce.zone == nil)
    }
}

func runPersistenceChecks() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("swishcore-check-\(ProcessInfo.processInfo.processIdentifier)")
    defer { try? FileManager.default.removeItem(at: dir) }
    do {
        let s1 = PersistenceStore(directory: dir)
        let freshDefaults = s1.best(for: "hoop-count") == 0 && s1.soundOn == true
        s1.setBest(7, for: "hoop-count")
        s1.soundOn = false
        let s2 = PersistenceStore(directory: dir)
        check("persistence: bests + soundOn survive a store reload (fresh defaults 0/true)",
              freshDefaults && s2.best(for: "hoop-count") == 7 && s2.soundOn == false)
        let better = s2.recordCount(9, for: "hoop-count")
        let worse = s2.recordCount(3, for: "hoop-count")
        check("persistence: recordCount keeps only a new best",
              better && !worse && s2.best(for: "hoop-count") == 9)
        s2.resetBests()
        let s3 = PersistenceStore(directory: dir)
        check("persistence: resetBests clears every stored best (and persists the wipe)",
              s2.best(for: "hoop-count") == 0 && s3.best(for: "hoop-count") == 0)
    }
}
