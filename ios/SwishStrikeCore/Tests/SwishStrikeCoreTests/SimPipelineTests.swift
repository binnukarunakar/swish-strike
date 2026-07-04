import XCTest
@testable import SwishStrikeCore

// Mirror of web-prototype/test/streak_pipeline.test.mjs: the free-throw sim run
// through the REAL pipeline (sim -> tracker -> engine), swept across frame rates
// and timing jitter. Every brick must resolve as a miss, never as a make.
final class SimPipelineTests: XCTestCase {

    // Deterministic LCG jitter — no randomness, so failures reproduce exactly.
    private func makeJitter(_ seed: UInt32) -> () -> Double {
        var s = seed
        return {
            s = s &* 1103515245 &+ 12345
            return Double(s % 1000) / 1000 - 0.5
        }
    }

    private struct Result { var makes = 0; var misses = 0; var longest = 0 }

    private func runPipeline(fps: Double, seconds: Double, jitterAmp: Double = 0) -> Result {
        let game = GameCatalog.game(slug: "free-throw-streak")!
        let sim = SimSource(game: game)
        let tracker = BallTracker()
        let eng = CountingEngine(rule: game.buildRule())
        let jitter = makeJitter(UInt32(fps) &* 7919)
        var r = Result()
        var t = 0.0
        while t < seconds {
            t += (1 / fps) * (1 + jitterAmp * jitter())
            let frame = sim.play(t: t)
            let tracked = tracker.update(x: frame.ball?.x, y: frame.ball?.y, t: t)
            let valid = tracked?.valid ?? false
            let conf: Double = (valid && !(tracked?.coasting ?? true))
                ? (frame.ball?.confidence ?? 0.8)
                : (valid ? 0.5 : 0)
            let before = eng.count
            _ = eng.update(Sample(t: t, x: tracked?.x, y: tracked?.y, confidence: conf))
            if eng.count > before {
                r.makes += 1
                r.longest = max(r.longest, eng.count)
            }
            if eng.justMissed { r.misses += 1 }
        }
        return r
    }

    // 12s covers cycles 0..4: makes at 0,1,2 (streak 3), a brick at 3, a make at 4.
    func testFreeThrowPipelineAcrossFrameRates() {
        for fps in [60.0, 15.0, 5.0] {
            let r = runPipeline(fps: fps, seconds: 12)
            XCTAssertGreaterThanOrEqual(r.longest, 3, "\(fps) fps: longest streak should reach 3")
            XCTAssertGreaterThanOrEqual(r.misses, 1, "\(fps) fps: the brick must register as a miss")
            XCTAssertLessThanOrEqual(r.makes, 4, "\(fps) fps: the brick must never count as a make")
        }
    }

    func testFreeThrowPipelineWithFrameJitter() {
        let r = runPipeline(fps: 30, seconds: 12, jitterAmp: 1.0)
        XCTAssertGreaterThanOrEqual(r.misses, 1, "jittered sampling: miss detected")
        XCTAssertLessThanOrEqual(r.makes, 4, "jittered sampling: no phantom make")
    }

    func testHoopCountPipelineMixesSwishAndRim() {
        let game = GameCatalog.game(slug: "hoop-count")!
        let sim = SimSource(game: game)
        let tracker = BallTracker()
        let eng = CountingEngine(rule: game.buildRule())
        for i in 0...(30 * 14) {
            let t = Double(i) / 30
            let frame = sim.play(t: t)
            let tracked = tracker.update(x: frame.ball?.x, y: frame.ball?.y, t: t)
            let valid = tracked?.valid ?? false
            let conf: Double = (valid && !(tracked?.coasting ?? true))
                ? (frame.ball?.confidence ?? 0.8)
                : (valid ? 0.5 : 0)
            _ = eng.update(Sample(t: t, x: tracked?.x, y: tracked?.y, confidence: conf))
        }
        let quals = eng.events.compactMap(\.quality)
        XCTAssertTrue(quals.contains("swish"), "expected at least one swish, got \(quals)")
        XCTAssertTrue(quals.contains("rim"), "expected at least one rim make, got \(quals)")
    }

    func testCalibrationWalksSearchingAdjustLocked() {
        let sim = SimSource(game: GameCatalog.game(slug: "hoop-count")!)
        let searching = sim.calibration(t: 0.2)
        XCTAssertFalse(searching.targetVisible)
        XCTAssertNil(searching.targetBox)
        XCTAssertFalse(searching.bodyVisible)
        let adjust = sim.calibration(t: 1.0)
        XCTAssertTrue(adjust.targetVisible)
        XCTAssertEqual(adjust.targetBox?.w ?? 0, (0.64 - 0.36) * 0.5, accuracy: 1e-9)
        let locked = sim.calibration(t: 2.0)
        XCTAssertTrue(locked.targetVisible)
        XCTAssertEqual(locked.targetBox?.w ?? 0, 0.64 - 0.36, accuracy: 1e-9)
        XCTAssertTrue(locked.bodyVisible)
    }
}
