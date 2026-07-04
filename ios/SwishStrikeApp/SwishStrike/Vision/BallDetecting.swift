import CoreMedia
import Foundation

/// Per-frame ball detection in the app's coordinate convention: normalized 0...1,
/// TOP-LEFT origin (y down) — the same convention as the web detector, so the
/// shared SwishStrikeCore CountingEngine behaves identically on both platforms.
///
/// Implementations run synchronously on the camera's sample queue; they must
/// never throw across the frame loop (return nil on any failure). The input is
/// the full CMSampleBuffer because Vision's trajectory detection requires the
/// frame's presentation timestamp, which the bare pixel buffer does not carry.
protocol BallDetecting: AnyObject {
    /// Detect the ball in one frame. `time` is the presentation timestamp in
    /// seconds (strictly increasing within a session). Returns nil on a miss.
    func detect(sampleBuffer: CMSampleBuffer, time: Double) -> (x: Double, y: Double, confidence: Double)?

    /// Drop any accumulated per-session state (stateful Vision requests).
    /// Called when a play session restarts.
    func reset()
}

/// Deterministic stub for previews and unit-style checks: replays an endless
/// centered make (drop from above the rim through the frame) with no camera,
/// no Vision, no model.
final class StubDetector: BallDetecting {
    func detect(sampleBuffer: CMSampleBuffer, time: Double) -> (x: Double, y: Double, confidence: Double)? {
        let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
        return (x: 0.5, y: 0.06 + phase * 0.9, confidence: 0.9)
    }

    func reset() {}
}
