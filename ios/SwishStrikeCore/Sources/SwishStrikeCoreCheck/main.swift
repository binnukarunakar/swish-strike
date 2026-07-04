import SwishStrikeCore
import Foundation

// Headless verification harness for SwishStrikeCore — runs WITHOUT XCTest so it works
// on a bare Swift toolchain (no Xcode). Mirrors SwishStrikeCoreTests/CountingEngineTests
// and web-prototype/test/engine.test.mjs. Exits non-zero if anything fails.

var failures = 0
var total = 0
func check(_ name: String, _ condition: Bool) {
    total += 1
    if condition { print("  ✔ \(name)") }
    else { print("  ✘ FAIL: \(name)"); failures += 1 }
}

let hoop = Zone(left: 0.35, top: 0.30, right: 0.65, bottom: 0.42)

func makeShot(_ t0: Double, x: Double = 0.5) -> [Sample] {
    [ Sample(t: t0 + 0.00, x: x, y: 0.10, confidence: 0.9),
      Sample(t: t0 + 0.05, x: x, y: 0.22, confidence: 0.9),
      Sample(t: t0 + 0.10, x: x, y: 0.36, confidence: 0.9),
      Sample(t: t0 + 0.15, x: x, y: 0.50, confidence: 0.9),
      Sample(t: t0 + 0.20, x: x, y: 0.70, confidence: 0.9) ]
}

print("SwishStrikeCore — counting engine verification")

