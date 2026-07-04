import SwiftUI

/// The guided-setup panel: coach message, actionable hints, and the Start
/// button that lights up when framing is good (demo auto-advances; camera
/// setup is manual — aim, tap to place, start).
struct SetupPanelView: View {
    let session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(session.game.accent)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(session.coachPrimary)
                    .font(Theme.title(17))
                    .foregroundStyle(Theme.text)
            }
            ForEach(session.coachHints, id: \.self) { hint in
                Label(hint, systemImage: "arrow.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
            }
            Button {
                session.beginPlay()
            } label: {
                Text("Start")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.coachReady ? Color(hex: "#33E07A") : session.game.accent)
            .foregroundStyle(Theme.bg)
            .disabled(!session.coachReady)
            .accessibilityHint(session.coachReady ? "Framing looks good" : "Adjust framing first")

            if session.game.needsTarget {
                Text(session.source == .camera
                     ? "Tap the view to place the target zone."
                     : "Auto-detecting the target — or tap the view to place it yourself.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.pad)
        .background(Theme.bg)
    }
}
