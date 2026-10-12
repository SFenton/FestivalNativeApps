import UIKit
import XCTest

/// Accessibility at the largest text size while the Song Leaderboard pages (issue #464,
/// for #316). #316 kept the song header across page changes and swapped only the rows
/// (`FestivalReloadGate`'s retained frame, load-transition R4). macOS has no Dynamic
/// Type, so the hosted `SoloLeaderboardPagingAccessibilityTests` (which hold a page to
/// read the loading state) cannot show AX5; this journey pages `fixture-pulse` Lead (26
/// rows, two pages) with no player at AX5 and checks, on each page, that the header is
/// one named heading that never leaves, VoiceOver reads it before the rows and the rows
/// before the pager, the pager's arrows keep their names, page states and 44 pt targets,
/// and the system audit (Dynamic Type, clipped text, descriptions, hit regions) passes.
///
/// Runs against `tools/mock_service.py` on `:8765` (the `apple-ci` simulator steps'
/// `--large-catalogue` fixture); set `FST_SONG_BOARD_PAGING_FIXTURE_URL` (as
/// `TEST_RUNNER_FST_SONG_BOARD_PAGING_FIXTURE_URL`) to use another port. Skips when the
/// board never loads.
final class SongLeaderboardPagingJourneyTests: XCTestCase {
    private static let headerID = "fst.song-leaderboard.header"
    private static let rowPrefix = "fst.song-leaderboard.row."
    private static let pageInfo = "fst.song-leaderboard.page-info"
    /// The pager's arrows in reading order around the badge, the word each name carries
    /// and whether it moves backward.
    private static let pagerArrows = [
        (id: "fst.song-leaderboard.page-first", word: "First", backward: true),
        (id: "fst.song-leaderboard.page-previous", word: "Previous", backward: true),
        (id: "fst.song-leaderboard.page-next", word: "Next", backward: false),
        (id: "fst.song-leaderboard.page-last", word: "Last", backward: false),
    ]
    /// `fixture-pulse` Lead's pages in the `--large-catalogue` fixture (26 rows, 25 a page).
    private static let pageCount = 2
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44

    // MARK: - Journey

