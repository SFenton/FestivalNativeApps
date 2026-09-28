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
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "leaderboards",
        ])
    }

    /// A rankings row navigates to the player's profile (`fixture-player-1`, seeded
    /// by `mock_service.py`'s rankings roster to overlap `player-demo`).
    ///
    /// **Fixed bug:** `AccountRankingRow`'s own `fst.rankings.row.<accountId>`
    /// accessibility identifier used to never reach the actual accessibility tree —
    /// every row (and the "View All" link) under a card reported the *card's*
    /// identifier instead, because the card's `.accessibilityIdentifier` shadowed
    /// its children (a container needs `.accessibilityElement(children: .contain)`
    /// before an identifier of its own, or the identifier silently propagates to
    /// every descendant). `LeaderboardsScreen.swift`'s `instrumentCard`/`bandCard`
    /// now set `.contain` first, so the row's own identifier is reachable directly.
    ///
    /// `fixture-player-1` ranks #1 on every instrument in the fixture roster, so
    /// `fst.rankings.row.fixture-player-1` alone matches once per card; scope the
    /// query to the Solo Guitar card specifically (`.descendants` under its own
    /// now-reachable-but-still-present container identifier) rather than the page.
    @MainActor
    func testRankingRowNavigatesToPlayerProfile() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let card = app.descendants(matching: .any)
            .matching(identifier: "fst.leaderboards.card.Solo_Guitar").firstMatch
        let row = card.buttons["fst.rankings.row.fixture-player-1"]
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
    /// Uses `viewAllLink`'s own per-card identifier
    /// (`fst.leaderboards.band-card.<type>.view-all`), now that the card container
    /// no longer shadows its children's identifiers (see the bug fix note above).
    @MainActor
    func testBandCardViewAllReachesBandRankings() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let viewAll = app.buttons["fst.leaderboards.band-card.Band_Duets.view-all"]
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

    /// **Fixed bug:** jumping used to land on an *earlier* section than requested
    /// — confirmed for both a near jump (tapping "Drums", the third instrument,
    /// landed on "Bass", the second) and a far jump (tapping "Quads", the last of
    /// 12 cards, landed on "Duos", two cards earlier); see
    /// `testQuickLinksJumpToNeverVisibleFarSectionReachesTarget` below. Root cause:
    /// `QuickLinksContainerModifier.scroll`'s `withAnimation(...) { proxy.scrollTo }`
    /// completion handler ran `QuickLinksController.jumpDidSettle()` immediately,
    /// before the target section's `onGeometryChange` had republished its real,
    /// post-scroll frame — so `QuickLinkTracker.settle` read stale geometry and
    /// fell back to `QuickLinks.naturalActive` one section short. Fixed by
    /// `correctAndSettle`: a second, corrective `scrollTo` plus a couple of
    /// run-loop turns for the real frame to publish before calling `settle`.
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
        XCTAssertEqual(quickLinks.value as? String, "Drums")
    }

    /// **Fixed bug:** the same "lands before the target" bug from
    /// `testQuickLinksJumpToNearbySectionReachesExactTarget`, magnified for a far,
    /// never-before-visible target: jumping straight from the top of the page to
    /// "Quads" (the last of 12 cards, its `LazyVStack` frame never previously
    /// measured) used to leave both the scroll position and the Quick Links
    /// button's reported active section on "Duos" (two cards earlier). See the fix
    /// description above (`QuickLinksContainerModifier.correctAndSettle`).
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
        XCTAssertEqual(quickLinks.value as? String, "Quads")
    }
}
