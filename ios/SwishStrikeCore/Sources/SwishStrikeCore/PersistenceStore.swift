import Foundation

// ----------------------------------------------------------------------------
// Swish Strike — PersistenceStore
//
// Local-only persistence for personal bests + settings. No network, no account,
// and NO UserDefaults — file-based JSON in Application Support keeps the app's
// privacy manifest empty. Falls back to in-memory state if the disk write
// fails. Foundation-only, so it compiles and tests on a bare Mac toolchain.
// ----------------------------------------------------------------------------

/// Per-game personal best (drives the card badge).
public struct PersonalBest: Codable, Sendable {
    public var gameId: String
    public var bestCount: Int
    public var achievedAt: Date
    public init(gameId: String, bestCount: Int, achievedAt: Date) {
        self.gameId = gameId
        self.bestCount = bestCount
        self.achievedAt = achievedAt
    }
}

public final class PersistenceStore {
    public static let shared = PersistenceStore()

    public private(set) var bests: [String: PersonalBest] = [:]
    private var settings = Settings()
    private let bestsURL: URL
    private let settingsURL: URL

    private struct Settings: Codable {
        var soundOn: Bool = true
    }

    /// `directory` overrides the storage location (used by tests); the default
    /// is the user's Application Support directory.
    public init(directory: URL? = nil) {
        let dir = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        bestsURL = dir.appendingPathComponent("swish-bests.json")
        settingsURL = dir.appendingPathComponent("swish-settings.json")
        load()
    }

    public func best(for slug: String) -> Int {
        bests[slug]?.bestCount ?? 0
    }

    /// Stores `value` as the best for `slug` unconditionally (callers own the
    /// max policy; see `recordCount` for the only-if-better variant).
    public func setBest(_ value: Int, for slug: String) {
        bests[slug] = PersonalBest(gameId: slug, bestCount: value, achievedAt: Date())
        saveBests()
    }

    /// Records a finished session's count; returns true if it set a new best.
    @discardableResult
    public func recordCount(_ count: Int, for slug: String) -> Bool {
        guard count > best(for: slug) else { return false }
        setBest(count, for: slug)
        return true
    }

    /// Sound on/off toggle, persisted with the same file-based posture.
    public var soundOn: Bool {
        get { settings.soundOn }
        set {
            settings.soundOn = newValue
            saveSettings()
        }
    }

    public func resetBests() {
        bests.removeAll()
        saveBests()
    }

    private func load() {
        if let data = try? Data(contentsOf: bestsURL),
           let decoded = try? JSONDecoder().decode([String: PersonalBest].self, from: data) {
            bests = decoded
        }
        if let data = try? Data(contentsOf: settingsURL),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        }
    }

    private func saveBests() {
        guard let data = try? JSONEncoder().encode(bests) else { return }
        try? data.write(to: bestsURL, options: .atomic)
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }
}
