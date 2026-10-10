import XCTest

/// Quick Links menu order on every iPhone page that has one (#11, after #6).
///
/// The shared `QuickLinksMenu` uses `.menuOrder(.fixed)`, so each page's menu must
/// list its sections top to bottom in the order the page draws them. Each test opens
/// the real system menu and compares the rows' on-screen order (by frame) with the
/// page's section order, which also catches missing or extra rows.
/// Settings is covered by `SettingsJourneyTests.testQuickLinksMenuListsSectionsInPageOrder`.
/// `testQuickLinksSheetIsAccessible*` check the sheet's names, selected state, reading
/// order, hit size and AX5 text (#392); hosted macOS twins: `QuickLinksAccessibilityTests`.
///
/// Fixture-backed against `tools/mock_service.py` (port 8765; Band Detail uses the
/// Bands lane's 18790 instance, like `BandsJourneyTests`).
final class QuickLinksOrderJourneyTests: XCTestCase {
    // MARK: - Helpers

    private static let itemPrefix = "fst.quick-links.item."

    /// Fixture app with no persisted profile.
    ///
    /// - Parameter environment: Extra launch environment (route, tab, profile).
    /// - Returns: The configured, not yet launched app.
    @MainActor
    private func fixtureApp(_ environment: [String: String] = [:]) -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ].merging(environment) { $1 })
    }

    /// Open the page's Quick Links menu and assert its rows run top to bottom in
    /// `expected` order, with nothing missing or extra.
    ///
    /// - Parameters:
    ///   - app: Launched app showing the page.
    ///   - expected: Section ids in the page's top-to-bottom order.
    ///   - name: Screenshot attachment name.
    @MainActor
    private func assertMenuOrder(
        _ app: XCUIApplication, _ expected: [String], name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let open = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "No Quick Links button", file: file, line: line)
        open.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.itemPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "The menu did not open", file: file, line: line)
        func visible() -> [String] {
            rows.allElementsBoundByIndex
                .map { (id: String($0.identifier.dropFirst(Self.itemPrefix.count)), top: $0.frame.minY) }
                .sorted { $0.top < $1.top }
                .map(\.id)
        }
        // A compact menu can build only the rows on screen: scroll it to collect the
        // rest in order.
        var actual = visible()
        SongsUITestSupport.record(app, name: name)
        // Swipe the list, not a row: a swipe that does not scroll lands as a tap and jumps.
        let list = app.collectionViews.containing(.button, identifier: Self.itemPrefix + (actual.first ?? ""))
            .firstMatch
        for _ in 0..<4 where list.exists && actual.count < expected.count {
            list.swipeUp(velocity: .slow)
            let before = actual.count
            for id in visible() where !actual.contains(id) { actual.append(id) }
            if actual.count == before { break }
        }
        XCTAssertEqual(actual, expected, "Quick Links rows top to bottom", file: file, line: line)
    }

    /// Instruments in Settings' default (all visible) order.
    private static let instruments = [
        "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar",
        "Solo_PeripheralBass", "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums",
    ]

    // MARK: - Compete and Song Detail (#11)

    /// Compete: Leaderboards, then Rivals.
    @MainActor
    func testCompeteMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv", "FST_DEBUG_TAB": "compete"])
        app.launch()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 15))
        assertMenuOrder(app, ["leaderboards", "rivals"], name: "quick-links-order-compete")
    }

    /// Song Detail (opened from a real Songs row): Intensity, Score History, then
    /// each charted, visible instrument's leaderboard card, then Duos, Trios and Quads.
    @MainActor
    func testSongDetailMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1"])
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fst.song-detail.intensity"].waitForExistence(timeout: 20))
        let history = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.song-detail.history")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 20), "Score History never appeared")
        assertMenuOrder(
            app,
            ["intensity", "score-history"]
                + ["Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals"].map { "instrument-\($0)" }
                + ["Band_Duets", "Band_Trios", "Band_Quad"].map { "band-\($0)" },
            name: "quick-links-order-song-detail"
        )
    }

    // MARK: - Sweep: every other Quick Links page

    /// Leaderboards: each visible instrument, then each band type.
    @MainActor
    func testLeaderboardsMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_TAB": "leaderboards"])
        app.launch()
        assertMenuOrder(
            app,
            Self.instruments.map { "instrument:\($0)" }
                + ["Band_Duets", "Band_Trios", "Band_Quad"].map { "band:\($0)" },
            name: "quick-links-order-leaderboards"
        )
    }

    /// Songs, Item Shop sort: Shop buckets in the sorted rows' order.
    @MainActor
    func testSongsShopSortMenuListsBucketsInPageOrder() throws {
        continueAfterFailure = false
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchArguments += [
            "-fst.settings.hideShop", "NO",
            "-fst.songs.sortMode", "shop",
            "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        assertMenuOrder(app, ["shop:leaving-tomorrow", "shop:in-shop"], name: "quick-links-order-songs-shop")
    }

    /// Player profile: Global Statistics, each instrument followed by its nested
    /// Rank History and Percentiles (when drawn), then Bands.
    @MainActor
    func testPlayerProfileMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_TAB": "settings", "FST_DEBUG_ROUTE": "player:fixture-player-1"])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["fst.player.available"].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.descendants(matching: .any)["fst.player.rank-history.Solo_Guitar"].waitForExistence(timeout: 20)
        )
        assertMenuOrder(
            app,
            ["global", "instrument:Solo_Guitar", "rank-history:Solo_Guitar", "percentiles:Solo_Guitar"]
                + Self.instruments.dropFirst().map { "instrument:\($0)" } + ["bands"],
            name: "quick-links-order-player"
        )
        // A nested entry is a real jump target that becomes the active section.
        app.buttons[Self.itemPrefix + "rank-history:Solo_Guitar"].tap()
        let jumped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Rank History"), object: app.buttons["fst.quick-links.open"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [jumped], timeout: 10), .completed)
    }

    // MARK: - Accessibility of the chooser (#392, for #11)

    /// Player profile with nested sections: open Quick Links, return its rows in
    /// accessibility (VoiceOver reading) order after checking each is a named,
    /// hittable button at least 44 pt tall.
    ///
    /// - Parameters:
    ///   - app: Launched app showing the profile.
    ///   - name: Screenshot attachment name.
    /// - Returns: The open chooser's rows in accessibility order.
    @MainActor
    private func openProfileQuickLinks(
        _ app: XCUIApplication, name: String, file: StaticString = #filePath, line: UInt = #line
    ) -> [XCUIElement] {
        XCTAssertTrue(app.descendants(matching: .any)["fst.player.available"].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.descendants(matching: .any)["fst.player.rank-history.Solo_Guitar"].waitForExistence(timeout: 20)
        )
        let open = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "No Quick Links button", file: file, line: line)
        XCTAssertEqual(open.label, "Quick Links", file: file, line: line)
        XCTAssertEqual(open.value as? String, "Global Statistics", file: file, line: line)
        open.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.itemPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "The menu did not open", file: file, line: line)
        SongsUITestSupport.record(app, name: name)
        return rows.allElementsBoundByIndex
    }

    /// The Quick Links sheet on a page with nested sections (#11): rows read in page
    /// order, nested rows say their instrument ("Lead Rank History", not the indented
    /// short title), only the current section's row is selected (also after jumping to a
    /// nested section), and every visible row is a hittable target at least 44 pt tall
    /// (HIG Accessibility: 44x44 pt default minimum).
    @MainActor
    func testQuickLinksSheetIsAccessible() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_TAB": "settings", "FST_DEBUG_ROUTE": "player:fixture-player-1"])
        app.launch()
        let rows = openProfileQuickLinks(app, name: "quick-links-a11y-player")
        let visible = rows.filter { $0.isHittable }
        XCTAssertGreaterThanOrEqual(visible.count, 4, "Too few rows on screen")
        // Reading order is the on-screen order.
        let ids = visible.map(\.identifier)
        XCTAssertEqual(ids, visible.sorted { $0.frame.minY < $1.frame.minY }.map(\.identifier))
        XCTAssertEqual(
            Array(ids.prefix(4)),
            ["global", "instrument:Solo_Guitar", "rank-history:Solo_Guitar", "percentiles:Solo_Guitar"]
                .map { Self.itemPrefix + $0 }
        )
        for row in visible {
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(row.identifier) \(row.frame)")
            XCTAssertFalse(row.label.isEmpty, row.identifier)
            XCTAssertFalse(row.label.contains("\u{2007}"), "Indent spoken in \(row.identifier)")
        }
        let rankHistory = app.buttons[Self.itemPrefix + "rank-history:Solo_Guitar"]
        XCTAssertEqual(rankHistory.label, "Lead Rank History")
        XCTAssertEqual(app.buttons[Self.itemPrefix + "percentiles:Solo_Guitar"].label, "Lead Percentiles")
        XCTAssertEqual(rows.filter(\.isSelected).map(\.identifier), [Self.itemPrefix + "global"])

        rankHistory.tap()
        let open = app.buttons["fst.quick-links.open"]
        let jumped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Rank History"), object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [jumped], timeout: 10), .completed)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        open.tap()
        let reopened = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.itemPrefix))
        XCTAssertTrue(reopened.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(
            reopened.allElementsBoundByIndex.filter(\.isSelected).map(\.identifier),
            [Self.itemPrefix + "rank-history:Solo_Guitar"]
        )
    }

    /// At the largest text size (AX5) the sheet's rows grow, stay named and hittable,
    /// keep page order and pass the Dynamic Type, clipped-text, hit-region and
    /// description audits. Only issues on the sheet's own elements fail; the page behind
    /// the sheet has its own audits ([accessibility.md](../../../.agents/testing/apple/accessibility.md)).
    @MainActor
    func testQuickLinksSheetIsAccessibleAtAX5() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_TAB": "settings", "FST_DEBUG_ROUTE": "player:fixture-player-1"])
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let rows = openProfileQuickLinks(app, name: "quick-links-a11y-player-ax5")
        let visible = rows.filter { $0.isHittable }
        XCTAssertGreaterThanOrEqual(visible.count, 2, "Too few rows on screen at AX5")
        let ids = visible.map(\.identifier)
        XCTAssertEqual(ids, visible.sorted { $0.frame.minY < $1.frame.minY }.map(\.identifier))
        XCTAssertEqual(ids.first, Self.itemPrefix + "global")
        for row in visible {
            // Body text at AX5 is 53 pt: a row that kept its default height clipped it.
            XCTAssertGreaterThanOrEqual(row.frame.height, 60, "\(row.identifier) \(row.frame)")
        }
        let window = app.windows.firstMatch.frame
        let list = app.collectionViews.containing(.button, identifier: ids[0]).firstMatch
        let rankHistory = app.buttons[Self.itemPrefix + "rank-history:Solo_Guitar"]
        for _ in 0..<4 where !(rankHistory.exists && rankHistory.isHittable) {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(rankHistory.isHittable, "Nested row unreachable at AX5")
        XCTAssertEqual(rankHistory.label, "Lead Rank History")
        XCTAssertLessThanOrEqual(rankHistory.frame.maxY, window.maxY)
        SongsUITestSupport.record(app, name: "quick-links-a11y-player-ax5-nested")

        var sheetIssues: [String] = []
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        ) { issue in
            let id = issue.element?.identifier ?? ""
            guard id.hasPrefix("fst.quick-links.") || id.hasPrefix("fst.page-tools.menu.") else { return true }
            sheetIssues.append("\(id): \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(sheetIssues, [], "Quick Links sheet audit issues at AX5")
    }

    /// Statistics tab (the selected player's profile): same order as the profile.
    @MainActor
    func testStatisticsMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp([
            "FST_DEBUG_PROFILE": "fixture-player-2:Fixture Player 2", "FST_DEBUG_TAB": "statistics",
        ])
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["fst.player.available"].waitForExistence(timeout: 20))
        // `fixture-player-2` has ranked Lead and Drums scores, so both carry their charts.
        assertMenuOrder(
            app,
            ["global", "instrument:Solo_Guitar", "rank-history:Solo_Guitar", "percentiles:Solo_Guitar",
             "instrument:Solo_Bass", "instrument:Solo_Drums", "rank-history:Solo_Drums", "percentiles:Solo_Drums"]
                + Self.instruments.dropFirst(3).map { "instrument:\($0)" } + ["bands"],
            name: "quick-links-order-statistics"
        )
    }

    /// Band Detail: Members, Summary, Statistics, Rank History, Songs.
    @MainActor
    func testBandDetailMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp([
            "FST_API_BASE_URL": "http://127.0.0.1:18790", "FST_DEBUG_ROUTE": "bandRankings:Band_Duets",
        ])
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "fst.band-rankings.row.fixture-team-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fst.band.members-section"].waitForExistence(timeout: 15))
        assertMenuOrder(
            app, ["members", "summary", "statistics", "rank-history", "songs"], name: "quick-links-order-band"
        )
    }

    /// Rivals (Song tab), every instrument visible: Common Rivals, then each
    /// instrument's rivals (a cross-group mix has no combo section).
    @MainActor
    func testRivalsMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv", "FST_DEBUG_ROUTE": "rivals"])
        app.launch()
        XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: 15))
        assertMenuOrder(app, ["common"] + Self.instruments, name: "quick-links-order-rivals")
    }

    /// Rivals (Song tab) with only Lead and Bass visible: Common Rivals, the
    /// combo section, then each instrument's rivals.
    @MainActor
    func testRivalsComboMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv", "FST_DEBUG_ROUTE": "rivals"])
        for key in ["Drums", "Vocals", "ProLead", "ProBass", "Karaoke", "ProCymbals", "ProDrums"] {
            app.launchArguments += ["-fst.settings.show\(key)", "NO"]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: 15))
        assertMenuOrder(app, ["common", "combo", "Solo_Guitar", "Solo_Bass"], name: "quick-links-order-rivals-combo")
    }

    /// Rival Detail: each non-empty category in its fixed order (this fixture rival
    /// has no Slipping Away or Dominating Them songs, so those are not drawn).
    @MainActor
    func testRivalDetailMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp([
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
            "FST_DEBUG_ROUTE": "rivalDetail:f1c749eb07c32578cfa3e59ec38c03a8:song:Solo_Guitar",
        ])
        app.launch()
        XCTAssertTrue(app.buttons["fst.rival-detail.view-profile"].waitForExistence(timeout: 15))
        assertMenuOrder(
            app,
            ["closest_battles", "almost_passed", "barely_winning", "pulling_forward"]
                .map { "rival-category:\($0)" },
            name: "quick-links-order-rival-detail"
        )
    }

    /// Rivalry is one list of songs: it offers no Quick Links, only View Profile, a
    /// full-size hittable button in the tab-bar accessory (owner, #545; `quick-links` R3).
    @MainActor
    func testRivalryOffersNoQuickLinks() throws {
        continueAfterFailure = false
        let app = fixtureApp([
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
            "FST_DEBUG_ROUTE": "rivalry:f1c749eb07c32578cfa3e59ec38c03a8:closest_battles:song:Solo_Guitar",
        ])
        app.launch()
        let profile = app.buttons["fst.rivalry.view-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        let lastRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Echo")).firstMatch
        XCTAssertTrue(lastRow.waitForExistence(timeout: 20), "The songs did not load")
        SongsUITestSupport.record(app, name: "rivalry-no-quick-links")
        XCTAssertFalse(app.buttons["fst.quick-links.open"].exists, "Rivalry offers Quick Links")
        XCTAssertTrue(profile.isHittable)
        XCTAssertEqual(profile.label, "View Profile")
        XCTAssertGreaterThanOrEqual(profile.frame.width, 44)
        XCTAssertGreaterThanOrEqual(profile.frame.height, 44)
    }
}
