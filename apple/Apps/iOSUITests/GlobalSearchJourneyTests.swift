import XCTest

/// Global search journeys against a loopback fixture started from this revision: open
/// from the Search tab, search songs, players and bands, and open a result
/// (`.agents/controls/global-search/ios.md`). "All" always searches bands (issue #320),
/// so the shared `:8765` listener, which may predate the band-search route, would show
/// "Bands unavailable"; start the fixture on its own port instead:
///
///     python3 tools/mock_service.py --port 18936
final class GlobalSearchJourneyTests: XCTestCase {
    /// The fixture origin every journey here uses.
    private static let origin = "http://127.0.0.1:18936"

    /// Skip unless the fixture serves band search (it predates issue #320 otherwise).
    ///
    /// - Throws: A skip when that service is not running.
    override func setUpWithError() throws {
        let probe = expectation(description: "band-search probe")
        var served = false
        URLSession.shared.dataTask(
            with: URL(string: "\(Self.origin)/api/bands/search?q=Syncing&page=1&pageSize=10")!
        ) { _, response, _ in
            served = (response as? HTTPURLResponse)?.statusCode == 200
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 10)
        try XCTSkipUnless(served, "Start `mock_service.py --port 18936` from this revision")
    }

    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
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
        let field = app.searchFields["Search songs, players, or bands"]
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

    /// Assert no "Songs", "Players" or "Bands" section title shows below the scope bar in
    /// a single scope (issue #299: the scope bar already names the scope).
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

    /// Assert "All" titles its Songs, Players and Bands results in that order, each
    /// title directly above its section's first row (issue #348).
    ///
    /// - Parameters:
    ///   - app: The running app with All results shown.
    ///   - rows: The first song, player and band rows, in that order.
    @MainActor
    private func assertSectionTitles(in app: XCUIApplication, above rows: [XCUIElement]) {
        var previousBottom = app.segmentedControls["fst.global-search.scope"].frame.maxY
        for (section, row) in zip(["songs", "players", "bands"], rows) {
            let title = app.descendants(matching: .any)
                .matching(identifier: "fst.global-search.section.\(section)").firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5), "\(section) title missing in All")
            XCTAssertEqual(title.label, section.capitalized)
            XCTAssertGreaterThanOrEqual(title.frame.minY, previousBottom - 1, "\(section) title out of order")
            XCTAssertLessThanOrEqual(title.frame.maxY, row.frame.minY + 1, "\(section) title not above its rows")
            previousBottom = row.frame.maxY
        }
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
        // "All" lists bands after players (issue #320).
        let band = app.buttons.matching(identifier: "fst.global-search.result.band").firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: 15), "Band results never arrived")
        XCTAssertGreaterThan(band.frame.minY, player.frame.minY, "Bands are not after players")
        assertSectionTitles(in: app, above: [song, player, band])
        // A single scope drops the titles again (issue #299).
        app.segmentedControls["fst.global-search.scope"].buttons["Players"].tap()
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        assertNoSectionTitles(in: app)
        app.segmentedControls["fst.global-search.scope"].buttons["All"].tap()
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        song.tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2) && field.isHittable, "Search stayed open")
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 10))
    }

    /// Issue #320: Bands searches member names, shows band cards with members and the
    /// shared song count, and a result closes Search and opens that band's page.
    @MainActor
    func testBandsScopeFindsBandsAndOpensOne() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        _ = openSearch(in: app)
        let scope = app.segmentedControls["fst.global-search.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.buttons["Bands"].tap()
        let hint = app.staticTexts["fst.global-search.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        let field = app.searchFields["Search bands"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Bands scope placeholder missing")
        field.tap()
        field.typeText("Syncing")
        let band = app.buttons.matching(identifier: "fst.global-search.result.band").firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: 15), "Band results never arrived")
        XCTAssertEqual(
            band.label, "Fixture Player 1 + Syncing Player + Empty Player, 4 songs together"
        )
        XCTAssertEqual(app.buttons.matching(identifier: "fst.global-search.result.band").count, 1)
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "fst.global-search.bands-unavailable")
                .firstMatch.exists, "The old band-search explanation is still shown"
        )
        assertNoSectionTitles(in: app)
        band.tap()
        XCTAssertFalse(field.waitForExistence(timeout: 2) && field.isHittable, "Search stayed open")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "fst.band.members-section").firstMatch
                .waitForExistence(timeout: 15),
            "The band page did not open"
        )
    }

    /// Issue #320: no matching band shows the centred Bands empty state without Retry,
    /// and a failed band search says so instead of reading as empty.
    @MainActor
    func testBandsEmptyAndFailedStayDistinct() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        _ = openSearch(in: app)
        let scope = app.segmentedControls["fst.global-search.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.buttons["Bands"].tap()
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("Pulse")
        let empty = app.descendants(matching: .any).matching(identifier: "fst.global-search.hint").firstMatch
        let shown = expectation(
            for: NSPredicate(
                format: "label == %@",
                "No Bands Found. Check the spelling or try a different band member's name."
            ),
            evaluatedWith: empty
        )
        wait(for: [shown], timeout: 15)
        XCTAssertFalse(app.buttons["Retry"].exists, "Bands empty state offered Retry")

        field.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue.repeated(5) + "busy")
        let failure = app.descendants(matching: .any).matching(identifier: "fst.global-search.bands-error").firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 15), "Band search failure not shown")
        XCTAssertFalse(app.buttons["Retry"].exists, "Bands failure offered Retry")
        XCTAssertFalse(empty.exists, "A failed band search read as empty")
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
        let origin = Self.origin
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
        // the Songs title and rows, with no Players or Bands row, title or empty message
        // (issue #348: web `shouldRenderGlobalSection`).
        let player = app.buttons.matching(identifier: "fst.global-search.result.player").firstMatch
        XCTAssertFalse(player.exists)
        let empty = app.descendants(matching: .any).matching(identifier: "fst.global-search.hint").firstMatch
        XCTAssertFalse(empty.exists, "All showed an empty Players message")
        let section = { (id: String) in
            app.descendants(matching: .any).matching(identifier: "fst.global-search.section.\(id)").firstMatch
        }
        XCTAssertTrue(section("songs").waitForExistence(timeout: 5), "Songs title missing in All")
        XCTAssertFalse(section("players").exists, "All titled an empty Players section")
        XCTAssertFalse(section("bands").exists, "All titled an empty Bands section")

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

private extension String {
    /// This string repeated `count` times.
    func repeated(_ count: Int) -> String {
        String(repeating: self, count: count)
    }
}
