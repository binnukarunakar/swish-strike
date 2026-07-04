import Foundation

// ----------------------------------------------------------------------------
// Swish Strike — Game model
//
// The platform-agnostic description of a bundled game: identity, copy, hero-art
// id, CV metadata (what to auto-calibrate, the ball's dominant hue, whether the
// player's body should be in frame), and a factory that hands the engine a
// fresh CountRule. This is the Swift mirror of web-prototype/js/games.js —
// keep the two in sync, field for field.
// ----------------------------------------------------------------------------

/// What the setup coach auto-calibrates before play ('hoop' rim / 'board'
/// cornhole / 'none').
public enum CalibrationMode: String, Sendable {
    case hoop, board, none
}

/// The ball's dominant hue, used by the color-assisted detector.
public enum BallHue: String, Sendable {
    case orange, white, yellow, red, blue
}

/// A bundled game. Carries everything the home grid and a scoring session need,
/// including a factory that builds the engine rule (`buildRule`), optionally on
/// a user-placed zone.
public struct Game: Identifiable, Sendable {
    public let slug: String          // stable id, e.g. "hoop-count"
    public let title: String
    public let sport: String
    public let tag: String           // the noun being counted ("Makes", "Touches")
    public let subtitle: String
    public let instructions: String
    public let accentHex: String     // accent color as "#RRGGBB"
    public let heroId: String
    public let flagship: Bool
    public let needsTarget: Bool
    public let needsBody: Bool
    public let calibrate: CalibrationMode
    public let ballHue: BallHue
    /// Default target zone for zone-crossing games; nil for bounce games.
    public let defaultZone: Zone?
    /// Builds a fresh counting rule, optionally with a user-placed zone override
    /// (ignored by bounce games).
    public let makeRule: @Sendable (Zone?) -> CountRule

    public var id: String { slug }

    public init(slug: String, title: String, sport: String, tag: String,
                subtitle: String, instructions: String, accentHex: String,
                heroId: String, flagship: Bool, needsTarget: Bool, needsBody: Bool,
                calibrate: CalibrationMode, ballHue: BallHue, defaultZone: Zone?,
                makeRule: @escaping @Sendable (Zone?) -> CountRule) {
        self.slug = slug
        self.title = title
        self.sport = sport
        self.tag = tag
        self.subtitle = subtitle
        self.instructions = instructions
        self.accentHex = accentHex
        self.heroId = heroId
        self.flagship = flagship
        self.needsTarget = needsTarget
        self.needsBody = needsBody
        self.calibrate = calibrate
        self.ballHue = ballHue
        self.defaultZone = defaultZone
        self.makeRule = makeRule
    }

    /// Produces the engine rule, substituting the override zone for zone games.
    public func buildRule(zoneOverride: Zone? = nil) -> CountRule {
        makeRule(zoneOverride)
    }
}
