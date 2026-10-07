import XCTest

/// iPhone Duo shell journey (issue #337): folding and unfolding keeps the phone tabs,
/// the selected section and its pushed pages, and the Profile button opens Statistics.
///
/// Neither `simctl` nor XCTest can fold the Duo, so the app runs with the Debug
/// `FST_DEBUG_DUO_WINDOW_REMOTE` switch: each ``post(_:)`` sends a Darwin notification
/// that makes the app simulate that window (`DebugDuoWindow`: size, size classes, hinge,
/// vertical bar) *and* overrides its root view controllers' size classes, so the real
/// `UITabBarController` goes through the trait changes a fold or unfold pushes (the
/// 2026-10-04 tab-rebuild crash path). Runs on any iPhone simulator, the Duo included,
/// against a fixture service started from this revision (skips without it):
///
///     python3 tools/mock_service.py --port 18337
final class DuoShellJourneyTests: XCTestCase {
    /// Tabs every phone pose shows with a player selected (`FestivalTabPolicy.fittingSearchTab`).
    private let playerTabs = ["Songs", "Suggestions", "Compete", "Settings"]
    /// Sections the wide shells list that phone tabs leave to Compete, the drawer and Profile.
    private let wideOnlyTabs = ["Leaderboards", "Rivals", "Statistics"]

    /// Fold → unfolded landscape → unfolded portrait → fold, with Compete selected and
    /// Rivals pushed on its stack, then Profile → Statistics on the same stack.
    @MainActor
    func testFoldAndUnfoldKeepPhoneTabsSelectionAndStack() throws {
        continueAfterFailure = false
        let origin = "http://127.0.0.1:18337"
        let probe = expectation(description: "fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: URL(string: "\(origin)/api/features")!) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --port 18337` from this revision")
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_TAB": "compete",
            "FST_DEBUG_DUO_WINDOW_REMOTE": "1",
            "FST_DEBUG_DUO_WINDOW": "folded",
        ])
        app.launch()
        waitForWindow("folded", in: app)
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: 15))
        assertPhoneTabs(selected: "Compete", in: app, pose: "folded")

        // Rivals is pushed on Compete's stack from the drawer (not a phone tab).
        ShellUITestSupport.tapToolbarItem("fst.shell.drawer.open", overflowLabels: ["Menu", "Open Navigation"], in: app)
        let rivals = app.buttons["fst.shell.drawer.rivals"]
        XCTAssertTrue(rivals.waitForExistence(timeout: 10))
        rivals.tap()
        XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: 15))

        for pose in ["unfolded-landscape", "unfolded-portrait", "folded"] {
            post(pose)
            waitForWindow(pose, in: app)
            XCTAssertEqual(app.state, .runningForeground, "The app stopped after switching to \(pose)")
            assertPhoneTabs(selected: "Compete", in: app, pose: pose)
            XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: 10),
                          "Compete's pushed Rivals page was lost after switching to \(pose)")
            record(app, name: "duo-shell-rivals-\(pose)")
        }

        // Unfolded, the Profile button pushes Statistics on the current stack.
        post("unfolded-landscape")
        waitForWindow("unfolded-landscape", in: app)
        ShellUITestSupport.tapToolbarItem("fst.shell.profile", overflowLabels: ["Profile: Fixture Player 1", "Fixture Player 1", "FP"], in: app)
        XCTAssertTrue(SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: 15),
                      "Profile did not open the selected player's Statistics")
        SongsUITestSupport.assertPlayerTitle("Fixture Player 1", in: app)
        assertPhoneTabs(selected: "Compete", in: app, pose: "unfolded-landscape")
        record(app, name: "duo-shell-statistics-unfolded-landscape")

        for pose in ["unfolded-portrait", "folded"] {
            post(pose)
            waitForWindow(pose, in: app)
            XCTAssertEqual(app.state, .runningForeground, "The app stopped after switching to \(pose)")
            assertPhoneTabs(selected: "Compete", in: app, pose: pose)
            XCTAssertTrue(SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: 10),
                          "Statistics left Compete's stack after switching to \(pose)")
        }

        // Back pops to the Rivals page underneath: the whole stack survived.
        // The Duo puts Back in the system vertical bar, outside the navigation bar.
        let back = app.buttons["BackButton"]
        (back.waitForExistence(timeout: 5) && back.isHittable ? back : app.navigationBars.buttons.firstMatch).tap()
        XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

    /// Ask the app to simulate a Duo window (`DebugDuoWindow`).
    ///
    /// - Parameter pose: `folded`, `unfolded-landscape` or `unfolded-portrait`.
    private func post(_ pose: String) {
        DuoWindowSwitch.post(pose)
    }

    /// Wait until the app reports the simulated window and its resolved layout.
    ///
    /// - Parameters:
    ///   - pose: Expected `DebugDuoWindow` raw value.
    ///   - app: The running app.
    @MainActor
    private func waitForWindow(_ pose: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let expected = NSPredicate(format: "label BEGINSWITH %@", "\(pose) ")
        let reached = XCTNSPredicateExpectation(predicate: expected, object: readout)
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: 10), .completed,
                       "The app never simulated \(pose): \(readout.exists ? readout.label : "no readout")",
                       file: file, line: line)
        XCTAssertTrue(readout.label.contains("regularSet=false"),
                      "\(pose) resolved the wide section set: \(readout.label)", file: file, line: line)
        if pose != "folded" {
            XCTAssertTrue(readout.label.contains("width=regular"), readout.label, file: file, line: line)
        }
    }

    /// Require the phone tab set with `selected` chosen, and none of the wide-only sections.
    ///
    /// The Duo shows its tabs in a vertical bar that XCUITest does not report as a tab bar,
    /// so tabs are the on-screen buttons with a section's title outside navigation bars
    /// (where a back button may carry the previous page's title).
    ///
    /// - Parameters:
    ///   - selected: The tab that must stay selected.
    ///   - app: The running app.
    ///   - pose: The simulated window, for failure messages.
    @MainActor
    private func assertPhoneTabs(
        selected: String, in app: XCUIApplication, pose: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // A minimized horizontal bar shows only the selected tab; expand it first.
        let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == %@", "Collapsed")).firstMatch
        if collapsed.exists { collapsed.tap() }
        let deadline = Date().addingTimeInterval(10)
        while playerTabs.contains(where: { ShellUITestSupport.tabButtons($0, in: app).isEmpty }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        for tab in playerTabs {
            XCTAssertFalse(ShellUITestSupport.tabButtons(tab, in: app).isEmpty, "\(pose) is missing the \(tab) tab", file: file, line: line)
        }
        for tab in wideOnlyTabs {
            XCTAssertTrue(ShellUITestSupport.tabButtons(tab, in: app).isEmpty, "\(pose) shows a \(tab) tab", file: file, line: line)
        }
        XCTAssertTrue(ShellUITestSupport.tabButtons(selected, in: app).contains(where: \.isSelected),
                      "\(pose) moved the selection off \(selected)", file: file, line: line)
    }

    /// Attach a screenshot to the test report.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
