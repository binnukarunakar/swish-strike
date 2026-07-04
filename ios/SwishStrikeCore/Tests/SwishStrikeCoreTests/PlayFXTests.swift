import XCTest
@testable import SwishStrikeCore

// Mirror of web-prototype/test/playfx.test.mjs (times converted ms -> seconds).
// If you change one suite, change the other and keep both green.
final class PlayFXTests: XCTestCase {

    func testTrailKeepsPointsInsideFadeWindowFreshestHighest() {
        let tb = TrailBuffer(maxAge: 0.8, maxCount: 64)
        tb.push(now: 0.0, x: 0.5, y: 0.5)   // age 0.8s at now=0.8 -> exactly on the edge
        tb.push(now: 0.4, x: 0.5, y: 0.4)
        tb.push(now: 0.8, x: 0.5, y: 0.3)   // freshest
        let live = tb.live(now: 0.8)
        XCTAssertEqual(live.count, 3)
        XCTAssertGreaterThan(live[2].fade, live[0].fade, "newer points fade in stronger")
        XCTAssertGreaterThan(live[2].fade, 0.99, "the just-pushed point is fully opaque")
    }

    func testTrailDropsPointsOlderThanWindow() {
        let tb = TrailBuffer(maxAge: 0.5)
        tb.push(now: 0.0, x: 0.5, y: 0.5)
        tb.push(now: 1.0, x: 0.5, y: 0.5)
        XCTAssertEqual(tb.live(now: 1.0).count, 1, "the 1s-old point has expired")
    }

    func testTrailIgnoresNonFiniteCoordinates() {
        let tb = TrailBuffer()
        tb.push(now: 0.00, x: Double.nan, y: 0.5)
        tb.push(now: 0.01, x: 0.5, y: Double.infinity)
        XCTAssertTrue(tb.live(now: 0.01).isEmpty)
        XCTAssertTrue(tb.snapshotArc(now: 0.01).isEmpty)
    }

    func testSnapshotArcReturnsRecentArcAsPlainPoints() {
        let tb = TrailBuffer()
        tb.push(now: 0.0, x: 0.5, y: 0.9)
        tb.push(now: 0.1, x: 0.5, y: 0.5)
        tb.push(now: 0.2, x: 0.5, y: 0.2)
        let arc = tb.snapshotArc(now: 0.2, span: 1.4)
        XCTAssertEqual(arc.count, 3)
        XCTAssertTrue(arc[0] == (x: 0.5, y: 0.9))
        XCTAssertTrue(arc[1] == (x: 0.5, y: 0.5))
        XCTAssertTrue(arc[2] == (x: 0.5, y: 0.2))
    }

    func testHeatRisesOnScoreClampsAndReportsOnFire() {
        let h = Heat(perScore: 0.34, decayPerSec: 0.5)
        h.tick(now: 0)
        h.bump(); h.bump(); h.bump()         // ~1.02 internal
        XCTAssertEqual(h.tick(now: 0), 1, "level is clamped to 1")
        XCTAssertTrue(h.onFire, "three quick scores light the fire")
    }

    func testHeatDecaysTowardZeroOverTime() {
        let h = Heat(perScore: 0.34, decayPerSec: 0.5)
        h.tick(now: 0); h.bump()             // value ~0.34
        h.tick(now: 1)                       // -0.5 -> 0 (clamped)
        XCTAssertEqual(h.level, 0, "heat cools after a quiet second")
        XCTAssertFalse(h.onFire)
    }
}
