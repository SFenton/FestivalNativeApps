import XCTest

/// The iPadOS menu bar's page tools (issue #633, page-tools-and-nav-chrome R28): View ›
/// Sort…, Filter…, Rank By ▸, Instrument ▸, Band Size ▸, as List / as Grid and Profile ›
/// Select / Switch to This Profile, View Rival's Profile, Find Rival…, each named,
/// disabled where the page in front lacks it and acting on that page.
///
/// The iPadOS 26 menu bar is not in the XCUITest tree (a top-edge swipe, pointer hover
/// or held ⌘ exposes no menu bar or menu item to the runner, 2026-10-14), so the Debug
/// launch flag `FST_DEBUG_MENU_BAR=1` lays the same items over the window
/// (`DebugMenuBarMirror` → `PageToolMenuBarMirror` for SwiftUI, or the UIKit-only
/// `UKDebugMenuBarMirror` using the same responder command identifiers). Fixture-backed
/// (`tools/mock_service.py` on 127.0.0.1:8765,
/// or the runner's `FST_FIXTURE_URL`), never production. Run with
/// `python3 tools/ios_sim.py uitest --device ipad --only IPadMenuBarJourneyTests`.
final class IPadMenuBarJourneyTests: XCTestCase {
    /// The loopback fixture service.
    static let fixtureURL = ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765"

    /// The View and Profile page tools in menu order, with the band sizes listed inline.
    static let menuNames = [
        "Sort…", "Filter…", "Rank By", "Instrument", "Band Size", "as List", "as Grid",
        "Duos", "Trios", "Quads", "Select This Profile", "View Rival's Profile", "Find Rival…",
    ]

    /// The fixture rival every fixture player shares.
    static let rivalId = "f1c749eb07c32578cfa3e59ec38c03a8"

