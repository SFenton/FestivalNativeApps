import UIKit
import XCTest

/// Accessibility at the largest text size for the Song Leaderboard's end of list (issue
/// #456, for #293). #293 removed the header gradient and rested the last row one 8 pt
/// row gap above the pinned footer, or above the pager without one, with the bottom fade
/// shrinking away at the end. macOS has no Dynamic Type, so the hosted
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

    /// Portrait with a selected player: the last row rests one row gap above the footer.
    @MainActor
    func testLastRowRestsAboveFooterAtLargestText() throws {
        try assertEndOfList(.portrait, withPlayer: true, duoWindow: nil)
    }

    /// Portrait with no player: no footer, and the last row rests one row gap above the pager.
    @MainActor
    func testLastRowRestsAbovePagerAtLargestText() throws {
        try assertEndOfList(.portrait, withPlayer: false, duoWindow: nil)
    }

    /// iPad landscape: a shorter board between the bars. iPhone is portrait-only.
    @MainActor
    func testLastRowRestsAboveFooterAtLargestTextLandscape() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone, "iPhone runs portrait only")
        try assertEndOfList(.landscapeLeft, withPlayer: true, duoWindow: nil)
    }

    /// iPhone Duo folded (outer display, vertical bar trailing).
    @MainActor
    func testLastRowRestsAboveFooterAtLargestTextDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertEndOfList(.portrait, withPlayer: true, duoWindow: "folded")
    }

    // MARK: - Assertions

    /// At AX5 the board's rows grow; the footer (with a player) is one named 44 pt
    /// button and nothing reads a rank without one; the pager's arrows keep their names,
    /// page-1 states, order and 44 pt targets on screen; VoiceOver reads the rows, then
    /// the footer, then the pager; the system audit (Dynamic Type, clipped text,
    /// descriptions, hit regions) passes for the board; and at the end of the page the
    /// last row rests whole, reachable and named, one row gap above the chrome.
    ///
    /// - Parameters:
    ///   - orientation: Device orientation for the run.
    ///   - withPlayer: Select `fixture-player-2` (an Open footer) rather than no player.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Throws: A skip when the board never loads, or a failed requirement.
    @MainActor
    private func assertEndOfList(_ orientation: UIDeviceOrientation, withPlayer: Bool, duoWindow: String?) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation
        defer { XCUIDevice.shared.orientation = .portrait }
        let (app, window) = try launchBoard(withPlayer: withPlayer, duoWindow: duoWindow)
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)), "No rows")
        let footer = app.buttons[Self.footerID]
        if withPlayer {
            XCTAssertTrue(footer.waitForExistence(timeout: FestivalApp.budget(10)), "No player footer")
        }

        // Rows grew to AX5: at least one body line per row.
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ).lineHeight
        XCTAssertGreaterThanOrEqual(rows.firstMatch.frame.height, bodyLine, "Row not at AX5: \(rows.firstMatch.frame)")

        let pagerTop = assertPager(in: app, window: window)
        let chromeTop: CGFloat
        if withPlayer {
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
            chromeTop = frame.minY
        } else {
            XCTAssertFalse(footer.exists, "A footer without a selected player")
            XCTAssertFalse(
                app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Your rank")).firstMatch.exists,
                "Something reads a rank without a selected player"
            )
            chromeTop = pagerTop
        }
        try assertReadingOrder(withPlayer: withPlayer, in: app)

        // The system audit at AX5, for the board only (the shell has its own). Contrast
        // is left to the hosted checks: rows crossing the fade read below 4.5:1 by design.
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion]
        ) { issue in
            !(issue.element?.identifier.hasPrefix("fst.song-leaderboard.") ?? false)
        }

        assertLastRowRestsAboveChrome(rows, chromeTop: chromeTop, in: app, window: window)
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

    /// Scroll to the end of the page: the last row (rank 25) rests whole, one row gap
    /// above the chrome's first element, reachable and named.
    ///
    /// - Parameters:
    ///   - rows: The rows.
    ///   - chromeTop: Top of the footer, or of the pager without one.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    @MainActor
    private func assertLastRowRestsAboveChrome(
        _ rows: XCUIElementQuery, chromeTop: CGFloat, in app: XCUIApplication, window: CGRect
    ) {
        // Flick up from just above the chrome, inside the rows (at AX5 the footer and
        // pager fill much of the screen), until two flicks leave the bottom row in place.
        // With a footer only ~64 pt of rows show, so plain drags took some 40 gestures to
        // reach rank 25 on iPhone; a fast flick carries on with momentum (#620).
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
        let last = app.descendants(matching: .any).matching(identifier: "\(Self.rowPrefix)fixture-player-25").firstMatch
        XCTAssertTrue(last.exists, "The page's last row is not realized at its end: bottom row \(lastFrame), chrome \(chromeTop)")
        let frame = last.frame
        XCTAssertLessThanOrEqual(frame.maxY, chromeTop + 0.5, "Last row under the chrome: \(frame) vs \(chromeTop)")
        XCTAssertEqual(
            chromeTop - frame.maxY, Self.rowGap, accuracy: Self.gapTolerance,
            "Last row does not rest one row gap above the chrome: \(frame) vs \(chromeTop)"
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
