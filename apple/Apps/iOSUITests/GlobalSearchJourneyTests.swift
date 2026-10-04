import XCTest

/// Global search journeys against the loopback fixture (`tools/mock_service.py` on
/// `127.0.0.1:8765`): open from the Search tab, search songs and players, open a
/// result, and the blocked Bands scope (`.agents/controls/global-search/ios.md`).
final class GlobalSearchJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ])
    }

    /// Open global search from the system Search tab and return its focused search field.
    ///
    /// - Parameter app: Launched app on any root tab.
    /// - Returns: The Search tab's system search field.
    @MainActor
    private func openSearch(in app: XCUIApplication) -> XCUIElement {
        let tab = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", "Search")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "Search tab missing")
        tab.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.nav.search").firstMatch
                .waitForExistence(timeout: 10),
            "Search tab content did not appear"
        )
        let field = app.searchFields["Search songs or players"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        return field
    }

    /// Close the system Search tab and assert Songs is active again.
    ///
    /// - Parameter app: The running app with the Search tab open.
    @MainActor
    private func closeSearch(in app: XCUIApplication) {
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Search Close missing")
        close.tap()
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        XCTAssertTrue(sort.isHittable, "Closing Search did not return to Songs")
    }

    /// Assert the Search page's navigation bar shows its "Search" title on screen.
    ///
    /// - Parameter app: The running app with the Search tab open.
    @MainActor
    private func assertSearchTitleVisible(in app: XCUIApplication) {
        let bar = app.navigationBars["Search"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "Search navigation bar missing")
        let title = bar.staticTexts["Search"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Search title missing")
        XCTAssertTrue(title.isHittable, "Search title is hidden while searching")
        XCTAssertGreaterThan(title.frame.minY, 0, "Search title is off screen")
    }

    /// The system Search tab focuses the field, raises the keyboard, keeps its "Search"
    /// title while searching and closes back to the previous Songs tab.
    @MainActor
    func testSearchTabFocusesFieldAndCloseReturnsToSongs() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let field = openSearch(in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Search did not focus the keyboard")
        // The active field must not hide the page's "Search" title (issue #100).
        assertSearchTitleVisible(in: app)
        field.typeText("Fixture")
        XCTAssertTrue(
            app.buttons.matching(identifier: "fst.global-search.result.song").firstMatch
                .waitForExistence(timeout: 10)
        )
        assertSearchTitleVisible(in: app)
        closeSearch(in: app)
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
        let hint = app.staticTexts["fst.global-search.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        // The hint is centred between the scope bar and the bottom of the sheet.
        let scope = app.segmentedControls["fst.global-search.scope"]
        XCTAssertGreaterThan(hint.frame.minY, scope.frame.maxY + 40)
        field.tap()
        field.typeText("Fixture")
        // Focusing the field must not hide the system Close beside it.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch.isHittable,
            "Close disappeared while searching"
        )
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

    /// Issue #99: in "All" an empty Players section is hidden while songs match; an
    /// empty Players, Songs or All scope shows a centred title and subtitle, with Retry
    /// wherever players were searched, as one VoiceOver element.
    @MainActor
    func testEmptyResultsShowCentredTitleSubtitleAndRetry() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let field = openSearch(in: app)
        field.tap()
        field.typeText("Pulse")
        XCTAssertTrue(
            app.buttons.matching(identifier: "fst.global-search.result.song").firstMatch
                .waitForExistence(timeout: 10)
        )
        // The fixture has no player named "Pulse": once players settle, no Players
        // section or inline "No players found" row remains in All.
        let playersSection = app.descendants(matching: .any)
            .matching(identifier: "fst.global-search.section.players").firstMatch
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: playersSection)
        wait(for: [gone], timeout: 15)
        let retry = app.descendants(matching: .any).matching(identifier: "fst.global-search.retry").firstMatch
        XCTAssertFalse(retry.exists, "All showed an empty Players row")

        let scope = app.segmentedControls["fst.global-search.scope"]
        scope.buttons["Players"].tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 10), "Players scope has no empty state")
        XCTAssertTrue(retry.label.hasPrefix("No Players Found. Check the spelling"), retry.label)
        XCTAssertTrue(retry.label.hasSuffix("Retry"), retry.label)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(retry.frame.midX, window.midX, accuracy: 2, "Empty state is not centred horizontally")
        XCTAssertGreaterThan(retry.frame.minY, scope.frame.maxY + 40, "Empty state is not centred vertically")
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 10), "Retry lost the empty state")

        // The field's prompt follows the scope ("Search players"), so find it afresh.
        let scopedField = app.searchFields.firstMatch
        scopedField.tap()
        scopedField.typeText("zzz")
        scope.buttons["Songs"].tap()
        let hint = app.descendants(matching: .any).matching(identifier: "fst.global-search.hint").firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 10), "Songs scope has no empty state")
        XCTAssertTrue(hint.label.hasPrefix("No Songs Found. Check the spelling"), hint.label)
        XCTAssertFalse(retry.exists, "Songs offered Retry for a local search")

        scope.buttons["All"].tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 15), "All scope has no empty state")
        XCTAssertTrue(retry.label.hasPrefix("No Results Found. Check the spelling"), retry.label)
    }
}
