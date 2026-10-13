import UIKit
import XCTest

// MARK: - Duo board pager at AX5 (issue #481, for #345)

/// The in-content pager #345 put back under each paged board on the iPhone Duo vertical
/// bar, replacing the rail's First, Previous, Next and Last toolbar items, at the largest
/// accessibility size (AX5) on the Debug `DebugDuoWindow` simulation (as
/// `SongLeaderboardEndJourneyTests`' folded case and `BoardFooterFadeJourneyTests`).
///
/// For Band Rankings (`RankingsFloatingBar`, which shows the pager alone on the vertical
/// bar while the band-size menu moves to the rail) and the song board
/// (`RankingsPagerView`, with `fixture-player-2` selected), folded and unfolded:
///
/// - each pager control is exactly one element, in the board and not in a toolbar,
///   navigation bar or tab bar (no rail copy), with the page laid out for the vertical bar;
/// - the arrows are named buttons with their page-1 states, the badge reads "Page" with
///   "1 of N", and the controls run left to right as 44 pt targets wholly on screen;
/// - the selected player's row is one named, reachable 44 pt button above the pager: pinned
///   only while it takes at most a third of the window, else after the page's rows, where
///   the journey scrolls to it (leaderboard-row R12, #386; as `SongLeaderboardEndJourneyTests`
///   since #620);
/// - VoiceOver reads the rows, then the selected row, then the pager in visual order (fixed:
///   `RankingsPagerView`'s controls were loose among the pinned row, so iOS read the
///   taller AX5 badge before First and, unfolded, the pinned row after the pager);
/// - Band Rankings' band-size menu stays one named rail button ("Band size", "Duos");
/// - the scoped system audit (Dynamic Type, clipped text, hit regions, descriptions)
///   passes for the board's own elements.
///
/// The simulation keeps the real iPhone window, so no hinge crosses the board and the
/// pager stays centred; `FestivalUITests/DuoBoardPagerAccessibilityTests` covers the
/// unfolded move to the screen beside the bar, the press on Next and every Duo pose
/// for names, roles, order and targets.
///
/// Needs `tools/mock_service.py` (`apple-ci` serves it with `--large-catalogue` on the
/// default port 8765; `FST_DUO_PAGER_FIXTURE_URL`, as `TEST_RUNNER_FST_DUO_PAGER_FIXTURE_URL`,
/// points a local run at another port). `apple-ci` runs it on its iPhone simulator
/// (`testing/apple/xcuitest.md#ci-journeys`). Skips off an iPhone, and when the board
/// never loads.
///
/// HIG Designing for iPhone Duo: "Keep controls near the content they affect". HIG
/// Accessibility: iOS default control size 44×44 pt. HIG Typography: "Keep text
/// truncation to a minimum as font size increases".
final class DuoBoardPagerAccessibilityJourneyTests: XCTestCase {
    private static let fixtureService = ProcessInfo.processInfo.environment["FST_DUO_PAGER_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    /// HIG Accessibility: iOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44
    /// The pager's controls after the identifier prefix, in visual and reading order.
    private static let pagerSuffixes = ["page-first", "page-previous", "page-info", "page-next", "page-last"]

    /// A board under test.
    private struct Board {
        /// Identifier prefix of the board's own elements (and its audit scope).
        let prefix: String
        /// Identifier prefix of the board's rows.
        let rowPrefix: String
        /// The selected player's row (pinned, or after the rows under R12), where one shows.
        let footer: String?
        /// The fixture board's page count.
        let totalPages: Int
        /// Launch environment for the board.
        let environment: [String: String]

        /// Band Rankings' Duos board: two bands, one page, no selected player.
        static let bandRankings = Board(
            prefix: "fst.band-rankings.", rowPrefix: "fst.band-rankings.row.", footer: nil, totalPages: 1,
            environment: ["FST_UI_TEST_CLEAR_PROFILE": "1", "FST_DEBUG_ROUTE": "bandRankings:Band_Duets"]
        )

        /// `fixture-pulse` Lead's song board (26 entries, two pages), `fixture-player-2`
        /// (ranked 2nd) selected: an Open row.
        static let song = Board(
            prefix: "fst.song-leaderboard.", rowPrefix: "fst.song-leaderboard.row.",
            footer: "fst.song-leaderboard.spotlight-open", totalPages: 2,
            environment: [
                "FST_UI_TEST_RESET_SONG_CARDS": "1",
                "FST_DEBUG_SONG": "fixture-pulse",
                "FST_DEBUG_SONG_INSTRUMENT": "Solo_Guitar",
                "FST_DEBUG_PROFILE": "fixture-player-2:Fixture Player 2",
            ]
        )

        func id(_ suffix: String) -> String { prefix + suffix }
    }

    /// The arrows with the word each name carries and whether page 1 of `total` enables it.
    private static func arrows(total: Int) -> [(suffix: String, word: String, enabled: Bool)] {
        [
            ("page-first", "First", false),
            ("page-previous", "Previous", false),
            ("page-next", "Next", total > 1),
            ("page-last", "Last", total > 1),
        ]
    }

    // MARK: - Journeys

    /// Band Rankings on the folded outer display (vertical bar trailing).
    @MainActor
    func testBandRankingsPagerIsAccessibleOnTheDuoFoldedBoardAtAX5() throws {
        try assertPagerOnBoard(.bandRankings, duoWindow: "folded")
    }

    /// Band Rankings on the unfolded inner display in landscape.
    @MainActor
    func testBandRankingsPagerIsAccessibleOnTheDuoUnfoldedBoardAtAX5() throws {
        try assertPagerOnBoard(.bandRankings, duoWindow: "unfolded-landscape")
    }

    /// The song board, with a selected player's row, on the folded outer display.
    @MainActor
    func testSongBoardPagerIsAccessibleOnTheDuoFoldedBoardAtAX5() throws {
        try assertPagerOnBoard(.song, duoWindow: "folded")
    }

    /// The song board, with a selected player's row, on the unfolded inner display.
    @MainActor
    func testSongBoardPagerIsAccessibleOnTheDuoUnfoldedBoardAtAX5() throws {
        try assertPagerOnBoard(.song, duoWindow: "unfolded-landscape")
    }

    // MARK: - Assertions

    /// Launch `board` at AX5 in the simulated Duo window and check its pager, selected
    /// row, reading order, rail item and audit.
    ///
    /// - Parameters:
    ///   - board: The board.
    ///   - duoWindow: `DebugDuoWindow` to simulate.
    /// - Throws: A skip off an iPhone or when the board never loads, or a failed requirement.
    @MainActor
    private func assertPagerOnBoard(_ board: Board, duoWindow: String) throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        continueAfterFailure = false
        let (app, window) = try launch(board, duoWindow: duoWindow)
        let context = "\(board.prefix) \(duoWindow) AX5"

        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", board.rowPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)), "No rows (\(context))")
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ).lineHeight
        XCTAssertGreaterThanOrEqual(rows.firstMatch.frame.height, bodyLine, "Row not at AX5 (\(context)): \(rows.firstMatch.frame)")

