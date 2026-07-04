import SwiftUI
import SwishStrikeCore

/// UI-side conveniences over the platform-agnostic SwishStrikeCore model.
extension Game {
    /// The game's accent as a SwiftUI Color (SwishStrikeCore stores it as hex).
    var accent: Color { Color(hex: accentHex) }

    /// Streak games headline the longest run, not the final count.
    var isStreakGame: Bool { buildRule().type == .zoneStreak }
}
