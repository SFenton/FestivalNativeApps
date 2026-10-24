import UIKit
import XCTest

/// Accessibility at the largest text size for the Song Leaderboard's end of list (issue
/// #456, for #293). #293 removed the header gradient and rested the last row one 8 pt
/// row gap above the pinned footer, or above the pager without one, with the bottom fade
/// shrinking away at the end. Since #386 (leaderboard-row R12) a player's row that would
/// cover more than a third of the board at AX5 follows the rows instead of pinning: on an
/// iPhone and the folded Duo the last row then rests one row gap above that row at the
/// end of the page, and the row one row gap above the pager; an iPad keeps the placement
/// its measured board gives (#620). macOS has no Dynamic Type, so the hosted
/// `SoloLeaderboardEndAccessibilityTests` cannot show AX5; this journey does, on
/// `fixture-pulse` Lead (26 rows, 25 a page) with `fixture-player-2` selected (ranked
/// 2nd: an Open footer) and with no player (no footer), in each iOS form: iPhone
/// portrait, iPad portrait and landscape, and the iPhone Duo outer display (the Debug
/// `DebugDuoWindow` simulation, as `BoardFooterFadeJourneyTests`).
///
/// Runs against `tools/mock_service.py` on `:8765` (the `apple-ci` simulator steps'
/// `--large-catalogue` fixture); set `FST_SONG_BOARD_END_FIXTURE_URL` (as
/// `TEST_RUNNER_FST_SONG_BOARD_END_FIXTURE_URL`) to use another port. Skips when the
/// board never loads.
final class SongLeaderboardEndJourneyTests: XCTestCase {
    private static let rowPrefix = "fst.song-leaderboard.row."
    private static let footerID = "fst.song-leaderboard.spotlight-open"
    /// The footer's visible row around its Open button.
    private static let footerCardID = "fst.song-leaderboard.spotlight-footer"
    /// The pager's arrows, in reading order around the page badge, with the word each
    /// name carries and whether page 1 enables it.
    private static let pagerArrows = [
        (id: "fst.song-leaderboard.page-first", word: "First", enabled: false),
        (id: "fst.song-leaderboard.page-previous", word: "Previous", enabled: false),
        (id: "fst.song-leaderboard.page-next", word: "Next", enabled: true),
        (id: "fst.song-leaderboard.page-last", word: "Last", enabled: true),
    ]
    private static let pageInfo = "fst.song-leaderboard.page-info"
    /// The row gap the last row rests above the chrome by (#293).
    private static let rowGap: CGFloat = 8
    /// Layout rounding allowed on that gap.
    private static let gapTolerance: CGFloat = 2
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44
    /// The selected fixture player: ranked 2nd on `fixture-pulse` Lead.
    private static let player = (id: "fixture-player-2", name: "Fixture Player 2", rank: "2nd")

    // MARK: - Journeys

    /// Portrait with a selected player: the last row rests one row gap above the footer,
    /// which follows the rows on an iPhone (R12) and goes where the iPad's board puts it.
    @MainActor
    func testLastRowRestsAboveFooterAtLargestText() throws {
        let footer: FooterPlacement = UIDevice.current.userInterfaceIdiom == .pad ? .measured : .afterRows
        try assertEndOfList(.portrait, footer: footer, duoWindow: nil)
    }

    /// Portrait with no player: no footer, and the last row rests one row gap above the pager.
    @MainActor
    func testLastRowRestsAbovePagerAtLargestText() throws {
        try assertEndOfList(.portrait, footer: nil, duoWindow: nil)
    }

