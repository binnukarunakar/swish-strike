import SwiftUI

/// Code-only hero art for a game card: an accent radial glow behind a sport glyph
/// on the near-black base, with a bottom scrim so the title stays legible. The
/// richer crafted SVG versions live in apps/swish/assets/heroes/ (used by the web
/// build and marketing); this is the lightweight in-app rendering.
struct HeroArtView: View {
    let heroId: String

    private static let symbols: [String: String] = [
        "basketball": "basketball.fill", "free-throw": "basketball.fill",
        "dribble": "basketball.fill", "soccer": "soccerball", "juggling": "soccerball",
        "tennis": "tennisball.fill", "ping-pong": "circle.circle.fill",
        "cornhole": "circle.grid.cross.fill", "bottle-flip": "waterbottle.fill",
        "catch": "baseball.fill",
        "golf": "figure.golf", "cup-pong": "cup.and.saucer.fill",
        "volleyball": "volleyball.fill", "hacky-sack": "circle.hexagongrid.fill",
    ]

    var body: some View {
        let accent = Theme.accent(heroId)
        ZStack {
            Theme.bg
            RadialGradient(colors: [accent.opacity(0.30), accent.opacity(0.04), .clear],
                           center: .init(x: 0.5, y: 0.38), startRadius: 4, endRadius: 200)
            Image(systemName: Self.symbols[heroId] ?? "circle.fill")
                .font(.system(size: 96, weight: .semibold))
                .foregroundStyle(accent.gradient)
                .shadow(color: accent.opacity(0.5), radius: 24)
                .offset(y: -18)
            LinearGradient(colors: [.clear, Theme.bg.opacity(0.92)], startPoint: .center, endPoint: .bottom)
        }
        .clipped()
    }
}
