import SwiftUI
import SwishStrikeCore
import UIKit

/// The phase container for one game session: the stage (camera or demo
/// backdrop) with the live overlay and HUD, plus the setup / play / result
/// panels — the Swift mirror of the web's phase-driven game screen.
struct GameView: View {
    @State private var session: GameSession
    @Environment(\.dismiss) private var dismiss

    init(game: Game) {
        _session = State(initialValue: GameSession(game: game))
    }

    var body: some View {
        VStack(spacing: 0) {
            stage
            panel
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(session.game.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { sourceToggle }
        }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }

    private var stage: some View {
        ZStack {
            if session.source == .camera && session.permission == .granted {
                CameraPreview(session: session.cameraSession)
            } else {
                Color.black
            }
            if session.permission == .denied {
                CameraDeniedView()
            } else {
                PlayOverlayView(session: session)
                CountHUDView(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { location in
            placeTarget(at: location)
        }
        .overlay(alignment: .bottom) {
            if let toast = session.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 15).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.surface.opacity(0.92)))
                    .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                    .padding(.bottom, 18)
                    .transition(.opacity)
                    .accessibilityLabel(toast)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.toast != nil)
        .background(StageSizeReader(size: $stageSize))
    }

    @State private var stageSize: CGSize = .zero

    /// Tap-to-place in normalized stage coordinates. With an aspect-fill
    /// preview the horizontal mapping is approximate near the crop edges; the
    /// rule's xTolerance absorbs the difference.
    private func placeTarget(at location: CGPoint) {
        guard session.game.needsTarget, stageSize.width > 0, stageSize.height > 0 else { return }
        session.placeTarget(atNormalized: location.x / stageSize.width,
                            y: location.y / stageSize.height)
    }

    @ViewBuilder
    private var panel: some View {
        switch session.phase {
        case .setup:
            SetupPanelView(session: session)
        case .play:
            Button {
                session.finish()
            } label: {
                Text("Finish")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.game.accent)
            .foregroundStyle(Theme.bg)
            .padding(Theme.pad)
            .accessibilityLabel("Finish the session and see results")
        case .result:
            ResultView(session: session) { dismiss() }
        }
    }

    private var sourceToggle: some View {
        Picker("Source", selection: Binding(
            get: { session.source },
            set: { session.setSource($0) }
        )) {
            Text("Demo").tag(SourceMode.sim)
            Text("Camera").tag(SourceMode.camera)
        }
        .pickerStyle(.segmented)
        .frame(width: 150)
        .accessibilityLabel("Ball source: demo simulation or live camera")
    }
}

/// Reports the stage's size so taps can be normalized.
private struct StageSizeReader: View {
    @Binding var size: CGSize
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { size = proxy.size }
                .onChange(of: proxy.size) { _, new in size = new }
        }
    }
}

/// The camera-permission error state: required by an app whose core loop IS the
/// camera. Explains why and deep-links to Settings.
struct CameraDeniedView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash")
                .font(.system(size: 42))
                .foregroundStyle(Theme.textDim)
            Text("Swish Strike needs the camera")
                .font(Theme.title(18)).foregroundStyle(Theme.text)
            Text("Counting works by watching the ball. Nothing is recorded or uploaded — detection runs entirely on this device.")
                .font(Theme.body).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.brand)
            }
        }
        .padding(28)
        .accessibilityElement(children: .combine)
    }
}
