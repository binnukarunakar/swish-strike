import CoreGraphics
import Foundation

/// The camera coach — the Swift mirror of web-prototype/js/coach.js. Given cheap
/// per-frame signals (target found? how big? where? how bright? body in frame?),
/// it returns concrete guidance: "move closer", "tilt up", "locked in". Pure so it
/// behaves identically for the simulation and the camera.
enum SetupCoach {
    enum Status {
        case searching
        case adjust
        case ready
    }

    struct Signals {
        var targetVisible: Bool
        var targetBox: CGRect?   // normalized 0...1, y down
        var brightness: Double   // 0...1 mean luminance
        var bodyVisible: Bool
        var needsBody: Bool
    }

    struct Verdict {
        var ready: Bool
        var status: Status
        var primary: String
        var hints: [String]
    }

    // Thresholds — identical to coach.js defaults.
    private static let minTargetArea = 0.012
    private static let maxTargetArea = 0.30
    private static let edgeMargin = 0.04
    private static let minBrightness = 0.18

    static func evaluate(_ s: Signals) -> Verdict {
        var hints: [String] = []

        if s.brightness < minBrightness {
            hints.append("Too dark — add light or move somewhere brighter")
        }

        guard s.targetVisible, let box = s.targetBox else {
            return Verdict(ready: false, status: .searching,
                           primary: "Point the camera at the target",
                           hints: hints.isEmpty ? ["Scanning for the target"] : hints)
        }

        let area = Double(box.width * box.height)
        let cx = Double(box.midX)

        if area < minTargetArea {
            hints.append("Move closer — the target looks small")
        } else if area > maxTargetArea {
            hints.append("Step back — the target fills the frame")
        }

        if Double(box.minY) < edgeMargin {
            hints.append("Tilt down a little")
        } else if Double(box.maxY) > 1 - edgeMargin {
            hints.append("Tilt up a little")
        }
        if cx < 0.2 {
            hints.append("Pan right to center the target")
        } else if cx > 0.8 {
            hints.append("Pan left to center the target")
        }

        if s.needsBody && !s.bodyVisible {
            hints.append("Step back so your whole body is in frame")
        }

        if hints.isEmpty {
            return Verdict(ready: true, status: .ready,
                           primary: "Locked in — start shooting", hints: [])
        }
        return Verdict(ready: false, status: .adjust, primary: hints[0], hints: hints)
    }
}
