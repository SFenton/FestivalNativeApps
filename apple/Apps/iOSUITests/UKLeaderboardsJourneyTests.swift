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

    /// The pager exposes four 44 pt buttons and the spoken page count. Unavailable steps
    /// stay visible, whether the fixture contains one page of rankings or many.
    @MainActor
    func testFullRankingsPagerIsAccessible() throws {
        let app = launch(route: "fullRankings:Solo_Guitar")
        let pager = element("fst.full-rankings.pager", in: app)
        XCTAssertTrue(pager.waitForExistence(timeout: FestivalApp.budget(20)))
        let info = element("fst.full-rankings.page-info", in: app)
        XCTAssertTrue(info.exists)
        XCTAssertEqual(info.label, "Page")
        let value = try XCTUnwrap(info.value as? String)
        XCTAssertTrue(value.hasPrefix("1 of "), value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let totalPages = try XCTUnwrap(formatter.number(from: String(value.dropFirst("1 of ".count)))).intValue
        XCTAssertGreaterThan(totalPages, 0)
        for step in ["first", "previous", "next", "last"] {
            let button = app.buttons["fst.full-rankings.page-\(step)"]
            XCTAssertTrue(button.exists, "missing \(step)")
            assertTarget(button, "\(step) button")
            XCTAssertEqual(button.isEnabled, totalPages > 1 && (step == "next" || step == "last"), step)
        }
        let first = app.buttons["fst.full-rankings.page-first"]
        let image = try XCTUnwrap(first.screenshot().image.cgImage)
        let pixels = try SongsUITestSupport.bitmapPixels(image)
        let glyphPixels = (image.height / 4 ..< 3 * image.height / 4).reduce(0) { count, y in
            count + (image.width / 4 ..< 3 * image.width / 4).filter { x in
                let offset = 4 * (y * image.width + x)
                return Int(pixels[offset + 2]) > 95 && Int(pixels[offset]) > 65
            }.count
        }
        XCTAssertGreaterThan(glyphPixels, 10, "the disabled First Page glyph is visible over the card")
        XCTAssertTrue(element("fst.full-rankings.ranked-count", in: app).exists)
        XCTAssertTrue(element("fst.full-rankings.title", in: app).exists)
        let firstRow = app.buttons["fst.rankings.row.fixture-player-1"]
        let secondRow = app.buttons["fst.rankings.row.fixture-player-2"]
        XCTAssertTrue(firstRow.exists && secondRow.exists)
        XCTAssertEqual(secondRow.frame.minY - firstRow.frame.minY, 49, accuracy: 1.0 / 3.0,
                       "row pitch includes the 48 pt content and 1 pt separator")
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
            let button = app.buttons["fst.band-rankings.page-\(step)"]
            assertTarget(button, "\(step) button")
            XCTAssertFalse(button.frame.intersects(menu.frame), "\(step) shares its touch area with the band size menu")
        }
    }
}
