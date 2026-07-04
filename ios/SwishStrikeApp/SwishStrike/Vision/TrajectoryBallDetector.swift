import CoreMedia
import Foundation
import Vision
import os

/// Ball detection via Apple Vision's trajectory API (ship plan D1). The request
/// is STATEFUL — it accumulates evidence across frames to recognize parabolic
/// motion (a thrown or bouncing ball) — so one request instance lives for the
/// whole session and each frame gets a fresh VNImageRequestHandler built from
/// the CMSampleBuffer (which carries the timestamps the request needs).
///
/// Coordinate note: Vision returns normalized points with a BOTTOM-LEFT origin;
/// the app (and the shared engine) use TOP-LEFT y-down, so y is flipped here.
final class TrajectoryBallDetector: BallDetecting {
    private var request: VNDetectTrajectoriesRequest
    private let log = Logger(subsystem: Log.subsystem, category: "detector")

    /// Trajectories shorter than this many points are ignored (noise gate).
    private static let trajectoryLength = 6

    init() {
        request = Self.makeRequest()
    }

    private static func makeRequest() -> VNDetectTrajectoriesRequest {
        let r = VNDetectTrajectoriesRequest(frameAnalysisSpacing: .zero,
                                            trajectoryLength: trajectoryLength)
        // Reject specks and huge blobs; a ball is somewhere in between.
        r.objectMinimumNormalizedRadius = 0.008
        r.objectMaximumNormalizedRadius = 0.30
        return r
    }

    func detect(sampleBuffer: CMSampleBuffer, time: Double) -> (x: Double, y: Double, confidence: Double)? {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            // Never throw across the frame loop; a failed frame is just a miss.
            log.debug("trajectory perform failed: \(error.localizedDescription)")
            return nil
        }
        guard let best = request.results?.max(by: { $0.confidence < $1.confidence }),
              best.confidence > 0,
              let point = best.detectedPoints.last else { return nil }
        return (x: point.x, y: 1 - point.y, confidence: Double(best.confidence))
    }

    /// Trajectory state must not leak between play sessions — a fresh request
    /// forgets every partial track.
    func reset() {
        request = Self.makeRequest()
    }
}
