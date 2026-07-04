import SwiftUI

/// The giant live count with its quality pulse ring: pop on a make (green ring
/// for a swish, amber for a rim rattle), amber shake on a broken streak.
struct CountHUDView: View {
    let session: GameSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringTick = 0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                PulseRing(tick: session.scoreTick, quality: session.lastQuality)
                Text("\(session.count)")
                    .font(Theme.counter(110))
                    .foregroundStyle(session.game.accent)
                    .shadow(color: .black.opacity(0.6), radius: 15, y: 4)
                    .scorePop(on: session.scoreTick)
                    .missShake(on: session.missFlash)
                    .accessibilityLabel("Count")
                    .accessibilityValue("\(session.count)")
            }
            Text(session.game.tag.uppercased())
                .font(Theme.caption).tracking(1.6)
                .foregroundStyle(Theme.textDim)
                .shadow(color: .black.opacity(0.6), radius: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 60)
        .opacity(session.phase == .play ? 1 : 0)
        .allowsHitTesting(false)
    }
}

/// The expanding ring fired on each score; color encodes shot quality.
private struct PulseRing: View {
    let tick: Int
    let quality: String?
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch quality {
        case "swish": Color(hex: "#33E07A")
        case "rim": Color(hex: "#FFB52E")
        default: Theme.brand
        }
    }

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 3)
            .frame(width: 190, height: 190)
            .scaleEffect(animating ? 1.85 : 0.6)
            .opacity(animating ? 0 : 0.5)
            .onChange(of: tick) { _, _ in
                guard !reduceMotion else { return }
                animating = false
                withAnimation(.easeOut(duration: 0.55)) { animating = true }
            }
    }
}

/// Horizontal shake + amber flash when a streak breaks.
private struct MissShake: ViewModifier {
    let trigger: Int
    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(travel: reduceMotion ? 0 : 9, shakes: CGFloat(shakes)))
            .onChange(of: trigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.42)) { shakes += 3 }
            }
    }
}

private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(shakes * .pi * 2), y: 0))
    }
}

extension View {
    func missShake(on trigger: Int) -> some View { modifier(MissShake(trigger: trigger)) }
}
