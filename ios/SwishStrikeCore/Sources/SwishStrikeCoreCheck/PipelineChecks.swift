import SwishStrikeCore
import Foundation

// Full-pipeline checks (sim -> tracker -> engine), the Swift mirror of
// web-prototype/test/streak_pipeline.test.mjs. The free-throw sim is swept
// across frame rates and timing jitter: every brick must resolve as a miss,
// never as a make, no matter how coarsely the flight is sampled.

// Deterministic LCG jitter — no randomness, so failures reproduce exactly.
func makeJitter(_ seed: UInt32) -> () -> Double {
    var s = seed
    return {
        s = s &* 1103515245 &+ 12345
        return Double(s % 1000) / 1000 - 0.5
    }
}

struct PipelineResult {
    var makes = 0
    var misses = 0
    var longest = 0
}

func runStreakPipeline(fps: Double, seconds: Double, jitterAmp: Double = 0) -> PipelineResult {
    let game = GameCatalog.game(slug: "free-throw-streak")!
    let sim = SimSource(game: game)
    let tracker = BallTracker()
    let eng = CountingEngine(rule: game.buildRule())
    let jitter = makeJitter(UInt32(fps) &* 7919)
    var r = PipelineResult()
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

func runPipelineChecks() {
    // 12s covers cycles 0..4: makes at 0,1,2 (streak 3), a brick at 3, a make at 4.
    for fps in [60.0, 15.0, 5.0] {
        let r = runStreakPipeline(fps: fps, seconds: 12)
        check("pipeline: free-throw at \(Int(fps)) fps — streak >= 3, brick is a miss, makes <= 4",
              r.longest >= 3 && r.misses >= 1 && r.makes <= 4)
    }
    do {
        let r = runStreakPipeline(fps: 30, seconds: 12, jitterAmp: 1.0)
        check("pipeline: 30 fps with +/-50% frame jitter still resolves the brick as a miss",
              r.misses >= 1 && r.makes <= 4)
    }
    // hoop-count regression guard: the demo still mixes swish and rim makes.
    do {
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
        check("pipeline: hoop-count sim mixes swish and rim at 30 fps",
              quals.contains("swish") && quals.contains("rim"))
    }
    // calibration sequence: searching -> adjust (half-size box) -> locked.
    do {
        let sim = SimSource(game: GameCatalog.game(slug: "hoop-count")!)
        let searching = sim.calibration(t: 0.2)
        let adjust = sim.calibration(t: 1.0)
        let locked = sim.calibration(t: 2.0)
        let zoneW = 0.64 - 0.36
        check("sim: calibration walks searching -> adjust -> locked",
              !searching.targetVisible && searching.targetBox == nil
              && adjust.targetVisible && abs((adjust.targetBox?.w ?? 0) - zoneW * 0.5) < 1e-9
              && locked.targetVisible && abs((locked.targetBox?.w ?? 0) - zoneW) < 1e-9
              && !searching.bodyVisible && locked.bodyVisible)
    }
}
