import XCTest

/// iPadOS shell journeys on "FST Native iPad Pro 11": the sections sidebar, three-pane
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

    override func setUp() {
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

    /// Rotating changes the window size: portrait (sidebar beside a too-narrow section)
    /// keeps one stack, landscape splits, and the selection survives both ways.
    @MainActor
    func testRotationReflowsListDetail() throws {
        let app = fixtureApp(profile: false)
        launchFilled(app)
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 20))
        XCUIDevice.shared.orientation = .portrait
        let split = element(app, "fst.nav.list-detail")
        XCTAssertTrue(waitForDisappearance(of: split, timeout: 10), "portrait keeps one stack")
        // The auto-selected song stays pushed on the one stack.
        XCTAssertTrue(element(app, "fst.song-detail.intensity").waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(split.waitForExistence(timeout: 10), "landscape splits again")
        XCTAssertTrue(element(app, "fst.song-detail.intensity").exists)
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
