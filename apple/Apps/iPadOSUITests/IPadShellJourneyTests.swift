import XCTest

/// iPadOS shell journeys for the universal FestivalMobile app on "FST Native iPad Pro 11"
/// (UI-test bundle `FestivalMobileIPadUITests`): the overlay flyout, the on-demand
/// split (`.agents/design/apple/split-view.md`), live reflow when the window size
/// changes (rotation, tiles) and hardware keyboard shortcuts. Fixture-backed (`tools/mock_service.py` on 127.0.0.1:8765),
/// never production. Run with
/// `python3 tools/ios_sim.py uitest --device ipad --only IPadShellJourneyTests`.
final class IPadShellJourneyTests: XCTestCase {
    /// Launch against the loopback fixture service, optionally with a selected player.
    @MainActor
    private func fixtureApp(profile: Bool) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
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

    /// A landscape grid row holds two cards; tapping the second opens only that song.
    /// A `List` row fired every `NavigationLink` in it, so both songs were pushed and
    /// Back revealed the first song's page instead of Songs.
    @MainActor
    func testSongsGridCardOpensOnlyItsSong() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(orbit.waitForExistence(timeout: 20))
        XCTAssertTrue(pulse.waitForExistence(timeout: 5))
        XCTAssertEqual(orbit.frame.minY, pulse.frame.minY, accuracy: 2, "both cards share one grid row")
        let (second, title) = orbit.frame.minX > pulse.frame.minX
            ? (orbit, "Fixture Orbit") : (pulse, "Fixture Pulse")
        XCTAssertGreaterThan(second.frame.minX, app.windows.firstMatch.frame.midX - 20, "the trailing card")
        second.tap()
        let hero = element(app, "fst.song-detail.hero-title")
        XCTAssertTrue(hero.waitForExistence(timeout: 20), "Song Detail opens")
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "the tapped song's page")
        // One push: a single Back returns to the Songs grid, not to another Song Detail.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(waitForDisappearance(of: hero, timeout: 10), "Back leaves Song Detail")
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertTrue(second.isHittable, "Songs is on top again")
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
        element(app, "fst.split.close").tap()
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "Close returns to full width")
    }

    /// Full Rankings starts full width; a row opens the player in the trailing half and
    /// stays selected; portrait pushes it; landscape lifts it back; Close returns to full
    /// width.
    @MainActor
    func testFullRankingsSplitsOnDemand() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        chooseInFlyout(app, "leaderboards")
        let viewAll = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.view-all'")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15))
        viewAll.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.rankings.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        let trailing = element(app, "fst.split.trailing")
        XCTAssertFalse(trailing.exists, "starts full width: nothing auto-selected")
        let first = rows.element(boundBy: 0)
        first.tap()
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "the player opens in the trailing half")
        XCTAssertTrue(first.waitForSelection(timeout: 5), "the row stays selected")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "portrait pushes")
        let playerTitle = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Fixture Player'")).firstMatch
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 10), "the chosen player stays open, pushed")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(trailing.waitForExistence(timeout: 10), "landscape splits again")
        element(app, "fst.split.close").tap()
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "Close returns to full width")
        XCTAssertTrue(rows.firstMatch.isHittable, "the list is full width again")
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
        viewAll.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.rankings.row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        rows.firstMatch.tap()
        let trailing = element(app, "fst.split.trailing")
        XCTAssertTrue(trailing.waitForExistence(timeout: 10))
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(of: trailing, timeout: 10), "⌘[ closes the open player")
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15), "⌘[ goes back")
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
