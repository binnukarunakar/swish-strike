import SwiftUI
import SwishStrikeCore

/// The home screen: a scrollable 2-column grid of game cards. Tapping one opens
/// the live GameView; the gear opens Settings.
struct HomeView: View {
    @State private var refresh = 0 // re-reads personal bests when returning home
    private let columns = [GridItem(.flexible(), spacing: Theme.gutter),
                           GridItem(.flexible(), spacing: Theme.gutter)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Theme.gutter) {
                    ForEach(GameCatalog.games) { game in
                        NavigationLink(value: game.slug) {
                            GameCardView(game: game,
                                         best: PersistenceStore.shared.best(for: game.slug))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(game.title), \(game.sport)")
                    }
                }
                .padding(.horizontal, Theme.pad)
                .padding(.bottom, 96)
                .id(refresh)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationDestination(for: String.self) { slug in
                if let game = GameCatalog.game(slug: slug) {
                    GameView(game: game)
                        .onDisappear { refresh += 1 }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("Swish Strike").font(Theme.display(26)).foregroundStyle(Theme.text)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(".").font(Theme.display(26)).foregroundStyle(Theme.brand)
                        }
                        Text("Point your camera. We'll keep score.")
                            .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(Theme.textDim)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .toolbarBackground(Theme.bg, for: .navigationBar)
        }
        .tint(Theme.brand)
        .preferredColorScheme(.dark)
    }
}
