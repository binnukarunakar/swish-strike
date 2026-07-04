import XCTest
@testable import SwishStrikeCore

// The catalog must mirror web-prototype/js/games.js field-for-field, including
// the META block (calibrate / ballHue / needsBody) and the ordering.
final class GameCatalogTests: XCTestCase {

    func testExactlyFourteenGamesInJSOrder() {
        let expected = ["hoop-count", "ping-pong-rally", "soccer-goal", "free-throw-streak",
                        "dribble-counter", "cornhole", "bottle-flip", "tennis-rally",
                        "catch-counter", "keepie-uppie", "golf-putt", "cup-pong",
                        "volley-bumps", "hacky-sack"]
        XCTAssertEqual(GameCatalog.games.count, 14)
        XCTAssertEqual(GameCatalog.games.map(\.slug), expected)
    }

    func testFreeThrowStreakRule() {
        let ft = GameCatalog.game(slug: "free-throw-streak")
        XCTAssertNotNil(ft)
        let r = ft!.buildRule()
        XCTAssertEqual(r.type, .zoneStreak)
        XCTAssertEqual(r.cooldown, 1.0)
        XCTAssertEqual(r.missMargin, 0.18)
        XCTAssertEqual(r.zone, Zone(left: 0.36, top: 0.26, right: 0.64, bottom: 0.38))
    }

    func testHoopCountIsFlagshipWithHoopMeta() {
        let hc = GameCatalog.game(slug: "hoop-count")!
        XCTAssertTrue(hc.flagship)
        XCTAssertEqual(hc.calibrate, .hoop)
        XCTAssertEqual(hc.ballHue, .orange)
        XCTAssertTrue(hc.needsBody)
        let r = hc.buildRule()
        XCTAssertEqual(r.type, .zoneCrossDown)
        XCTAssertEqual(r.cooldown, 0.9)
    }

    func testMetaMirrorsGamesJS() {
        let ch = GameCatalog.game(slug: "cornhole")!
        XCTAssertEqual(ch.calibrate, .board)
        XCTAssertEqual(ch.ballHue, .red)
        XCTAssertFalse(ch.needsBody)
        let vb = GameCatalog.game(slug: "volley-bumps")!
        XCTAssertEqual(vb.calibrate, CalibrationMode.none)
        XCTAssertEqual(vb.ballHue, .yellow)
        XCTAssertTrue(vb.needsBody)
    }

    func testBuildRuleHonorsZoneOverrideAndBounceIgnoresIt() {
        let custom = Zone(left: 0.1, top: 0.1, right: 0.3, bottom: 0.2)
        XCTAssertEqual(GameCatalog.game(slug: "soccer-goal")!.buildRule(zoneOverride: custom).zone, custom)
        XCTAssertNil(GameCatalog.game(slug: "keepie-uppie")!.buildRule(zoneOverride: custom).zone)
    }
}