// 1. clean make counts once
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop))
    e.feed(makeShot(0))
    check("a clean make counts exactly once", e.count == 1 && e.events.count == 1)
}
// 2. two makes past cooldown
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop, cooldown: 1.0))
    e.feed(makeShot(0)); e.feed(makeShot(2.0))
    check("two makes past the cooldown count twice", e.count == 2)
}
// 3. second crossing inside cooldown does not double-count
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop, cooldown: 1.0))
    e.feed(makeShot(0)); e.feed(makeShot(0.3))
    check("a re-cross inside the cooldown does NOT double-count", e.count == 1)
}
// 4. rim-out does not count
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop))
    e.feed([
        Sample(t: 0.00, x: 0.50, y: 0.10, confidence: 0.9),
        Sample(t: 0.05, x: 0.62, y: 0.28, confidence: 0.9),
        Sample(t: 0.10, x: 0.85, y: 0.45, confidence: 0.9),
        Sample(t: 0.15, x: 0.95, y: 0.70, confidence: 0.9),
    ])
    check("a rim-out (ball leaves the x-band) does NOT count", e.count == 0)
}
// 5. upward pass does not count
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop))
    e.feed([
        Sample(t: 0.00, x: 0.5, y: 0.70, confidence: 0.9),
        Sample(t: 0.05, x: 0.5, y: 0.50, confidence: 0.9),
        Sample(t: 0.10, x: 0.5, y: 0.36, confidence: 0.9),
        Sample(t: 0.15, x: 0.5, y: 0.10, confidence: 0.9),
    ])
    check("an upward pass through the zone does NOT count", e.count == 0)
}
// 6. low confidence ignored
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop))
    let shot = makeShot(0).map { Sample(t: $0.t, x: $0.x, y: $0.y, confidence: 0.1) }
    e.feed(shot)
    check("low-confidence detections are ignored", e.count == 0)
}
// 7. dropout mid-flight still counts
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop))
    e.feed([
        Sample(t: 0.00, x: 0.5, y: 0.10, confidence: 0.9),
        Sample(t: 0.05, x: 0.5, y: 0.30, confidence: 0.0),
        Sample(t: 0.10, x: 0.5, y: 0.50, confidence: 0.9),
        Sample(t: 0.15, x: 0.5, y: 0.70, confidence: 0.9),
    ])
    check("a detector dropout mid-flight still counts the make", e.count == 1)
}
// 8. arm timeout
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop, armWindow: 0.5))
    e.feed([
        Sample(t: 0.0, x: 0.5, y: 0.10, confidence: 0.9),
        Sample(t: 1.0, x: 0.5, y: 0.36, confidence: 0.9),
        Sample(t: 1.1, x: 0.5, y: 0.50, confidence: 0.9),
    ])
    check("an expired arm window does not count a late drop", e.count == 0)
}
// 9. bounce reversal counts juggles
do {
    let e = CountingEngine(rule: .bounceReversal(direction: .bottom, minAmplitude: 0.15, cooldown: 0.1))
    var samples: [Sample] = []
    var t = 0.0
    let apex = 0.3, trough = 0.8
    for _ in 0..<3 {
        for y in [0.4, 0.6, trough] { t += 0.05; samples.append(Sample(t: t, x: 0.5, y: y, confidence: 0.9)) }
        for y in [0.6, 0.4, apex]   { t += 0.05; samples.append(Sample(t: t, x: 0.5, y: y, confidence: 0.9)) }
    }
    e.feed(samples)
    check("bounceReversal counts juggle touches (amplitude-gated)", e.count == 3)
}
// 10. micro jitter does not count
do {
    let e = CountingEngine(rule: .bounceReversal(direction: .bottom, minAmplitude: 0.20, cooldown: 0.05))
    var samples: [Sample] = []
    var t = 0.0
    for i in 0..<20 {
        let y = 0.5 + (i % 2 == 0 ? 0.015 : -0.015)
        t += 0.05; samples.append(Sample(t: t, x: 0.5, y: y, confidence: 0.9))
    }
    e.feed(samples)
    check("micro-jitter below the amplitude threshold does not count", e.count == 0)
}
// 11. reset
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop))
    e.feed(makeShot(0))
    let before = e.count
    e.reset()
    check("reset() clears all state", before == 1 && e.count == 0 && e.events.isEmpty && e.position == nil)
}
// 12. order guard
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop))
    e.feed(makeShot(0))                                            // count 1, last t = 0.20
    let before = e.count
    _ = e.update(Sample(t: 0.10, x: 0.5, y: 0.50, confidence: 0.9)) // older -> ignored
    _ = e.update(Sample(t: 0.20, x: 0.5, y: 0.50, confidence: 0.9)) // duplicate t -> ignored
    check("out-of-order and duplicate timestamps are dropped", e.count == before)
}
// 13. non-finite coordinates
do {
    let e = CountingEngine(rule: .zoneCrossDown(hoop))
    _ = e.update(Sample(t: 0.0, x: Double.nan, y: 0.5, confidence: 0.9))
    _ = e.update(Sample(t: 0.1, x: 0.5, y: Double.infinity, confidence: 0.9))
    _ = e.update(Sample(t: 0.2, x: 0.5, y: 0.5, confidence: Double.nan))
    check("non-finite coordinates are treated as misses", e.count == 0)
    e.feed(makeShot(1.0))
    check("a real make still counts after non-finite garbage", e.count == 1)
}
// 14. long-gap discontinuity: track resets instead of blending across the gap
do {
    let g = CountingEngine(rule: .zoneCrossDown(hoop, maxGap: 1.0))
    _ = g.update(Sample(t: 0.0, x: 0.2, y: 0.10, confidence: 0.9))
    _ = g.update(Sample(t: 5.0, x: 0.8, y: 0.90, confidence: 0.9)) // gap 5s > maxGap -> reset
    let gp = g.position
    check("long gap resets the track (no blend across occlusion)",
          gp != nil && abs(gp!.x - 0.8) < 1e-9 && abs(gp!.y - 0.90) < 1e-9 && g.count == 0)

    let c = CountingEngine(rule: .zoneCrossDown(hoop, maxGap: 10))
    _ = c.update(Sample(t: 0.0, x: 0.2, y: 0.10, confidence: 0.9))
    _ = c.update(Sample(t: 5.0, x: 0.8, y: 0.90, confidence: 0.9)) // gap < maxGap -> blends
    let cp = c.position
    check("control: sub-maxGap gap blends (EMA midpoint)",
          cp != nil && abs(cp!.x - 0.5) < 1e-9 && abs(cp!.y - 0.5) < 1e-9)
}
// 15. degenerate zone
do {
    let bad = Zone(left: 0.6, top: 0.3, right: 0.4, bottom: 0.2) // right<left, bottom<top
    let e = CountingEngine(rule: .zoneCrossDown(bad))
    e.feed(makeShot(0))
    check("degenerate (inverted) zone never fires", e.count == 0)
}

