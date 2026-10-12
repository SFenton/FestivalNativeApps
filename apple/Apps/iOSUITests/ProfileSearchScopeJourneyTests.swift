import XCTest

/// Profile search scope journeys (issue #600) against a loopback fixture started from
/// this revision: the Profiles sheet searches players and bands together under an
/// All · Players · Bands scope bar that starts on All, and a band result opens its page
/// (`.agents/controls/profile-selection/ios.md#profile-search-scopes-issue-600`,
/// `.agents/patterns/search-scopes.md`). All searches bands, so like
/// `GlobalSearchJourneyTests` it needs a fixture that serves band search:
///
///     python3 tools/mock_service.py --port 18936
final class ProfileSearchScopeJourneyTests: XCTestCase {
    /// The fixture origin every journey here uses.
    private static let origin = "http://127.0.0.1:18936"

    /// Skip unless the fixture serves band search.
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

    /// The Profiles sheet's system search field, matched by the scope's prompt.
    ///
    /// - Parameters:
    ///   - prompt: The current scope's placeholder.
    ///   - app: The running app with the Profiles sheet open.
    /// - Returns: The search field (it may not exist yet).
    @MainActor
    private func field(_ prompt: String, in app: XCUIApplication) -> XCUIElement {
        app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", prompt)).firstMatch
    }

    /// Any element carrying `identifier`.
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Launch, open the Profiles sheet and search "Syncing" in the default All scope.
    ///
    /// - Returns: The app and its scope bar, with the Syncing player and band shown.
    @MainActor
    private func searchSyncingInAll() -> (XCUIApplication, XCUIElement) {
        let app = fixtureApp()
        app.launch()
        let profile = app.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        let scope = app.segmentedControls["fst.profile.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 10), "Profile scope bar missing")
        XCTAssertEqual(scope.buttons.count, 3)
        XCTAssertEqual(scope.buttons.element(boundBy: 0).label, "All")
        XCTAssertEqual(scope.buttons.element(boundBy: 1).label, "Players")
        XCTAssertEqual(scope.buttons.element(boundBy: 2).label, "Bands")
        XCTAssertTrue(scope.buttons["All"].isSelected, "Profile search did not start on All")
        let hint = app.staticTexts["fst.profile.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertEqual(hint.label, "Enter at least two characters to search for players or bands.")
        let search = field("Search players or bands", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5), "All scope prompt missing")
        search.tap()
        search.typeText("Syncing")
        return (app, scope)
    }

    /// All lists players then bands under their section titles, Players and Bands narrow
    /// to one kind without a section title, and the sheet passes the accessibility audit.
    @MainActor
    func testAllListsPlayersAndBandsAndScopesNarrow() throws {
        continueAfterFailure = false
        let (app, scope) = searchSyncingInAll()
        let player = app.buttons["fst.profile.result.fixture-syncing"]
        let band = app.buttons.matching(identifier: "fst.profile.result.band").firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 15), "Player results never arrived")
        XCTAssertTrue(band.waitForExistence(timeout: 15), "Band results never arrived")
        XCTAssertEqual(band.label, "Fixture Player 1 + Syncing Player + Empty Player, 4 songs together")
        XCTAssertGreaterThan(band.frame.minY, player.frame.minY, "Bands are not after players")
        let playersTitle = element("fst.profile.section.players", in: app)
        let bandsTitle = element("fst.profile.section.bands", in: app)
        XCTAssertTrue(playersTitle.exists && bandsTitle.exists, "All lacks its section titles")
        XCTAssertLessThan(playersTitle.frame.minY, player.frame.minY)
        XCTAssertLessThan(bandsTitle.frame.minY, band.frame.minY)
        XCTAssertFalse(element("fst.profile.bands-unavailable", in: app).exists, "Bands are still gated")
        // Search dismisses the keyboard (its prediction bar is system chrome); results stay.
        app.typeText("\n")
        XCTAssertTrue(band.waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: .all) { issue in
            SongsUITestSupport.isSystemSearchIssue(issue)
        }

        scope.buttons["Bands"].tap()
        XCTAssertTrue(scope.buttons["Bands"].isSelected)
        XCTAssertTrue(field("Search bands", in: app).waitForExistence(timeout: 5), "Bands prompt missing")
        XCTAssertTrue(band.waitForExistence(timeout: 5))
        XCTAssertFalse(player.exists, "Bands still lists players")
        XCTAssertFalse(bandsTitle.exists, "A single scope repeats its title")

        scope.buttons["Players"].tap()
        XCTAssertTrue(field("Search players", in: app).waitForExistence(timeout: 5), "Players prompt missing")
        XCTAssertTrue(player.waitForExistence(timeout: 5))
        XCTAssertFalse(band.exists, "Players still lists bands")
        XCTAssertFalse(playersTitle.exists, "A single scope repeats its title")
    }

    /// With no player and no band, All shows one centred players-or-bands empty state
    /// without Retry, not a "Bands unavailable" failure.
    @MainActor
    func testAllEmptyNamesPlayersAndBands() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let profile = app.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        let search = field("Search players or bands", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("missing\n")
        let empty = app.staticTexts["fst.profile.hint"]
        let shown = expectation(
            for: NSPredicate(format: "label BEGINSWITH %@", "No Results Found"), evaluatedWith: empty
        )
        wait(for: [shown], timeout: 15)
        XCTAssertFalse(element("fst.profile.bands-error", in: app).exists, "Band search failed")
        XCTAssertFalse(app.buttons["Retry"].exists, "Profile search offered Retry")
    }

    /// A band result closes the Profiles sheet and opens that band's page.
    @MainActor
    func testBandResultOpensBandPage() throws {
        continueAfterFailure = false
        let (app, _) = searchSyncingInAll()
        let band = app.buttons.matching(identifier: "fst.profile.result.band").firstMatch
        XCTAssertTrue(band.waitForExistence(timeout: 15), "Band results never arrived")
        band.tap()
        XCTAssertTrue(
            element("fst.band.members-section", in: app).waitForExistence(timeout: 15),
            "The band page did not open"
        )
        XCTAssertFalse(app.segmentedControls["fst.profile.scope"].exists, "The Profiles sheet stayed open")
    }
}
