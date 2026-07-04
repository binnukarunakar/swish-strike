import XCTest
@testable import SwishStrikeCore

// Mirror of the tracker behavior encoded in web-prototype/js/tracker.js:
// first-fix, smooth tracking, and coast-then-reset through detector dropouts.
final class BallTrackerTests: XCTestCase {

    func testFirstFixEchoesMeasurementAndNilBeforeAnyFix() {
        let tr = BallTracker()
        XCTAssertNil(tr.update(x: nil, y: nil, t: 0), "a miss before any fix yields nothing")
        let p = tr.update(x: 0.5, y: 0.6, t: 0.1)
        XCTAssertNotNil(p)
        XCTAssertTrue(p!.valid)
        XCTAssertFalse(p!.coasting)
        XCTAssertEqual(p!.x, 0.5)
        XCTAssertEqual(p!.y, 0.6)
        XCTAssertEqual(p!.vx, 0)
        XCTAssertEqual(p!.vy, 0)
    }

    func testTracksAConstantVelocityPoint() {
        let tr = BallTracker()
        var last: TrackedPoint?
        for i in 0...20 {
            last = tr.update(x: 0.1 + 0.02 * Double(i), y: 0.5, t: Double(i) / 30)
        }
        XCTAssertNotNil(last)
        XCTAssertEqual(last!.x, 0.5, accuracy: 0.05, "filter converges on the true position")
        XCTAssertEqual(last!.y, 0.5, accuracy: 1e-9)
        XCTAssertGreaterThan(tr.speed, 0, "a moving point produces a velocity estimate")
    }

    func testCoastsThroughMissesThenResetsAfterMaxCoastFrames() {
        let tr = BallTracker() // maxCoastFrames = 6
        _ = tr.update(x: 0.50, y: 0.5, t: 0.0)
        _ = tr.update(x: 0.52, y: 0.5, t: 1.0 / 30)
        for i in 2...7 { // 6 misses: all coast on the prediction, all still valid
            let p = tr.update(x: nil, y: nil, t: Double(i) / 30)
            XCTAssertNotNil(p)
            XCTAssertTrue(p!.coasting)
            XCTAssertTrue(p!.valid, "miss \(i - 1) of 6 is still within the coast budget")
        }
        let stale = tr.update(x: nil, y: nil, t: 8.0 / 30) // 7th miss -> stale + reset
        XCTAssertNotNil(stale)
        XCTAssertTrue(stale!.coasting)
        XCTAssertFalse(stale!.valid, "the 7th consecutive miss invalidates the track")
        XCTAssertNil(tr.update(x: nil, y: nil, t: 9.0 / 30),
                     "after the reset the tracker is back to the no-fix state")
    }
}
