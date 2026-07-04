import SwiftUI
import SwishStrikeCore

/// The shareable score card: "THE SHOT" panel drawing the frozen arc of the
/// last make through the target zone, the headline number, and the swish/rim
/// split — the Swift mirror of the web's drawShareCard. Designed at 540×720;
/// scales to any thumbnail.
struct ShareCardView: View {
    let session: GameSession

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let unit = w / 540 // design-space scale factor
            ZStack {
                LinearGradient(colors: [Theme.bg, Theme.surface],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 8 * unit) {
                    Text("Swish Strike")
                        .font(.system(size: 32 * unit, weight: .heavy))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 26 * unit)

                    shotPanel(unit: unit)
                        .frame(width: 420 * unit, height: 240 * unit)

                    Text("\(session.resultHeadline)")
                        .font(.system(size: 150 * unit, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(session.game.accent)
                        .frame(height: 150 * unit)

                    Text(session.game.isStreakGame
                         ? "\(session.game.title) · longest streak"
                         : "\(session.game.title) · \(session.game.tag)")
                        .font(.system(size: 22 * unit, weight: .semibold))
                        .foregroundStyle(Theme.textDim)

                    if session.swishCount + session.rimCount > 0 {
                        Text("\(session.swishCount) swish · \(session.rimCount) off the rim")
                            .font(.system(size: 18 * unit, weight: .bold))
                            .foregroundStyle(session.game.accent)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: w, height: h)
            }
        }
        .aspectRatio(540.0 / 720.0, contentMode: .fit)
    }

    /// The framed panel with the made-shot arc, brighter toward the make.
    private func shotPanel(unit: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18 * unit, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 18 * unit).stroke(Theme.line, lineWidth: 1))
            Text("THE SHOT")
                .font(.system(size: 11 * unit, weight: .bold)).tracking(1.2)
                .foregroundStyle(Theme.textDim)
                .padding(16 * unit)
            Canvas { ctx, size in
                let pad = 22 * unit
                let inner = CGRect(x: pad, y: pad + 8 * unit,
                                   width: size.width - pad * 2,
                                   height: size.height - pad * 2 - 8 * unit)
                let mapX = { (nx: Double) in inner.minX + min(1, max(0, nx)) * inner.width }
                let mapY = { (ny: Double) in inner.minY + min(1, max(0, ny)) * inner.height }

                if let z = session.activeZone {
                    var zone = Path()
                    zone.addRect(CGRect(x: mapX(z.left), y: mapY(z.top),
                                        width: (z.right - z.left) * inner.width,
                                        height: (z.bottom - z.top) * inner.height))
                    ctx.stroke(zone, with: .color(session.game.accent.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                }

                let arc = session.savedArc
                guard arc.count > 1 else { return }
                for i in 1..<arc.count {
                    let a = arc[i - 1], b = arc[i]
                    let f = Double(i) / Double(arc.count)
                    var seg = Path()
                    seg.move(to: CGPoint(x: mapX(a.x), y: mapY(a.y)))
                    seg.addLine(to: CGPoint(x: mapX(b.x), y: mapY(b.y)))
                    ctx.stroke(seg, with: .color(session.game.accent.opacity(0.25 + f * 0.65)),
                               style: StrokeStyle(lineWidth: 2 + f * 5, lineCap: .round))
                }
                if let end = arc.last {
                    ctx.fill(Path(ellipseIn: CGRect(x: mapX(end.x) - 6, y: mapY(end.y) - 6,
                                                    width: 12, height: 12)),
                             with: .color(.white))
                }
            }
        }
    }
}
