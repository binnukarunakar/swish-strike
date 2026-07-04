import Foundation

/// Where a session gets its ball positions from.
/// `.sim` replays the deterministic SwishStrikeCore simulation (Demo mode);
/// `.camera` runs the live Vision pipeline.
enum SourceMode: String {
    case sim
    case camera
}

/// Logging namespace shared by the app layer.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.binnu.swish"
}

/// Tiny file-backed flags. Deliberately NOT UserDefaults/@AppStorage: file-based
/// persistence keeps PrivacyInfo.xcprivacy free of required-reason API entries
/// (same stance as SwishStrikeCore's PersistenceStore — see docs/10_IOS_SHIP.md D5).
enum AppFlags {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SwishStrike", isDirectory: true)
    }

    private static var onboardingMarker: URL {
        directory.appendingPathComponent("onboarding-seen")
    }

    private static var sourceFile: URL {
        directory.appendingPathComponent("source-mode")
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
    }

    /// True once the user has completed (or skipped) onboarding.
    static var onboardingSeen: Bool {
        FileManager.default.fileExists(atPath: onboardingMarker.path)
    }

    static func markOnboardingSeen() {
        ensureDirectory()
        try? Data().write(to: onboardingMarker)
    }

    /// The user's preferred source from Settings; nil until they choose one.
    static var preferredSource: SourceMode? {
        get {
            guard let raw = try? String(contentsOf: sourceFile, encoding: .utf8) else { return nil }
            return SourceMode(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        set {
            ensureDirectory()
            if let newValue {
                try? newValue.rawValue.write(to: sourceFile, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: sourceFile)
            }
        }
    }

    /// Demo in the Simulator (no camera hardware), camera on a real device.
    static var defaultSource: SourceMode {
        #if targetEnvironment(simulator)
        return .sim
        #else
        return .camera
        #endif
    }

    /// The source a new session should start with.
    static var startupSource: SourceMode { preferredSource ?? defaultSource }
}
