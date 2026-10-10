import UIKit
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
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765",
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

    // MARK: - Compete -> rival row (#369)

    /// A phone window (iPhone, the folded iPhone Duo) never splits: a rival row on
    /// Compete pushes Rival Detail full width with the system Back (no split Close), a
    /// category's View All pushes Rivalry on the same stack, and Back returns step by
    /// step to Compete. The split-capable layouts open the rival beside Compete instead
    /// (`IPadShellJourneyTests.testCompeteRivalOpensBesideCompete`).
    @MainActor
    func testCompeteRivalRowPushesFullPageOnPhone() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_TAB"] = "compete"
        app.launch()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 15))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.rivals.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15), "Compete lists rivals")
        for _ in 0..<8 where !rows.allElementsBoundByIndex.contains(where: \.isHittable) {
            app.swipeUp()
        }
        let row = try XCTUnwrap(rows.allElementsBoundByIndex.first(where: \.isHittable), "an on-screen rival row")
        row.tap()
        XCTAssertTrue(app.buttons["fst.rival-detail.view-profile"].waitForExistence(timeout: 15), "Rival Detail opens")
        XCTAssertFalse(app.descendants(matching: .any)["fst.split.trailing"].exists, "no trailing pane on a phone")
        XCTAssertFalse(app.buttons["fst.split.close"].exists, "a pushed page has Back, not Close")
        XCTAssertFalse(app.navigationBars["Compete"].exists, "Rival Detail covers Compete")
        let viewAll = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "fst.rival-detail.category.", ".view-all"
        )).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15))
        viewAll.tap()
        XCTAssertTrue(app.buttons["fst.rivalry.view-profile"].waitForExistence(timeout: 15), "Rivalry opens")
        XCTAssertFalse(app.buttons["fst.split.close"].exists, "Rivalry has Back, not Close")
        tapBack(app)
        XCTAssertTrue(app.buttons["fst.rival-detail.view-profile"].waitForExistence(timeout: 10), "Back to Rival Detail")
        tapBack(app)
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 10), "Back to Compete")
    }

    /// The system Back: in the iPhone Duo vertical bar when it has one, else the
    /// navigation bar's first button.
    @MainActor
    private func tapBack(_ app: XCUIApplication) {
        let bar = app.buttons["BackButton"]
        (bar.exists && bar.isHittable ? bar : app.navigationBars.buttons.firstMatch).tap()
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

    // MARK: - Song comparison cards (#558, pattern rival-rows)

    /// At the largest accessibility size each Rival Detail song card is still one element
    /// reading the song, both ranks and who leads (colour is never the only signal), keeps a
    /// 44 pt target, and the audit finds no clipped text or small hit region in the cards
    /// now that their "#rank Name" pills wrap and the art column joins them.
    @MainActor
    func testRivalDetailSongCardsAreAccessibleAtAX5() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_ROUTE"] =
            "rivalDetail:f1c749eb07c32578cfa3e59ec38c03a8:song:Solo_Guitar"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", ", you rank ")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertTrue(
            card.label.hasSuffix(" leads") || card.label.hasSuffix("you lead") || card.label.hasSuffix(", tied"),
            "Card label must name who leads: \(card.label)"
        )
        XCTAssertTrue(card.label.contains(" ranks "), "Card label must read the rival's rank: \(card.label)")
        XCTAssertGreaterThanOrEqual(card.frame.height, 44)

        var open: [String] = []
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion]) { issue in
            guard let element = issue.element, element.label.contains(", you rank ") else { return true }
            open.append("\(issue.compactDescription): '\(element.label)' \(element.frame)")
            return true
        }
        XCTAssertEqual(open, [], "Rival song cards must not clip or shrink at AX5")
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

    // MARK: - All Rivals title (#557)

    /// All Rivals leads with its own icon-led title (Full Rankings' `InstrumentPageTitle`):
    /// read once, above the rows, with no section title repeating it on the card. Once
    /// it scrolls under the bar, the bar shows the compact copy, still read as the title
    /// alone (the icon is hidden). The title passes the accessibility audit at the top and
    /// pinned, and at AX5 it grows with the text and stays on screen. The fixture's six
    /// rivals only overflow the screen at AX5, so the pinned title is checked there.
    @MainActor
    func testAllRivalsTitleLeadsTheListAndPinsAfterScroll() throws {
        continueAfterFailure = false
        let defaultHeight = try checkAllRivalsTitle(largeText: false)
        let largeHeight = try checkAllRivalsTitle(largeText: true)
        XCTAssertGreaterThan(
            largeHeight, defaultHeight * 1.35,
            "The title did not scale: \(largeHeight) pt at AX5, \(defaultHeight) pt default"
        )
    }

    /// Open Lead Rivals and check its title at the top and pinned.
    ///
    /// - Parameter largeText: Launch at the largest accessibility text size (AX5).
    /// - Returns: The in-list title's height.
    @MainActor
    private func checkAllRivalsTitle(largeText: Bool) throws -> CGFloat {
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_ROUTE"] = "allRivals:song:Solo_Guitar"
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        defer { app.terminate() }
        let title = app.descendants(matching: .any)["fst.all-rivals.title"]
        XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(15)))
        let firstRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "fst.all-rivals.row."
        )).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertEqual(title.label, "Lead Rivals", "The icon adds nothing to the spoken title")
        XCTAssertLessThanOrEqual(title.frame.maxY, firstRow.frame.minY + 1, "The title reads before the rows")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(title.frame.minX, window.minX)
        XCTAssertLessThanOrEqual(title.frame.maxX, window.maxX, "The title fits the window: \(title.frame)")
        let bar = app.navigationBars.firstMatch.frame
        let named = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Lead Rivals"))
            .allElementsBoundByIndex.filter { $0.exists && $0.frame.minY >= bar.maxY && $0.frame.height > 0 }
        let elsewhere = named.filter { !title.frame.insetBy(dx: -1, dy: -1).contains($0.frame) }
        XCTAssertTrue(elsewhere.isEmpty, "No section title repeats the page name: \(elsewhere.map(\.frame))")
        XCTAssertFalse(app.descendants(matching: .any)["fst.all-rivals.pinned-title"].exists,
                       "No bar copy while the title is in view")
        let height = title.frame.height
        // The title's own text, right of the icon, measured as rendered over the page
        // background: at least 4.5:1, so the audit's estimate is checked, not trusted.
        let titleText = named.first { $0.frame.minX > title.frame.minX + 1 } ?? title
        try SongsUITestSupport.assertHeaderContrast(titleText, in: app)
        // The fixture's six rivals fit the default-size screen, so only AX5 scrolls. The
        // audit cycles text sizes and then restores the system size, so it runs last.
        guard largeText else {
            try auditAllRivals(app, name: "top")
            return height
        }
        let pinned = app.descendants(matching: .any)["fst.all-rivals.pinned-title"]
        for _ in 0..<4 where !pinned.exists {
            app.swipeUp()
            _ = pinned.waitForExistence(timeout: FestivalApp.budget(2))
        }
        XCTAssertTrue(pinned.exists, "The title pins to the bar after scrolling")
        XCTAssertEqual(pinned.label, "Lead Rivals", "The pinned icon is hidden too")
        XCTAssertLessThan(pinned.frame.midY, app.navigationBars.firstMatch.frame.maxY, "Pinned in the bar")
        try auditAllRivals(app, name: "ax5 scrolled")
        return height
    }

    /// Beside the iPhone Duo vertical bar (folded outer display and inner landscape),
    /// iOS 27 minimizes the top bar on scroll, so All Rivals never pins its custom title
    /// there: the system title is in the bar at the top, no custom copy appears after the
    /// in-list title scrolls away, and on a real Duo (whose bar minimizes, title and all)
    /// the system title returns at the top (page-tools-and-nav-chrome R14, #557). The app simulates each Duo
    /// window through the Debug `FST_DEBUG_DUO_WINDOW` switch (`DebugDuoWindow`: size
    /// classes and vertical bar), so this runs on any iPhone simulator, the Duo included.
    /// At AX5 the fixture's six rivals overflow the screen, so the title can scroll away.
    @MainActor
    func testAllRivalsDuoVerticalBarKeepsSystemTitle() throws {
        continueAfterFailure = false
        for window in ["folded", "unfolded-landscape"] {
            let app = fixtureApp()
            app.launchEnvironment["FST_DEBUG_ROUTE"] = "allRivals:song:Solo_Guitar"
            app.launchEnvironment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            app.launchEnvironment["FST_DEBUG_DUO_WINDOW"] = window
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
            app.launch()
            defer { app.terminate() }
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let simulated = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                       "\(window) ", "chrome=verticalBar"),
                object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [simulated], timeout: FestivalApp.budget(15)), .completed,
                           "\(window): the app never simulated the vertical bar (\(readout.label))")
            let title = app.descendants(matching: .any)["fst.all-rivals.title"]
            XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(15)), "\(window): no in-list title")
            let pinned = app.descendants(matching: .any)["fst.all-rivals.pinned-title"]
            let systemTitle = app.navigationBars.staticTexts
                .matching(NSPredicate(format: "label == %@", "Lead Rivals")).firstMatch
            XCTAssertTrue(systemTitle.waitForExistence(timeout: FestivalApp.budget(10)),
                          "\(window): the system title is in the bar at the top")
            XCTAssertFalse(pinned.exists, "\(window): no custom pinned title at the top")

            let bar = app.navigationBars.firstMatch
            for _ in 0..<4 where title.exists && title.frame.maxY > bar.frame.maxY {
                app.swipeUp()
            }
            XCTAssertTrue(!title.exists || title.frame.maxY <= bar.frame.maxY + 1,
                          "\(window): the in-list title never scrolled under the bar (\(title.frame))")
            // Give the pinned-title animation time to run before asserting it never came.
            XCTAssertFalse(pinned.waitForExistence(timeout: FestivalApp.budget(2)),
                           "\(window): the custom pinned title replaced the system title after scrolling")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "all-rivals-duo-\(window)-scrolled"
            shot.lifetime = .keepAlways
            add(shot)
            if Self.isRealDuoWindow(app.windows.firstMatch.frame.size) {
                // A real Duo vertical bar minimizes the top bar, system title included,
                // on scroll; it must come back, still the system title, at the top.
                for _ in 0..<4 where !systemTitle.exists { app.swipeDown() }
                XCTAssertTrue(systemTitle.waitForExistence(timeout: FestivalApp.budget(5)),
                              "\(window): the system title returns at the top")
                XCTAssertFalse(pinned.exists, "\(window): no custom pinned title back at the top")
            } else {
                XCTAssertTrue(systemTitle.exists, "\(window): the system title stays after scrolling")
            }
        }
    }

    /// Whether the real window is one of the iPhone Duo's (outer 466 × 678 or inner
    /// 951 × 669 pt, either orientation; `DebugDuoWindow.size`), where the system
    /// vertical bar is real and minimizes the top bar on scroll.
    private static func isRealDuoWindow(_ size: CGSize) -> Bool {
        let sides = [min(size.width, size.height).rounded(), max(size.width, size.height).rounded()]
        return sides == [466, 678] || sides == [669, 951]
    }

    /// Audit the title region this page owns (#557): the in-list title, the pinned bar
    /// title and anything else named by the title. Other regions (rows, chrome) have their
    /// own journeys; their issues are listed as an activity, not failed here. A contrast
    /// estimate on the title text is accepted only because the caller first measured the
    /// title's rendered contrast (`SongsUITestSupport.assertHeaderContrast`).
    ///
    /// - Parameters:
    ///   - app: All Rivals.
    ///   - name: Names the audit pass.
    @MainActor
    private func auditAllRivals(_ app: XCUIApplication, name: String) throws {
        let owned: Set<String> = ["fst.all-rivals.title", "fst.all-rivals.pinned-title"]
        var rejected: [String] = []
        var elsewhere: [String] = []
        let check: (XCUIAccessibilityAuditIssue) -> Bool = { issue in
            let element = issue.element.map {
                "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)' \($0.frame)"
            } ?? "no element"
            let description = "\(issue.compactDescription) [\(element)]"
            if let target = issue.element, owned.contains(target.identifier) || target.label == "Lead Rivals" {
                if issue.auditType == .contrast, target.elementType == .staticText {
                    // The audit cycles text sizes and samples the artwork behind the
                    // title; its rendered contrast was measured at ≥ 4.5:1 above.
                    elsewhere.append("title measured ≥ 4.5:1: \(description)")
                } else {
                    rejected.append(description)
                }
            } else {
                elsewhere.append(description)
            }
            return true
        }
        do {
            try app.performAccessibilityAudit(for: .all, check)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            rejected = []
            elsewhere = []
            try app.performAccessibilityAudit(for: .all, check)
        }
        XCTContext.runActivity(named: "\(name): outside the title \(elsewhere)") { _ in }
        XCTAssertTrue(rejected.isEmpty, "\(name): \(rejected)")
    }
}
