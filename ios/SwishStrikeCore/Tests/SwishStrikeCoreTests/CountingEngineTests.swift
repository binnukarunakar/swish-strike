import XCTest
@testable import SwishStrikeCore

// Mirror of web-prototype/test/engine.test.mjs. Same scenarios, same expected
// counts. If you change one suite, change the other and keep both green.
final class CountingEngineTests: XCTestCase {

    let hoop = Zone(left: 0.35, top: 0.30, right: 0.65, bottom: 0.42)

    private func makeShot(_ t0: Double, x: Double = 0.5) -> [Sample] {
        [ Sample(t: t0 + 0.00, x: x, y: 0.10, confidence: 0.9),
          Sample(t: t0 + 0.05, x: x, y: 0.22, confidence: 0.9),
          Sample(t: t0 + 0.10, x: x, y: 0.36, confidence: 0.9),
          Sample(t: t0 + 0.15, x: x, y: 0.50, confidence: 0.9),
          Sample(t: t0 + 0.20, x: x, y: 0.70, confidence: 0.9) ]
    }

    func testCleanMakeCountsOnce() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop))
        e.feed(makeShot(0))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e.events.count, 1)
    }

    func testTwoMakesPastCooldown() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop, cooldown: 1.0))
        e.feed(makeShot(0))
        e.feed(makeShot(2.0))
        XCTAssertEqual(e.count, 2)
    }

    func testSecondCrossingInsideCooldownDoesNotDoubleCount() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop, cooldown: 1.0))
        e.feed(makeShot(0))
        e.feed(makeShot(0.3))
        XCTAssertEqual(e.count, 1)
    }

    func testRimOutDoesNotCount() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop))
        e.feed([
            Sample(t: 0.00, x: 0.50, y: 0.10, confidence: 0.9),
            Sample(t: 0.05, x: 0.62, y: 0.28, confidence: 0.9),
            Sample(t: 0.10, x: 0.85, y: 0.45, confidence: 0.9),
            Sample(t: 0.15, x: 0.95, y: 0.70, confidence: 0.9),
        ])
        XCTAssertEqual(e.count, 0)
    }

    func testUpwardPassDoesNotCount() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop))
        e.feed([
            Sample(t: 0.00, x: 0.5, y: 0.70, confidence: 0.9),
            Sample(t: 0.05, x: 0.5, y: 0.50, confidence: 0.9),
            Sample(t: 0.10, x: 0.5, y: 0.36, confidence: 0.9),
            Sample(t: 0.15, x: 0.5, y: 0.10, confidence: 0.9),
        ])
        XCTAssertEqual(e.count, 0)
    }

    func testLowConfidenceIgnored() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop))
        let shot = makeShot(0).map { Sample(t: $0.t, x: $0.x, y: $0.y, confidence: 0.1) }
        e.feed(shot)
        XCTAssertEqual(e.count, 0)
    }

    func testDropoutMidFlightStillCounts() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop))
        e.feed([
            Sample(t: 0.00, x: 0.5, y: 0.10, confidence: 0.9),
            Sample(t: 0.05, x: 0.5, y: 0.30, confidence: 0.0),
            Sample(t: 0.10, x: 0.5, y: 0.50, confidence: 0.9),
            Sample(t: 0.15, x: 0.5, y: 0.70, confidence: 0.9),
        ])
        XCTAssertEqual(e.count, 1)
    }

    func testArmTimeoutDoesNotCount() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop, armWindow: 0.5))
        e.feed([
            Sample(t: 0.0, x: 0.5, y: 0.10, confidence: 0.9),
            Sample(t: 1.0, x: 0.5, y: 0.36, confidence: 0.9),
            Sample(t: 1.1, x: 0.5, y: 0.50, confidence: 0.9),
        ])
        XCTAssertEqual(e.count, 0)
    }

    func testBounceReversalCountsJuggles() {
        let e = CountingEngine(rule: .bounceReversal(direction: .bottom, minAmplitude: 0.15, cooldown: 0.1))
        var samples: [Sample] = []
        var t = 0.0
        let apex = 0.3, trough = 0.8
        for _ in 0..<3 {
            for y in [0.4, 0.6, trough] { t += 0.05; samples.append(Sample(t: t, x: 0.5, y: y, confidence: 0.9)) }
            for y in [0.6, 0.4, apex]   { t += 0.05; samples.append(Sample(t: t, x: 0.5, y: y, confidence: 0.9)) }
        }
        e.feed(samples)
        XCTAssertEqual(e.count, 3)
    }

    func testMicroJitterDoesNotCount() {
        let e = CountingEngine(rule: .bounceReversal(direction: .bottom, minAmplitude: 0.20, cooldown: 0.05))
        var samples: [Sample] = []
        var t = 0.0
        for i in 0..<20 {
            let y = 0.5 + (i % 2 == 0 ? 0.015 : -0.015)
            t += 0.05; samples.append(Sample(t: t, x: 0.5, y: y, confidence: 0.9))
        }
        e.feed(samples)
        XCTAssertEqual(e.count, 0)
    }

    func testResetClearsState() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop))
        e.feed(makeShot(0))
        XCTAssertEqual(e.count, 1)
        e.reset()
        XCTAssertEqual(e.count, 0)
        XCTAssertEqual(e.events.count, 0)
        XCTAssertNil(e.position?.x)
    }

    // --- edge-case hardening -------------------------------------------------

    func testOrderGuardDropsStaleFrames() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop))
        e.feed(makeShot(0))
        let before = e.count
        _ = e.update(Sample(t: 0.10, x: 0.5, y: 0.50, confidence: 0.9)) // older
        _ = e.update(Sample(t: 0.20, x: 0.5, y: 0.50, confidence: 0.9)) // duplicate
        XCTAssertEqual(e.count, before)
    }

    func testNonFiniteCoordinatesAreMisses() {
        let e = CountingEngine(rule: .zoneCrossDown(hoop))
        _ = e.update(Sample(t: 0.0, x: Double.nan, y: 0.5, confidence: 0.9))
        _ = e.update(Sample(t: 0.1, x: 0.5, y: Double.infinity, confidence: 0.9))
        _ = e.update(Sample(t: 0.2, x: 0.5, y: 0.5, confidence: Double.nan))
        XCTAssertEqual(e.count, 0)
        e.feed(makeShot(1.0))
        XCTAssertEqual(e.count, 1)
    }

    func testLongGapResetsTrack() {
        let g = CountingEngine(rule: .zoneCrossDown(hoop, maxGap: 1.0))
        _ = g.update(Sample(t: 0.0, x: 0.2, y: 0.10, confidence: 0.9))
        _ = g.update(Sample(t: 5.0, x: 0.8, y: 0.90, confidence: 0.9))
        XCTAssertEqual(g.position?.x ?? -1, 0.8, accuracy: 1e-9)
        XCTAssertEqual(g.position?.y ?? -1, 0.90, accuracy: 1e-9)
        XCTAssertEqual(g.count, 0)

        let c = CountingEngine(rule: .zoneCrossDown(hoop, maxGap: 10))
        _ = c.update(Sample(t: 0.0, x: 0.2, y: 0.10, confidence: 0.9))
        _ = c.update(Sample(t: 5.0, x: 0.8, y: 0.90, confidence: 0.9))
        XCTAssertEqual(c.position?.x ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(c.position?.y ?? -1, 0.5, accuracy: 1e-9)
    }

    func testDegenerateZoneNeverFires() {
        let bad = Zone(left: 0.6, top: 0.3, right: 0.4, bottom: 0.2)
        let e = CountingEngine(rule: .zoneCrossDown(bad))
        e.feed(makeShot(0))
        XCTAssertEqual(e.count, 0)
    }

    // --- shot-quality classification (swish vs rim) — mirrors quality.test.mjs --
    // Center x = 0.5; the hoop zone spans 0.36–0.64 with a 0.9s cooldown.
    let qualityHoop = Zone(left: 0.36, top: 0.26, right: 0.64, bottom: 0.38)

    func testCenteredMonotonicDropIsSwish() {
        let e = CountingEngine(rule: .zoneCrossDown(qualityHoop, cooldown: 0.9))
        e.feed([
            Sample(t: 0.1, x: 0.5, y: 0.08, confidence: 0.95),
            Sample(t: 0.2, x: 0.5, y: 0.12, confidence: 0.95),
            Sample(t: 0.3, x: 0.5, y: 0.20, confidence: 0.95),
            Sample(t: 0.4, x: 0.5, y: 0.30, confidence: 0.95),
            Sample(t: 0.5, x: 0.5, y: 0.40, confidence: 0.95),
            Sample(t: 0.6, x: 0.5, y: 0.55, confidence: 0.95),
        ])
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e.lastEvent?.quality, "swish")
        XCTAssertLessThanOrEqual(e.lastEvent?.centerError ?? 1, 0.5)
    }

    func testOffCenterMakeIsRim() {
        let e = CountingEngine(rule: .zoneCrossDown(qualityHoop, cooldown: 0.9))
        e.feed([
            Sample(t: 0.1, x: 0.62, y: 0.08, confidence: 0.95),
            Sample(t: 0.2, x: 0.62, y: 0.12, confidence: 0.95),
            Sample(t: 0.3, x: 0.62, y: 0.20, confidence: 0.95),
            Sample(t: 0.4, x: 0.62, y: 0.30, confidence: 0.95),
            Sample(t: 0.5, x: 0.62, y: 0.40, confidence: 0.95),
            Sample(t: 0.6, x: 0.62, y: 0.55, confidence: 0.95),
        ])
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e.lastEvent?.quality, "rim")
        XCTAssertGreaterThan(e.lastEvent?.centerError ?? 0, 0.5)
    }

    func testCenteredPopUpIsRim() {
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
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e.lastEvent?.quality, "rim")
        XCTAssertLessThanOrEqual(e.lastEvent?.centerError ?? 1, 0.5)
    }

    // --- zoneStreak (Free-Throw Streak) — mirrors streak.test.mjs ----------------
    // Center x = 0.5; a make increments the streak, a detected miss resets it to 0.
    let streakHoop = Zone(left: 0.36, top: 0.26, right: 0.64, bottom: 0.38)
    private func streakRule() -> CountRule { .zoneStreak(streakHoop, cooldown: 0.4, missMargin: 0.18) }

    private func feedMake(_ e: CountingEngine, _ t0: Double) {
        for (dt, y) in [(0.0, 0.08), (0.05, 0.20), (0.10, 0.40), (0.15, 0.56)] {
            _ = e.update(Sample(t: t0 + dt, x: 0.5, y: y, confidence: 0.95))
        }
    }
    private func feedMiss(_ e: CountingEngine, _ t0: Double) {
        let pts: [(Double, Double, Double)] = [(0, 0.5, 0.08), (0.05, 0.62, 0.20), (0.10, 0.80, 0.40),
                                               (0.15, 0.85, 0.60), (0.20, 0.88, 0.78), (0.25, 0.90, 0.92)]
        for (dt, x, y) in pts { _ = e.update(Sample(t: t0 + dt, x: x, y: y, confidence: 0.95)) }
    }

    func testStreakConsecutiveMakesBuildStreak() {
        let e = CountingEngine(rule: streakRule())
        feedMake(e, 0); feedMake(e, 1); feedMake(e, 2)
        XCTAssertEqual(e.count, 3)
        XCTAssertFalse(e.justMissed)
    }

    func testStreakMissResetsToZero() {
        let e = CountingEngine(rule: streakRule())
        feedMake(e, 0); feedMake(e, 1)
        XCTAssertEqual(e.count, 2)
        feedMiss(e, 2)
        XCTAssertEqual(e.count, 0)
        XCTAssertEqual(e.lastEvent?.type, "miss")
    }

    func testStreakRebuildsAfterMiss() {
        let e = CountingEngine(rule: streakRule())
        feedMake(e, 0); feedMake(e, 1); feedMiss(e, 2); feedMake(e, 3); feedMake(e, 4)
        XCTAssertEqual(e.count, 2)
    }

    func testStreakMakeStillClassifiesSwish() {
        let e = CountingEngine(rule: streakRule())
        feedMake(e, 0)
        XCTAssertEqual(e.lastEvent?.quality, "swish")
    }

    func testStreakJustMissedFiresOnExactlyOneFrame() {
        let e = CountingEngine(rule: streakRule())
        feedMake(e, 0)
        var missFrames = 0
        let pts: [(Double, Double, Double)] = [(2.0, 0.5, 0.08), (2.05, 0.62, 0.20), (2.10, 0.80, 0.40),
                                               (2.15, 0.85, 0.62), (2.20, 0.86, 0.7)]
        for (t, x, y) in pts {
            _ = e.update(Sample(t: t, x: x, y: y, confidence: 0.95))
            if e.justMissed { missFrames += 1 }
        }
        XCTAssertEqual(missFrames, 1)
        XCTAssertEqual(e.count, 0)
    }
}
