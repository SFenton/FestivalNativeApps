import XCTest

/// Structural accessibility journeys for the redesigned iPad / iPhone Duo shell
/// (`.agents/testing/apple/accessibility.md`, "Shell structure"): the overlay flyout is
/// modal, dismisses from its Close button and the scrim, keeps its footer reachable at
/// AX5 and moves focus in and back out; each on-demand split reads leading → trailing,
/// marks exactly one row selected, moves focus to the trailing pane's title when it opens
/// and back to the opened row when it closes.
///
/// XCUITest cannot read VoiceOver focus, so the app runs with
/// `FST_DEBUG_A11Y_FOCUS_TRACE=1` (Debug) and shows its last focus move as the element
/// `fst.nav.a11y-focus` (`AccessibilityFocusMove.swift`); spoken confirmation is the
/// operator's VoiceOver walkthrough (`voiceover.md`). Fixture-backed (127.0.0.1:8765).
final class IPadShellAccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad || IPadAccessibilityAuditTests.runningOnDuo, "iPad and iPhone Duo journeys")
        continueAfterFailure = true
    }

    override func tearDown() {
        guard !IPadAccessibilityAuditTests.runningOnDuo else { return }
        MainActor.assumeIsolated {
            let app = FestivalApp.makeApp()
            if app.state == .runningForeground { WindowResize.fill(app) }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Helpers

    /// A traced fixture app.
    @MainActor
    private func makeApp(
        profile: Bool = true, env extra: [String: String] = [:], contentSize: UIContentSizeCategory? = nil
    ) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_A11Y_FOCUS_TRACE": "1",
        ]
        if profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        env.merge(extra) { _, new in new }
        let app = FestivalApp.makeApp(env)
        app.launchArguments += ["-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES"]
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue] }
        return app
    }

    /// Launch, filling the screen on iPad.
    @MainActor
    private func launch(_ app: XCUIApplication) {
        app.launch()
        if !IPadAccessibilityAuditTests.runningOnDuo { WindowResize.fill(app) }
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        IPadAccessibilityAuditTests.anyElement(app, id)
    }

    /// The app's last traced focus move.
    @MainActor
    private func trace(_ app: XCUIApplication) -> String {
        let node = element(app, "fst.nav.a11y-focus")
        return node.exists ? node.label : ""
    }

    /// Wait until the trace satisfies `predicate` (focus moves wait out the presentation).
    @MainActor
    @discardableResult
    private func waitForTrace(
        _ app: XCUIApplication, timeout: TimeInterval = 6, _ predicate: (String) -> Bool
    ) -> String {
        let deadline = Date.now.addingTimeInterval(timeout)
        var last = trace(app)
        while Date.now < deadline {
            last = trace(app)
            if predicate(last) { return last }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return last
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while element.exists, Date.now < deadline { Thread.sleep(forTimeInterval: 0.2) }
        return !element.exists
    }

    /// Tap the trailing pane's Close: in the iPhone Duo vertical bar it can overflow into
    /// the system "More" menu when the pane's page has many bar items.
    @MainActor
    private func closeSplit(_ app: XCUIApplication) {
        let close = element(app, "fst.split.close")
        if close.waitForExistence(timeout: 3), close.isHittable {
            close.tap()
            return
        }
        let more = app.buttons.matching(NSPredicate(format: "label IN %@", ["More", "Show More"])).firstMatch
        if more.waitForExistence(timeout: 3) {
            more.tap()
            let item = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Close'")).firstMatch
            if item.waitForExistence(timeout: 3) { item.tap(); return }
        }
        XCTFail("the trailing pane's Close is neither in the bar nor its overflow menu")
    }

    /// Identifiers in depth-first accessibility order.
    @MainActor
    private func order(_ app: XCUIApplication) throws -> [XCUIElementSnapshot] {
        IPadAuditPageEvidence.flatten(try app.snapshot())
    }

    // MARK: - Flyout

    /// The flyout is modal (the page behind leaves the accessibility tree), focus moves to
    /// its title on open and back to the flyout button after Close or a scrim tap.
    @MainActor
    func testFlyoutIsModalAndReturnsFocus() throws {
        let orientations: [UIDeviceOrientation] = IPadAccessibilityAuditTests.runningOnDuo
            ? [.unknown] : [.landscapeLeft, .portrait]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            try flyoutIsModalAndReturnsFocus()
        }
    }

    /// One orientation of ``testFlyoutIsModalAndReturnsFocus()``.
    @MainActor
    private func flyoutIsModalAndReturnsFocus() throws {
        let app = makeApp()
        launch(app)
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 25))

        for dismissal in ["close", "scrim"] {
            // The button, or on the iPhone Duo rail its overflow menu.
            XCTAssertTrue(IPadAccessibilityAuditTests.openDrawer(app), "opens (\(dismissal))")
            let opened = waitForTrace(app) { $0.hasPrefix("heading: ") }
            XCTAssertEqual(opened, "heading: Festival Score Tracker", "focus moves to the flyout's title")
            let ids = try order(app).map(\.identifier)
            XCTAssertTrue(ids.contains("fst.shell.drawer.songs"), "flyout rows in the tree")
            XCTAssertFalse(ids.contains { $0.hasPrefix("fst.songs.row.") || $0 == "fst.songs.list" },
                           "the page behind the modal flyout is out of the accessibility tree")
            if dismissal == "close" {
                element(app, "fst.shell.drawer.close").tap()
            } else {
                // The scrim right of the panel, in screen points from the window (iPhone
                // Duo: `app.coordinate` taps never reached the inner display).
                // Midway between the panel and the window's trailing edge, clear of the
                // Duo's system vertical bar.
                let window = app.windows.firstMatch.frame
                let panel = element(app, "fst.shell.drawer").frame
                let x = panel.width > 0 && panel.maxX < window.maxX - 80
                    ? (panel.maxX + window.maxX) / 2 : window.minX + window.width * 0.9
                IPadAccessibilityAuditTests.screenOrigin(app)
                    .withOffset(CGVector(dx: x, dy: window.midY)).tap()
            }
            XCTAssertTrue(waitForDisappearance(of: element(app, "fst.shell.drawer"), timeout: 5), "\(dismissal) closes")
            let closed = waitForTrace(app) { $0.hasPrefix("fst.shell.drawer.open") }
            // The button, or the iPhone Duo rail's "More" overflow that holds it.
            XCTAssertTrue(["fst.shell.drawer.open: Open Navigation", "fst.shell.drawer.open: More"].contains(closed),
                          "focus returns to the flyout button (\(closed))")
            XCTAssertTrue(element(app, "fst.songs.list").exists, "the page is back in the tree")
        }
        app.terminate()
    }

    /// In a ⅓ window (phone tabs and drawer) the page behind the open drawer leaves the
    /// accessibility tree too: there the panel's `isModal` alone left the Songs rows in it
    /// (the ⅓ audit measured the covered rows at 1:1).
    @MainActor
    func testCompactDrawerIsModal() throws {
        try XCTSkipIf(IPadAccessibilityAuditTests.runningOnDuo, "the Duo outer display is covered by the folded audits")
        XCUIDevice.shared.orientation = .portrait
        let app = makeApp()
        launch(app)
        guard WindowResize.tile(app, .thirds), app.tabBars.firstMatch.waitForExistence(timeout: 10) else {
            throw XCTSkip("window-controls tiling unavailable")
        }
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 25))
        let open = element(app, "fst.shell.drawer.open")
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(element(app, "fst.shell.drawer.songs").waitForExistence(timeout: 5))
        let ids = try order(app).map(\.identifier)
        XCTAssertFalse(ids.contains { $0.hasPrefix("fst.songs.row.") || $0 == "fst.songs.list" },
                       "the page behind the drawer is out of the accessibility tree")
        element(app, "fst.shell.drawer.close").tap()
        XCTAssertTrue(waitForDisappearance(of: element(app, "fst.shell.drawer"), timeout: 5))
        XCTAssertTrue(element(app, "fst.songs.list").waitForExistence(timeout: 5), "back in the tree after closing")
        let closed = waitForTrace(app) { $0.hasPrefix("fst.shell.drawer.open") }
        XCTAssertEqual(closed, "fst.shell.drawer.open: Open Navigation", "focus returns to the drawer button")
    }

    /// At AX5 the flyout's footer (profile, Deselect, Settings) scrolls with the rows and
    /// every footer action can be brought fully on screen, portrait and landscape.
    @MainActor
    func testFlyoutFooterReachableAtAX5() throws {
        let orientations: [UIDeviceOrientation] = IPadAccessibilityAuditTests.runningOnDuo
            ? [.unknown] : [.portrait, .landscapeLeft]
        for orientation in orientations {
            if orientation != .unknown { XCUIDevice.shared.orientation = orientation }
            let app = makeApp(contentSize: .accessibilityExtraExtraExtraLarge)
            launch(app)
            let open = element(app, "fst.shell.drawer.open")
            XCTAssertTrue(open.waitForExistence(timeout: 25), "the flyout button")
            open.tap()
            XCTAssertTrue(element(app, "fst.shell.drawer.songs").waitForExistence(timeout: 5))
            let window = app.windows.firstMatch.frame
            for id in ["fst.shell.drawer.view-profile", "fst.shell.drawer.deselect-profile", "fst.shell.drawer.settings"] {
                let target = element(app, id)
                var attempts = 0
                while !(target.exists && target.isHittable && window.contains(target.frame)), attempts < 10 {
                    let panel = element(app, "fst.shell.drawer").frame
                    IPadAccessibilityAuditTests.slowDrag(
                        app, x: panel.midX, fromY: window.minY + window.height * 0.75,
                        toY: window.minY + window.height * 0.4
                    )
                    attempts += 1
                }
                XCTAssertTrue(target.exists && target.isHittable, "\(id) reachable at AX5 (\(orientation.rawValue))")
                XCTAssertTrue(window.contains(target.frame), "\(id) wholly on screen at AX5: \(target.frame) in \(window)")
            }
            app.terminate()
        }
    }

    // MARK: - On-demand split

    /// A split page and the row that opens its trailing pane.
    struct SplitPage {
        let name: String
        let env: [String: String]
        var profile = true
        let ready: String
        /// First row whose identifier begins with this, or the exact identifier.
        let row: String
        var exact = false
        /// Open this song from Songs first (Song Detail's split).
        var song: String?
    }

    static let splitPages: [SplitPage] = [
        SplitPage(name: "full-rankings", env: ["FST_DEBUG_ROUTE": "fullRankings:Solo_Guitar"],
                  ready: "Lead Rankings", row: "fst.rankings.row."),
        SplitPage(name: "rivals", env: ["FST_DEBUG_ROUTE": "rivals"], ready: "Rivals", row: "fst.rivals.row."),
        // iPhone Duo: with a profile `FST_DEBUG_TAB=leaderboards` resolves against the
        // compact tab set and opens Songs (Lane A11Y3's unreached row); the route pushes it.
        SplitPage(name: "leaderboards",
                  env: IPadAccessibilityAuditTests.runningOnDuo
                      ? ["FST_DEBUG_ROUTE": "leaderboards"] : ["FST_DEBUG_TAB": "leaderboards"],
                  ready: "Leaderboards", row: "fst.rankings.row."),
        SplitPage(name: "song-board", env: [:], profile: false, ready: "fst.songs.list",
                  row: "fst.song-detail.leaderboard.Solo_Guitar", exact: true, song: "fixture-pulse"),
        SplitPage(name: "settings", env: ["FST_DEBUG_TAB": "settings"], ready: "Settings",
                  row: "fst.settings.licenses", exact: true),
    ]

    /// Every split page in a landscape window: starts full width; the opened row reads
    /// before the trailing pane and is the one selected row; focus moves to the trailing
    /// pane's title (a heading inside the pane); Close returns to full width, clears the
    /// selection and gives focus back to that row.
    @MainActor
    func testSplitReadingOrderSelectionAndFocus() throws {
        if !IPadAccessibilityAuditTests.runningOnDuo { XCUIDevice.shared.orientation = .landscapeLeft }
        var summary: [[String: Any]] = []
        for page in Self.splitPages {
            let app = makeApp(profile: page.profile, env: page.env)
            launch(app)
            XCTAssertTrue(element(app, page.ready).waitForExistence(timeout: 25), "\(page.name) loads")
            let window = app.windows.firstMatch.frame
            guard window.width > window.height else {
                XCTFail("\(page.name): the window is not landscape (\(window)); no split to check")
                app.terminate()
                continue
            }
            if let song = page.song {
                XCTAssertTrue(IPadAccessibilityAuditTests.openSong(app, song), "\(page.name): Song Detail opens")
            }
            XCTAssertNil(IPadAccessibilityAuditTests.trailingPane(app), "\(page.name) starts full width")
            guard IPadAccessibilityAuditTests.openSplit(
                app, ids: page.exact ? [page.row] : [], prefix: page.exact ? nil : page.row
            ) != nil, let paneFrame = IPadAccessibilityAuditTests.trailingPane(app) else {
                XCTFail("\(page.name): the trailing pane did not open")
                if let dir = ProcessInfo.processInfo.environment["FST_AUDIT_OUT"] {
                    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                    try? XCUIScreen.main.screenshot().pngRepresentation
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent("split-\(page.name)-unopened.png"))
                    try? app.debugDescription.write(
                        toFile: dir + "/split-\(page.name)-unopened.tree.txt", atomically: true, encoding: .utf8
                    )
                }
                app.terminate()
                continue
            }
            // The same item can be listed more than once (Leaderboards: one row per
            // instrument card; Full Rankings: the selected-profile footer): every selected
            // row is the opened item's.
            let selected = app.descendants(matching: .any).matching(NSPredicate(format: "isSelected == true"))
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", page.row))
            let selectedIDs = Set((0..<selected.count).map { selected.element(boundBy: $0).identifier })
            XCTAssertEqual(selectedIDs.count, 1, "\(page.name): only the opened item's rows are selected: \(selectedIDs)")
            let rowID = selectedIDs.first ?? ""

            let nodes = try order(app)
            let rowIndex = nodes.firstIndex { $0.identifier == rowID }
            // The pane's container, or (iOS 27.1, no container identifier) its first element.
            let paneIndex = nodes.firstIndex { $0.identifier == "fst.split.trailing" }
                ?? nodes.firstIndex { paneFrame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) && $0.frame.width > 0
                    && $0.frame.width < paneFrame.width + 1 }
            if let rowIndex, let paneIndex {
                XCTAssertLessThan(rowIndex, paneIndex, "\(page.name): the leading pane reads before the trailing pane")
            } else {
                XCTFail("\(page.name): row \(rowID) or trailing pane missing from the tree")
            }
            XCTAssertEqual(paneFrame.minX, window.midX, accuracy: 30, "\(page.name): trailing half")

            // Focus: the trailing pane's top heading.
            let focus = waitForTrace(app) { $0.hasPrefix("heading: ") }
            let title = String(focus.dropFirst("heading: ".count))
            XCTAssertTrue(focus.hasPrefix("heading: ") && !title.isEmpty, "\(page.name): focus moves into the pane (\(focus))")
            let paneHeadings = nodes.filter {
                IPadAccessibilityAuditTests.isHeader($0) && paneFrame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
            }.map(\.label)
            XCTAssertTrue(paneHeadings.contains(title), "\(page.name): focus target '\(title)' is a heading in the pane \(paneHeadings)")

            // Close: full width, no selection, focus back to the row.
            closeSplit(app)
            let deadline = Date.now.addingTimeInterval(10)
            while IPadAccessibilityAuditTests.trailingPane(app) != nil, Date.now < deadline { Thread.sleep(forTimeInterval: 0.3) }
            XCTAssertNil(IPadAccessibilityAuditTests.trailingPane(app), "\(page.name): Close returns to full width")
            let back = waitForTrace(app) { $0.hasPrefix("row: ") }
            XCTAssertTrue(back.hasPrefix("row: "), "\(page.name): focus returns to the opened row (\(back))")
            XCTAssertEqual(
                app.descendants(matching: .any).matching(NSPredicate(format: "isSelected == true"))
                    .matching(NSPredicate(format: "identifier == %@", rowID)).count, 0,
                "\(page.name): the closed row is no longer selected"
            )
            summary.append(["page": page.name, "row": rowID, "openFocus": focus, "closeFocus": back,
                            "paneHeadings": paneHeadings])
            app.terminate()
        }
        if let dir = ProcessInfo.processInfo.environment["FST_AUDIT_OUT"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("split-structure.json"))
        }
    }
}
