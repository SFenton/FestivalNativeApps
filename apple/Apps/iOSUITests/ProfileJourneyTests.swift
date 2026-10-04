import XCTest

// MARK: - ProfileJourneyTests

/// Player-selection journeys against the loopback fixture (`tools/mock_service.py`
/// on `127.0.0.1:8765`), guarding the wrong-account bug fixed by Lane Z2.
///
/// Root cause: `ProfileSelectionSheet` placed every search result inside one Form
/// row, and an iOS List row fires *every* default-style Button it contains on one
/// tap, so tapping any result pushed one `/player/:accountId` per result and left
/// the last result's profile on top. These journeys assert the tapped account, and
/// only that account, is pushed: the page names it, and one Back returns to the
/// presenting tab root.
final class ProfileJourneyTests: XCTestCase {
    // MARK: Launch

    /// Anonymous fixture app on Songs with a still background (no carousel idle waits).
    @MainActor
    private func launchFixtureApp() -> XCUIApplication {
        FestivalApp.launch([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ])
    }

    // MARK: Helpers

    /// Open the root profile sheet, search, and tap one exact result row.
    ///
    /// - Parameters:
    ///   - accountId: Fixture account whose result row to tap.
    ///   - query: Search text that returns several results including `accountId`.
    ///   - app: Launched fixture app on a tab root.
    @MainActor
    private func openResult(_ accountId: String, query: String, in app: XCUIApplication) {
        let profile = app.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(query)
        let result = app.buttons["fst.profile.result.\(accountId)"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
    }

    /// Require the pushed profile page to belong to exactly `displayName`.
    ///
    /// - Parameters:
    ///   - displayName: Fixture display name expected in the page title.
    ///   - app: App on the pushed player page.
    @MainActor
    private func assertViewing(_ displayName: String, in app: XCUIApplication) {
        XCTAssertTrue(SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: 15))
        SongsUITestSupport.assertPlayerTitle(displayName, in: app)
    }

    /// One Back must land on the presenting tab root: only one route was pushed.
    ///
    /// - Parameter app: App on the pushed player page.
    @MainActor
    private func assertSingleBackReturnsToRoot(in app: XCUIApplication) {
        let back = app.navigationBars.buttons["BackButton"].exists
            ? app.navigationBars.buttons["BackButton"]
            : app.navigationBars.buttons.element(boundBy: 0)
        back.tap()
        XCTAssertTrue(
            app.buttons["fst.shell.profile"].waitForExistence(timeout: 10),
            "Back did not return to the tab root; more than one profile was pushed"
        )
        XCTAssertFalse(SongsUITestSupport.playerPage(in: app).exists)
    }

    // MARK: Journeys

    /// Tapping the *first* of several results opens that player, not the last one.
    @MainActor
    func testTappedSearchResultOpensExactlyThatPlayer() {
        let app = launchFixtureApp()
        openResult("fixture-player-1", query: "Fixture Player", in: app)
        assertViewing("Fixture Player 1", in: app)
        assertSingleBackReturnsToRoot(in: app)
    }

    /// A middle result of a longer list opens only that account.
    @MainActor
    func testMiddleSearchResultOpensExactlyThatPlayer() {
        let app = launchFixtureApp()
        openResult("fixture-player-2", query: "Player", in: app)
        assertViewing("Fixture Player 2", in: app)
        assertSingleBackReturnsToRoot(in: app)
    }