    override func setUpWithError() throws {
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad, "the menu bar is iPad-only")
        // Any orientation: a full-screen iPad window is regular width either way. These
        // journeys never rotate: rotating back with no app in front hung the simulator
        // until the runner was killed (2026-10-14). Each journey terminates its app itself
        // (as ScoreHistoryAccessibilityJourneyTests does): an app left running for tear-down
        // was intermittently reported as "crashed with signal term" after every assertion passed.
        continueAfterFailure = false
    }

    // MARK: - Names and disabled states

    /// With no page tools in front (Settings), every item is listed in menu order, the
    /// submenus stay available and every other item is disabled (HIG The menu bar:
    /// "Disable, don't hide, unavailable items").
    @MainActor
    func testMenuBarPageToolsAreListedAndDisabledWithoutPageTools() throws {
        let app = launch(["FST_DEBUG_TAB": "settings"])
        defer { app.terminate() }
        let mirror = self.mirror(app)
        XCTAssertTrue(mirror.waitForExistence(timeout: 30), "the Debug menu-bar mirror")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        XCTAssertEqual(names(in: mirror), Self.menuNames, "every page tool, in menu order")
        for name in Self.menuNames {
            let item = self.item(name, in: mirror)
            XCTAssertTrue(item.exists, name)
            if ["Rank By", "Instrument", "Band Size"].contains(name) {
                XCTAssertTrue(item.isEnabled, "the \(name) submenu stays available")
            } else {
                XCTAssertFalse(item.isEnabled, "Settings offers no \(name)")
            }
        }
    }

    // MARK: - Invocation against the page in front

    /// Item Shop: as List / as Grid check the layout in effect and switch the page's
    /// own List/Grid toolbar toggle; Sort… and Filter… are offered.
    @MainActor
    func testItemShopLayoutItemsSwitchThePage() throws {
        let app = launch(["FST_DEBUG_ROUTE": "shop"])
        defer { app.terminate() }
        let mirror = self.mirror(app)
        let mirrorFound = mirror.waitForExistence(timeout: 30)
        attachDiagnosticState(app, mirror: mirror, name: "shop-before-menu-query")
        XCTAssertTrue(mirrorFound, "the Debug menu-bar mirror")
        let asList = item("as List", in: mirror)
        let asGrid = item("as Grid", in: mirror)
        XCTAssertTrue(wait(for: asGrid, "isEnabled == true", timeout: 30), "as Grid on the Item Shop")
        let toggle = element(app, "fst.shop.view-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "the page's List/Grid toggle")
        XCTAssertTrue(item("Sort…", in: mirror).isEnabled && item("Filter…", in: mirror).isEnabled)
        XCTAssertFalse(item("Select This Profile", in: mirror).isEnabled)
        if isOn(asList) { flip(asGrid) }
        XCTAssertTrue(wait(for: asGrid, "value == '1'", timeout: 10), "as Grid in effect")
        XCTAssertEqual(toggle.label, "List View")

        flip(asList)
        attachTrace(app)
        XCTAssertTrue(wait(for: asList, "value == '1'", timeout: 10), "as List takes effect")
        XCTAssertFalse(isOn(asGrid))
        XCTAssertTrue(wait(for: toggle, "label == 'Grid View'", timeout: 10), "the page shows its list")

        flip(asGrid)
        attachTrace(app)
        XCTAssertTrue(wait(for: asGrid, "value == '1'", timeout: 10), "as Grid takes effect")
        XCTAssertTrue(wait(for: toggle, "label == 'List View'", timeout: 10), "the page shows its grid")
    }

    /// Band Rankings: Band Size checks the board's size and switches the board.
    @MainActor
    func testBandSizeItemsSwitchTheBoard() throws {
        let app = launch(["FST_DEBUG_ROUTE": "bandRankings:Band_Duets"])
        defer { app.terminate() }
        let mirror = self.mirror(app)
        let duos = item("Duos", in: mirror)
        XCTAssertTrue(wait(for: duos, "value == '1'", timeout: 30), "Duos checked on the duos board")
        for size in ["Duos", "Trios", "Quads"] {
            XCTAssertTrue(item(size, in: mirror).isEnabled, "\(size) is offered")
        }
        let trios = item("Trios", in: mirror)
        flip(trios)
        XCTAssertTrue(wait(for: trios, "value == '1'", timeout: 10), "Trios takes effect")
        XCTAssertFalse(isOn(duos))
        let pageMenu = element(app, "fst.band-rankings.band-type-menu")
        XCTAssertTrue(wait(for: pageMenu, "value == 'Trios'", timeout: 15), "the board's own Band size reads Trios")
    }

    /// Player page: Select This Profile selects the shown player.
    @MainActor
    func testSelectThisProfileSelectsTheShownPlayer() throws {
        let app = launch(["FST_DEBUG_ROUTE": "player:fixture-player-1"])
        defer { app.terminate() }
        let mirror = self.mirror(app)
        let select = item("Select This Profile", in: mirror)
        XCTAssertTrue(wait(for: select, "isEnabled == true", timeout: 30), "Select This Profile on the player page")
        XCTAssertFalse(item("View Rival's Profile", in: mirror).isEnabled)
        let nativeSelect = element(app, "fst.player.select")
        XCTAssertEqual(nativeSelect.label, "Select Profile")
        select.tap()
        attachDiagnosticState(app, mirror: mirror, name: "profile-after-selection")
        let selectedProfile = element(app, "fst.player.deselect")
        XCTAssertTrue(
            wait(for: selectedProfile, "label == 'Deselect Profile'", timeout: 15),
            "the shown player is selected"
        )
        let selectedCommand = item("Select This Profile", in: mirror)
        XCTAssertTrue(
            wait(for: selectedCommand, "isEnabled == false", timeout: 10),
            "nothing to select on your own page"
        )
    }

    /// Rivalry: View Rival's Profile opens the rival's player page.
    @MainActor
    func testViewRivalsProfileOpensTheRival() throws {
        let app = launch(
            ["FST_DEBUG_ROUTE": "rivalry:\(Self.rivalId):closest_battles"],
            profile: "fixture-riv:Fixture Riv"
        )
        defer { app.terminate() }
        let mirror = self.mirror(app)
        let view = item("View Rival's Profile", in: mirror)
        XCTAssertTrue(wait(for: view, "isEnabled == true", timeout: 30), "View Rival's Profile on the rivalry")
        XCTAssertFalse(item("Select This Profile", in: mirror).isEnabled)
        view.tap()
        let rival = app.navigationBars.matching(NSPredicate(format: "identifier CONTAINS 'Fixture Rival Golf'")).firstMatch
        XCTAssertTrue(rival.waitForExistence(timeout: 15), "the rival's player page opens")
    }

    /// Suggestions: Filter… opens the page's Filter sheet.
    @MainActor
    func testSuggestionsFilterOpensThePageFilter() throws {
        let app = launch(["FST_DEBUG_ROUTE": "suggestions"], profile: "fixture-player-1:Fixture Player 1")
        defer { app.terminate() }
        let mirror = self.mirror(app)
        let filter = item("Filter…", in: mirror)
        XCTAssertTrue(wait(for: filter, "isEnabled == true", timeout: 30), "Filter… on Suggestions")
        XCTAssertFalse(item("as List", in: mirror).isEnabled)
        filter.tap()
        XCTAssertTrue(app.navigationBars["Filter Suggestions"].waitForExistence(timeout: 10), "the Filter sheet")
        XCTAssertTrue(element(app, "fst.suggestions.filter.form").exists, "the page's filter form")
    }

    /// Full Rankings' native command tree applies the Settings experimental-ranks gate.
    @MainActor
    func testFullRankingsRankByMenuHonorsExperimentalRanksFlag() throws {
        for enabled in [false, true] {
            let app = launch(
                ["FST_DEBUG_ROUTE": "fullRankings:Solo_Guitar"],
                experimentalRanks: enabled
            )
            let mirror = self.mirror(app)
            XCTAssertTrue(mirror.waitForExistence(timeout: 30), "the Debug menu-bar mirror")
            XCTAssertTrue(app.navigationBars["Lead Rankings"].waitForExistence(timeout: 20))
            XCTAssertTrue(item("Rank By", in: mirror).exists, "Rank By remains a fixed submenu")
            let expected = enabled
                ? ["Total Score", "Adjusted", "Weighted", "FC Rate", "Max Score"]
                : ["Total Score"]
            for metric in ["Total Score", "Adjusted", "Weighted", "FC Rate", "Max Score"] {
                XCTAssertEqual(
                    item(metric, in: mirror).exists,
                    expected.contains(metric),
                    "\(metric) follows Experimental Ranks \(enabled ? "on" : "off")"
                )
            }
            app.terminate()
        }
    }

    /// Band Rankings' native command tree applies the same gate without exposing Max Score.
    @MainActor
    func testBandRankingsRankByMenuHonorsExperimentalRanksFlag() throws {
        for enabled in [false, true] {
            let app = launch(
                ["FST_DEBUG_ROUTE": "bandRankings:Band_Duets"],
                experimentalRanks: enabled
            )
            let mirror = self.mirror(app)
            XCTAssertTrue(mirror.waitForExistence(timeout: 30), "the Debug menu-bar mirror")
            XCTAssertTrue(app.navigationBars["Duos Rankings"].waitForExistence(timeout: 20))
            let expected = enabled
                ? ["Total Score", "Adjusted", "Weighted", "FC Rate"]
                : ["Total Score"]
            for metric in ["Total Score", "Adjusted", "Weighted", "FC Rate", "Max Score"] {
                XCTAssertEqual(
                    item(metric, in: mirror).exists,
                    expected.contains(metric),
                    "\(metric) follows Band Experimental Ranks \(enabled ? "on" : "off")"
                )
            }
            app.terminate()
        }
    }

    // MARK: - Helpers

    /// Capture the complete UIKit/XCUITest surface before a potentially failing query.
    @MainActor
    private func attachDiagnosticState(_ app: XCUIApplication, mirror: XCUIElement, name: String) {
        XCTContext.runActivity(named: name) { activity in
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(name)-accessibility-tree"
            activity.add(tree)

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(name)-screen"
            activity.add(screenshot)

            let trace = element(app, "fst.menu-bar-trace")
            if trace.exists {
                let traceAttachment = XCTAttachment(string: trace.value as? String ?? trace.label)
                traceAttachment.name = "\(name)-menu-trace"
                activity.add(traceAttachment)
            }

            let mirrorDescription = XCTAttachment(string: mirror.debugDescription)
            mirrorDescription.name = "\(name)-mirror-tree"
            activity.add(mirrorDescription)
        }
    }

    /// Attach the durable trace projected from the actual UIKit command tree and page render state.
    @MainActor
    private func attachTrace(_ app: XCUIApplication) {
        let trace = element(app, "fst.menu-bar-trace")
        guard trace.exists else { return }
        let attachment = XCTAttachment(string: trace.value as? String ?? trace.label)
        attachment.name = "UIKit native menu render trace"
        XCTContext.runActivity(named: "UIKit native menu render trace") { activity in
            activity.add(attachment)
        }
    }

    /// Launch against the fixture service with the mirror, filling the screen.
    @MainActor
    private func launch(
        _ extra: [String: String],
        profile: String? = nil,
        experimentalRanks: Bool? = nil
    ) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": Self.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_MENU_BAR": "1",
            "FST_DEBUG_MENU_TRACE": "1",
        ]
        if let profile { env["FST_DEBUG_PROFILE"] = profile }
        env.merge(extra) { $1 }
        let app = FestivalApp.makeApp(env)
        if let experimentalRanks {
            app.launchArguments += [
                "-fst.settings.experimentalRanks",
                experimentalRanks ? "YES" : "NO",
            ]
        }
        app.launch()
        WindowResize.fill(app)
        return app
    }

    /// The mirror of the menu bar's page tools.
    @MainActor
    private func mirror(_ app: XCUIApplication) -> XCUIElement {
        element(app, "fst.menu-bar-mirror")
    }

    /// Any element by accessibility identifier.
    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// The mirror's item named `name` (a button, submenu or checkmarked toggle).
    @MainActor
    private func item(_ name: String, in mirror: XCUIElement) -> XCUIElement {
        mirror.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d OR elementType == %d)",
                        name, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.switch.rawValue,
                        XCUIElement.ElementType.popUpButton.rawValue)
        ).firstMatch
    }

    /// The mirror's item names, top to bottom.
    @MainActor
    private func names(in mirror: XCUIElement) -> [String] {
        Self.menuNames
            .map { (name: $0, item: item($0, in: mirror)) }
            .filter { $0.item.exists }
            .sorted { $0.item.frame.minY < $1.item.frame.minY }
            .map(\.name)
    }

    /// Whether a checkmarked toggle is on.
    @MainActor
    private func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1"
    }

    /// Turn a checkmarked toggle on: tap its switch at the row's trailing end.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        let knob = toggle.switches.firstMatch
        if knob.exists, knob.frame != toggle.frame {
            knob.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
    }

    /// Wait until `predicate` holds for `element`.
    @MainActor
    private func wait(for element: XCUIElement, _ predicate: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
