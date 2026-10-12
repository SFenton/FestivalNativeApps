import UIKit
import XCTest

/// Accessibility of a full leaderboard in two columns at the largest text size (issue
/// #484, for #353). #353 pairs a full board's rows in two row-major columns when the
/// board fills a wide landscape window (pattern `wide-columns` R1/R2/R8): iPad landscape
/// and the unfolded iPhone Duo. macOS has no Dynamic Type, so the hosted
/// `WideBoardColumnsAccessibilityTests` check the stacked rows' structure; this journey
/// opens Lead Full Rankings and Duets Band Rankings full width in landscape at AX5 and
/// checks that the rows still pair, every row is one named, reachable 44 pt button whose
/// text grew and that sits wholly on screen, VoiceOver reads the ranks left then right and
/// then down (the drawn order) before the pager, and the system audit passes for the board.
///
/// Runs against `tools/mock_service.py --large-catalogue` on `:8765` (the `apple-ci` iPad
/// step's fixture: three ranked accounts, two Duets teams); set `FST_FIXTURE_URL` (as
/// `TEST_RUNNER_FST_FIXTURE_URL`) to use another port. Skips when the board never loads,
/// and on iPhone, which runs portrait only (one column).
final class WideBoardColumnsJourneyTests: XCTestCase {
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44

    /// A board the fixture fills with at least two rows.
    private struct Board {
        let route: String
        let rows: [String]
        let pagerPrefix: String

        /// The prefix every row identifier shares.
        var rowPrefix: String { board(rows[0]) + ".row." }
        /// The prefix of the board's own chrome (pager, pinned row).
        var chromePrefix: String { String(pagerPrefix.dropLast("page-".count)) }

        private func board(_ row: String) -> String { row.components(separatedBy: ".row.")[0] }
    }

    private static let fullRankings = Board(
        route: "fullRankings:Solo_Guitar",
        rows: ["fixture-player-1", "fixture-player-2", "fixture-rank-3"].map { "fst.rankings.row.\($0)" },
        pagerPrefix: "fst.full-rankings.page-"
    )
    private static let bandRankings = Board(
        route: "bandRankings:Band_Duets",
        rows: ["fixture-team-1", "fixture-team-2"].map { "fst.band-rankings.row.\($0)" },
        pagerPrefix: "fst.band-rankings.page-"
    )

    // MARK: - Journeys

    /// Full Rankings: ranks 1 and 2 pair on the first line, rank 3 starts the second.
    @MainActor
    func testFullRankingsTwoColumnsAreAccessibleAtLargestText() throws {
        try assertTwoColumnBoard(Self.fullRankings)
    }

    /// Band Rankings: the two Duets teams pair on one line.
    @MainActor
    func testBandRankingsTwoColumnsAreAccessibleAtLargestText() throws {
        try assertTwoColumnBoard(Self.bandRankings)
    }

    // MARK: - Assertions

    /// At AX5 in landscape the board pairs its rows; each row is a named, hittable 44 pt
    /// button on screen whose text grew; rows read in rank order (row-major) before the
    /// pager; the system audit passes for the board.
    ///
    /// - Parameter board: The board to open.
    /// - Throws: A skip on iPhone or when the board never loads, or a failed requirement.
    @MainActor
    private func assertTwoColumnBoard(_ board: Board) throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone, "iPhone runs portrait only (one column)")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = try launch(board)
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "Not landscape: \(window)")

        let rows = board.rows.map { app.buttons[$0] }
        for (row, id) in zip(rows, board.rows) {
            XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(10)), "\(id) is not a button")
        }
        // Two columns are in effect: rank 2 beside rank 1, rank 3 under rank 1.
        let first = rows[0].frame, second = rows[1].frame
        XCTAssertEqual(first.minY, second.minY, accuracy: 1, "Rank 2 is not beside rank 1: \(first) \(second)")
        XCTAssertGreaterThan(second.minX, first.maxX, "Rank 2 is not beside rank 1: \(first) \(second)")
        if rows.count > 2 {
            let third = rows[2].frame
            XCTAssertEqual(third.minX, first.minX, accuracy: 1, "Rank 3 does not start a line: \(third)")
            XCTAssertGreaterThanOrEqual(third.minY, first.maxY - 0.5, "Rank 3 does not start a line: \(third)")
        }

        // Text grew to AX5: a stacked row holds at least two body lines.
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ).lineHeight
        for (row, id) in zip(rows, board.rows) {
            let frame = row.frame
            XCTAssertFalse(row.label.isEmpty, "\(id) has no name")
            XCTAssertFalse(row.label.contains("fst."), "\(id) reads its identifier: \(row.label)")
            XCTAssertTrue(row.isHittable, "\(id) is not reachable")
            XCTAssertGreaterThanOrEqual(frame.width, Self.minimumTarget - 0.5, "\(id) target \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, bodyLine * 2, "\(id) not at AX5: \(frame)")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(id) runs off screen: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(id) runs off screen: \(frame)")
        }

        try assertReadingOrder(board, in: app)

        // The system audit at AX5, for the board only (the shell has its own). Contrast is
        // left to the hosted checks: rows crossing the fade read below 4.5:1 by design.
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion]
        ) { issue in
            let identifier = issue.element?.identifier ?? ""
            return !(identifier.hasPrefix(board.chromePrefix) || identifier.hasPrefix(board.rowPrefix))
        }
    }

    /// VoiceOver reads the board's ranks consecutively in rank order, which is the drawn
    /// order (each line left to right, then down), and every row before the pager.
    ///
    /// - Parameters:
    ///   - board: The open board.
    ///   - app: The running app.
    /// - Throws: An unavailable accessibility snapshot.
    @MainActor
    private func assertReadingOrder(_ board: Board, in app: XCUIApplication) throws {
        var identifiers: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty { identifiers.append(element.identifier) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        let rowPrefix = board.rowPrefix
        let read = identifiers.filter { $0.hasPrefix(rowPrefix) }
        XCTAssertEqual(Array(read.prefix(board.rows.count)), board.rows, "Ranks read out of order: \(read)")
        let lastRow = try XCTUnwrap(identifiers.lastIndex { $0.hasPrefix(rowPrefix) }, "No row in the tree")
        let firstPager = try XCTUnwrap(
            identifiers.firstIndex { $0.hasPrefix(board.pagerPrefix) }, "No pager in the tree"
        )
        XCTAssertLessThan(lastRow, firstPager, "The pager reads before a row")
    }

    // MARK: - Helpers

    /// Launch `board` full width at AX5 against the fixture.
    ///
    /// - Parameter board: The board to open.
    /// - Returns: The running app.
    /// - Throws: A skip when the board never loads.
    @MainActor
    private func launch(_ board: Board) throws -> XCUIApplication {
        let base = ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_DEBUG_ROUTE": board.route,
        ])
        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", ax5.rawValue]
        app.launch()
        guard app.descendants(matching: .any)[board.pagerPrefix + "info"]
            .waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("The board never loaded; run tools/mock_service.py --large-catalogue on \(base).")
        }
        return app
    }
}
