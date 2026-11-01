import UIKit
import XCTest

// MARK: - Leaderboards accessibility

/// Identifiers, labels, traits, 44 pt targets, AX5 growth and a scoped accessibility audit
/// for the Leaderboards overview, Full Rankings and Band Rankings, fixture-backed against
/// `tools/mock_service.py`. Both apps satisfy the same contract, so the tests run in the
/// SwiftUI app and in the UIKit port (`--app uikit`).
///
/// HIG Accessibility: "Strive for the platform's recommended minimum control size" (iOS
/// 44x44 pt); HIG Typography: "Keep text truncation to a minimum as font size increases".
final class UKLeaderboardsJourneyTests: XCTestCase {
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    @MainActor
    private func launch(tab: String? = nil, route: String? = nil, size: String? = nil) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if let tab { env["FST_DEBUG_TAB"] = tab }
        if let route { env["FST_DEBUG_ROUTE"] = route }
        let app = FestivalApp.makeApp(env)
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertTarget(_ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.height, 43.5, "\(name) is shorter than 44 pt", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.5, "\(name) is narrower than 44 pt", file: file, line: line)
    }

    // MARK: Overview

    /// The Solo Guitar card is a group of rows and a View All button, each a 44 pt target
    /// with its spoken label.
    @MainActor
    func testOverviewCardRowsAndViewAllAreAccessibleTargets() throws {
        let app = launch(tab: "leaderboards")
        let card = element("fst.leaderboards.card.Solo_Guitar", in: app)
        XCTAssertTrue(card.waitForExistence(timeout: FestivalApp.budget(20)))
        let row = card.buttons["fst.rankings.row.fixture-player-1"]
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(10)))
        assertTarget(row, "ranking row")
        XCTAssertTrue(row.label.contains("Fixture Player 1"), "Row label \(row.label)")
        XCTAssertTrue(row.label.hasPrefix("#1"), "Row label \(row.label)")
        let viewAll = app.buttons["fst.leaderboards.card.Solo_Guitar.view-all"]
        XCTAssertTrue(viewAll.exists)
        assertTarget(viewAll, "View all rankings")
        XCTAssertTrue(viewAll.label.hasPrefix("View all rankings"), "View all label \(viewAll.label)")
    }

    // MARK: Full Rankings

    /// The pager is one group of four 44 pt buttons and an adjustable `page / total`
    /// element ("Page, 1 of 1"); edge buttons are disabled on a one-page board.
    @MainActor
    func testFullRankingsPagerIsAccessible() throws {
        let app = launch(route: "fullRankings:Solo_Guitar")
        let pager = element("fst.full-rankings.pager", in: app)
        XCTAssertTrue(pager.waitForExistence(timeout: FestivalApp.budget(20)))
        for step in ["first", "previous", "next", "last"] {
            let button = app.buttons["fst.full-rankings.page-\(step)"]
            XCTAssertTrue(button.exists, "missing \(step)")
            assertTarget(button, "\(step) button")
            XCTAssertFalse(button.isEnabled, "\(step) is enabled on a one-page board")
        }
        let info = element("fst.full-rankings.page-info", in: app)
        XCTAssertTrue(info.exists)
        XCTAssertEqual(info.label, "Page")
        XCTAssertEqual(info.value as? String, "1 of 1")
        XCTAssertTrue(element("fst.full-rankings.ranked-count", in: app).exists)
        XCTAssertTrue(element("fst.full-rankings.title", in: app).exists)
    }

    /// At AX5 the rows stack and grow, nothing is clipped past the screen edges, and the
    /// scoped audit finds no Dynamic Type or clipped-text issues.
    @MainActor
    func testFullRankingsGrowsAtAX5() throws {
        let app = launch(route: "fullRankings:Solo_Guitar", size: Self.ax5)
        let row = app.buttons["fst.rankings.row.fixture-player-1"]
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(20)))
        let screen = app.windows.firstMatch.frame
        XCTAssertGreaterThan(row.frame.height, 80, "AX5 row did not grow: \(row.frame)")
        XCTAssertGreaterThanOrEqual(row.frame.minX, screen.minX - 0.5)
        XCTAssertLessThanOrEqual(row.frame.maxX, screen.maxX + 0.5)
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            // The system bar and floating tools are not this page's.
            guard let element = issue.element else { return false }
            return !element.identifier.hasPrefix("fst.rankings.") && !element.identifier.hasPrefix("fst.full-rankings.")
        }
    }

    // MARK: Band Rankings

    /// Band Rankings shows its ranked count, rows and the floating pager bar with the
    /// band-size switcher, every control a 44 pt target.
    @MainActor
    func testBandRankingsBarIsAccessible() throws {
        let app = launch(route: "bandRankings:Band_Duets")
        XCTAssertTrue(element("fst.band-rankings.ranked-count", in: app).waitForExistence(timeout: FestivalApp.budget(20)))
        let menu = app.buttons["fst.band-rankings.band-type-menu"]
        XCTAssertTrue(menu.exists, "band-size menu missing")
        assertTarget(menu, "band-size menu")
        XCTAssertEqual(menu.label, "Band size")
        let info = element("fst.band-rankings.page-info", in: app)
        XCTAssertTrue(info.exists)
        XCTAssertEqual(info.label, "Page")
        for step in ["first", "previous", "next", "last"] {
            assertTarget(app.buttons["fst.band-rankings.page-\(step)"], "\(step) button")
        }
    }
}
