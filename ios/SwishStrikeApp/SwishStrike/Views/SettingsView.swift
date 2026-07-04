import SwiftUI
import SwishStrikeCore

/// Settings: sound, default ball source, personal-best reset (with
/// confirmation), the privacy statement, and the app version.
struct SettingsView: View {
    @State private var soundOn = PersistenceStore.shared.soundOn
    @State private var source = AppFlags.startupSource
    @State private var confirmingReset = false

    var body: some View {
        List {
            Section("Game") {
                Toggle("Sound effects", isOn: $soundOn)
                    .onChange(of: soundOn) { _, on in
                        PersistenceStore.shared.soundOn = on
                    }
                Picker("Ball source", selection: $source) {
                    Text("Camera").tag(SourceMode.camera)
                    Text("Demo (simulation)").tag(SourceMode.sim)
                }
                .onChange(of: source) { _, new in
                    AppFlags.preferredSource = new
                }
            }

            Section {
                Button("Reset personal bests", role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog("Reset all personal bests?",
                                    isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    Button("Reset", role: .destructive) {
                        PersistenceStore.shared.resetBests()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This clears every game's best score. It cannot be undone.")
                }
            }

            Section("Privacy") {
                Text("Everything runs on this device. No video, detection, or score ever leaves it. No account, no ads, no analytics, no tracking.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textDim)
            }

            Section {
                LabeledContent("Version",
                               value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
    }
}
