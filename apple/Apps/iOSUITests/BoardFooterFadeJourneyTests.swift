import UIKit
import XCTest

/// Accessibility at the largest text size for the board footer fade (issue #473, for
/// #329): every paginated board fades its rows over 40 pt above its pinned pager
/// (`bottomChromeFade`, pattern `scroll-edge` R3/R9). macOS has no Dynamic Type, so the
/// hosted `bandBoardFooterFadeKeepsRowsAndPagerAccessible` cannot show AX5; this journey
/// does, on Player Bands (a board the CI fixture pages: `fixture-player-1`'s 30-band
/// "All" group, 25 a page) with no selected player, in each iOS form: iPhone portrait,
/// iPad portrait and landscape, and the iPhone Duo outer display (the Debug
/// `DebugDuoWindow` simulation, as `DuoShellJourneyTests`, so it runs on the CI iPhone).
///
/// Runs against `tools/mock_service.py` on `:8765` (the `apple-ci` simulator steps'
/// `--large-catalogue` fixture); set `FST_BOARD_FADE_FIXTURE_URL` (as
/// `TEST_RUNNER_FST_BOARD_FADE_FIXTURE_URL`) to use another port. Skips when the board
/// never loads.
final class BoardFooterFadeJourneyTests: XCTestCase {
    /// Identifier prefix of Player Bands' rows.
    private static let rowPrefix = "fst.player-bands.row."
    /// The pager's arrows, in reading order around the page badge, with the word each
    /// name carries and whether it moves toward the first page.
    private static let pagerArrows = [
        (id: "fst.player-bands.page-first", word: "First", backward: true),
        (id: "fst.player-bands.page-previous", word: "Previous", backward: true),
        (id: "fst.player-bands.page-next", word: "Next", backward: false),
        (id: "fst.player-bands.page-last", word: "Last", backward: false),
    ]
    /// The page badge (an adjustable element, not a button).
    private static let pageInfo = "fst.player-bands.page-info"
    /// `ScrollEdgeFade.distance`: the board footer ramp (#329).
    private static let fadeDistance: CGFloat = 40
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44
    /// The fixture's "All" group: 30 bands, 25 a page.
    private static let totalPages = 2

    // MARK: - Journeys

    /// Portrait (iPhone, iPad, and the real iPhone Duo when run there).
    @MainActor
    func testBoardFooterFadeAtLargestText() throws {
        try assertBoardFooterFade(.portrait, duoWindow: nil)
    }

