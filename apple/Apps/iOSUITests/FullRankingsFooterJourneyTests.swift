import UIKit
import XCTest

/// Accessibility at the largest text size for Full Rankings' pinned player footer on the
/// player's own page (issue #466, for #318). #318 kept the selected player's row pinned
/// above the pager even when the page shows it, where the footer opens Statistics
/// (`RankingSpotlight.pinnedFooter`, leaderboard-row R5/R7). Since #386 (R12) a footer
/// that would cover more than a third of the board at AX5 follows the rows instead, as it
/// does on an iPhone: the journey then scrolls to it (#620). macOS has no Dynamic Type,
/// so the hosted `FullRankingsFooterAccessibilityTests` check the stacked layout only;
/// this journey opens Lead Full Rankings at AX5 with `fixture-player-1` (rank 1 of 3, the
/// only page) and checks the footer is one named 44 pt button on screen whose text grew,
/// VoiceOver reads the rows (the player's own among them) before it and it before the
/// pager, the system audit passes, and activating it opens the player's statistics.
///
/// Runs against `tools/mock_service.py` on `:8765` (the `apple-ci` simulator steps'
/// `--large-catalogue` fixture); set `FST_FULL_RANKINGS_FOOTER_FIXTURE_URL` (as
/// `TEST_RUNNER_FST_FULL_RANKINGS_FOOTER_FIXTURE_URL`) to use another port. Skips when
/// the board never loads.
final class FullRankingsFooterJourneyTests: XCTestCase {
    private static let openID = "fst.full-rankings.spotlight-open"
    private static let jumpID = "fst.full-rankings.spotlight-jump"
    private static let rowPrefix = "fst.rankings.row."
    private static let ownRowID = "fst.rankings.row.fixture-player-1"
    private static let pageInfo = "fst.full-rankings.page-info"
    private static let openLabel = "Your rank, 1st. Open your statistics."
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44

    // MARK: - Journey

    /// At AX5 on the player's own page the footer is pinned, or follows the rows when it is
    /// too tall to pin (R12); either way it is named, full size, on screen above the pager
    /// and in reading order between the rows and the pager; the audit passes; it opens
    /// Statistics.
    @MainActor
    func testFooterOnThePlayersPageIsAccessibleAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = try launchBoard()
        let window = app.windows.firstMatch.frame

        let ownRow = app.descendants(matching: .any)[Self.ownRowID]
        XCTAssertTrue(ownRow.waitForExistence(timeout: FestivalApp.budget(10)), "The player's own row did not load")
        XCTAssertEqual(ownRow.label, "Your rank, 1st. Fixture Player 1.", "The page's own row")