    /// iPad landscape: a shorter board between the bars. iPhone is portrait-only.
    @MainActor
    func testLastRowRestsAboveFooterAtLargestTextLandscape() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone, "iPhone runs portrait only")
        try assertEndOfList(.landscapeLeft, footer: .measured, duoWindow: nil)
    }

    /// iPhone Duo folded (outer display, vertical bar trailing).
    @MainActor
    func testLastRowRestsAboveFooterAtLargestTextDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertEndOfList(.portrait, footer: .afterRows, duoWindow: "folded")
    }

    // MARK: - Assertions

    /// Where leaderboard-row R12 puts the selected player's row at AX5 on a form.
    enum FooterPlacement {
        /// Pinned above the pager (R7): it takes at most a third of the board.
        case pinned
        /// After the page's rows, above the pager: pinned, it would cover more than a third.
        case afterRows
        /// Whichever the board settles on once it has measured the row (iPad: the board's
        /// height depends on the window), then checked as that placement.
        case measured
    }

    /// At AX5 the board's rows grow; the footer (with a player) is one named 44 pt
    /// button, pinned or after the rows as R12 places it, and nothing reads a rank without
    /// one; the pager's arrows keep their names, page-1 states, order and 44 pt targets on
    /// screen; VoiceOver reads the rows, then the footer, then the pager; the system audit
    /// (Dynamic Type, clipped text, descriptions, hit regions) passes for the board; and
    /// at the end of the page the last row rests whole, reachable and named, one row gap
    /// above the footer, or above the pager without one.
    ///
    /// - Parameters:
    ///   - orientation: Device orientation for the run.
    ///   - footer: Where the selected `fixture-player-2`'s Open footer goes, or nil for no
    ///     player.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Throws: A skip when the board never loads, or a failed requirement.
    @MainActor
    private func assertEndOfList(_ orientation: UIDeviceOrientation, footer placement: FooterPlacement?, duoWindow: String?) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        defer { XCUIDevice.shared.orientation = .portrait }
        let (app, window) = try launchBoard(withPlayer: placement != nil, duoWindow: duoWindow)
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)), "No rows")
        let footer = app.buttons[Self.footerID]

        // Rows grew to AX5: at least one body line per row.
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ).lineHeight
        XCTAssertGreaterThanOrEqual(rows.firstMatch.frame.height, bodyLine, "Row not at AX5: \(rows.firstMatch.frame)")

        let pagerTop = assertPager(in: app, window: window)
        // The row pins until it is measured, then leaves the chrome if it is too tall (R12).
        let unpinned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated { Self.footerLeftChrome(in: app, window: window) }
            }, object: nil
        )
        var resolved = placement
        switch placement {
        case .pinned:
            XCTAssertTrue(footer.waitForExistence(timeout: FestivalApp.budget(10)), "No player footer")
            XCTAssertEqual(
                XCTWaiter().wait(for: [unpinned], timeout: FestivalApp.budget(3)), .timedOut,
                "The player's footer left the chrome: \(footer.frame)"
            )
        case .afterRows:
            XCTAssertEqual(
                XCTWaiter().wait(for: [unpinned], timeout: FestivalApp.budget(10)), .completed,
                "The player's row stays pinned at AX5 over the board (R12): \(footer.frame)"
            )
        case .measured:
            // Measured before it first draws (iPad landscape), the row never pins; the
            // after-rows path still requires it at the page's end.
            let pinned = footer.waitForExistence(timeout: FestivalApp.budget(10))
                && XCTWaiter().wait(for: [unpinned], timeout: FestivalApp.budget(3)) == .timedOut
            resolved = pinned ? .pinned : .afterRows
        case nil:
            break
        }
        switch resolved {
        case .pinned, .measured:
            assertFooter(footer, above: pagerTop, window: window)
            XCTAssertLessThanOrEqual(
                footer.frame.height, window.height / 3, "A pinned footer covers over a third of the board (R12): \(footer.frame)"
            )
            try assertBoard(withPlayer: true, in: app)
            scrollToEndOfPage(rows, above: footer.frame.minY, in: app, window: window)
            assertLastRow(restsAbove: footer.frame.minY, in: app)
        case .afterRows:
            // Measured too tall to pin, the row left the chrome (R12): only the page's end
            // shows it, after rank 25.
            scrollToEndOfPage(rows, above: pagerTop, in: app, window: window)
            XCTAssertTrue(footer.waitForExistence(timeout: FestivalApp.budget(10)), "No player footer after the rows")
            // Scrolling down minimizes the tab bar, which lowers the pager.
            let endPagerTop = assertPager(in: app, window: window)
            assertFooter(footer, above: endPagerTop, window: window)
            // As a List row the Open button spans its cell, row insets included; the gaps
            // are the visible row's.
            let card = app.descendants(matching: .any)[Self.footerCardID]
            XCTAssertEqual(
                endPagerTop - card.frame.maxY, Self.rowGap, accuracy: Self.gapTolerance,
                "The footer does not rest one row gap above the pager: \(card.frame) vs \(endPagerTop)"
            )
            assertLastRow(restsAbove: card.frame.minY, in: app)
            // Measure before the audit: after it, XCUI saw no List cells at the end of the
            // page until the next scroll.
            try assertBoard(withPlayer: true, in: app)
        case nil:
            XCTAssertFalse(footer.exists, "A footer without a selected player")
            XCTAssertFalse(
                app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Your rank")).firstMatch.exists,
                "Something reads a rank without a selected player"
            )
            try assertBoard(withPlayer: false, in: app)
            scrollToEndOfPage(rows, above: pagerTop, in: app, window: window)
            assertLastRow(restsAbove: assertPager(in: app, window: window), in: app)
        }
    }

    /// Whether the player's footer has left the pinned chrome: gone from the tree or wholly
    /// off screen. Read from one accessibility snapshot, never `isHittable`: polled for
    /// seconds over a pinned footer, a slow runner's hit test once found no activation point
    /// on the visible, unmoving row and failed the journey outright (#682). A snapshot that
    /// fails, or a node with no frame yet, proves nothing and reads as still pinned; the
    /// footer's reachability is asserted once it has settled (``assertFooter(_:above:window:)``).
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - window: The app window's frame.
    /// - Returns: True once the footer is gone or off screen.
    @MainActor
    private static func footerLeftChrome(in app: XCUIApplication, window: CGRect) -> Bool {
        guard let nodes = try? FestivalApp.snapshotNodes(in: app, where: {
            $0.elementType == .button && $0.identifier == footerID
        }) else { return false }
        guard let node = nodes.first else { return true }
        return !node.frame.isEmpty && !window.intersects(node.frame)
    }

    /// The player's footer: one enabled, reachable, named 44 pt button on screen above the
    /// pager.
    ///
    /// - Parameters:
    ///   - footer: The footer's Open button.
    ///   - pagerTop: Top of the pager's controls.
    ///   - window: The app window's frame.
    @MainActor
    private func assertFooter(_ footer: XCUIElement, above pagerTop: CGFloat, window: CGRect) {
        let frame = footer.frame
        XCTAssertTrue(
            footer.label.hasPrefix("Your rank, \(Self.player.rank).") && footer.label.hasSuffix("Open your statistics."),
            "Footer reads \(footer.label)"
        )
        XCTAssertTrue(footer.isEnabled, "Footer is not enabled")
        XCTAssertTrue(footer.isHittable, "Footer is not reachable: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, Self.minimumTarget - 0.5, "Footer target \(frame)")
        XCTAssertTrue(window.contains(frame), "Footer off screen: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxY, pagerTop + 0.5, "Footer under the pager: \(frame) vs \(pagerTop)")
    }

    /// VoiceOver order, then the system audit at AX5 for the board only (the shell has its
    /// own). Contrast is left to the hosted checks: rows crossing the fade read below 4.5:1
    /// by design.
    ///
    /// - Parameters:
    ///   - withPlayer: Whether a footer shows.
    ///   - app: The running app.
    /// - Throws: An unavailable accessibility snapshot or a failed audit.
    @MainActor
    private func assertBoard(withPlayer: Bool, in app: XCUIApplication) throws {
        try assertReadingOrder(withPlayer: withPlayer, in: app)
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion]
        ) { issue in
            !(issue.element?.identifier.hasPrefix("fst.song-leaderboard.") ?? false)
        }
    }

    /// The pager on page 1: each arrow a named 44 pt button on screen, in reading order,
    /// enabled only where it can move; the badge between them.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - window: The app window's frame.
    /// - Returns: The top of the pager's controls.
    @MainActor
    private func assertPager(in app: XCUIApplication, window: CGRect) -> CGFloat {
        let info = app.descendants(matching: .any)[Self.pageInfo]
        XCTAssertTrue(info.exists, "No page badge")
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
            XCTAssertEqual(button.isEnabled, arrow.enabled, "\(arrow.id) enabled on page 1")
            if arrow.enabled { XCTAssertTrue(button.isHittable, "\(arrow.id) is not reachable") }
        }
        return pagerTop
    }

    /// VoiceOver reaches every realized row before the footer, and the footer before the
    /// pager (`boardBottomChrome`, leaderboard-row R5).
    ///
    /// - Parameters:
    ///   - withPlayer: Whether a footer shows.
    ///   - app: The running app.
    /// - Throws: An unavailable accessibility snapshot.
    @MainActor
    private func assertReadingOrder(withPlayer: Bool, in app: XCUIApplication) throws {
        var identifiers: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty { identifiers.append(element.identifier) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        let lastRow = try XCTUnwrap(identifiers.lastIndex { $0.hasPrefix(Self.rowPrefix) }, "No row in the tree")
        let firstPager = try XCTUnwrap(
            identifiers.firstIndex { $0.hasPrefix("fst.song-leaderboard.page-") }, "No pager in the tree"
        )
        XCTAssertLessThan(lastRow, firstPager, "The pager reads before a row")
        if withPlayer {
            let footer = try XCTUnwrap(identifiers.firstIndex(of: Self.footerID), "No footer in the tree")
            XCTAssertLessThan(lastRow, footer, "The footer reads before a row")
            XCTAssertLessThan(footer, firstPager, "The pager reads before the footer")
        }
    }

    /// Flick to the end of the page, until two flicks leave the bottom row in place.
    ///
    /// - Parameters:
    ///   - rows: The rows.
    ///   - chromeTop: Top of the pinned chrome: flicks start just above it, inside the
    ///     rows (at AX5 the footer and pager fill much of the screen).
    ///   - app: The running app.
    ///   - window: The app window's frame.
    @MainActor
    private func scrollToEndOfPage(_ rows: XCUIElementQuery, above chromeTop: CGFloat, in app: XCUIApplication, window: CGRect) {
        // With a pinned footer only ~64 pt of rows show, so plain drags took some 40
        // gestures to reach rank 25 on iPhone; a fast flick carries on with momentum (#620).
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let startY = chromeTop - 16
        let distance = min(window.height * 0.3, max(startY - window.minY - 160, 60))
        var lastFrame = CGRect.null
        var unchanged = 0
        for _ in 0..<60 where unchanged < 2 {
            let start = origin.withOffset(CGVector(dx: window.midX - window.minX, dy: startY - window.minY))
            start.press(
                forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                withVelocity: .fast, thenHoldForDuration: 0
            )
            let bottom = rows.allElementsBoundByIndex.map(\.frame).filter { window.intersects($0) }
                .max { $0.maxY < $1.maxY } ?? .null
            unchanged = bottom == lastFrame ? unchanged + 1 : 0
            lastFrame = bottom
        }
    }

    /// At the end of the page the last row (rank 25) rests whole, one row gap above the
    /// next element, reachable and named.
    ///
    /// - Parameters:
    ///   - nextTop: Top of the footer, or of the pager without one.
    ///   - app: The running app.
    @MainActor
    private func assertLastRow(restsAbove nextTop: CGFloat, in app: XCUIApplication) {
        let last = app.descendants(matching: .any).matching(identifier: "\(Self.rowPrefix)fixture-player-25").firstMatch
        XCTAssertTrue(last.exists, "The page's last row is not realized at its end (next element at \(nextTop))")
        let frame = last.frame
        XCTAssertLessThanOrEqual(frame.maxY, nextTop + 0.5, "Last row under the next element: \(frame) vs \(nextTop)")
        XCTAssertEqual(
            nextTop - frame.maxY, Self.rowGap, accuracy: Self.gapTolerance,
            "Last row does not rest one row gap above the next element: \(frame) vs \(nextTop)"
        )
        let button = last.buttons.firstMatch.exists ? last.buttons.firstMatch : last
        XCTAssertTrue(button.isHittable, "Last row is not reachable: \(frame)")
        XCTAssertTrue(button.isEnabled, "Last row is not enabled")
        XCTAssertTrue(button.label.contains("Fixture Player 25"), "Last row reads \(button.label)")
        XCTAssertTrue(app.buttons["fst.song-leaderboard.page-next"].isHittable, "Pager lost at the end of the page")
    }

    // MARK: - Helpers

    /// Launch `fixture-pulse` Lead's board at AX5 against the fixture.
    ///
    /// - Parameters:
    ///   - withPlayer: Select `fixture-player-2` rather than no player.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Returns: The app and its window's frame.
    /// - Throws: A skip when the board never loads.
    @MainActor
    private func launchBoard(withPlayer: Bool, duoWindow: String?) throws -> (XCUIApplication, CGRect) {
        let base = ProcessInfo.processInfo.environment["FST_SONG_BOARD_END_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
        var environment = [
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_SONG": "fixture-pulse",
            "FST_DEBUG_SONG_INSTRUMENT": "Solo_Guitar",
        ]
        if withPlayer {
            environment["FST_DEBUG_PROFILE"] = "\(Self.player.id):\(Self.player.name)"
        } else {
            environment["FST_DEBUG_ANONYMOUS"] = "1"
        }
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
            throw XCTSkip("The song leaderboard never loaded; run tools/mock_service.py on \(base).")
        }
        if let duoWindow { waitForDuoWindow(duoWindow, in: app) }
        return (app, app.windows.firstMatch.frame)
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
