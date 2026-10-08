import XCTest

/// iPadOS shell journeys for the universal FestivalMobile app on "FST Native iPad Pro 11"
/// (UI-test bundle `FestivalMobileIPadUITests`): the overlay flyout, the on-demand
/// split (`.agents/design/apple/split-view.md`), live reflow when the window size
/// changes (rotation, tiles) and hardware keyboard shortcuts. Fixture-backed (`tools/mock_service.py` on 127.0.0.1:8765,
/// or the loopback origin in the runner's `FST_FIXTURE_URL`), never production. Run with
/// `python3 tools/ios_sim.py uitest --device ipad --only IPadShellJourneyTests`
/// (`TEST_RUNNER_FST_FIXTURE_URL=http://127.0.0.1:<port>` selects another fixture port).
final class IPadShellJourneyTests: XCTestCase {
    /// The loopback fixture service.
    static let fixtureURL = ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765"

    /// Launch against the loopback fixture service, optionally with a selected player.
    @MainActor
    private func fixtureApp(profile: Bool) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": Self.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if profile {
            env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        }
        return FestivalApp.makeApp(env)
    }

    override func setUpWithError() throws {
        // The universal app also installs on iPhone; these journeys assert the iPad shell.
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad, "iPad-only journeys")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDown() {
        // Never leave a resized window behind: iPadOS remembers it for the next launch.
        MainActor.assumeIsolated {
            let app = FestivalApp.makeApp()
            if app.state == .runningForeground { WindowResize.fill(app) }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// Any element by accessibility identifier.
    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Open the flyout from the toolbar button.
    @MainActor
    private func openFlyout(_ app: XCUIApplication) {
        let button = element(app, "fst.shell.drawer.open")
        XCTAssertTrue(button.waitForExistence(timeout: 20), "the flyout button")
        button.tap()
        XCTAssertTrue(element(app, "fst.shell.drawer").waitForExistence(timeout: 5), "the flyout opens")
    }

    /// Choose a flyout row; the flyout closes.
    @MainActor
    private func chooseInFlyout(_ app: XCUIApplication, _ id: String) {
        openFlyout(app)
        let row = element(app, "fst.shell.drawer.\(id)")
        XCTAssertTrue(row.waitForExistence(timeout: 5), id)
        row.tap()
        XCTAssertTrue(waitForDisappearance(of: element(app, "fst.shell.drawer"), timeout: 5), "the flyout closes")
    }

    // MARK: - Flyout

    /// Regular width: no persistent sidebar and no tab bar; the overlay flyout lists Search
    /// and the web sidebar's destinations (Item Shop included).
    @MainActor
    func testFlyoutListsWebDestinations() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 20))
        XCTAssertFalse(element(app, "fst.nav.sidebar").exists, "no persistent sidebar (operator 2026-10-04)")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "regular width uses the flyout, not tabs")
        openFlyout(app)
        for id in ["search", "songs", "leaderboards", "shop", "settings"] {
            XCTAssertTrue(element(app, "fst.shell.drawer.\(id)").exists, id)
        }
        XCTAssertFalse(element(app, "fst.shell.drawer.suggestions").exists, "profile rows need a player")
    }

    /// Flyout rows switch destinations, including Item Shop and Settings.
    @MainActor
    func testFlyoutSwitchesDestinations() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        chooseInFlyout(app, "shop")
        XCTAssertTrue(app.navigationBars["Item Shop"].waitForExistence(timeout: 15))
        chooseInFlyout(app, "leaderboards")
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        chooseInFlyout(app, "settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
    }

    /// With a player, the flyout adds the profile rows and its footer names the player.
    @MainActor
    func testFlyoutProfileRowsAndFooter() throws {
        let app = fixtureApp(profile: true)
        launchFilled(app)
        openFlyout(app)
        for id in ["suggestions", "statistics", "rivals"] {
            XCTAssertTrue(element(app, "fst.shell.drawer.\(id)").exists, id)
        }
        XCTAssertTrue(element(app, "fst.shell.drawer.view-profile").exists)
        XCTAssertTrue(element(app, "fst.shell.drawer.deselect-profile").exists)
        XCTAssertFalse(element(app, "fst.shell.drawer.compete").exists, "Compete is the phone slot")
    }

    /// The flyout overlays the content (never resizes it) and closes from its Close
    /// button and the scrim; a leading-edge swipe opens it. (Escape, View › Close, is not
    /// deliverable to the app from XCUITest on this simulator: split-view.md.)
    @MainActor
    func testFlyoutOverlaysAndDismisses() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        let list = element(app, "fst.songs.list")
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        let before = list.frame
        openFlyout(app)
        XCTAssertEqual(list.frame, before, "the flyout slides over the content without resizing it")
        element(app, "fst.shell.drawer.close").tap()
        XCTAssertTrue(waitForDisappearance(of: element(app, "fst.shell.drawer"), timeout: 5), "Close closes")
        openFlyout(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(waitForDisappearance(of: element(app, "fst.shell.drawer"), timeout: 5), "the scrim closes")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.002, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)))
        XCTAssertTrue(element(app, "fst.shell.drawer").waitForExistence(timeout: 5), "an edge swipe opens it")
    }

    // MARK: - On-demand split

    /// Songs never splits: landscape shows full-width rows (two per row) and a song
    /// opens full width.
    @MainActor
    func testSongsNeverSplits() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        XCTAssertFalse(element(app, "fst.split.trailing").exists)
        row.tap()
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 20))
        XCTAssertFalse(element(app, "fst.split.trailing").exists, "Song Detail opens full width")
        XCTAssertFalse(element(app, "fst.songs.list").isHittable, "Songs is covered, not beside it")
    }

    /// A landscape grid row holds two cards; tapping either opens only that song.
    /// A `List` row fired every `NavigationLink` in it, so both songs were pushed: the
    /// trailing song covered the tapped leading one, and Back revealed a Song Detail
    /// instead of Songs.
    @MainActor
    func testSongsGridCardOpensOnlyItsSong() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(orbit.waitForExistence(timeout: 20))
        XCTAssertTrue(pulse.waitForExistence(timeout: 5))
        XCTAssertEqual(orbit.frame.minY, pulse.frame.minY, accuracy: 2, "both cards share one grid row")
        let cards = orbit.frame.minX < pulse.frame.minX
            ? [(orbit, "Fixture Orbit", "Fixture Pulse"), (pulse, "Fixture Pulse", "Fixture Orbit")]
            : [(pulse, "Fixture Pulse", "Fixture Orbit"), (orbit, "Fixture Orbit", "Fixture Pulse")]
        let midX = app.windows.firstMatch.frame.midX
        XCTAssertLessThan(cards[0].0.frame.maxX, midX + 20, "the leading card")
        XCTAssertGreaterThan(cards[1].0.frame.minX, midX - 20, "the trailing card")
        for (card, title, neighbour) in cards {
            card.tap()
            let hero = element(app, "fst.song-detail.hero-title")
            XCTAssertTrue(hero.waitForExistence(timeout: 20), "Song Detail opens for \(title)")
            XCTAssertTrue(hero.label.hasPrefix(title), "the tapped song's page on top, not \(hero.label)")
            XCTAssertFalse(hero.label.hasPrefix(neighbour), "the row's other song was not pushed over it")
            // One push: a single Back returns to the Songs grid, not to another Song Detail.
            let back = app.navigationBars.buttons.element(boundBy: 0)
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(waitForDisappearance(of: hero, timeout: 10), "Back from \(title) leaves Song Detail")
            XCTAssertTrue(card.waitForExistence(timeout: 10))
            XCTAssertTrue(card.isHittable, "Songs is on top again after \(title)")
        }
    }

    /// Issue #350 (`wide-columns`): Search results pair into two columns in landscape,
    /// stack in portrait and pair again on rotation without a new search (the
    /// results never leave the screen).
    @MainActor
    func testSearchResultsUseTwoColumnsInLandscapeOnly() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 20))
        chooseInFlyout(app, "search")
        let field = app.searchFields["Search songs, players, or bands"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Fixture")
        let songs = app.buttons.matching(identifier: "fst.global-search.result.song")
        XCTAssertTrue(songs.element(boundBy: 1).waitForExistence(timeout: 15), "two song results")
        func assertPaired(_ paired: Bool, _ message: String) {
            let first = songs.element(boundBy: 0).frame
            let second = songs.element(boundBy: 1).frame
            if paired {
                XCTAssertEqual(first.minY, second.minY, accuracy: 2, "\(message): one row")
                XCTAssertLessThan(min(first.maxX, second.maxX), max(first.minX, second.minX), "\(message): side by side")
            } else {
                XCTAssertGreaterThan(abs(first.minY - second.minY), first.height - 2, "\(message): stacked")
                XCTAssertEqual(first.width, second.width, accuracy: 2, "\(message): full width")
            }
        }
        assertPaired(true, "landscape")
        XCUIDevice.shared.orientation = .portrait
        let stacked = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                abs(songs.element(boundBy: 0).frame.minY - songs.element(boundBy: 1).frame.minY) > 10
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [stacked], timeout: 10), .completed, "portrait reflows")
        XCTAssertFalse(app.activityIndicators.firstMatch.exists, "rotation does not search again")
        assertPaired(false, "portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let paired = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                abs(songs.element(boundBy: 0).frame.minY - songs.element(boundBy: 1).frame.minY) < 2
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [paired], timeout: 10), .completed, "landscape reflows")
        XCTAssertFalse(app.activityIndicators.firstMatch.exists, "rotation does not search again")
        assertPaired(true, "landscape again")
        // The trailing card of a paired List row opens only its own song (architecture
        // "List rows hold one action": each card is its own plain button).
        let pair = [songs.element(boundBy: 0), songs.element(boundBy: 1)]
        let trailing = pair.max { $0.frame.minX < $1.frame.minX }!
        let title = trailing.label.contains("Orbit") ? "Fixture Orbit" : "Fixture Pulse"
        trailing.tap()
        let hero = element(app, "fst.song-detail.hero-title")
        XCTAssertTrue(hero.waitForExistence(timeout: 20), "Song Detail opens")
        XCTAssertTrue(hero.label.hasPrefix(title), "the tapped trailing song, not \(hero.label)")
    }

    /// Song Detail splits on demand: its full leaderboard opens in the trailing half
    /// beside the song page; Close returns to full width.
    @MainActor
    func testSongDetailOpensLeaderboardInTrailingHalf() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let board = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(board.waitForExistence(timeout: 20))
        board.tap()
        let trailing = element(app, "fst.split.trailing")
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "the board opens in the trailing half")
        XCTAssertTrue(element(app, "fst.song-detail.intensity").exists, "the song page stays beside it")
        XCTAssertEqual(trailing.frame.minX, app.windows.firstMatch.frame.midX, accuracy: 2, "split at the midpoint")
        // Beside its song the board is titled by its instrument, never a second song
        // header (owner-approved song-leaderboard-header variant, #342).
        XCTAssertTrue(element(app, "fst.song-leaderboard.board-title").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "fst.song-leaderboard.header").exists, "no repeated song header")
        element(app, "fst.split.close").tap()
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "Close returns to full width")
    }

    /// Song Detail → a band size's "View full leaderboard" opens that band board in the
    /// trailing half beside the song, titled by its band size (issue #367, #342 variant);
    /// Back on Song Detail closes it first and keeps the song (issue #347).
    ///
    /// The band preview routes are newer than the shared `:8765` listener, so this
    /// journey needs a fixture service from this revision:
    ///
    ///     python3 tools/mock_service.py --port 18934
    @MainActor
    func testSongDetailOpensBandLeaderboardInTrailingHalf() throws {
        let origin = "http://127.0.0.1:18934"
        let probe = expectation(description: "band fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: URL(string: "\(origin)/api/leaderboard/fixture-pulse/bands/all")!) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --port 18934` from this revision")
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ])
        launchFilled(app)
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 20))
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        quickLinks.tap()
        let duos = app.buttons["fst.quick-links.item.band-Band_Duets"]
        XCTAssertTrue(duos.waitForExistence(timeout: 10), "Quick Links has no Duos section")
        duos.tap()
        let viewFull = app.buttons["fst.song-detail.band-leaderboard.Band_Duets"]
        XCTAssertTrue(viewFull.waitForExistence(timeout: 15))
        for _ in 0..<4 where !viewFull.isHittable { app.swipeUp() }
        viewFull.tap()
        let trailing = element(app, "fst.split.trailing")
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "the band board opens in the trailing half")
        XCTAssertEqual(trailing.frame.minX, app.windows.firstMatch.frame.midX, accuracy: 2, "split at the midpoint")
        XCTAssertTrue(element(app, "fst.song-detail.intensity").exists, "the song page stays beside it")
        // Beside its song the board is titled by its band size, never a second song header.
        let title = element(app, "fst.song-band-leaderboard.board-title")
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(title.frame.minX, trailing.frame.minX, "the title is in the trailing pane")
        XCTAssertFalse(element(app, "fst.song-band-leaderboard.header").exists, "no repeated song header")
        let back = app.buttons["fst.split.list-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Song Detail's Back closes the open pane")
        back.tap()
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "Back closes the band board")
        XCTAssertTrue(element(app, "fst.song-detail.hero-title").waitForExistence(timeout: 5), "Song Detail stays")
    }

    /// The leading pane's Back: the split's own while the trailing pane is open (issue
    /// #347), else the system Back of the leading pane's bar.
    @MainActor
    private func leadingBack(_ app: XCUIApplication) -> XCUIElement {
        let split = app.buttons["fst.split.list-back"]
        if split.exists { return split }
        let midX = app.windows.firstMatch.frame.midX
        let buttons = app.navigationBars.buttons.allElementsBoundByIndex.filter { $0.frame.maxX < midX }
        return buttons.min { $0.frame.minX < $1.frame.minX } ?? app.navigationBars.buttons.firstMatch
    }

    /// Back on Song Detail beside its open leaderboard closes the leaderboard and keeps
    /// Song Detail; a second Back returns to Songs (issue #347).
    @MainActor
    func testBackClosesSongDetailTrailingPaneFirst() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        let board = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(board.waitForExistence(timeout: 20))
        board.tap()
        let trailing = element(app, "fst.split.trailing")
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "the board opens in the trailing half")
        let back = app.buttons["fst.split.list-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Song Detail's Back closes the open pane")
        back.tap()
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "Back closes the leaderboard")
        let hero = element(app, "fst.song-detail.hero-title")
        XCTAssertTrue(hero.waitForExistence(timeout: 5), "Song Detail stays")
        XCTAssertFalse(app.buttons["fst.songs.row.fixture-pulse"].isHittable, "Songs is still covered")
        let secondBack = leadingBack(app)
        XCTAssertTrue(secondBack.waitForExistence(timeout: 5))
        secondBack.tap()
        XCTAssertTrue(waitForDisappearance(of: hero, timeout: 10), "a second Back leaves Song Detail")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.isHittable, "a second Back returns to Songs")
    }

    /// View All Rankings opens Full Rankings in the trailing half beside the overview and
    /// stays selected; portrait pushes it and landscape lifts it back. A player opened
    /// from it is a full page over both halves; Back returns to the split with the board
    /// and its selection kept; Close returns to the full-width overview (issue #352).
    @MainActor
    func testFullRankingsOpensBesideLeaderboards() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        chooseInFlyout(app, "leaderboards")
        let viewAll = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.view-all'")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15))
        let trailing = element(app, "fst.split.trailing")
        XCTAssertFalse(trailing.exists, "starts full width: nothing auto-selected")
        viewAll.tap()
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "Full Rankings opens in the trailing half")
        XCTAssertTrue(viewAll.waitForSelection(timeout: 5), "View All Rankings stays selected")
        XCTAssertTrue(viewAll.isHittable, "the overview stays beside it")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "portrait pushes")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "landscape splits again")

        let midX = app.windows.firstMatch.frame.midX
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.rankings.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        let boardRow = try XCTUnwrap(
            rows.allElementsBoundByIndex.first { $0.frame.minX > midX && $0.isHittable },
            "a Full Rankings row in the trailing half"
        )
        boardRow.tap()
        let playerTitle = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Fixture'")).firstMatch
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 10), "the player opens")
        XCTAssertFalse(viewAll.isHittable, "the profile is a full page over the overview")
        XCTAssertLessThan(trailing.frame.minX, midX - 100, "the profile covers both halves")
        let back = app.navigationBars.buttons.allElementsBoundByIndex.min { $0.frame.minX < $1.frame.minX }
        try XCTUnwrap(back, "the profile's Back").tap()
        XCTAssertTrue(viewAll.waitForSelection(timeout: 10), "Back returns to the split, selection kept")
        XCTAssertTrue(viewAll.isHittable, "the overview is beside the board again")
        XCTAssertEqual(trailing.frame.minX, midX, accuracy: 30, "Full Rankings is back in the trailing half")
        element(app, "fst.split.close").tap()
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "Close returns to full width")
        XCTAssertTrue(viewAll.isHittable, "the overview is full width again")
    }

    /// A player row on the Leaderboards overview pushes the full profile page (no
    /// trailing pane, in either orientation); Back returns to the overview with its
    /// place kept (issue #352).
    @MainActor
    func testLeaderboardsPlayerOpensFullPage() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        chooseInFlyout(app, "leaderboards")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.rankings.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        let viewAll = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.view-all'")).firstMatch
        let row = rows.element(boundBy: 0)
        row.tap()
        let playerTitle = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Fixture'")).firstMatch
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 10), "the player opens")
        let trailing = element(app, "fst.split.trailing")
        XCTAssertFalse(trailing.exists, "a profile is a full page, not a trailing pane")
        XCTAssertFalse(viewAll.isHittable, "the profile covers the overview")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 10), "portrait keeps the profile")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 10), "landscape keeps the profile full width")
        XCTAssertFalse(trailing.exists, "landscape does not lift the profile into a pane")
        leadingBack(app).tap()
        XCTAssertTrue(waitForDisappearance(of: playerTitle, timeout: 10), "Back leaves the profile")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Leaderboards is back")
        XCTAssertTrue(row.isHittable, "the overview is on top, full width")
        XCTAssertFalse(trailing.exists, "nothing is left open")
    }

    // MARK: - Compete (issue #369)

    /// Launch with a player on Compete. The regular-width shell lists Leaderboards and
    /// Rivals instead of Compete (`FestivalTabPolicy`), so the route pushes Compete on
    /// Songs, as a link from another page does; a compact window shows it as a tab.
    @MainActor
    private func launchCompete() -> XCUIApplication {
        let app = fixtureApp(profile: true)
        app.launchEnvironment["FST_DEBUG_ROUTE"] = "compete"
        launchFilled(app)
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 20), "Compete opens")
        return app
    }

    /// Compete's rival rows (one per instrument card a rival appears on).
    @MainActor
    private func competeRivalRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.rivals.row.'"))
    }

    /// The first rival row on screen, by its index among Compete's rival rows (one rival
    /// can be listed on several cards, so its identifier alone is not one row). A single
    /// column lists Rivals below Leaderboards, so it scrolls until one is on screen.
    @MainActor
    private func firstHittableRivalRow(_ app: XCUIApplication) throws -> XCUIElement {
        let rows = competeRivalRows(app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20), "Compete lists rivals")
        for _ in 0..<8 where !rows.allElementsBoundByIndex.contains(where: \.isHittable) {
            app.swipeUp()
        }
        let all = rows.allElementsBoundByIndex
        let index = try XCTUnwrap(all.firstIndex { $0.isHittable }, "an on-screen rival row")
        return rows.element(boundBy: index)
    }

    /// The trailing pane's own Back: the leftmost navigation bar button inside the pane.
    @MainActor
    private func trailingBack(_ app: XCUIApplication, pane: CGRect) -> XCUIElement? {
        app.navigationBars.buttons.allElementsBoundByIndex
            .filter { $0.frame.minX >= pane.minX - 1 && $0.frame.maxX <= pane.midX && $0.identifier != "fst.split.close" }
            .min { $0.frame.minX < $1.frame.minX }
    }

    /// A full-width page's Back: the leftmost on-screen navigation bar button.
    @MainActor
    private func fullPageBack(_ app: XCUIApplication) -> XCUIElement? {
        app.navigationBars.buttons.allElementsBoundByIndex.filter(\.isHittable).min { $0.frame.minX < $1.frame.minX }
    }

    /// A Rival Detail category's View All (it pushes that category's Rivalry page).
    @MainActor
    private func rivalCategoryViewAll(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'fst.rival-detail.category.' AND identifier ENDSWITH '.view-all'"
        )).firstMatch
    }

    /// Landscape: a rival row on Compete opens Rival Detail in the trailing half beside
    /// Compete, with Close on the pane's root and the row selected; a category's View
    /// All pushes Rivalry inside the pane with Back (no Close), and that Back returns to
    /// Rival Detail with Close. Portrait pushes the open rival and landscape lifts it
    /// back. Compete's own Back closes the pane first and keeps Compete in place; a
    /// second Back leaves Compete (issue #369, back-keeps-place R6, split-panes).
    @MainActor
    func testCompeteRivalOpensBesideCompete() throws {
        let app = launchCompete()
        let trailing = element(app, "fst.split.trailing")
        let row = try firstHittableRivalRow(app)
        let rowID = row.identifier
        let before = row.frame
        XCTAssertFalse(trailing.exists, "Compete starts full width")
        row.tap()

        // Rival Detail beside Compete; its root has Close, not Back.
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "the rival opens in the trailing half")
        let midX = app.windows.firstMatch.frame.midX
        XCTAssertEqual(trailing.frame.minX, midX, accuracy: 30, "split at the midpoint")
        XCTAssertTrue(element(app, "fst.rival-detail.view-profile").waitForExistence(timeout: 15), "Rival Detail loads")
        XCTAssertTrue(app.navigationBars["Compete"].exists, "Compete stays beside it")
        let selected = competeRivalRows(app).matching(NSPredicate(format: "isSelected == true"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 5), "the opened rival's row is selected")
        XCTAssertTrue(selected.allElementsBoundByIndex.allSatisfy { $0.identifier == rowID }, "only the opened rival is selected")
        let close = element(app, "fst.split.close")
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the pane's root has Close")
        XCTAssertGreaterThanOrEqual(close.frame.minX, trailing.frame.minX - 1, "Close sits in the trailing pane")
        XCTAssertNil(trailingBack(app, pane: trailing.frame), "the pane's root has no Back")
        let listBack = app.buttons["fst.split.list-back"]
        XCTAssertTrue(listBack.waitForExistence(timeout: 5), "Compete's Back closes the pane first")
        XCTAssertLessThan(listBack.frame.maxX, midX, "Compete's Back sits in the leading pane")

        // A sub-page pushes inside the pane, with Back instead of Close.
        let viewAll = rivalCategoryViewAll(app)
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15), "a Rival Detail category has View All")
        viewAll.tap()
        XCTAssertTrue(app.buttons["fst.rivalry.view-profile"].waitForExistence(timeout: 15), "Rivalry opens")
        XCTAssertEqual(trailing.frame.minX, midX, accuracy: 30, "Rivalry stays in the trailing half")
        XCTAssertTrue(app.navigationBars["Compete"].exists, "Compete stays beside Rivalry")
        XCTAssertTrue(waitForDisappearance(of: close, timeout: 5), "a pushed pane page has no Close")
        let paneBack = try XCTUnwrap(trailingBack(app, pane: trailing.frame), "the pushed page's Back in the pane")
        paneBack.tap()
        XCTAssertTrue(waitForDisappearance(of: app.buttons["fst.rivalry.view-profile"], timeout: 10), "Back leaves Rivalry")
        XCTAssertTrue(element(app, "fst.rival-detail.view-profile").waitForExistence(timeout: 10), "back on Rival Detail")
        XCTAssertTrue(trailing.exists, "still in the trailing pane")
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the pane's root has Close again")

        // Portrait pushes the open rival full width; landscape lifts it back beside Compete.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "portrait pushes")
        XCTAssertTrue(element(app, "fst.rival-detail.view-profile").waitForExistence(timeout: 10), "the rival stays open")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "landscape splits again")
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 5), "beside Compete")

        // Compete's Back closes the pane first; Compete keeps its place.
        XCTAssertTrue(listBack.waitForExistence(timeout: 5))
        listBack.tap()
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "Back closes the rival")
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 5), "Compete stays")
        XCTAssertTrue(row.waitForExistence(timeout: 5) && row.isHittable, "the opened row is on screen again")
        XCTAssertEqual(row.frame.minY, before.minY, accuracy: 2, "Compete kept its scroll position")
        XCTAssertFalse(row.isSelected, "nothing is selected once closed")
        let back = leadingBack(app)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(waitForDisappearance(of: app.navigationBars["Compete"], timeout: 10), "a second Back leaves Compete")
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 10), "back on Songs")
    }

    /// Where the split does not apply, a Compete rival row pushes Rival Detail full width
    /// with the system Back (no Close) and its sub-pages push on the same stack: iPad
    /// portrait, and a compact (½) window with the phone tab bar, where Compete is a tab
    /// as on iPhone and the folded Duo (issue #369).
    @MainActor
    func testCompeteRivalPushesFullPageWithoutSplit() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launchCompete()
        try assertCompeteRivalPushes(app, window: "portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        guard WindowResize.tile(app, .left) else {
            throw XCTSkip("window-controls tiling menu unavailable (full-screen multitasking mode)")
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "a ½ window is compact")
        let competeTab = app.tabBars.buttons["Compete"]
        XCTAssertTrue(competeTab.waitForExistence(timeout: 5), "Compete is a phone tab")
        competeTab.tap()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 15), "the Compete tab opens")
        try assertCompeteRivalPushes(app, window: "compact")
    }

    /// Tap a Compete rival row and require full-width pushes down to Rivalry and back.
    ///
    /// - Parameters:
    ///   - app: The app on Compete.
    ///   - window: The window, for failure messages.
    @MainActor
    private func assertCompeteRivalPushes(_ app: XCUIApplication, window: String) throws {
        let row = try firstHittableRivalRow(app)
        row.tap()
        XCTAssertTrue(element(app, "fst.rival-detail.view-profile").waitForExistence(timeout: 15), "\(window): Rival Detail opens")
        XCTAssertFalse(element(app, "fst.split.trailing").exists, "\(window): no trailing pane")
        XCTAssertFalse(element(app, "fst.split.close").exists, "\(window): a pushed page has Back, not Close")
        XCTAssertFalse(app.navigationBars["Compete"].exists, "\(window): Rival Detail covers Compete")
        let viewAll = rivalCategoryViewAll(app)
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15), "\(window): a category has View All")
        viewAll.tap()
        XCTAssertTrue(app.buttons["fst.rivalry.view-profile"].waitForExistence(timeout: 15), "\(window): Rivalry opens")
        XCTAssertFalse(element(app, "fst.split.trailing").exists, "\(window): Rivalry is full width")
        try XCTUnwrap(fullPageBack(app), "\(window): Rivalry's Back").tap()
        XCTAssertTrue(element(app, "fst.rival-detail.view-profile").waitForExistence(timeout: 10), "\(window): Back to Rival Detail")
        try XCTUnwrap(fullPageBack(app), "\(window): Rival Detail's Back").tap()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 10), "\(window): Back to Compete")
        XCTAssertTrue(row.waitForExistence(timeout: 5) && row.isHittable, "\(window): Compete is on top with the row")
    }

    /// Narrowing the window (an exact ½ or ⅓ tile) falls back to the phone tab bar and
    /// drawer, keeping the section; filling the screen returns to the flyout shell.
    @MainActor
    func testNarrowWindowFallsBackToTabs() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 20))
        guard WindowResize.tile(app, .left) else {
            throw XCTSkip("window-controls tiling menu unavailable (full-screen multitasking mode)")
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "a ½ window is compact")
        XCTAssertTrue(app.tabBars.buttons["Songs"].exists, "the selected section survives")
        XCTAssertTrue(WindowResize.tile(app, .thirds))
        XCTAssertTrue(app.tabBars.firstMatch.exists, "a ⅓ window is compact")
        XCTAssertTrue(WindowResize.fill(app), "window fills the screen again")
        XCTAssertTrue(waitForDisappearance(of: app.tabBars.firstMatch, timeout: 10), "regular width again")
    }

    // MARK: - Keyboard

    /// ⌘2 selects the second destination and ⌘1 returns to Songs.
    @MainActor
    func testCommandDigitSelectsDestination() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 20))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Item Shop"].waitForExistence(timeout: 15))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 15))
    }

    /// The iPadOS menu bar's shortcuts: ⌘K opens Search, ⇧⌘P profile selection, ⌘5 leaves
    /// Search for Leaderboards, ⌘[ closes the open player and then leaves Full Rankings.
    @MainActor
    func testMenuBarShortcuts() throws {
        let app = fixtureApp(profile: true)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 20))
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 10), "⌘K opens Search")
        app.typeKey("p", modifierFlags: [.shift, .command])
        let scope = element(app, "fst.profile.scope")
        XCTAssertTrue(scope.waitForExistence(timeout: 10), "⇧⌘P opens profile selection")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        if !waitForDisappearance(of: scope, timeout: 5) {
            app.swipeDown(velocity: .fast)
            XCTAssertTrue(waitForDisappearance(of: scope, timeout: 10))
        }
        app.typeKey("5", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15), "⌘5 is Leaderboards")
        XCTAssertFalse(app.navigationBars["Search"].exists, "⌘5 leaves Search")
        let viewAll = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.view-all'")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15))
        // The tapped card's own View All (a profile page may have other View All rows).
        let cardViewAll = element(app, viewAll.identifier)
        viewAll.tap()
        // View All opens Full Rankings beside the overview; its player opens full page
        // over both (issue #352).
        let trailing = element(app, "fst.split.trailing")
        XCTAssertTrue(trailing.waitForExistence(timeout: 10))
        let rows = trailing.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.rankings.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        rows.firstMatch.tap()
        let playerTitle = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Fixture'")).firstMatch
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 10), "the player opens")
        XCTAssertFalse(cardViewAll.isHittable, "the player covers the overview")
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(of: playerTitle, timeout: 10), "⌘[ leaves the player")
        XCTAssertTrue(cardViewAll.isHittable, "⌘[ returns to the overview beside Full Rankings")
        XCTAssertTrue(trailing.exists, "Full Rankings is still beside the overview")
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "⌘[ closes Full Rankings")
        XCTAssertTrue(app.navigationBars["Leaderboards"].exists, "⌘[ returns to Leaderboards")
    }

    // MARK: - Windows

    /// A Songs row's context menu opens the song in a second window; windows share one
    /// session, so a profile deselected in the first is not selected in the new one.
    @MainActor
    func testOpenInNewWindowSharesProfile() throws {
        let app = fixtureApp(profile: true)
        launchFilled(app)
        openFlyout(app)
        let deselect = element(app, "fst.shell.drawer.deselect-profile")
        XCTAssertTrue(deselect.waitForExistence(timeout: 5))
        deselect.tap()
        // The dialog's button, not the flyout's own "Deselect Profile" button.
        let confirm = app.buttons.matching(NSPredicate(
            format: "label == 'Deselect Profile' AND identifier != 'fst.shell.drawer.deselect-profile'"
        )).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation")
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(of: element(app, "fst.shell.drawer"), timeout: 5), "the flyout closes")
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.press(forDuration: 1.2)
        // Landscape grid rows carry one menu naming each card ("Open “Fixture Pulse” in
        // New Window"); a single-card row reads "Open in New Window".
        let open = app.buttons.matching(NSPredicate(
            format: "label == 'Open in New Window' OR (label CONTAINS 'New Window' AND label CONTAINS 'Fixture Pulse')"
        )).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "the row offers Open in New Window")
        let cards = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'card:com.sfenton.festivalscoretracker.native:sceneID:'"))
        let first = cards.firstMatch.identifier
        open.tap()
        let newScene = cards.matching(NSPredicate(format: "identifier != %@", first)).firstMatch
        XCTAssertTrue(newScene.waitForExistence(timeout: 15), "a second window opens")
        // iPadOS reconnects every open window at the next launch: never leave this one
        // behind, even when an assertion below fails (it broke the later journeys).
        var secondWindowOpen = true
        addTeardownBlock { @MainActor in
            if secondWindowOpen { _ = WindowResize.closeFrontWindow(app) }
        }
        XCTAssertTrue(app.navigationBars["Fixture Pulse"].waitForExistence(timeout: 20), "it shows the song")
        // The song is pushed (no flyout button on it): back to the Songs root first.
        app.typeKey("[", modifierFlags: .command)
        openFlyout(app)
        XCTAssertFalse(element(app, "fst.shell.drawer.suggestions").exists, "no player in the new window: shared session")
        element(app, "fst.shell.drawer.close").tap()
        XCTAssertTrue(WindowResize.closeFrontWindow(app), "close the second window")
        secondWindowOpen = false
    }

    // MARK: - Helpers

    /// Launch and make the window fill the screen (iPadOS remembers resized windows).
    @MainActor
    private func launchFilled(_ app: XCUIApplication) {
        app.launch()
        WindowResize.fill(app)
    }

    /// Wait until an element no longer exists.
    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }
}

extension XCUIElement {
    /// Wait until the element reports the selected state.
    @MainActor
    func waitForSelection(timeout: TimeInterval) -> Bool {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: self)
        return XCTWaiter().wait(for: [selected], timeout: timeout) == .completed
    }
}
