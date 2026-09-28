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
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_CLEAR_PROFILE"] = "1"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launch()
        return app
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
        let search = app.textFields["fst.profile.search"]
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
    ///   - displayName: Fixture display name expected in the page header.
    ///   - app: App on the pushed player page.
    @MainActor
    private func assertViewing(_ displayName: String, in app: XCUIApplication) {
        let name = app.staticTexts["fst.player.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", displayName), object: name
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [settled], timeout: 10), .completed,
            "Viewed \(name.label), expected \(displayName)"
        )
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
        XCTAssertFalse(app.staticTexts["fst.player.name"].exists)
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
}
