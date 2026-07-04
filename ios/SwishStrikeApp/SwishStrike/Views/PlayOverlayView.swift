import SwiftUI
import SwishStrikeCore

/// The live canvas over the stage: streak-heat vignette, target zone, comet
/// trail, ball marker, and the on-fire badge — the Swift mirror of the web's
/// drawPlayOverlay. TimelineView drives redraw; all data comes from the session.
struct PlayOverlayView: View {
    let session: GameSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: session.phase != .play)) { timeline in
            Canvas { ctx, size in
                let accent = session.game.accent
                drawHeat(ctx: &ctx, size: size)
                drawZone(ctx: &ctx, size: size, accent: accent)
                drawTrail(ctx: &ctx, size: size, accent: accent)
                drawBall(ctx: &ctx, size: size, accent: accent)
                drawOnFire(ctx: &ctx, size: size, date: timeline.date)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawHeat(ctx: inout GraphicsContext, size: CGSize) {
        let level = session.heatLevel
        guard level > 0.02 else { return }
        let gradient = Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Theme.brand.opacity(0.40 * level), location: 1),
        ])
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(gradient,
                                       center: CGPoint(x: size.width / 2, y: size.height / 2),
                                       startRadius: min(size.width, size.height) * 0.34,
                                       endRadius: max(size.width, size.height) * 0.66))
    }

    private func drawZone(ctx: inout GraphicsContext, size: CGSize, accent: Color) {
        guard let z = session.activeZone else { return }
        let rect = CGRect(x: z.left * size.width, y: z.top * size.height,
                          width: (z.right - z.left) * size.width,
                          height: (z.bottom - z.top) * size.height)
        var path = Path()
        path.addRect(rect)
        ctx.stroke(path, with: .color(accent.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 2.5, dash: [9, 7]))
    }

    private func drawTrail(ctx: inout GraphicsContext, size: CGSize, accent: Color) {
        let points = session.trailPoints(at: session.clock)
        guard points.count > 1 else { return }
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            var seg = Path()
            seg.move(to: CGPoint(x: a.x * size.width, y: a.y * size.height))
            seg.addLine(to: CGPoint(x: b.x * size.width, y: b.y * size.height))
            ctx.stroke(seg, with: .color(accent.opacity(b.fade * 0.7)),
                       style: StrokeStyle(lineWidth: 2 + b.fade * 7, lineCap: .round))
        }
    }

    private func drawBall(ctx: inout GraphicsContext, size: CGSize, accent: Color) {
        guard let ball = session.ballPosition else { return }
        let center = CGPoint(x: ball.x * size.width, y: ball.y * size.height)
        let glow = Gradient(stops: [
            .init(color: accent, location: 0),
            .init(color: accent.opacity(0), location: 1),
        ])
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 24, y: center.y - 24, width: 48, height: 48)),
                 with: .radialGradient(glow, center: center, startRadius: 2, endRadius: 24))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)),
                 with: .color(.white))
    }

    private func drawOnFire(ctx: inout GraphicsContext, size: CGSize, date: Date) {
        guard session.onFire else { return }
        let pulse = reduceMotion ? 0.85
            : 0.7 + 0.3 * sin(date.timeIntervalSinceReferenceDate * 9)
        let text = Text("ON FIRE")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color(hex: "#FFB52E").opacity(pulse))
        ctx.draw(ctx.resolve(text), at: CGPoint(x: size.width / 2, y: size.height * 0.30))
    }
}
