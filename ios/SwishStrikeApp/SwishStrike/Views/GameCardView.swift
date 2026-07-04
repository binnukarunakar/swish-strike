import SwiftUI
import SwishStrikeCore

/// A tappable game tile: hero art, title, sport·mode tag, flagship + PB badges.
struct GameCardView: View {
    let game: Game
    let best: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HeroArtView(heroId: game.heroId)

            if game.flagship {
                badge("FLAGSHIP", bg: Theme.brand, fg: .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            if best > 0 {
                badge("PB \(best)", bg: Color.black.opacity(0.55), fg: Theme.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(game.title).font(Theme.title(19)).foregroundStyle(Theme.text)
                Text("\(game.sport) · \(game.tag)").font(Theme.caption).foregroundStyle(game.accent)
            }
            .padding(14)
        }
        .aspectRatio(4.0 / 5.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rMd, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .shadow(color: game.accent.opacity(0.20), radius: 14, y: 4)
    }

    private func badge(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold)).tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(bg))
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }
}
