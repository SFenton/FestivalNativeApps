import XCTest

// MARK: - PlayerProfileLinksJourneyTests

/// Player-page push stability and stat-tile links (Lane AP3) against the loopback
/// fixture (`tools/mock_service.py` on `127.0.0.1:8765`).
///
/// Fixture facts used: the catalogue has `fixture-pulse` and `fixture-orbit`;
/// `fixture-player-2` has Lead full combos on both and one non-FC Drums score on
/// `fixture-pulse` (so Drums Songs Played filters Songs down to that one row).
final class PlayerProfileLinksJourneyTests: XCTestCase {
    // MARK: Launch

    /// Anonymous fixture app on the Leaderboards tab.
    @MainActor
    private func anonymousApp() -> XCUIApplication {
        FestivalApp.launch([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "leaderboards",
        ])
    }

    /// Fixture app with `fixture-player-2` selected, on the Statistics tab.
    @MainActor
    private func selectedApp() -> XCUIApplication {
        FestivalApp.launch([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_DEBUG_PROFILE": "fixture-player-2:Fixture Player 2",
            "FST_DEBUG_TAB": "statistics",
        ])
    }

    // MARK: Helpers

    /// Element by accessibility identifier, of any type.
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Push a player page from the Lead card of the Leaderboards overview.
    @MainActor
    private func pushPlayer(_ accountId: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let card = element("fst.leaderboards.card.Solo_Guitar", in: app)
        let row = card.buttons["fst.rankings.row.\(accountId)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
    }

    /// Scroll the page in short, momentum-free drags until a tile sits clear of the
    /// navigation and tab bars, then tap it (fast swipes overshoot a whole card).
    @MainActor
    private func tapTile(_ identifier: String, in app: XCUIApplication) {
        let tile = element(identifier, in: app)
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "\(identifier) never appeared")
        let window = app.windows.firstMatch.frame
        func clear() -> Bool {
            tile.isHittable && tile.frame.minY > window.minY + 140 && tile.frame.maxY < window.maxY - 140
        }
        var attempts = 0
        while !clear() && attempts < 20 {
            let below = tile.frame.midY > window.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.7 : 0.4))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.45 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            attempts += 1
        }
        XCTAssertTrue(clear(), "\(identifier) never scrolled into view: \(tile.frame)")
        tile.tap()
    }

    // MARK: Push stability

    /// The push lands on a page whose toolbar and tiles do not move once shown: the
    /// identity button is in the bar from the start, and the late global-rank and
    /// rank-history reads fill reserved space instead of growing cards.
    @MainActor
    func testPushToProfileKeepsFramesStableAfterSettle() throws {
        continueAfterFailure = false
        let app = anonymousApp()
        pushPlayer("fixture-player-1", in: app)

        let select = app.buttons["fst.player.select"]
        let pending = app.buttons["fst.player.select.pending"]
        XCTAssertTrue(
            select.waitForExistence(timeout: 5) || pending.exists,
            "The identity button was not in the toolbar during the push"
        )

        let watched = [
            "fst.player.stat.overview.songs-played",
            "fst.player.stat.Solo_Guitar.songs-played",
            "fst.player.stat.Solo_Guitar.global-rank",
            "fst.player.stat.Solo_Guitar.percentile",
        ]
        for identifier in watched {
            XCTAssertTrue(element(identifier, in: app).waitForExistence(timeout: 15), "\(identifier) missing")
        }
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        // Past the staggered fade-ins (≤ ~0.8 s for these sections).
        Thread.sleep(forTimeInterval: 1.5)
        let settled = watched.map { element($0, in: app).frame } + [select.frame]
        Thread.sleep(forTimeInterval: 2.5)
        let later = watched.map { element($0, in: app).frame } + [select.frame]
        XCTAssertEqual(settled, later, "Player page elements moved after settling")
        XCTAssertTrue(select.isEnabled)
    }

    // MARK: Viewed player: select first

    /// A viewed (unselected) player's Songs tile selects that player first (web
    /// `withProfileSwitch`), then shows Songs filtered to the chart.
    @MainActor
    func testViewedPlayerSongsTileSelectsThenFiltersSongs() throws {
        continueAfterFailure = false
        let app = anonymousApp()
        pushPlayer("fixture-player-2", in: app)
        XCTAssertTrue(app.buttons["fst.player.select"].waitForExistence(timeout: 15))

        tapTile("fst.player.stat.Solo_Drums.songs-played", in: app)
        XCTAssertTrue(element("fst.songs.row.fixture-pulse", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(element("fst.songs.row.fixture-orbit", in: app).exists, "Drums filter kept an unplayed song")
        XCTAssertTrue(
            SongsUITestSupport.rootControl("Statistics", app: app).waitForExistence(timeout: 10),
            "The viewed player was not selected before filtering"
        )
    }

    // MARK: Selected player: every link

    /// On the selected player's Statistics page each linked tile lands on its target:
    /// Full Combos → Songs, Lead Global Rank → Lead Rankings, Drums Best Rank → Song
    /// Detail. Plain tiles are not buttons.
    @MainActor
    func testSelectedPlayerStatLinksReachTheirPages() throws {
        continueAfterFailure = false
        let app = selectedApp()
        let statistics = SongsUITestSupport.rootControl("Statistics", app: app)

        let goldStars = element("fst.player.stat.overview.gold-stars", in: app)
        XCTAssertTrue(goldStars.waitForExistence(timeout: 20))
        XCTAssertNotEqual(goldStars.elementType, .button, "Gold Stars has no web link")

        tapTile("fst.player.stat.overview.full-combos", in: app)
        XCTAssertTrue(element("fst.songs.row.fixture-pulse", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("fst.songs.row.fixture-orbit", in: app).exists)

        statistics.tap()
        tapTile("fst.player.stat.Solo_Guitar.global-rank", in: app)
        XCTAssertTrue(app.navigationBars["Lead Rankings"].waitForExistence(timeout: 15))

        statistics.tap()
        tapTile("fst.player.stat.Solo_Drums.best-rank", in: app)
        XCTAssertTrue(element("fst.song-detail.intensity", in: app).waitForExistence(timeout: 15))
    }

    // MARK: Percentile table

    /// A percentile table row opens Songs filtered to that band (web
    /// `instPercentileBucketUpdater`); the row is a button with the band's identifier.
    @MainActor
    func testPercentileRowOpensSongsFilteredToItsBand() throws {
        continueAfterFailure = false
        let app = selectedApp()
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fst.player.percentile-row.Solo_Guitar.")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "No Lead percentile row")
        tapTile(row.identifier, in: app)
        let songRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row.")).firstMatch
        XCTAssertTrue(songRow.waitForExistence(timeout: 15), "Songs did not open filtered")
        XCTAssertTrue(SongsUITestSupport.rootControl("Songs", app: app).isSelected, "Songs is not the selected tab")
    }
}
