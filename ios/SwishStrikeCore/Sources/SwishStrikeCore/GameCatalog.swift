import Foundation

// ----------------------------------------------------------------------------
// Swish Strike — GameCatalog
//
// The static catalog of bundled games — the Swift mirror of games.js, same
// entries in the same order (interleaving warm/cool accents; see
// docs/04_DESIGN_SYSTEM.md → color science). Every field, zone, rule option,
// and per-game CV META value (calibrate / ballHue / needsBody) mirrors the JS
// catalog exactly, so the same game behaves the same on both platforms.
// ----------------------------------------------------------------------------

public enum GameCatalog {
    // Default target zones (normalized 0..1, y down) for the zone-crossing games.
    static let hoop = Zone(left: 0.36, top: 0.26, right: 0.64, bottom: 0.38) // band near top-center
    static let goal = Zone(left: 0.20, top: 0.30, right: 0.80, bottom: 0.46) // wide goal mouth
    static let hole = Zone(left: 0.42, top: 0.40, right: 0.58, bottom: 0.52) // small central target
    static let cup  = Zone(left: 0.44, top: 0.55, right: 0.56, bottom: 0.66) // putting cup, lower frame
    static let cups = Zone(left: 0.38, top: 0.42, right: 0.62, bottom: 0.56) // cup-pong rack, mid frame

