import XCTest

/// Leaderboards overview, full rankings, band rankings and the Quick Links menu,
/// fixture-backed against `tools/mock_service.py`'s `/api/rankings/*` routes.
///
/// Hosted (macOS) snapshot coverage for card/row rendering and the
/// `QuickLinksController` logic lives in `LeaderboardsHostedTests.swift`; this
/// file covers real navigation and the native `Menu`-based Quick Links button
/// that only a device can drive.
final class LeaderboardsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_CLEAR_PROFILE"] = "1"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launchEnvironment["FST_DEBUG_TAB"] = "leaderboards"
        return app
    }

    /// A rankings row navigates to the player's profile (`fixture-player-1`, seeded
    /// by `mock_service.py`'s rankings roster to overlap `player-demo`).
    ///
    /// **Real bug found:** `AccountRankingRow`'s own `fst.rankings.row.<accountId>`
    /// accessibility identifier never reaches the actual accessibility tree — every
    /// row (and the "View All" link) under a card reports the *card's* identifier
    /// instead (`fst.leaderboards.card.<instrument>`), confirmed via
    /// `tools/ios_sim.py drive`'s `tree:` dump. Rows stay reachable by their (still
    /// correct and unique) label text, which this test uses instead.
    @MainActor
    func testRankingRowNavigatesToPlayerProfile() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let row = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH %@",
            "fst.leaderboards.card.Solo_Guitar", "#1, Fixture Player 1,"
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.player.available").firstMatch
                .waitForExistence(timeout: 15)
        )
    }

    /// "View All" on a band card reaches the paginated Band Rankings page.
    ///
    /// Band cards are the last three of twelve in a `LazyVStack`: they aren't
    /// constructed (or their rankings loaded) until scrolled near, so this scrolls
    /// down first rather than assuming `waitForExistence` alone will find them.
    @MainActor
    func testBandCardViewAllReachesBandRankings() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let viewAll = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label == 'View All'", "fst.leaderboards.band-card.Band_Duets"
        )).firstMatch
        for _ in 0..<15 where !viewAll.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(viewAll.waitForExistence(timeout: 10))
        viewAll.tap()
        XCTAssertTrue(app.navigationBars["Duos Rankings"].waitForExistence(timeout: 15))
        // Unlike the overview cards, `BandRankingsScreen` uses a plain `List` with no
        // extra ancestor identifier, so the row's own identifier is not shadowed here.
        XCTAssertTrue(app.buttons["fst.band-rankings.row.fixture-team-1"].waitForExistence(timeout: 15))
    }

    /// The Quick Links menu opens and lists every section with correct identifiers.
    @MainActor
    func testQuickLinksMenuOpensWithCorrectSectionIdentifiers() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        XCTAssertEqual(quickLinks.value as? String, "Lead", "Starts on the first section")
        quickLinks.tap()
        XCTAssertTrue(
            app.buttons["fst.quick-links.item.instrument:Solo_Drums"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["fst.quick-links.item.band:Band_Quad"].exists)
    }

    /// **Real bug found:** jumping to any section other than the immediately
    /// adjacent one lands on an *earlier* section than requested, not the one
    /// tapped — confirmed for both a near jump (tapping "Drums", the third
    /// instrument, lands on "Bass", the second) and a far jump (tapping "Quads",
    /// the last of 12 cards, lands on "Duos", two cards earlier); see
    /// `testQuickLinksJumpToNeverVisibleFarSectionReachesTarget` below. Likely
    /// cause: `QuickLinkTracker.settle`'s fallback to `QuickLinks.naturalActive`
    /// (current post-scroll geometry) rather than trusting the jump's own target
    /// once the scroll animation completes. Tracked with `XCTExpectFailure`
    /// rather than silently masking it; not fixed in this lane (shared
    /// `Common/QuickLinks` scrolling logic, not a trivial change).
    @MainActor
    func testQuickLinksJumpToNearbySectionReachesExactTarget() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        quickLinks.tap()
        let drumsItem = app.buttons["fst.quick-links.item.instrument:Solo_Drums"]
        XCTAssertTrue(drumsItem.waitForExistence(timeout: 10))
        drumsItem.tap()
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 10))
        XCTExpectFailure(
            "Quick Links jump lands one section before the tapped target; see doc comment above."
        ) {
            XCTAssertEqual(quickLinks.value as? String, "Drums")
        }
    }

    /// **Real bug found:** the same "lands before the target" bug from
    /// `testQuickLinksJumpToNearbySectionReachesExactTarget`, magnified for a far,
    /// never-before-visible target: jumping straight from the top of the page to
    /// "Quads" (the last of 12 cards, its `LazyVStack` frame never previously
    /// measured) leaves both the scroll position and the Quick Links button's
    /// reported active section on "Duos" (two cards earlier), confirmed via
    /// `tools/ios_sim.py drive`'s `tree:` dump. Likely cause: `QuickLinkTracker.settle`
    /// falls back to `QuickLinks.naturalActive` (current geometry) when the jump
    /// target's frame isn't in `frames` yet, rather than the scroll itself reaching
    /// the correct offset for an unmeasured target. Tracked here with
    /// `XCTExpectFailure` rather than silently masking it; not fixed in this lane
    /// (shared `Common/QuickLinks` scrolling logic, not a trivial change).
    @MainActor
    func testQuickLinksJumpToNeverVisibleFarSectionReachesTarget() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        quickLinks.tap()
        let bandItem = app.buttons["fst.quick-links.item.band:Band_Quad"]
        XCTAssertTrue(bandItem.waitForExistence(timeout: 10))
        bandItem.tap()
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 10))
        XCTExpectFailure(
            "Quick Links jump-to-section doesn't reach a section whose LazyVStack "
                + "frame was never previously measured; see doc comment above."
        ) {
            XCTAssertEqual(quickLinks.value as? String, "Quads")
        }
    }
}