        let footer = app.buttons[Self.openID]
        XCTAssertTrue(footer.waitForExistence(timeout: FestivalApp.budget(10)), "No footer on the player's page")
        XCTAssertEqual(footer.label, Self.openLabel)
        XCTAssertFalse(app.descendants(matching: .any)[Self.jumpID].exists, "One footer action at a time")
        let info = app.descendants(matching: .any)[Self.pageInfo]
        XCTAssertTrue(info.exists, "No page badge")
        // The footer pins until it is measured, then follows the rows if it is too tall (R12).
        let unpinned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !footer.isHittable }, object: nil
        )
        if XCTWaiter().wait(for: [unpinned], timeout: FestivalApp.budget(3)) == .completed {
            scrollToFooter(footer, above: info, in: app, window: window)
            let rowsBottom = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
                .allElementsBoundByIndex.map(\.frame.maxY).max()
            let bottom = try XCTUnwrap(rowsBottom, "No row is realized at the page's end")
            XCTAssertGreaterThanOrEqual(
                footer.frame.minY, bottom - 0.5, "The unpinned footer does not follow the rows: \(footer.frame) vs \(bottom)"
            )
        } else {
            XCTAssertLessThanOrEqual(
                footer.frame.height, window.height / 3, "A pinned footer covers over a third of the board (R12): \(footer.frame)"
            )
        }
        XCTAssertTrue(footer.isHittable, "The footer is not reachable")
        XCTAssertTrue(window.contains(footer.frame), "The footer is off screen: \(footer.frame)")
        XCTAssertGreaterThanOrEqual(footer.frame.height, Self.minimumTarget - 0.5, "Footer target \(footer.frame)")
        // Text grew to AX5: the stacked row holds at least two body lines.
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ).lineHeight
        XCTAssertGreaterThanOrEqual(footer.frame.height, bodyLine * 2, "Footer not at AX5: \(footer.frame)")

        XCTAssertEqual(info.value as? String, "1 of 1")
        XCTAssertLessThanOrEqual(footer.frame.maxY, info.frame.minY + 0.5, "The footer rests above the pager")
        XCTAssertTrue(window.contains(info.frame), "The pager is off screen: \(info.frame)")
        XCTAssertGreaterThanOrEqual(info.frame.height, Self.minimumTarget - 0.5, "Badge target \(info.frame)")

        try assertReadingOrder(in: app)

        // The system audit at AX5, for the board only (the shell has its own). Contrast is
        // left to the hosted checks: rows crossing the fade read below 4.5:1 by design.
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion]
        ) { issue in
            let identifier = issue.element?.identifier ?? ""
            return !(identifier.hasPrefix("fst.full-rankings.") || identifier.hasPrefix(Self.rowPrefix))
        }

        footer.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["fst.player.available"].waitForExistence(timeout: FestivalApp.budget(20)),
            "Open your statistics did not open the player's statistics"
        )
    }

    // MARK: - Assertions

    /// VoiceOver reaches every row, the player's own included, before the footer, and the
    /// footer before the pager.
    ///
    /// - Parameter app: The running app.
    /// - Throws: An unavailable accessibility snapshot.
    @MainActor
    private func assertReadingOrder(in app: XCUIApplication) throws {
        var identifiers: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty { identifiers.append(element.identifier) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        let ownRow = try XCTUnwrap(identifiers.firstIndex(of: Self.ownRowID), "No own row in the tree")
        let lastRow = try XCTUnwrap(identifiers.lastIndex { $0.hasPrefix(Self.rowPrefix) }, "No row in the tree")
        let footer = try XCTUnwrap(identifiers.firstIndex(of: Self.openID), "No footer in the tree")
        let firstPager = try XCTUnwrap(
            identifiers.firstIndex { $0.hasPrefix("fst.full-rankings.page-") }, "No pager in the tree"
        )
        XCTAssertLessThan(ownRow, footer, "The footer reads before the player's own row")
        XCTAssertLessThan(lastRow, footer, "The footer reads before a row")
        XCTAssertLessThan(footer, firstPager, "The pager reads before the footer")
    }

    // MARK: - Helpers

    /// Flick the rows up until the footer that follows them rests whole on screen above
    /// the pager.
    ///
    /// - Parameters:
    ///   - footer: The footer's Open button.
    ///   - info: The pager's page badge.
    ///   - app: The running app.
    ///   - window: The app window's frame.
    @MainActor
    private func scrollToFooter(_ footer: XCUIElement, above info: XCUIElement, in app: XCUIApplication, window: CGRect) {
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let startY = info.frame.minY - 16
        let distance = min(window.height * 0.3, max(startY - window.minY - 160, 60))
        for _ in 0..<12 {
            if footer.isHittable, window.contains(footer.frame), footer.frame.maxY <= info.frame.minY + 0.5 { return }
            let start = origin.withOffset(CGVector(dx: window.midX - window.minX, dy: startY - window.minY))
            start.press(
                forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                withVelocity: .fast, thenHoldForDuration: 0
            )
        }
    }

    /// Launch Lead Full Rankings at AX5 with `fixture-player-1` selected, against the fixture.
    ///
    /// - Returns: The running app.
    /// - Throws: A skip when the board never loads.
    @MainActor
    private func launchBoard() throws -> XCUIApplication {
        let base = ProcessInfo.processInfo.environment["FST_FULL_RANKINGS_FOOTER_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_ROUTE": "fullRankings:Solo_Guitar",
        ])
        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", ax5.rawValue]
        app.launch()
        guard app.descendants(matching: .any)[Self.pageInfo].waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("Full Rankings never loaded; run tools/mock_service.py on \(base).")
        }
        return app
    }
}
