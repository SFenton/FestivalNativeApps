import XCTest

/// iPadOS shell journeys for the universal FestivalMobile app on "FST Native iPad Pro 11"
/// (UI-test bundle `FestivalMobileIPadUITests`): the sections sidebar, three-pane
/// list/detail, live reflow when the window size changes (rotation) and hardware
/// keyboard shortcuts. Fixture-backed (`tools/mock_service.py` on 127.0.0.1:8765),
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

    // MARK: - Sidebar

    /// Regular width shows the web sidebar's destinations (Item Shop included) and no tab bar.
    @MainActor
    func testSidebarListsWebDestinations() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.nav.sidebar").waitForExistence(timeout: 20))
        for id in ["fst.nav.songs", "fst.nav.leaderboards", "fst.nav.shop", "fst.nav.settings"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 5), id)
        }
        XCTAssertFalse(element(app, "fst.nav.suggestions").exists, "profile rows need a player")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "regular width uses the sidebar, not tabs")
    }

    /// Sidebar rows switch destinations, including the sidebar-only Item Shop and the
    /// footer Settings row.
    @MainActor
    func testSidebarSwitchesDestinations() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.nav.shop").waitForExistence(timeout: 20))
        element(app, "fst.nav.shop").tap()
        XCTAssertTrue(app.navigationBars["Item Shop"].waitForExistence(timeout: 15))
        element(app, "fst.nav.leaderboards").tap()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        element(app, "fst.nav.settings").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
    }

    /// With a player, the sidebar adds the profile rows and its footer names the player.
    @MainActor
    func testSidebarProfileRowsAndFooter() throws {
        let app = fixtureApp(profile: true)
        launchFilled(app)
        for id in ["fst.nav.suggestions", "fst.nav.statistics", "fst.nav.rivals"] {
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 20), id)
        }
        XCTAssertTrue(element(app, "fst.profile.sidebar").exists)
        XCTAssertTrue(element(app, "fst.nav.sidebar.deselect-profile").exists)
        XCTAssertFalse(element(app, "fst.nav.compete").exists, "Compete is the phone slot")
    }

    // MARK: - List/detail

    /// Landscape Songs shows list and detail side by side with the detail populated
    /// (auto-selected), never an empty "Select a Song" pane.
    @MainActor
    func testSongsShowsTwoPopulatedColumns() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.nav.list-detail").waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Select a Song"].exists)
        // Row identifiers survive inside the split (a container identifier must not
        // replace them).
        let split = element(app, "fst.nav.list-detail")
        let row = split.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'fst.songs.row.'")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "a Songs row is findable inside the split")
        XCTAssertTrue(split.descendants(matching: .any)["fst.songs.list"].exists)
    }

    /// Rotating changes the window size: portrait keeps one stack showing the list
    /// (the auto-selected detail nobody chose is not left pushed), landscape splits
    /// again and restores the same selection.
    @MainActor
    func testRotationReflowsListDetail() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 20))
        XCUIDevice.shared.orientation = .portrait
        let split = element(app, "fst.nav.list-detail")
        XCTAssertTrue(waitForDisappearance(of: split, timeout: 10), "portrait keeps one stack")
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 10), "the list shows")
        XCTAssertFalse(element(app, "fst.song-detail.intensity").exists, "no unchosen detail pushed")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(split.waitForExistence(timeout: 10), "landscape splits again")
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 10))
    }

    /// Leaderboards › View All opens Full Rankings as a list beside a populated player
    /// detail (three columns in landscape).
    @MainActor
    func testFullRankingsSplitsWithPlayerDetail() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.nav.leaderboards").waitForExistence(timeout: 20))
        element(app, "fst.nav.leaderboards").tap()
        let viewAll = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.view-all'")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15))
        viewAll.tap()
        XCTAssertTrue(element(app, "fst.nav.list-detail").waitForExistence(timeout: 15), "rankings split")
        XCTAssertFalse(app.staticTexts["Select a Player"].exists)
        // The player column shows the auto-selected top player's page.
        let playerTitle = app.navigationBars.matching(
            NSPredicate(format: "identifier CONTAINS 'Fixture Player'")
        ).firstMatch
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 15), "a player page fills the detail")
    }

    /// A row the person picked stays open as the pushed page when portrait collapses
    /// the split.
    @MainActor
    func testChosenDetailSurvivesRotation() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 20))
        // The fixture catalogue's second song (the first is auto-selected).
        let second = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        second.tap()
        XCTAssertTrue(second.waitForSelection(timeout: 5), "the tapped row is selected")
        let title = "Fixture Pulse"
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForDisappearance(of: element(app, "fst.nav.list-detail"), timeout: 10))
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 10),
                      "the chosen song (\(title)) stays pushed")
    }

    /// Narrowing the window (a Split View ⅓ or narrow window) falls back to the phone
    /// tab bar and drawer, keeping the section; widening brings the sidebar back.
    @MainActor
    func testNarrowWindowFallsBackToTabs() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.nav.sidebar").waitForExistence(timeout: 20))
        guard WindowResize.resize(app, toScreenFraction: 0.33) else {
            throw XCTSkip("window not resizable (full-screen multitasking mode)")
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "compact width uses tabs")
        XCTAssertFalse(element(app, "fst.nav.sidebar").exists)
        XCTAssertTrue(app.tabBars.buttons["Songs"].exists, "the selected section survives")
        XCTAssertTrue(WindowResize.fill(app), "window fills the screen again")
        XCTAssertTrue(element(app, "fst.nav.sidebar").waitForExistence(timeout: 10), "regular width again")
    }

    /// Exact Split View tiles from the window-controls menu: a landscape ½ (600 pt) and
    /// ⅓ (≈ 397 pt) window are compact, so the phone tabs show. The detail the
    /// three-column split auto-selected is not left pushed over the Songs list in the
    /// tab shell, even when another section was in front as the window narrowed (the
    /// Songs stack was not on screen to pop it; reproduced on master), and filling the
    /// screen splits again with a populated detail.
    @MainActor
    func testExactTilesDropUnchosenDetail() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 20))
        element(app, "fst.nav.leaderboards").tap()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let screen = WindowResize.currentScreenWidth
        guard WindowResize.tile(app, .left) else {
            throw XCTSkip("window-controls tiling menu unavailable (full-screen multitasking mode)")
        }
        XCTAssertEqual(WindowResize.windowWidth(app), screen / 2, accuracy: 12, "exact half (minus the gap)")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "a ½ window is compact")
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 10), "the list shows")
        XCTAssertFalse(element(app, "fst.song-detail.intensity").exists, "no unchosen detail pushed")
        XCTAssertTrue(WindowResize.tile(app, .thirds))
        XCTAssertEqual(WindowResize.windowWidth(app), screen / 3, accuracy: 12, "exact third")
        XCTAssertTrue(app.tabBars.firstMatch.exists, "a ⅓ window is compact")
        XCTAssertTrue(WindowResize.fill(app), "window fills the screen again")
        XCTAssertTrue(element(app, "fst.nav.list-detail").waitForExistence(timeout: 10), "splits again")
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 15), "detail populated")
    }

    /// A row the person picked survives the compact tab shell (it stays pushed), then
    /// returns to the detail column.
    @MainActor
    func testChosenDetailSurvivesCompactTile() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 20))
        let second = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        second.tap()
        XCTAssertTrue(second.waitForSelection(timeout: 5))
        guard WindowResize.tile(app, .left) else {
            throw XCTSkip("window-controls tiling menu unavailable (full-screen multitasking mode)")
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 10), "picked song stays")
        XCTAssertTrue(WindowResize.fill(app))
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForSelection(timeout: 10), "still selected")
    }

    // MARK: - Keyboard

    /// ⌘2 selects the second sidebar destination and ⌘1 returns to Songs.
    @MainActor
    func testCommandDigitSelectsDestination() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.nav.sidebar").waitForExistence(timeout: 20))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Item Shop"].waitForExistence(timeout: 15))
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(element(app, "fst.nav.list-detail").waitForExistence(timeout: 15))
    }

    /// The iPadOS menu bar's shortcuts reach the window in front: ⌘K opens search,
    /// ⇧⌘P profile selection, ⌘5 Leaderboards (sidebar order with a player), ⌘[ goes
    /// back from Full Rankings, ⌘R refreshes without leaving the page.
    @MainActor
    func testMenuBarShortcuts() throws {
        let app = fixtureApp(profile: true)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.nav.sidebar").waitForExistence(timeout: 20))
        app.typeKey("k", modifierFlags: .command)
        let field = app.textFields["fst.global-search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "⌘K opens search")
        app.buttons["fst.global-search.close"].tap()
        XCTAssertTrue(waitForDisappearance(of: field, timeout: 10))
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
        let viewAll = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.view-all'")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15))
        viewAll.tap()
        XCTAssertTrue(element(app, "fst.nav.list-detail").waitForExistence(timeout: 15))
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(element(app, "fst.nav.list-detail").exists, "⌘R stays on the page")
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15), "⌘[ goes back")
    }

    // MARK: - Windows

    /// A Songs row's context menu opens the song in a second window (HIG Windows: "Consider
    /// offering a context-menu ... command to view content in a new window"). Windows share
    /// one session: a profile deselected in the first window is not selected in the new
    /// one (a separate session would re-read the debug profile and show it).
    @MainActor
    func testOpenInNewWindowSharesProfile() throws {
        let app = fixtureApp(profile: true)
        launchFilled(app)
        let deselect = element(app, "fst.nav.sidebar.deselect-profile")
        XCTAssertTrue(deselect.waitForExistence(timeout: 20))
        deselect.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Deselect Profile'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation")
        confirm.tap()
        XCTAssertTrue(waitForDisappearance(of: element(app, "fst.nav.suggestions"), timeout: 10))
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.press(forDuration: 1.2)
        let open = app.buttons["Open in New Window"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "the row offers Open in New Window")
        let cards = XCUIApplication(bundleIdentifier: "com.apple.springboard").descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'card:com.sfenton.festivalscoretracker.native:sceneID:'"))
        let first = cards.firstMatch.identifier
        open.tap()
        // A full-width window: the new scene takes the screen (the first goes behind it).
        let newScene = cards.matching(NSPredicate(format: "identifier != %@", first)).firstMatch
        XCTAssertTrue(newScene.waitForExistence(timeout: 15), "a second window opens")
        XCTAssertTrue(app.navigationBars["Fixture Pulse"].waitForExistence(timeout: 20), "it shows the song")
        XCTAssertTrue(element(app, "fst.nav.sidebar").exists)
        XCTAssertFalse(element(app, "fst.nav.suggestions").exists, "no player in the new window: shared session")
        XCTAssertFalse(element(app, "fst.nav.sidebar.deselect-profile").exists)
        // iPadOS reconnects every open window at the next launch: close this one.
        XCTAssertTrue(WindowResize.closeFrontWindow(app), "close the second window")
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
