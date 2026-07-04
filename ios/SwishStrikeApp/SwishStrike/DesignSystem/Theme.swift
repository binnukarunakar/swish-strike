import SwiftUI

/// Central design tokens — the one source of visual truth. Dark-first palette,
/// type scale, spacing, and the per-game accents from docs/04_DESIGN_SYSTEM.md.
enum Theme {
    // Core palette (near-black base; ~L*70-80 accents).
    static let bg = Color(hex: "#0A0B0E")
    static let surface = Color(hex: "#15171C")
    static let surface2 = Color(hex: "#1B1E25")
    static let text = Color(hex: "#F4F6FA")
    static let textDim = Color(hex: "#9BA3B0")
    static let brand = Color(hex: "#FF5A1F")
    static let brand2 = Color(hex: "#22D3EE")
    static let line = Color.white.opacity(0.08)

    // Spacing grid
    static let pad: CGFloat = 20
    static let gutter: CGFloat = 14
    static let rSm: CGFloat = 10
    static let rMd: CGFloat = 16
    static let rLg: CGFloat = 22

    // Type (SF Pro + SF Rounded for the giant tabular counter)
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .default) }
    static func counter(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded).monospacedDigit() }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static let body = Font.system(size: 15, weight: .regular)
    static let caption = Font.system(size: 12, weight: .semibold)

    /// Accent per heroId — the color-science set (see docs/04_DESIGN_SYSTEM.md).
    static let accents: [String: String] = [
        "basketball": "#FF7A33", "soccer": "#33E07A", "juggling": "#C77DFF",
        "tennis": "#D4FF3D", "cornhole": "#FFB52E", "ping-pong": "#2EC4FF",
        "bottle-flip": "#2E7DFF", "catch": "#FF4D8D", "free-throw": "#FF3B5C",
        "dribble": "#19E6C3",
        "golf": "#5BE049", "cup-pong": "#FF5147", "volleyball": "#FFE03D",
        "hacky-sack": "#8B7DFF",
    ]
    static func accent(_ heroId: String) -> Color { Color(hex: accents[heroId] ?? "#9BA3B0") }
}

/// A score-flash modifier: a quick scale pop honoring Reduce Motion.
struct ScorePop: ViewModifier {
    let trigger: Int
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(popped && !reduceMotion ? 1.12 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.5), value: popped)
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion else { return }
                popped = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { popped = false }
            }
    }
}

extension View {
    func scorePop(on trigger: Int) -> some View { modifier(ScorePop(trigger: trigger)) }
}