    /// Operator rule: Select on the Player Profile page updates it in place (the
    /// Select action leaves; Deselect lives in the drawer since operator batch 7; there
    /// is no "This Is Me" / "Public Profile" subtitle, matching the web). They never pop, push or dismiss, and
    /// the page keeps showing the same account throughout. Uses Settings, the one
    /// iPhone tab that exists both with and without a selected player, so tab-set
    /// changes cannot mask a navigation.
    @MainActor
    func testSelectAndDeselectUpdateProfilePageInPlace() {
        let app = FestivalApp.launch([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "settings",
            "FST_DEBUG_ROUTE": "player:fixture-player-1",
        ])
        assertViewing("Fixture Player 1", in: app)

        let select = app.buttons["fst.player.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        // Selected in place: the Select action leaves and no Deselect replaces it (the
        // drawer owns Deselect since operator batch 7).
        let selectGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: select)
        XCTAssertEqual(XCTWaiter.wait(for: [selectGone], timeout: 10), .completed,
                       "Select did not update the page to its selected state in place")
        XCTAssertFalse(app.buttons["fst.player.deselect"].exists, "The player page must not offer Deselect")
        XCTAssertFalse(app.staticTexts["This Is Me"].exists)
        assertViewing("Fixture Player 1", in: app)
        XCTAssertTrue(app.navigationBars.buttons["BackButton"].exists, "The page was popped")
    }

    /// View A, go back, then view B: B's page shows B (no state kept from A).
    @MainActor
    func testSecondSearchShowsSecondPlayerNotFirst() {
        let app = launchFixtureApp()
        openResult("fixture-player-2", query: "Fixture Player", in: app)
        assertViewing("Fixture Player 2", in: app)
        assertSingleBackReturnsToRoot(in: app)
        openResult("fixture-player-1", query: "Fixture Player", in: app)
        assertViewing("Fixture Player 1", in: app)
        assertSingleBackReturnsToRoot(in: app)
    }

    /// Issue #290, the reported steps: choose a player from the profile button, select
    /// them, return to Songs, then press the profile button again. It opens that player's
    /// own profile (Statistics) instead of profile search, every time, and pressing it on
    /// that page pushes nothing more.
    @MainActor
    func testProfileButtonOpensSelectedPlayerInsteadOfSearch() {
        let app = launchFixtureApp()
        openResult("fixture-player-1", query: "Fixture Player", in: app)
        assertViewing("Fixture Player 1", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        let profile = app.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        XCTAssertTrue(profile.label.contains("Fixture Player 1"), profile.label)
        let page = SongsUITestSupport.playerPage(in: app)
        for attempt in 1...2 {
            profile.tap()
            XCTAssertTrue(page.waitForExistence(timeout: 15), "Press \(attempt) did not open the selected profile")
            XCTAssertFalse(app.buttons["fst.profile.close"].exists, "Press \(attempt) opened profile search")
            if UIDevice.current.userInterfaceIdiom == .pad {
                // Statistics is a sidebar row on iPad: the button selected it.
                SongsUITestSupport.rootControl("Songs", app: app).tap()
                XCTAssertTrue(page.waitForNonExistence(timeout: 10))
            } else {
                // Already on the selected player's page: nothing more is pushed.
                app.buttons["fst.shell.profile"].firstMatch.tap()
                XCTAssertFalse(app.buttons["fst.profile.close"].waitForExistence(timeout: 2))
                assertSingleBackReturnsToRoot(in: app)
            }
        }
    }

    /// The native search field keeps the sheet's title and Close while focused
    /// (`.searchable` hides the navigation bar by default) and the two-character hint
    /// sits below the scope control. Anonymous: with a selected player the profile
    /// button opens their Statistics instead (issue #290).
    @MainActor
    func testSearchFocusKeepsTitleAndCloseInProfileSheet() {
        let app = launchFixtureApp()
        let profile = app.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        let close = app.buttons["fst.profile.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["fst.profile.selected"].exists)
        let hint = app.staticTexts["fst.profile.search-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(hint.frame.minY, app.segmentedControls["fst.profile.scope"].frame.maxY)
        let search = app.searchFields.matching(
            NSPredicate(format: "placeholderValue == %@", "Find Player")
        ).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("F")
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(close.isHittable, "Close hid behind the focused search field")
        XCTAssertTrue(app.navigationBars["Profiles"].exists, "Sheet title hid while searching")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }
}
