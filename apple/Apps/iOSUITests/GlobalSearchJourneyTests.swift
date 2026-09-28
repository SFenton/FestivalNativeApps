import XCTest

/// Global search journeys against the loopback fixture (`tools/mock_service.py` on
/// `127.0.0.1:8765`): open from any page, search songs and players, open a result,
/// and the blocked Bands scope (`.agents/controls/global-search/ios.md`).
final class GlobalSearchJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ])
    }

    /// Open global search (accessory on iOS 26.1+, toolbar button elsewhere) and return
    /// its search field.
    @MainActor
    private func openSearch(in app: XCUIApplication) -> XCUIElement {
        let open = app.buttons.matching(identifier: "fst.global-search.open").firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        let field = app.searchFields.matching(
            NSPredicate(format: "placeholderValue == %@", "Search songs or players")
        ).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        return field
    }

    /// Short queries show the hint; a song and a player match; a song opens Song Detail
    /// on the presenting tab and Back returns there.
    @MainActor
    func testSearchSongsAndPlayersThenOpenSong() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let field = openSearch(in: app)
        XCTAssertTrue(app.staticTexts["fst.global-search.hint"].waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Fixture")
        let song = app.buttons.matching(identifier: "fst.global-search.result.song").firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        let player = app.buttons.matching(identifier: "fst.global-search.result.player").firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 15), "Player results never arrived")
        song.tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2) && field.isHittable, "Search stayed open")
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 10))
    }

    /// Bands is visible but never searched: it explains why and links to Band Rankings.
    @MainActor
    func testBandsScopeExplainsBlockedSearch() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        _ = openSearch(in: app)
        let scope = app.segmentedControls["fst.global-search.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.buttons["Bands"].tap()
        let explanation = app.descendants(matching: .any)
            .matching(identifier: "fst.global-search.bands-unavailable").firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Band Rankings"].exists)
    }
}
