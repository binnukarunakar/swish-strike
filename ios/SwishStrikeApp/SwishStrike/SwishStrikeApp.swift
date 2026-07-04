import SwiftUI

/// App entry. Dark-first; first launch shows onboarding (camera explanation +
/// privacy stance) before the game grid. No accounts, no network — everything
/// is on-device.
@main
struct SwishStrikeApp: App {
    @State private var showOnboarding = !AppFlags.onboardingSeen

    var body: some Scene {
        WindowGroup {
            if showOnboarding {
                OnboardingView { showOnboarding = false }
                    .preferredColorScheme(.dark)
            } else {
                HomeView()
                    .preferredColorScheme(.dark)
            }
        }
    }
}