    /// iPad landscape: a shorter board between the bars. iPhone is portrait-only.
    @MainActor
    func testBoardFooterFadeAtLargestTextLandscape() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone, "iPhone runs portrait only")
        try assertBoardFooterFade(.landscapeLeft, duoWindow: nil)
    }

    /// iPhone Duo folded (outer display, vertical bar trailing): the board's rail
    /// clearance and pager placement (`pagerScreenPlacement`) resolve the Duo layout.
    @MainActor
    func testBoardFooterFadeAtLargestTextDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertBoardFooterFade(.portrait, duoWindow: "folded")
    }

    /// iPad with a hardware keyboard (CI: `--a11y full-keyboard-access`): the focus
    /// system's stops are on screen and never on a row under the pager.
    @MainActor
    func testBoardKeyboardFocusClearsFooter() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "The hardware-keyboard journey runs on iPad")
        continueAfterFailure = false
        let (app, window) = try launchBoard(duoWindow: nil)
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)), "No band rows")
        let pagerTop = assertPager(page: 1, in: app, window: window)
        assertKeyboardFocusClearsFooter(rows, pagerTop: pagerTop, in: app, window: window)
    }

    // MARK: - Assertions

    /// At AX5 the board's rows grow and the 40 pt fade above the pager stays drawing
    /// only: rows in it are still enabled, named buttons and reachable; the pager's
    /// arrows keep their names, enabled states, reading order and 44 pt targets on
    /// screen; at the end of the page the last row rests whole above the pager; the
    /// pager pages and its states follow. The system audit (Dynamic Type, clipped text,
    /// descriptions, hit regions) covers the board's rows and pager.
    ///
    /// - Parameters:
    ///   - orientation: Device orientation for the run.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Throws: A skip when the board never loads, or a failed requirement.
    @MainActor
    private func assertBoardFooterFade(_ orientation: UIDeviceOrientation, duoWindow: String?) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        defer { XCUIDevice.shared.orientation = .portrait }
        let (app, window) = try launchBoard(duoWindow: duoWindow)
        let pageInfo = app.descendants(matching: .any)[Self.pageInfo]
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)), "No band rows")
        assertRowsAreEnabledButtons(rows, in: app)
        try assertRowsReadBeforePager(in: app)

        let pagerTop = assertPager(page: 1, in: app, window: window)

        // Rows grew to AX5: at least one body line per card.
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ).lineHeight
        XCTAssertGreaterThanOrEqual(rows.firstMatch.frame.height, bodyLine, "Row not at AX5: \(rows.firstMatch.frame)")

        // Rows inside the fade band stay enabled, named buttons, reachable while their
        // middle is above the pager (the mask is drawing only, scroll-edge R7 keeps the
        // cut below).
        var crossed = false
        for step in 0..<4 {
            let fadeBand = CGRect(
                x: window.minX, y: pagerTop - 8 - Self.fadeDistance, width: window.width, height: Self.fadeDistance
            )
            for row in rows.allElementsBoundByIndex where row.frame.intersects(fadeBand) {
                crossed = true
                XCTAssertEqual(row.elementType, .button, "\(row.identifier) in the fade is not a button")
                XCTAssertTrue(row.isEnabled, "\(row.identifier) in the fade is not enabled")
                XCTAssertFalse(row.label.isEmpty, "\(row.identifier) has no name in the fade")
                if row.frame.midY < fadeBand.maxY {
                    XCTAssertTrue(row.isHittable, "\(row.identifier) in the fade is not reachable: \(row.frame)")
                }
            }
            if step < 3 {
                let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)))
            }
        }
        XCTAssertTrue(crossed, "No row crossed the 40 pt fade above the pager")

        // The system audit at AX5, for the board's rows and pager only (the shell has its own).
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion]
        ) { issue in
            !(issue.element?.identifier.hasPrefix("fst.player-bands.") ?? false)
        }

        // End of the page: the last row rests whole above the pager (the fade has shrunk
        // to nothing), reachable and fully on screen.
        assertLastRowRestsAbovePager(rows, pagerTop: pagerTop, in: app, window: window)

        // Activation at the boundary: Next pages; the arrows' states follow, and the
        // second page's last row rests above the pager too. First returns.
        app.buttons["fst.player-bands.page-next"].tap()
        XCTAssertTrue(waitForPage(2, in: app), "Next page did not page: \(pageInfo.value as? String ?? "nil")")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)), "No band rows on page 2")
        assertRowsAreEnabledButtons(rows, in: app)
        let secondTop = assertPager(page: 2, in: app, window: window)
        assertLastRowRestsAbovePager(rows, pagerTop: secondTop, in: app, window: window)
        app.buttons["fst.player-bands.page-first"].tap()
        XCTAssertTrue(waitForPage(1, in: app), "First page did not page: \(pageInfo.value as? String ?? "nil")")
        _ = assertPager(page: 1, in: app, window: window)
    }

    /// Every row is an enabled button element (`PlayerBandRow`'s `.isButton` link), not
    /// a static element: the button query finds each row the any-type query does.
    ///
    /// - Parameters:
    ///   - rows: The rows, queried as any element type.
    ///   - app: The running app.
    @MainActor
    private func assertRowsAreEnabledButtons(_ rows: XCUIElementQuery, in app: XCUIApplication) {
        let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
        let all = rows.allElementsBoundByIndex
        XCTAssertFalse(all.isEmpty, "No band rows")
        XCTAssertEqual(buttons.count, all.count, "Some band rows are not buttons")
        for row in all {
            XCTAssertEqual(row.elementType, .button, "\(row.identifier) is not a button")
            XCTAssertTrue(row.isEnabled, "\(row.identifier) is not enabled")
        }
    }

    /// VoiceOver reaches every realized row before the pinned pager, in the order
    /// drawn (`boardBottomChrome`, scroll-edge R10).
    ///
    /// - Parameter app: The running app.
    /// - Throws: An unavailable accessibility snapshot.
    @MainActor
    private func assertRowsReadBeforePager(in app: XCUIApplication) throws {
        var identifiers: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty { identifiers.append(element.identifier) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        let lastRow = try XCTUnwrap(identifiers.lastIndex { $0.hasPrefix(Self.rowPrefix) }, "No row in the tree")
        let firstPager = try XCTUnwrap(
            identifiers.firstIndex { $0.hasPrefix("fst.player-bands.page-") }, "No pager in the tree"
        )
        XCTAssertLessThan(lastRow, firstPager, "The pager reads before a row")
    }

    /// The pager on `page`: the badge reads "Page, <page> of 2"; each arrow is a named
    /// 44 pt button, on screen, in reading order, enabled only where it can move.
    ///
    /// - Parameters:
    ///   - page: The page the board shows.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    /// - Returns: The top of the pager's controls.
    @MainActor
    private func assertPager(page: Int, in app: XCUIApplication, window: CGRect) -> CGFloat {
        let info = app.descendants(matching: .any)[Self.pageInfo]
        XCTAssertEqual(info.label, "Page")
        XCTAssertEqual(info.value as? String, "\(page) of \(Self.totalPages)")
        var pagerTop = info.frame.minY
        var previousMaxX = -CGFloat.greatestFiniteMagnitude
        let order = Self.pagerArrows.prefix(2).map(\.id) + [Self.pageInfo] + Self.pagerArrows.suffix(2).map(\.id)
        for identifier in order {
            let control = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(control.exists, "\(identifier) missing")
            let frame = control.frame
            XCTAssertGreaterThanOrEqual(frame.width, Self.minimumTarget - 0.5, "\(identifier) target \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, Self.minimumTarget - 0.5, "\(identifier) target \(frame)")
            XCTAssertTrue(window.contains(frame), "\(identifier) off screen: \(frame)")
            XCTAssertGreaterThan(frame.minX, previousMaxX - 0.5, "\(identifier) out of reading order")
            previousMaxX = frame.maxX
            pagerTop = min(pagerTop, frame.minY)
        }
        for arrow in Self.pagerArrows {
            let button = app.buttons[arrow.id]
            XCTAssertTrue(button.exists, "\(arrow.id) is not a button")
            XCTAssertTrue(button.label.localizedCaseInsensitiveContains(arrow.word), "\(arrow.id) reads \(button.label)")
            let enabled = arrow.backward ? page > 1 : page < Self.totalPages
            XCTAssertEqual(button.isEnabled, enabled, "\(arrow.id) enabled on page \(page)")
            if enabled { XCTAssertTrue(button.isHittable, "\(arrow.id) is not reachable") }
        }
        return pagerTop
    }

    /// Scroll to the end of the page: the last row rests whole above the pager, at it,
    /// reachable and named, and the pager stays reachable.
    ///
    /// - Parameters:
    ///   - rows: The rows.
    ///   - pagerTop: Top of the pager's controls.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    @MainActor
    private func assertLastRowRestsAbovePager(
        _ rows: XCUIElementQuery, pagerTop: CGFloat, in app: XCUIApplication, window: CGRect
    ) {
        // Settled only after two drags in a row leave the bottom row in place (a single
        // unchanged reading once ended early on iPad, with the row still under the pager).
        var lastFrame = CGRect.null
        var unchanged = 0
        for _ in 0..<60 where unchanged < 2 {
            let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -window.height * 0.4)))
            let bottom = rows.allElementsBoundByIndex.map(\.frame).filter { window.intersects($0) }
                .max { $0.maxY < $1.maxY } ?? .null
            unchanged = bottom == lastFrame ? unchanged + 1 : 0
            lastFrame = bottom
        }
        guard let last = rows.allElementsBoundByIndex.filter({ window.intersects($0.frame) })
            .max(by: { $0.frame.maxY < $1.frame.maxY }) else {
            return XCTFail("No row on screen at the end of the page")
        }
        XCTAssertLessThanOrEqual(last.frame.maxY, pagerTop + 0.5, "Last row under the pager: \(last.frame) vs \(pagerTop)")
        XCTAssertGreaterThanOrEqual(last.frame.maxY, pagerTop - 8 - 12, "Last row does not rest at the pager: \(last.frame)")
        XCTAssertTrue(last.isHittable, "Last row is not reachable: \(last.frame)")
        XCTAssertEqual(last.elementType, .button)
        XCTAssertFalse(last.label.isEmpty)
        let next = app.buttons["fst.player-bands.page-next"]
        let previous = app.buttons["fst.player-bands.page-previous"]
        XCTAssertTrue((next.isEnabled ? next : previous).isHittable, "Pager lost at the end of the page")
    }

    /// iPad hardware-keyboard focus (CI: `ios_sim.py uitest --a11y full-keyboard-access`):
    /// Tab and ↓ move the UIKit focus system's stops, and every stop is on screen and
    /// never on a row under the pager (WCAG 2.4.11 Focus Not Obscured, scroll-edge R10).
    /// A run with no focus stop fails rather than passing on nothing.
    ///
    /// Full Keyboard Access traversal itself (rows → pager arrow → Space) cannot be
    /// driven here: the simulator's FKA agent starts only through a private setter, and
    /// XCUITest's synthesized keys never reach its event tap, so its focus ring stays on
    /// its first stop (design/apple/ipados.md#keyboard-only-and-full-keyboard-access).
    /// That walk is an operator check; this journey guards the focus system's stops.
    ///
    /// - Parameters:
    ///   - rows: The rows.
    ///   - pagerTop: Top of the pager's controls.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    @MainActor
    private func assertKeyboardFocusClearsFooter(
        _ rows: XCUIElementQuery, pagerTop: CGFloat, in app: XCUIApplication, window: CGRect
    ) {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
        var stops: [String] = []
        /// Record the focused element, checked: a focused row must sit on screen and
        /// wholly above the pager.
        func record() {
            guard let element = focused.allElementsBoundByIndex.last else { return stops.append("-") }
            let identifier = element.identifier
            stops.append(identifier.isEmpty ? element.label : identifier)
            guard identifier.hasPrefix(Self.rowPrefix) else { return }
            let frame = element.frame
            XCTAssertLessThanOrEqual(frame.maxY, pagerTop + 0.5, "Focus on \(identifier) under the pager: \(frame)")
            XCTAssertTrue(window.contains(frame.insetBy(dx: 0.5, dy: 0.5)), "Focus on \(identifier) off screen: \(frame)")
        }
        defer {
            XCTContext.runActivity(named: "Keyboard focus stops: \(stops.joined(separator: ", "))") { _ in }
        }

        record()
        for key in Array(repeating: XCUIKeyboardKey.tab, count: 6) + Array(repeating: .downArrow, count: 6) {
            app.typeKey(key.rawValue, modifierFlags: [])
            record()
        }
        XCTAssertTrue(
            stops.contains { $0 != "-" },
            "No hardware-keyboard focus stop (stops: \(stops)); run with --a11y full-keyboard-access"
        )
        XCTAssertLessThanOrEqual(rows.allElementsBoundByIndex.filter(\.hasFocus).count, 1, "More than one row focused")
    }

    // MARK: - Helpers

    /// Launch Player Bands at AX5 against the fixture, with no selected player.
    ///
    /// - Parameter duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Returns: The app and its window's frame.
    /// - Throws: A skip when the board never loads.
    @MainActor
    private func launchBoard(duoWindow: String?) throws -> (XCUIApplication, CGRect) {
        let base = ProcessInfo.processInfo.environment["FST_BOARD_FADE_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
        var environment = [
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_ROUTE": "playerBands:fixture-player-1",
        ]
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        }
        let app = FestivalApp.makeApp(environment)
        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", ax5.rawValue]
        app.launch()

        let pageInfo = app.descendants(matching: .any)[Self.pageInfo]
        guard pageInfo.waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("Player Bands never loaded; run tools/mock_service.py on \(base).")
        }
        if let duoWindow { waitForDuoWindow(duoWindow, in: app) }
        let window = app.windows.firstMatch.frame
        return (app, window)
    }

    /// Wait for the badge to read `page` of the total.
    ///
    /// - Parameters:
    ///   - page: Expected page.
    ///   - app: The running app.
    /// - Returns: Whether the badge reached it.
    @MainActor
    private func waitForPage(_ page: Int, in app: XCUIApplication) -> Bool {
        let info = app.descendants(matching: .any)[Self.pageInfo]
        let reached = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "\(page) of \(Self.totalPages)"), object: info
        )
        return XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(15)) == .completed
    }

    /// Wait until the app reports the simulated Duo window (`DuoShellJourneyTests`).
    ///
    /// - Parameters:
    ///   - pose: Expected `DebugDuoWindow` raw value.
    ///   - app: The running app.
    @MainActor
    private func waitForDuoWindow(_ pose: String, in app: XCUIApplication) {
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let reached = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "\(pose) "), object: readout
        )
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
                       "The app never simulated \(pose): \(readout.exists ? readout.label : "no readout")")
    }
}
