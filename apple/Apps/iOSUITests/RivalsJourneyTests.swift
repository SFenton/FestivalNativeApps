import XCTest

/// Rivals/Compete navigation journeys, fixture-backed against
/// `tools/mock_service.py`'s Rivals/Compete/rankings routes (extended by this
/// lane: `/api/player/{id}/rivals/*`, `/api/player/{id}/leaderboard-rivals/*`
/// and `/api/rankings/{instrument}`; see `mock_service.py`'s `RIVAL_DISPLAY_NAMES`
/// and `_rivals_scenario` for the `-empty`/`-503` account-id scenario switch).
///
/// Hosted (macOS) snapshot coverage for every declared control state (loading,
/// loaded song/leaderboard tab, Common/Combo sections, empty, unavailable, Find
/// Rival search states, rival detail categories, rivalry ordering) lives in
/// `RivalsRenderTests.swift`/`CompeteRenderTests.swift`; this file covers only
/// what a real device navigation stack and native controls (`NSSegmentedControl`
/// has no iOS analog here — Rivals' Song/Leaderboard picker is a real
/// `UISegmentedControl` on device) can prove: taps actually pushing routes,
/// the Quick Links menu, Find Rival's real search-then-push, and `DebugLaunchRoute`
/// scope-carrying deep links.
final class RivalsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
        ])
    }

    // MARK: - Compete -> Rivals -> rival row -> All Rivals -> Rival Detail -> Rivalry

    /// A full drill-down: Compete tab, into the Rivals hub, "View All Rivals" on a
    /// per-instrument section, a row in All Rivals, then the purple "View All"
    /// below the first (non-empty) rivalry category (#321).
    @MainActor
    func testCompeteToRivalsToAllRivalsToDetailToRivalryDrillDown() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_TAB"] = "compete"
        app.launch()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 15))

        // Drawer -> Rivals (Rivals is a drawer-reached pushed page, not a tab root;
        // see `.agents/controls/app-navigation/ios.md`).
        let drawerOpen = app.buttons["fst.shell.drawer.open"]
        XCTAssertTrue(drawerOpen.waitForExistence(timeout: 15))
        drawerOpen.tap()
        let rivalsItem = app.buttons["fst.shell.drawer.rivals"]
        XCTAssertTrue(rivalsItem.waitForExistence(timeout: 10))
        rivalsItem.tap()
        XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: 15))

        // The first "View All Rivals" row belongs to whichever section loaded
        // first (Common Rivals when 2+ instruments are visible, else the first
        // per-instrument section); either way it reaches `AllRivalsScreen`.
        let viewAll = app.buttons["View All Rivals"].firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15))
        viewAll.tap()

        // A rival row in All Rivals pushes to Rival Detail.
        let allRivalsRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "fst.all-rivals.row."
        )).firstMatch
        XCTAssertTrue(allRivalsRow.waitForExistence(timeout: 15))
        allRivalsRow.tap()
        let viewProfile = app.buttons["fst.rival-detail.view-profile"]
        XCTAssertTrue(viewProfile.waitForExistence(timeout: 15))

        // "View All" under the first category (always "Closest Battles" when any
        // shared songs exist) reaches Rivalry; it speaks the label first, then the card.
        let categoryViewAll = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "fst.rival-detail.category.", ".view-all"
        )).firstMatch
        XCTAssertTrue(categoryViewAll.waitForExistence(timeout: 10))
        XCTAssertTrue(categoryViewAll.label.hasPrefix("View All, "))
        XCTAssertFalse(app.buttons["See All"].exists)
        categoryViewAll.tap()
        XCTAssertTrue(app.buttons["fst.rivalry.view-profile"].waitForExistence(timeout: 15))
    }

    // MARK: - Compete -> View Full Leaderboard (#36)

    /// Like the web's `CompetePage`, Compete has no "Leaderboards Overview" button;
    /// each instrument's "View Full Leaderboard" pushes that instrument's full board.
    @MainActor
    func testCompeteHasNoOverviewButtonAndViewFullLeaderboardPushesFullRankings() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_TAB"] = "compete"
        app.launch()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 15))
        // The section's container identifier overrides this link's own in the
        // accessibility tree, so match the label; the first board is Lead.
        let viewFull = app.buttons["View Full Leaderboard"].firstMatch
        XCTAssertTrue(viewFull.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Leaderboards Overview"].exists)
        XCTAssertFalse(app.staticTexts["Leaderboards Overview"].exists)
        viewFull.tap()
        XCTAssertTrue(app.navigationBars["Lead Rankings"].waitForExistence(timeout: 15))
    }

    // MARK: - Quick Links

    /// Compete's Quick Links menu lists its two coarse sections ("Leaderboards",
    /// "Rivals") and jumping to one updates the active section.
    ///
    /// **Fixed bug (lane/bugfix, 2026-09-28):** tapping a `QuickLinksMenu` row
    /// other than the first used to activate the row *above* the one tapped —
    /// reproduced here (tapping `fst.quick-links.item.rivals`, the 2nd of 2 rows,
    /// activated "Leaderboards", the 1st) and on `RivalsScreen`. Root cause was in
    /// the shared `Common/QuickLinks/QuickLinksModifiers.swift`: the scroll
    /// animation's completion handler could fire before the target section's real,
    /// post-scroll frame had published, so `QuickLinkTracker.settle` read stale
    /// geometry and fell back to the previous section. Fixed by
    /// `QuickLinksContainerModifier.correctAndSettle`, which polls the target's
    /// frame until it stabilizes before settling — see that lane's commit for the
    /// full root-cause writeup. The polling loop below is kept (rather than a bare
    /// wait) since settling is still asynchronous, just now correct.
    @MainActor
    func testCompeteQuickLinksMenuListsBothSections() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_TAB"] = "compete"
        app.launch()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 15))
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        quickLinks.tap()
        XCTAssertTrue(app.buttons["fst.quick-links.item.leaderboards"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["fst.quick-links.item.rivals"].exists)
        app.buttons["fst.quick-links.item.rivals"].tap()
        var value = quickLinks.value as? String
        for _ in 0..<40 where value != "Rivals" {
            Thread.sleep(forTimeInterval: 0.1)
            value = quickLinks.value as? String
        }
        XCTAssertEqual(value, "Rivals")
    }

    // MARK: - Find Rival: search -> select

    /// Typing a search term in Find Rival, waiting for a real result, and
    /// selecting it pushes straight to that rival's detail.
    @MainActor
    func testFindRivalSearchThenSelectPushesToRivalDetail() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_ROUTE"] = "rivals"
        app.launch()
        XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: 15))
        let findRival = app.buttons["fst.rivals.findRival"]
        XCTAssertTrue(findRival.waitForExistence(timeout: 15))
        findRival.tap()
        let search = app.textFields["fst.rivals.findRival.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Fixture")
        let result = app.buttons["fst.rivals.findRival.result.fixture-player-1"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        XCTAssertTrue(app.buttons["fst.rival-detail.view-profile"].waitForExistence(timeout: 15))
    }

    // MARK: - Deep link with a carried `RivalScope`

    /// `DebugLaunchRoute`'s `rivalDetail:<id>:<scope>` opens directly into the
    /// scope-resolved detail — the same information a tapped row would carry,
    /// with no navigation bridge to re-stash it (see `RivalScope`).
    @MainActor
    func testDeepLinkIntoRivalDetailWithSongScope() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_ROUTE"] =
            "rivalDetail:f1c749eb07c32578cfa3e59ec38c03a8:song:Solo_Guitar"
        app.launch()
        XCTAssertTrue(app.buttons["fst.rival-detail.view-profile"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Closest Battles"].waitForExistence(timeout: 10))
    }

    /// A `leaderboard:<instrument>:<rankBy>` scope also resolves directly.
    @MainActor
    func testDeepLinkIntoAllRivalsWithLeaderboardScope() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_ROUTE"] = "allRivals:leaderboard:Solo_Guitar:totalscore"
        app.launch()
        // `Instrument.lead.rawValue == "Solo_Guitar"`; `AllRivalsScreen`'s title
        // uses the instrument's display label ("Lead"), not its raw wire value.
        XCTAssertTrue(app.navigationBars["Lead Leaderboard Rivals"].waitForExistence(timeout: 15))
    }
}
