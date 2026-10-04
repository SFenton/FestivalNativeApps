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

    /// Assert no "Songs", "Players" or "Bands" section title shows below the scope bar
    /// (issue #299: the scope bar already names the scope).
    ///
    /// - Parameter app: The running app with the Search tab open.
    @MainActor
    private func assertNoSectionTitles(in app: XCUIApplication) {
        let scopeBottom = app.segmentedControls["fst.global-search.scope"].frame.maxY
        let field = app.searchFields.firstMatch.frame
        // The results area ends at the field when it sits below the scope bar (iOS 26).
        let resultsBottom = field.minY > scopeBottom ? field.minY : app.windows.firstMatch.frame.maxY
        let titles = app.staticTexts.matching(
            NSPredicate(format: "label IN[c] %@", ["Songs", "Players", "Bands"])
        ).allElementsBoundByIndex
        for title in titles where title.exists {
            let y = title.frame.midY
            XCTAssertFalse(
                y > scopeBottom && y < resultsBottom, "Section title \(title.label) shown in results"
            )
        }
        let tagged = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.global-search.section"))
        XCTAssertEqual(tagged.count, 0, "Section title element shown in results")
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
        XCTAssertEqual(hint.label, "Enter at least two characters to search for songs, players, or bands.")
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
        assertNoSectionTitles(in: app)
        song.tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2) && field.isHittable, "Search stayed open")
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 10))
    }

    /// Bands is visible but never searched: once a query is typed it explains why and
    /// links to Band Rankings.
    @MainActor
    func testBandsScopeExplainsBlockedSearch() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        _ = openSearch(in: app)
        let scope = app.segmentedControls["fst.global-search.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.buttons["Bands"].tap()
        // Under two characters Bands shows its hint; a query brings the explanation.
        let hint = app.staticTexts["fst.global-search.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("Fixture")
        let explanation = app.descendants(matching: .any)
            .matching(identifier: "fst.global-search.bands-unavailable").firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Band Rankings"].exists)
        assertNoSectionTitles(in: app)
    }

    /// Issue #299: under two characters each scope's hint names what it searches.
    @MainActor
    func testShortQueryHintNamesEachScope() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        _ = openSearch(in: app)
        let scope = app.segmentedControls["fst.global-search.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        let hint = app.staticTexts["fst.global-search.hint"]
        for (segment, ending) in [
            ("All", "songs, players, or bands."), ("Songs", "songs."),
            ("Players", "players."), ("Bands", "bands."),
        ] {
            scope.buttons[segment].tap()
            let expected = "Enter at least two characters to search for \(ending)"
            let shown = expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: hint)
            wait(for: [shown], timeout: 5)
        }
    }

    /// Issue #299: one spinner, centred horizontally and vertically between the scope
    /// bar and the field/keyboard, while the player search is in flight.
    ///
    /// Needs a fixture service started from this revision (the shared `:8765` listener
    /// may predate the delayed "slowpoke" account search):
    ///
    ///     python3 tools/mock_service.py --port 18936
    ///
    /// - Throws: A skip when that service is not running.
    @MainActor
    func testSearchingSpinnerIsCentredBelowScopeBar() throws {
        continueAfterFailure = false
        let origin = "http://127.0.0.1:18936"
        let probe = expectation(description: "slow account-search probe")
        var delayed = false
        let started = Date()
        URLSession.shared.dataTask(
            with: URL(string: "\(origin)/api/account/search?q=slowpoke&limit=10")!
        ) { _, response, _ in
            delayed = (response as? HTTPURLResponse)?.statusCode == 200
                && Date().timeIntervalSince(started) >= 3
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 10)
        try XCTSkipUnless(delayed, "Start `mock_service.py --port 18936` from this revision")
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ])
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        _ = openSearch(in: app)
        let scope = app.segmentedControls["fst.global-search.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.buttons["Players"].tap()
        let scopedField = app.searchFields.firstMatch
        scopedField.tap()
        // The fixture holds this account search for a few seconds.
        scopedField.typeText("slowpoke")
        let spinner = app.descendants(matching: .any)
            .matching(identifier: "fst.global-search.loading").firstMatch
        XCTAssertTrue(spinner.waitForExistence(timeout: 5), "No search spinner")
        assertNoSectionTitles(in: app)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(spinner.frame.midX, window.midX, accuracy: 2, "Spinner is not centred horizontally")
        // Centred in the area between the scope bar and the search field above the keyboard.
        let bottom = scopedField.frame.minY
        let areaMid = (scope.frame.maxY + bottom) / 2
        XCTAssertEqual(spinner.frame.midY, areaMid, accuracy: 40, "Spinner is not centred vertically")
        // The empty envelope then replaces it with the centred empty state, no Retry.
        let empty = app.descendants(matching: .any).matching(identifier: "fst.global-search.hint").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertFalse(spinner.exists)
        XCTAssertFalse(app.buttons["Retry"].exists, "Empty search offered Retry")
    }

    /// Issue #99: in "All" an empty Players section is hidden while songs match; an
    /// empty Players, Songs or All scope shows a centred title and subtitle as one
    /// VoiceOver element, with no Retry (issue #299).
    @MainActor
    func testEmptyResultsShowCentredTitleAndSubtitleWithoutRetry() throws {
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
        // The fixture has no player named "Pulse": once players settle, All shows only
        // the song rows, with no Players row, title or empty message.
        let player = app.buttons.matching(identifier: "fst.global-search.result.player").firstMatch
        XCTAssertFalse(player.exists)
        let empty = app.descendants(matching: .any).matching(identifier: "fst.global-search.hint").firstMatch
        XCTAssertFalse(empty.exists, "All showed an empty Players message")
        assertNoSectionTitles(in: app)

        let scope = app.segmentedControls["fst.global-search.scope"]
        scope.buttons["Players"].tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "Players scope has no empty state")
        XCTAssertEqual(empty.label, "No Players Found. Check the spelling or try a different player name.")
        XCTAssertFalse(app.buttons["Retry"].exists, "Players empty state offered Retry")
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(empty.frame.midX, window.midX, accuracy: 2, "Empty state is not centred horizontally")
        XCTAssertGreaterThan(empty.frame.minY, scope.frame.maxY + 40, "Empty state is not centred vertically")
        // Without Retry, the keyboard's Search key re-runs a possibly timed-out search.
        let scopedField = app.searchFields.firstMatch
        scopedField.typeText("\n")
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "Re-running lost the empty state")

        scopedField.tap()
        scopedField.typeText("zzz")
        scope.buttons["Songs"].tap()
        let songsEmpty = expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "No Songs Found. Check the spelling"),
            evaluatedWith: empty
        )
        wait(for: [songsEmpty], timeout: 10)
        XCTAssertFalse(app.buttons["Retry"].exists, "Songs empty state offered Retry")

        scope.buttons["All"].tap()
        let allEmpty = expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "No Results Found. Check the spelling"),
            evaluatedWith: empty
        )
        wait(for: [allEmpty], timeout: 15)
        XCTAssertFalse(app.buttons["Retry"].exists, "All empty state offered Retry")
    }
}
