import XCTest
@testable import SwishStrikeCore

// File-backed store (Application Support JSON, no UserDefaults). Tests run
// against a temp directory so they never touch the real store.
final class PersistenceStoreTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swishcore-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testBestsAndSoundOnSurviveReload() {
        let s1 = PersistenceStore(directory: dir)
        XCTAssertEqual(s1.best(for: "hoop-count"), 0, "fresh store starts at zero")
        XCTAssertTrue(s1.soundOn, "sound defaults to on")
        s1.setBest(7, for: "hoop-count")
        s1.soundOn = false
        let s2 = PersistenceStore(directory: dir)
        XCTAssertEqual(s2.best(for: "hoop-count"), 7)
        XCTAssertFalse(s2.soundOn)
    }

    func testRecordCountKeepsOnlyNewBest() {
        let s = PersistenceStore(directory: dir)
        XCTAssertTrue(s.recordCount(9, for: "hoop-count"))
        XCTAssertFalse(s.recordCount(3, for: "hoop-count"))
        XCTAssertEqual(s.best(for: "hoop-count"), 9)
    }

    func testResetBestsClearsAndPersists() {
        let s1 = PersistenceStore(directory: dir)
        s1.setBest(5, for: "cornhole")
        s1.resetBests()
        XCTAssertEqual(s1.best(for: "cornhole"), 0)
        let s2 = PersistenceStore(directory: dir)
        XCTAssertEqual(s2.best(for: "cornhole"), 0, "the wipe is persisted")
    }
}