        // One pager, in the board: no toolbar or navigation-bar copy (the old rail).
        var frames: [CGRect] = []
        for suffix in Self.pagerSuffixes {
            let id = board.id(suffix)
            let matches = app.descendants(matching: .any).matching(identifier: id)
            XCTAssertEqual(matches.count, 1, "\(id) is not exactly one element (\(context))")
            XCTAssertEqual(app.toolbars.descendants(matching: .any).matching(identifier: id).count, 0,
                           "\(id) is in a toolbar (\(context))")
            XCTAssertEqual(app.navigationBars.descendants(matching: .any).matching(identifier: id).count, 0,
                           "\(id) is in a navigation bar (\(context))")
            XCTAssertEqual(app.tabBars.descendants(matching: .any).matching(identifier: id).count, 0,
                           "\(id) is in a tab bar (\(context))")
            let frame = matches.firstMatch.frame
            XCTAssertGreaterThanOrEqual(frame.width, Self.minimumTarget - 0.5, "\(id) target \(frame) (\(context))")
            XCTAssertGreaterThanOrEqual(frame.height, Self.minimumTarget - 0.5, "\(id) target \(frame) (\(context))")
            XCTAssertTrue(window.contains(frame), "\(id) off screen: \(frame) (\(context))")
            if let previous = frames.last {
                XCTAssertGreaterThanOrEqual(frame.minX, previous.maxX - 0.5, "\(id) drawn before its neighbour (\(context))")
            }
            frames.append(frame)
        }
        for arrow in Self.arrows(total: board.totalPages) {
            let button = app.buttons[board.id(arrow.suffix)]
            XCTAssertTrue(button.exists, "\(board.id(arrow.suffix)) is not a button (\(context))")
            XCTAssertTrue(button.label.localizedCaseInsensitiveContains(arrow.word),
                          "\(board.id(arrow.suffix)) reads '\(button.label)' (\(context))")
            XCTAssertEqual(button.isEnabled, arrow.enabled, "\(board.id(arrow.suffix)) enabled on page 1 (\(context))")
            if arrow.enabled { XCTAssertTrue(button.isHittable, "\(board.id(arrow.suffix)) is not reachable (\(context))") }
        }
        let info = app.descendants(matching: .any)[board.id("page-info")]
        XCTAssertEqual(info.label, "Page", "page badge name (\(context))")
        XCTAssertEqual(info.value as? String, "1 of \(board.totalPages)", "page badge value (\(context))")