// --- shot-quality classification (swish vs rim) — mirrors quality.test.mjs ---
// Center x = 0.5; the hoop zone spans 0.36–0.64 with a 0.9s cooldown.
let qualityHoop = Zone(left: 0.36, top: 0.26, right: 0.64, bottom: 0.38)

// 16. centered, monotonic drop -> swish (still counts once)
do {
    let e = CountingEngine(rule: .zoneCrossDown(qualityHoop, cooldown: 0.9))
    e.feed([
        Sample(t: 0.1, x: 0.5, y: 0.08, confidence: 0.95),
        Sample(t: 0.2, x: 0.5, y: 0.12, confidence: 0.95),
        Sample(t: 0.3, x: 0.5, y: 0.20, confidence: 0.95),
        Sample(t: 0.4, x: 0.5, y: 0.30, confidence: 0.95),
        Sample(t: 0.5, x: 0.5, y: 0.40, confidence: 0.95),
        Sample(t: 0.6, x: 0.5, y: 0.55, confidence: 0.95),
    ])
    check("a centered monotonic drop is a swish (counts once)",
          e.count == 1 && e.lastEvent?.quality == "swish" && (e.lastEvent?.centerError ?? 1) <= 0.5)
}
// 17. off-center make (x = 0.62, near the right edge) -> rim (still counts once)
do {
    let e = CountingEngine(rule: .zoneCrossDown(qualityHoop, cooldown: 0.9))
    e.feed([
        Sample(t: 0.1, x: 0.62, y: 0.08, confidence: 0.95),
        Sample(t: 0.2, x: 0.62, y: 0.12, confidence: 0.95),
        Sample(t: 0.3, x: 0.62, y: 0.20, confidence: 0.95),
        Sample(t: 0.4, x: 0.62, y: 0.30, confidence: 0.95),
        Sample(t: 0.5, x: 0.62, y: 0.40, confidence: 0.95),
        Sample(t: 0.6, x: 0.62, y: 0.55, confidence: 0.95),
    ])
    check("an off-center make is a rim rattle (counts once)",
          e.count == 1 && e.lastEvent?.quality == "rim" && (e.lastEvent?.centerError ?? 0) > 0.5)
}
// 18. centered make that pops up off the rim mid-descent -> rim (still counts once)
do {
    let e = CountingEngine(rule: .zoneCrossDown(qualityHoop, cooldown: 0.9))
    e.feed([
        Sample(t: 0.1, x: 0.5, y: 0.08, confidence: 0.95),
        Sample(t: 0.2, x: 0.5, y: 0.12, confidence: 0.95),
        Sample(t: 0.3, x: 0.5, y: 0.20, confidence: 0.95),
        Sample(t: 0.4, x: 0.5, y: 0.30, confidence: 0.95),
        Sample(t: 0.5, x: 0.5, y: 0.40, confidence: 0.95),
        Sample(t: 0.6, x: 0.5, y: 0.30, confidence: 0.95), // pops up off the rim
        Sample(t: 0.7, x: 0.5, y: 0.55, confidence: 0.95), // then drops in
    ])
    check("a centered make that pops up off the rim is a rim rattle (counts once)",
          e.count == 1 && e.lastEvent?.quality == "rim" && (e.lastEvent?.centerError ?? 1) <= 0.5)
}

