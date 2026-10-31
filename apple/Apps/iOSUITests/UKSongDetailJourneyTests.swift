import XCTest

/// Song Detail in the UIKit port (`UIKitPort/Features/SongDetail`), reached through the
/// Debug-only `FST_UIKIT_DEBUG_SONGDETAIL` hook (so it does not depend on the Songs list; on the
/// SwiftUI app, which has no hook, every test skips). The backdrop test needs the UIKit app's
/// background probe (`FST_DEBUG_BACKGROUND_PROBE`, see ``UKBackgroundJourneyTests``) and skips
/// on the SwiftUI app; the page tests run on both apps, so a port difference shows up as a
/// failure on one of them only.
///
/// Run with `python3 tools/ios_sim.py uitest --app uikit --only UKSongDetailJourneyTests`.
final class UKSongDetailJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func openSongDetail(
        _ env: [String: String] = [:], contentSize: String? = nil
    ) throws -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_BACKGROUND_PROBE": "1",
            "FST_UIKIT_DEBUG_SONGDETAIL": "fixture-pulse",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ]
        environment.merge(env) { $1 }
        let app = FestivalApp.makeApp(environment)
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        let hero = app.descendants(matching: .any)["fst.song-detail.hero-title"]
        try XCTSkipUnless(
            hero.waitForExistence(timeout: FestivalApp.budget(25)), "Song Detail did not open (no debug hook in this app?)"
        )
        return app
    }

    @MainActor
    private func probeState(_ app: XCUIApplication) throws -> [String: String] {
        let probe = app.descendants(matching: .any)["fst.debug.backgroundProbe"]
        try XCTSkipUnless(probe.waitForExistence(timeout: 10), "This app has no background probe.")
        let value = (probe.value as? String) ?? ""
        return Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        })
    }

    // MARK: - Journeys

    /// Pushing a song takes its cover as the backdrop; popping returns to the carousel, which
    /// resumes without the loader or the backdrop view being rebuilt.
    @MainActor
    func testBackdropFollowsTheCoverAndTheCarouselResumes() throws {
        let app = try openSongDetail()
        let beforePush = try probeState(app)
        Thread.sleep(forTimeInterval: 1.5)
        let onSong = try probeState(app)
        XCTAssertEqual(onSong["mode"], "song", "the backdrop did not take the song's cover")
        XCTAssertNotEqual(onSong["cover"], "none")
        app.buttons["BackButton"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["fst.song-detail.hero-title"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.5)
        let back = try probeState(app)
        XCTAssertEqual(back["mode"], "carousel")
        XCTAssertEqual(back["views"], beforePush["views"], "the backdrop view was rebuilt")
        let plays = (Int(back["plays"] ?? "") ?? 0) - (Int(beforePush["plays"] ?? "") ?? 0)
        XCTAssertLessThanOrEqual(plays, 2, "the carousel restarted instead of resuming")
    }

    /// Identifiers, labels and traits of the page's landmarks, and 44 pt targets.
    @MainActor
    func testPageLandmarksAndTargets() throws {
        let app = try openSongDetail()
        let hero = app.descendants(matching: .any)["fst.song-detail.hero-title"]
        XCTAssertTrue(hero.label.hasPrefix("Fixture Pulse"))
        for id in ["fst.song-detail.intensity", "fst.song-detail.card.Solo_Guitar", "fst.song-detail.card-header.Solo_Guitar"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].waitForExistence(timeout: 5), "missing \(id)")
        }
        let row = app.buttons["fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Your rank, 1st, Fixture Player 1, 99,900, Accuracy 98%")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        let paths = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(paths.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(paths.frame.width, 44)
        XCTAssertGreaterThanOrEqual(paths.frame.height, 44)
    }

    /// At the largest accessibility text size the page lays out in one column and its rows
    /// grow instead of clipping; the scoped audit finds no hit-area or clipping problems.
    @MainActor
    func testAccessibilityTextSizeGrowthAndAudit() throws {
        let app = try openSongDetail(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let row = app.buttons["fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(row.frame.height, 80, "the row did not grow at AX5")
        XCTAssertLessThanOrEqual(row.frame.maxX, app.windows.firstMatch.frame.maxX + 1)
        try app.performAccessibilityAudit(for: [.hitRegion, .textClipped, .sufficientElementDescription])
    }
}
