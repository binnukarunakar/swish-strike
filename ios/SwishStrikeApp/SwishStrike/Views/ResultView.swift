import SwiftUI
import SwishStrikeCore

/// The session result: headline number (longest streak for streak games), a
/// new-personal-best badge, the swish/rim breakdown, the share card, and the
/// play-again / home actions.
struct ResultView: View {
    let session: GameSession
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if session.isNewPersonalBest {
                Text("NEW PERSONAL BEST")
                    .font(.system(size: 12, weight: .heavy)).tracking(1.4)
                    .foregroundStyle(Color(hex: "#33E07A"))
            }
            Text(session.game.isStreakGame
                 ? "\(session.game.title) · longest streak"
                 : "\(session.game.title) · \(session.game.tag)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textDim)
            Text("\(session.resultHeadline)")
                .font(Theme.counter(88))
                .foregroundStyle(session.game.accent)
                .accessibilityLabel("Final score \(session.resultHeadline)")
            if session.swishCount + session.rimCount > 0 {
                Text("\(session.swishCount) swish · \(session.rimCount) off the rim")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }

            ShareCardView(session: session)
                .frame(width: 135, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 15, y: 6)

            HStack(spacing: 10) {
                Button {
                    session.playAgain()
                } label: {
                    Text("Play again")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(session.game.accent)
                .foregroundStyle(Theme.bg)

                shareButton

                Button {
                    onHome()
                } label: {
                    Text("Home")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(Theme.textDim)
            }
            .padding(.horizontal, Theme.pad)
        }
        .padding(.vertical, Theme.pad)
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
    }

    /// Renders the full-size share card (540×720 @2x) and hands it to the
    /// system share sheet.
    private var shareButton: some View {
        let renderer = ImageRenderer(content: ShareCardView(session: session)
            .frame(width: 540, height: 720))
        renderer.scale = 2
        let image = renderer.uiImage.map(Image.init(uiImage:)) ?? Image(systemName: "photo")
        return ShareLink(item: image,
                         preview: SharePreview("Swish Strike — \(session.resultHeadline) \(session.game.tag)",
                                               image: image)) {
            Text("Share")
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(session.game.accent)
    }
}
