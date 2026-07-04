import SwiftUI

/// First-launch onboarding: what the app does, the privacy stance, and how to
/// set up a shot — three concise pages, skippable, shown once (file-marker
/// flag, not UserDefaults, to keep the privacy manifest empty).
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(symbol: "camera.viewfinder",
             title: "Point your camera. It keeps score.",
             body: "Swish Strike watches the ball and counts for you — basketball makes, free-throw streaks, juggling touches, and more. It even knows a clean swish from a shot that rattles in."),
        Page(symbol: "lock.shield",
             title: "Everything stays on your phone.",
             body: "Detection runs entirely on-device. No video is recorded or uploaded, no account, no ads, no tracking. The camera permission exists only so the app can see the ball."),
        Page(symbol: "scope",
             title: "Set up in seconds.",
             body: "Prop the phone with the hoop or target in view, tap the screen to place the zone, then play. Try Demo mode first to see it work without a camera."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 18) {
                        Image(systemName: pages[i].symbol)
                            .font(.system(size: 56))
                            .foregroundStyle(Theme.brand)
                        Text(pages[i].title)
                            .font(Theme.display(26))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                        Text(pages[i].body)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textDim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .padding(32)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    AppFlags.markOnboardingSeen()
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Pick a game")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.pad)

            Button {
                AppFlags.markOnboardingSeen()
                onDone()
            } label: {
                Text("Skip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
            .padding(.vertical, 12)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
