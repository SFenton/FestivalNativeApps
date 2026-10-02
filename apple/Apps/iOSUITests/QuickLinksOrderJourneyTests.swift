import XCTest

/// Quick Links menu order on every iPhone page that has one (#11, after #6).
///
/// The iPhone menu opens upward from the bottom dock, where iOS reverses an
/// `.automatic`-order menu so its first item sits nearest the touch. The shared
/// `QuickLinksMenu` uses `.menuOrder(.fixed)` instead, so each page's menu must
/// list its sections top to bottom in the order the page draws them. Each test
/// opens the real system menu and compares the rows' on-screen order (by frame)
/// with the page's section order, which also catches missing or extra rows.
/// Settings is covered by `SettingsJourneyTests.testQuickLinksMenuListsSectionsInPageOrder`.
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
        let actual = rows.allElementsBoundByIndex
            .map { (id: String($0.identifier.dropFirst(Self.itemPrefix.count)), top: $0.frame.minY) }
            .sorted { $0.top < $1.top }
            .map(\.id)
        SongsUITestSupport.record(app, name: name)
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

    /// Rivalry: one entry per song in the category, in list order.
    @MainActor
    func testRivalryMenuListsSongsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp([
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
            "FST_DEBUG_ROUTE": "rivalry:f1c749eb07c32578cfa3e59ec38c03a8:closest_battles:song:Solo_Guitar",
        ])
        app.launch()
        XCTAssertTrue(app.buttons["fst.rivalry.view-profile"].waitForExistence(timeout: 15))
        // Ids end in the row's list position, so a reversed menu cannot pass.
        assertMenuOrder(
            app,
            ["fixture-drift", "fixture-pulse", "fixture-orbit", "fixture-echo"].enumerated()
                .map { "\($0.element):Solo_Guitar:\($0.offset)" },
            name: "quick-links-order-rivalry"
        )
    }
}