// --- zoneStreak (Free-Throw Streak) — mirrors web-prototype/test/streak.test.mjs ---
// The count is a CONSECUTIVE streak: a make increments it, a detected miss resets to 0.
// A miss is a shot that armed (aimed at the rim) then fell past the zone without scoring.
let streakHoop = Zone(left: 0.36, top: 0.26, right: 0.64, bottom: 0.38) // center x = 0.5
func streakRule() -> CountRule { .zoneStreak(streakHoop, cooldown: 0.4, missMargin: 0.18) }

// A clean make centered on the rim, starting at time `t0`.
func feedMake(_ e: CountingEngine, _ t0: Double) {
    for (dt, y) in [(0.0, 0.08), (0.05, 0.20), (0.10, 0.40), (0.15, 0.56)] {
        _ = e.update(Sample(t: t0 + dt, x: 0.5, y: y, confidence: 0.95))
    }
}
// A miss: arms above the rim, then drifts OUT of the band and falls well past it.
// (Enough descent frames for the EMA-smoothed y to clear the miss line.)
func feedMiss(_ e: CountingEngine, _ t0: Double) {
    let pts: [(Double, Double, Double)] = [(0, 0.5, 0.08), (0.05, 0.62, 0.20), (0.10, 0.80, 0.40),
                                           (0.15, 0.85, 0.60), (0.20, 0.88, 0.78), (0.25, 0.90, 0.92)]
    for (dt, x, y) in pts { _ = e.update(Sample(t: t0 + dt, x: x, y: y, confidence: 0.95)) }
}

// 19. three centered makes -> streak of 3
do {
    let e = CountingEngine(rule: streakRule())
    feedMake(e, 0); feedMake(e, 1); feedMake(e, 2)
    check("zoneStreak: three in a row = streak of 3", e.count == 3 && e.justMissed == false)
}
// 20. two makes then a miss -> count 0, last event is a miss
do {
    let e = CountingEngine(rule: streakRule())
    feedMake(e, 0); feedMake(e, 1)
    let afterTwo = e.count
    feedMiss(e, 2)
    check("zoneStreak: a miss resets the streak to zero (last event = miss)",
          afterTwo == 2 && e.count == 0 && e.lastEvent?.type == "miss")
}
// 21. make,make,miss,make,make -> 2
do {
    let e = CountingEngine(rule: streakRule())
    feedMake(e, 0); feedMake(e, 1); feedMiss(e, 2); feedMake(e, 3); feedMake(e, 4)
    check("zoneStreak: the streak rebuilds after a miss (= 2)", e.count == 2)
}
// 22. a make in streak mode still classifies swish vs rim
do {
    let e = CountingEngine(rule: streakRule())
    feedMake(e, 0) // centered
    check("zoneStreak: a make is still classified swish in streak mode", e.lastEvent?.quality == "swish")
}
// 23. justMissed is true on exactly one frame
do {
    let e = CountingEngine(rule: streakRule())
    feedMake(e, 0)
    var missFrames = 0
    let pts: [(Double, Double, Double)] = [(2.0, 0.5, 0.08), (2.05, 0.62, 0.20), (2.10, 0.80, 0.40),
                                           (2.15, 0.85, 0.62), (2.20, 0.86, 0.7)]
    for (t, x, y) in pts {
        _ = e.update(Sample(t: t, x: x, y: y, confidence: 0.95))
        if e.justMissed { missFrames += 1 }
    }
    check("zoneStreak: justMissed fires on exactly one frame, not every frame after",
          missFrames == 1 && e.count == 0)
}

// --- ported modules: tracker (tracker.js), playfx (playfx.test.mjs), catalog
// --- (games.js), persistence, and the sim -> tracker -> engine pipeline
// --- (streak_pipeline.test.mjs). Implemented in ModelChecks/PipelineChecks.
runTrackerChecks()
runPlayFXChecks()
runCatalogChecks()
runPersistenceChecks()
runPipelineChecks()

print("")
if failures == 0 {
    print("All checks passed (\(total)/\(total)).")
} else {
    print("\(failures) of \(total) check(s) FAILED.")
    exit(1)
}