    public static let games: [Game] = [
        Game(slug: "hoop-count", title: "Hoop Count", sport: "Basketball", tag: "Makes",
             subtitle: "Prop your phone courtside. Every swish counts itself.",
             instructions: "Aim the camera at the hoop, tap the rim to place the zone, then shoot. A made basket = the ball falling down through the zone.",
             accentHex: "#FF7A33", heroId: "basketball", flagship: true,
             needsTarget: true, needsBody: true, calibrate: .hoop, ballHue: .orange,
             defaultZone: hoop, makeRule: { z in .zoneCrossDown(z ?? GameCatalog.hoop, cooldown: 0.9) }),

        Game(slug: "ping-pong-rally", title: "Ping-Pong Rally", sport: "Table Tennis", tag: "Volleys",
             subtitle: "Count every volley across the table.",
             instructions: "Frame the table side-on. Each bounce-and-return is one volley. Best with bright light and a fast camera.",
             accentHex: "#2EC4FF", heroId: "ping-pong", flagship: false,
             needsTarget: false, needsBody: false, calibrate: .none, ballHue: .white,
             defaultZone: nil, makeRule: { _ in .bounceReversal(direction: .bottom, minAmplitude: 0.08, cooldown: 0.18) }),

        Game(slug: "soccer-goal", title: "Goal Scored", sport: "Soccer", tag: "Goals",
             subtitle: "Bury it. Real goal, pop-up net, or a wall target.",
             instructions: "Tap the four corners of the goal mouth, then shoot. A goal = the ball crossing down into the mouth.",
             accentHex: "#33E07A", heroId: "soccer", flagship: false,
             needsTarget: true, needsBody: false, calibrate: .none, ballHue: .white,
             defaultZone: goal, makeRule: { z in .zoneCrossDown(z ?? GameCatalog.goal, xTolerance: 0.06, cooldown: 1.0) }),

        Game(slug: "free-throw-streak", title: "Free-Throw Streak", sport: "Basketball", tag: "Streak",
             subtitle: "Make them in a row. One miss resets it. Pure pressure.",
             instructions: "Set the zone on the rim and step to the line. Sink them consecutively — the streak is the score. A miss resets it to zero.",
             accentHex: "#FF3B5C", heroId: "free-throw", flagship: false,
             needsTarget: true, needsBody: true, calibrate: .hoop, ballHue: .orange,
             defaultZone: hoop, makeRule: { z in .zoneStreak(z ?? GameCatalog.hoop, cooldown: 1.0, missMargin: 0.18) }),

        Game(slug: "dribble-counter", title: "Dribble Counter", sport: "Basketball", tag: "Dribbles",
             subtitle: "Crossover, between-the-legs — rack up the handles.",
             instructions: "Frame your dribble. Each floor bounce is one dribble. Speed-dribble mode times your fastest 30 seconds.",
             accentHex: "#19E6C3", heroId: "dribble", flagship: false,
             needsTarget: false, needsBody: true, calibrate: .none, ballHue: .orange,
             defaultZone: nil, makeRule: { _ in .bounceReversal(direction: .bottom, minAmplitude: 0.10, cooldown: 0.12) }),

        Game(slug: "cornhole", title: "Cornhole", sport: "Bag Toss", tag: "In the hole",
             subtitle: "Three-in-the-hole, automatically scored.",
             instructions: "Tap the hole to place the target. A bag dropping into the hole zone scores 3; resting on the board scores 1.",
             accentHex: "#FFB52E", heroId: "cornhole", flagship: false,
             needsTarget: true, needsBody: false, calibrate: .board, ballHue: .red,
             defaultZone: hole, makeRule: { z in .zoneCrossDown(z ?? GameCatalog.hole, xTolerance: 0.04, cooldown: 0.8) }),

        Game(slug: "bottle-flip", title: "Bottle Flip", sport: "Trick", tag: "Sticks",
             subtitle: "Flip it. Stick it. Count the landings.",
             instructions: "Flip a partly-filled bottle. A clean upright landing counts. (Prototype: counts the apex of each flip; production uses orientation.)",
             accentHex: "#2E7DFF", heroId: "bottle-flip", flagship: false,
             needsTarget: false, needsBody: false, calibrate: .none, ballHue: .blue,
             defaultZone: nil, makeRule: { _ in .bounceReversal(direction: .top, minAmplitude: 0.10, cooldown: 0.5) }),

        Game(slug: "tennis-rally", title: "Rally Counter", sport: "Tennis", tag: "Shots",
             subtitle: "Longest rally wins. Solo wall or with a partner.",
             instructions: "Frame the court or wall. Each hit is one shot. Fast balls need a bright scene and a high-frame-rate camera.",
             accentHex: "#D4FF3D", heroId: "tennis", flagship: false,
             needsTarget: false, needsBody: true, calibrate: .none, ballHue: .yellow,
             defaultZone: nil, makeRule: { _ in .bounceReversal(direction: .bottom, minAmplitude: 0.09, cooldown: 0.2) }),

        Game(slug: "catch-counter", title: "Catch Counter", sport: "Catch", tag: "Catches",
             subtitle: "Play catch. Every clean catch counts; a drop ends it.",
             instructions: "Toss and catch. Each catch at the top of the arc counts. Great for kids and warm-ups.",
             accentHex: "#FF4D8D", heroId: "catch", flagship: false,
             needsTarget: false, needsBody: true, calibrate: .none, ballHue: .white,
             defaultZone: nil, makeRule: { _ in .bounceReversal(direction: .top, minAmplitude: 0.12, cooldown: 0.4) }),

        Game(slug: "keepie-uppie", title: "Keepie-Uppie", sport: "Soccer", tag: "Touches",
             subtitle: "Juggle it. Feet, knees, head — keep it up.",
             instructions: "Keep the ball off the ground. Each touch (the ball bottoming out and rising again) counts. The run ends when it drops.",
             accentHex: "#C77DFF", heroId: "juggling", flagship: false,
             needsTarget: false, needsBody: true, calibrate: .none, ballHue: .white,
             defaultZone: nil, makeRule: { _ in .bounceReversal(direction: .bottom, minAmplitude: 0.10, cooldown: 0.22) }),

        Game(slug: "golf-putt", title: "Golf Putt", sport: "Golf", tag: "Holed",
             subtitle: "Drain putts. The cup keeps its own tally.",
             instructions: "Set the phone on the green behind the hole, facing your ball. A putt that rolls in = the ball dropping through the cup zone.",
             accentHex: "#5BE049", heroId: "golf", flagship: false,
             needsTarget: true, needsBody: false, calibrate: .none, ballHue: .white,
             defaultZone: cup, makeRule: { z in .zoneCrossDown(z ?? GameCatalog.cup, xTolerance: 0.04, cooldown: 1.5) }),

        Game(slug: "cup-pong", title: "Cup Pong", sport: "Party", tag: "Sinks",
             subtitle: "House rules, auto-scored. Every sink counts.",
             instructions: "Frame the cup rack from the side or behind. A ball dropping into the rack zone is one sink. Re-rack whenever — the count keeps going.",
             accentHex: "#FF5147", heroId: "cup-pong", flagship: false,
             needsTarget: true, needsBody: false, calibrate: .none, ballHue: .white,
             defaultZone: cups, makeRule: { z in .zoneCrossDown(z ?? GameCatalog.cups, cooldown: 1.0) }),

        Game(slug: "volley-bumps", title: "Volley Bumps", sport: "Volleyball", tag: "Bumps",
             subtitle: "Bump, set, repeat. How long can you keep it alive?",
             instructions: "Frame yourself with headroom — the ball should peak inside the frame. Each bump (the ball dropping to your arms and rising) counts.",
             accentHex: "#FFE03D", heroId: "volleyball", flagship: false,
             needsTarget: false, needsBody: true, calibrate: .none, ballHue: .yellow,
             defaultZone: nil, makeRule: { _ in .bounceReversal(direction: .bottom, minAmplitude: 0.11, cooldown: 0.30) }),

        Game(slug: "hacky-sack", title: "Hacky Sack", sport: "Footbag", tag: "Kicks",
             subtitle: "Keep the sack off the ground. Old school.",
             instructions: "Frame your whole body. Each kick (the sack bottoming out and popping back up) is one. The run ends when it hits the dirt.",
             accentHex: "#8B7DFF", heroId: "hacky-sack", flagship: false,
             needsTarget: false, needsBody: true, calibrate: .none, ballHue: .red,
             defaultZone: nil, makeRule: { _ in .bounceReversal(direction: .bottom, minAmplitude: 0.07, cooldown: 0.25) }),
    ]

    public static func game(slug: String) -> Game? {
        games.first { $0.slug == slug }
    }
}