    /// Next, then Previous, at AX5: the header stays one named heading and reads first
    /// on each page, only the rows change, and the pager and audit pass on both pages.
    @MainActor
    func testPagingKeepsHeaderReadableAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = try launchBoard()
        let window = app.windows.firstMatch.frame
        let header = app.descendants(matching: .any).matching(identifier: Self.headerID).firstMatch
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))

        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)), "Page 1 rows did not load")
        let firstPageRow = rows.firstMatch.identifier
        try assertPage(1, header: header, rows: rows, in: app, window: window)

        app.buttons[Self.pagerArrows[2].id].tap()
        XCTAssertTrue(header.exists, "The song header left with the rows on Next")
        try waitForPage(2, in: app)
        let secondPageRow = rows.firstMatch
        XCTAssertTrue(secondPageRow.waitForExistence(timeout: FestivalApp.budget(10)), "Page 2 rows did not load")
        XCTAssertNotEqual(secondPageRow.identifier, firstPageRow, "Page 2 still shows page 1's rows")
        try assertPage(2, header: header, rows: rows, in: app, window: window)

        app.buttons[Self.pagerArrows[1].id].tap()
        XCTAssertTrue(header.exists, "The song header left with the rows on Previous")
        try waitForPage(1, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: firstPageRow).firstMatch
                .waitForExistence(timeout: FestivalApp.budget(10)),
            "Page 1 rows did not return"
        )
        try assertPage(1, header: header, rows: rows, in: app, window: window)
    }

    // MARK: - Assertions

    /// One page at AX5: the header is one named heading on screen, its rows grew, the
    /// reading order is header, rows, pager; the pager is right for `page`; the audit passes.
    ///
    /// - Parameters:
    ///   - page: The page shown.
    ///   - header: The song header.
    ///   - rows: The board's rows.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    /// - Throws: An unavailable snapshot or a failed audit.
    @MainActor
    private func assertPage(
        _ page: Int, header: XCUIElement, rows: XCUIElementQuery, in app: XCUIApplication, window: CGRect
    ) throws {
        XCTAssertTrue(header.exists, "The song header is missing on page \(page)")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: Self.headerID).count, 1,
            "One song header on page \(page)"
        )
        for part in ["Fixture Pulse", "Lead"] {
            XCTAssertTrue(header.label.contains(part), "The header reads \(part) on page \(page): \(header.label)")
        }
        XCTAssertFalse(header.frame.isEmpty, "The header has a frame on page \(page)")
        XCTAssertTrue(window.intersects(header.frame), "The header is on screen on page \(page): \(header.frame)")

        // Rows grew to AX5: at least one body line per row.
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ).lineHeight
        XCTAssertGreaterThanOrEqual(rows.firstMatch.frame.height, bodyLine, "Row not at AX5: \(rows.firstMatch.frame)")

        try assertReadingOrder(page, in: app)
        assertPager(page, in: app, window: window)

        // The system audit at AX5, for the board only (the shell has its own). Contrast
        // is left to the hosted checks: rows crossing the fade read below 4.5:1 by design.
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion]
        ) { issue in
            !(issue.element?.identifier.hasPrefix("fst.song-leaderboard.") ?? false)
        }
    }

    /// VoiceOver reaches the header before every row and every row before the pager.
    ///
    /// - Parameters:
    ///   - page: The page shown.
    ///   - app: The running app.
    /// - Throws: An unavailable accessibility snapshot.
    @MainActor
    private func assertReadingOrder(_ page: Int, in app: XCUIApplication) throws {
        var identifiers: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty { identifiers.append(element.identifier) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        let header = try XCTUnwrap(identifiers.firstIndex(of: Self.headerID), "No header in the tree on page \(page)")
        let firstRow = try XCTUnwrap(identifiers.firstIndex { $0.hasPrefix(Self.rowPrefix) }, "No row on page \(page)")
        let lastRow = try XCTUnwrap(identifiers.lastIndex { $0.hasPrefix(Self.rowPrefix) }, "No row on page \(page)")
        let firstPager = try XCTUnwrap(
            identifiers.firstIndex { $0.hasPrefix("fst.song-leaderboard.page-") }, "No pager on page \(page)"
        )
        XCTAssertLessThan(header, firstRow, "A row reads before the header on page \(page)")
        XCTAssertLessThan(lastRow, firstPager, "The pager reads before a row on page \(page)")
    }

    /// The pager on `page`: each arrow a named 44 pt button on screen, in reading order,
    /// enabled only where it can move; the badge between them reads the page.
    ///
    /// - Parameters:
    ///   - page: The page shown.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    @MainActor
    private func assertPager(_ page: Int, in app: XCUIApplication, window: CGRect) {
        let info = app.descendants(matching: .any)[Self.pageInfo]
        XCTAssertTrue(info.exists, "No page badge on page \(page)")
        XCTAssertEqual(info.label, "Page", "The badge's name on page \(page)")
        XCTAssertEqual(info.value as? String, "\(page) of \(Self.pageCount)", "The badge's value on page \(page)")
        var previousMaxX = -CGFloat.greatestFiniteMagnitude
        let order = Self.pagerArrows.prefix(2).map(\.id) + [Self.pageInfo] + Self.pagerArrows.suffix(2).map(\.id)
        for identifier in order {
            let frame = app.descendants(matching: .any)[identifier].frame
            XCTAssertGreaterThanOrEqual(frame.width, Self.minimumTarget - 0.5, "\(identifier) target \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, Self.minimumTarget - 0.5, "\(identifier) target \(frame)")
            XCTAssertTrue(window.contains(frame), "\(identifier) off screen on page \(page): \(frame)")
            XCTAssertGreaterThan(frame.minX, previousMaxX - 0.5, "\(identifier) out of reading order")
            previousMaxX = frame.maxX
        }
        for arrow in Self.pagerArrows {
            let button = app.buttons[arrow.id]
            XCTAssertTrue(button.exists, "\(arrow.id) is not a button")
            XCTAssertTrue(button.label.localizedCaseInsensitiveContains(arrow.word), "\(arrow.id) reads \(button.label)")
            let enabled = arrow.backward ? page > 1 : page < Self.pageCount
            XCTAssertEqual(button.isEnabled, enabled, "\(arrow.id) enabled on page \(page)")
            if enabled { XCTAssertTrue(button.isHittable, "\(arrow.id) is not reachable on page \(page)") }
        }
    }

    // MARK: - Helpers

    /// Wait until the page badge reads `page`.
    ///
    /// - Parameters:
    ///   - page: The expected page.
    ///   - app: The running app.
    @MainActor
    private func waitForPage(_ page: Int, in app: XCUIApplication) throws {
        let info = app.descendants(matching: .any)[Self.pageInfo]
        let reached = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "\(page) of \(Self.pageCount)"), object: info
        )
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
                       "Never reached page \(page): \(info.exists ? String(describing: info.value) : "no badge")")
    }

    /// Launch `fixture-pulse` Lead's board at AX5 with no player, against the fixture.
    ///
    /// - Returns: The running app.
    /// - Throws: A skip when the board never loads.
    @MainActor
    private func launchBoard() throws -> XCUIApplication {
        let base = ProcessInfo.processInfo.environment["FST_SONG_BOARD_PAGING_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_SONG": "fixture-pulse",
            "FST_DEBUG_SONG_INSTRUMENT": "Solo_Guitar",
            "FST_DEBUG_ANONYMOUS": "1",
        ])
        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", ax5.rawValue]
        app.launch()
        guard app.descendants(matching: .any)[Self.pageInfo].waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("The song leaderboard never loaded; run tools/mock_service.py on \(base).")
        }
        return app
    }
}