        let pagerTop = frames.map(\.minY).min() ?? window.maxY
        if let footerID = board.footer {
            try assertSelectedRow(board, footerID: footerID, rows: rows, pagerTop: pagerTop, in: app, window: window,
                                  context: context)
        }
        if board.prefix == Board.bandRankings.prefix {
            try assertBandSizeRailItem(in: app, pager: frames, context: context)
        }
        try assertReadingOrder(board, in: app, context: context)
        try audit(board, in: app, context: context)
    }

    /// The selected player's row under leaderboard-row R12: it pins until measured, then
    /// stays pinned only if it takes at most a third of the window; otherwise it follows the
    /// page's rows, so the journey flicks to the end of the page to find it. Either way it is
    /// one named, reachable 44 pt button wholly on screen above the pager.
    ///
    /// - Parameters:
    ///   - board: The board.
    ///   - footerID: The selected row's button identifier.
    ///   - rows: The board's rows.
    ///   - pagerTop: Top of the pager's controls.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    ///   - context: Label for failure messages.
    @MainActor
    private func assertSelectedRow(
        _ board: Board, footerID: String, rows: XCUIElementQuery, pagerTop: CGFloat, in app: XCUIApplication,
        window: CGRect, context: String
    ) throws {
        let footer = app.buttons[footerID]
        let unpinned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !footer.exists || !footer.isHittable }, object: nil
        )
        let pinned = footer.waitForExistence(timeout: FestivalApp.budget(10))
            && XCTWaiter().wait(for: [unpinned], timeout: FestivalApp.budget(3)) == .timedOut
        if pinned {
            XCTAssertLessThanOrEqual(
                footer.frame.height, window.height / 3,
                "A pinned row covers over a third of the board (R12, \(context)): \(footer.frame)"
            )
        } else {
            // Too tall to pin at AX5, the row follows the page's rows (R12): only the end
            // of the page shows it, after the last row.
            scrollToEndOfPage(rows, above: pagerTop, in: app, window: window)
            XCTAssertTrue(footer.waitForExistence(timeout: FestivalApp.budget(10)),
                          "No selected row after the rows (\(context))")
        }
        let endPagerTop = app.descendants(matching: .any)[board.id("page-first")].frame.minY
        let frame = footer.frame
        XCTAssertFalse(footer.label.isEmpty, "The selected row has no name (\(context))")
        XCTAssertTrue(footer.isHittable, "The selected row is not reachable (\(context)): \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, Self.minimumTarget - 0.5, "Selected row target \(frame) (\(context))")
        XCTAssertTrue(window.contains(frame), "Selected row off screen: \(frame) (\(context))")
        XCTAssertLessThanOrEqual(frame.maxY, endPagerTop + 0.5, "Selected row under the pager: \(frame) vs \(endPagerTop) (\(context))")
    }

    /// Flick to the end of the page, until two flicks leave the bottom row in place (as
    /// `SongLeaderboardEndJourneyTests`: at AX5 plain drags took dozens of gestures).
    ///
    /// - Parameters:
    ///   - rows: The rows.
    ///   - chromeTop: Top of the pinned chrome: flicks start just above it, inside the rows.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    @MainActor
    private func scrollToEndOfPage(_ rows: XCUIElementQuery, above chromeTop: CGFloat, in app: XCUIApplication, window: CGRect) {
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

    /// Band Rankings' band-size menu: one named rail button, not part of the pager.
    ///
    /// - Parameters:
    ///   - app: The app on Band Rankings.
    ///   - pager: The pager's frames.
    ///   - context: Label for failure messages.
    @MainActor
    private func assertBandSizeRailItem(in app: XCUIApplication, pager: [CGRect], context: String) throws {
        let id = "fst.band-rankings.band-type-menu"
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: id).count, 1,
                       "the band-size menu is not one element (\(context))")
        let menu = app.buttons[id]
        XCTAssertTrue(menu.exists, "the band-size menu is not a button (\(context))")
        // A bar item's name carries its state in every bar (`festivalBarItemAccessibility`).
        XCTAssertTrue(menu.label.hasPrefix("Band size"), "band-size menu reads '\(menu.label)' (\(context))")
        XCTAssertTrue("\(menu.label) \(menu.value as? String ?? "")".contains("Duos"),
                      "band-size menu state reads '\(menu.label)' '\(menu.value ?? "")' (\(context))")
        XCTAssertTrue(menu.isHittable, "the band-size menu is not reachable (\(context)): \(menu.frame)")
        let span = pager.reduce(pager[0]) { $0.union($1) }
        XCTAssertFalse(span.intersects(menu.frame), "the band-size menu \(menu.frame) sits in the pager \(span) (\(context))")
    }

    /// VoiceOver reaches every realized row, then the selected row, then the pager left to
    /// right (`boardBottomChrome`, leaderboard-row R5 and R12).
    ///
    /// - Parameters:
    ///   - board: The board.
    ///   - app: The running app.
    ///   - context: Label for failure messages.
    /// - Throws: An unavailable accessibility snapshot.
    @MainActor
    private func assertReadingOrder(_ board: Board, in app: XCUIApplication, context: String) throws {
        var identifiers: [String] = []
        var tree: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty {
                identifiers.append(element.identifier)
                tree.append("\(identifiers.count - 1) \(element.identifier) \(element.frame)")
            }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        let lastRow = try XCTUnwrap(identifiers.lastIndex { $0.hasPrefix(board.rowPrefix) }, "No row in the tree (\(context))")
        let chrome = (board.footer.map { [$0] } ?? []) + Self.pagerSuffixes.map(board.id)
        let positions = try chrome.map { id in
            try XCTUnwrap(identifiers.firstIndex(of: id), "\(id) not in the tree (\(context))")
        }
        XCTAssertTrue(positions.allSatisfy { $0 > lastRow }, "The chrome \(positions) reads before a row \(lastRow) (\(context))")
        XCTAssertEqual(positions, positions.sorted(), "Selected row, then the pager left to right (\(context)): \(chrome)\n\(tree.joined(separator: "\n"))")
    }

    /// The system audit at AX5 for the board's own elements (the shell has its own).
    /// Contrast is left to the hosted checks: rows crossing the bottom fade read below
    /// 4.5:1 by design.
    ///
    /// - Parameters:
    ///   - board: The board.
    ///   - app: The running app.
    ///   - context: Label for failure messages.
    @MainActor
    private func audit(_ board: Board, in app: XCUIApplication, context: String) throws {
        var issues: [String] = []
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        ) { issue in
            let id = issue.element?.identifier ?? ""
            guard id.hasPrefix(board.prefix) else { return true }
            issues.append("\(id) '\(issue.element?.label ?? "")': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Board audit issues (\(context))")
    }

    // MARK: - Launch

    /// Launch `board` at AX5 in the simulated Duo window.
    ///
    /// - Parameters:
    ///   - board: The board.
    ///   - duoWindow: `DebugDuoWindow` to simulate.
    /// - Returns: The app with its pager loaded, and the window's frame.
    /// - Throws: A skip when the board never loads.
    @MainActor
    private func launch(_ board: Board, duoWindow: String) throws -> (XCUIApplication, CGRect) {
        var environment = board.environment
        environment["FST_API_BASE_URL"] = Self.fixtureService
        environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
        environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        let app = FestivalApp.makeApp(environment)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        app.launch()
        guard app.descendants(matching: .any)[board.id("page-info")].waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("The board never loaded; run tools/mock_service.py on \(Self.fixtureService).")
        }
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let reached = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "\(duoWindow) "), object: readout
        )
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
                       "The app never simulated \(duoWindow): \(readout.exists ? readout.label : "no readout")")
        // The pages lay out for the vertical bar (the rail's items, the pager alone in
        // the floating bar); the simulation keeps the system tab bar's drawing.
        XCTAssertTrue(readout.label.contains("chrome=verticalBar"), "Not laid out for the vertical bar: \(readout.label)")
        return (app, app.windows.firstMatch.frame)
    }
}
