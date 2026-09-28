import UIKit
import XCTest

/// Fixture-backed native journeys for Bands: a Band Rankings row pushing into Band
/// Detail and then into a catalog-linked song, and Player Bands paging past the
/// first page. Both rely on `tools/mock_service.py` fixture data this lane added
/// (`_band_ranking_entry`/`_band_detail`/`_player_band_entry`/
/// `_song_band_leaderboard_entry` — see `.agents/testing/fixtures.md`).
final class BandsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp(route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FST_UI_TEST_CLEAR_PROFILE"] = "1"
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:18790"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launchEnvironment["FST_DEBUG_ROUTE"] = route
        return app
    }

    /// Band Rankings (rank 1, `fixture-team-1`) → Band Detail → its catalog-linked
    /// "fixture-pulse" Best song → Song Detail.
    @MainActor
    func testBandRankingsRowOpensBandDetailThenSong() throws {
        continueAfterFailure = false
        let app = fixtureApp(route: "bandRankings:Band_Duets")
        app.launch()

        let row = app.descendants(matching: .any)
            .matching(identifier: "fst.band-rankings.row.fixture-team-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "band-rankings-loaded")
        row.tap()

        let membersSection = app.descendants(matching: .any)
            .matching(identifier: "fst.band.members-section").firstMatch
        XCTAssertTrue(
            membersSection.waitForExistence(timeout: 15),
            "Band Detail never loaded: \(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        SongsUITestSupport.record(app, name: "band-detail-loaded")

        let songRow = app.descendants(matching: .any)
            .matching(identifier: "fst.band.song-row.fixture-pulse").firstMatch
        for _ in 0..<8 {
            if songRow.exists && songRow.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(songRow.exists, "Catalog-linked Best song row is missing")
        XCTAssertTrue(songRow.isHittable, "Best song row is not reachable by scrolling")
        songRow.tap()

        let intensity = app.descendants(matching: .any).matching(identifier: "fst.song-detail.intensity").firstMatch
        XCTAssertTrue(
            intensity.waitForExistence(timeout: 15),
            "Tapping the band's Best song never reached Song Detail"
        )
        SongsUITestSupport.record(app, name: "band-song-opened-song-detail")
    }

    /// `fixture-player-1`'s synthetic 30-entry "All" group needs a second page.
    @MainActor
    func testPlayerBandsPagesPastTheFirstPage() throws {
        continueAfterFailure = false
        let app = fixtureApp(route: "playerBands:fixture-player-1")
        app.launch()

        let pageInfo = app.descendants(matching: .any)
            .matching(identifier: "fst.player-bands.page-info").firstMatch
        XCTAssertTrue(pageInfo.waitForExistence(timeout: 15))
        XCTAssertEqual(pageInfo.label, "1 / 2")
        SongsUITestSupport.record(app, name: "player-bands-page-1")

        let next = app.buttons["fst.player-bands.page-next"]
        XCTAssertTrue(next.exists && next.isEnabled)
        next.tap()
        let onPageTwo = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "2 / 2"), object: pageInfo
        )
        XCTAssertEqual(XCTWaiter.wait(for: [onPageTwo], timeout: 10), .completed)
        SongsUITestSupport.record(app, name: "player-bands-page-2")

        let previous = app.buttons["fst.player-bands.page-previous"]
        XCTAssertTrue(previous.exists && previous.isEnabled)
        previous.tap()
        let backOnPageOne = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "1 / 2"), object: pageInfo
        )
        XCTAssertEqual(XCTWaiter.wait(for: [backOnPageOne], timeout: 10), .completed)
    }
}
