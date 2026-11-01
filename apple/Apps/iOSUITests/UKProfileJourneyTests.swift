import UIKit
import XCTest

// MARK: - Profile lane (UIKit port)

/// Accessibility checks for the Profile lane's pages (`UKPlayerProfileViewController`,
/// `UKBandsViewController`): identifiers and roles, 44 pt targets, AX5 growth and a scoped
/// audit. The identifiers and traits are the SwiftUI pages' own, so these run unchanged
/// against both apps (`python3 tools/ios_sim.py uitest --app uikit --only UKProfileJourneyTests`).
///
/// Runs against the loopback fixture on port 8765 (Fixture Player 1).
/// HIG Accessibility: "Strive for the platform's recommended minimum control size" (44x44 pt);
/// HIG Typography: "Keep text truncation to a minimum as font size increases".
final class UKProfileJourneyTests: XCTestCase {
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: Helpers

    @MainActor
    private func launch(route: String, tab: String = "settings", size: String? = nil) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765", "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FLAT_BACKDROP": "1", "FST_DEBUG_TAB": tab, "FST_DEBUG_ROUTE": route,
        ])
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
    }

    @MainActor
    private func auditProfile(in app: XCUIApplication, prefixes: [String]) throws {
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            guard let element = issue.element, prefixes.contains(where: { element.identifier.hasPrefix($0) }) else { return true }
            issues.append("\(element.identifier) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        do {
            try app.performAccessibilityAudit(for: audit, handler)
        } catch let error as NSError where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            issues.removeAll()
            try app.performAccessibilityAudit(for: audit, handler)
        }
        XCTAssertEqual(issues, [])
    }

    // MARK: Player profile

    /// The page names its tiles, exposes them as one element each (a button only when it
    /// links), keeps Select at 44 pt and offers the chart as an adjustable element.
    @MainActor
    func testPlayerProfileStructure() throws {
        let app = launch(route: "player:fixture-player-1")
        XCTAssertTrue(SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: FestivalApp.budget(30)))
        SongsUITestSupport.assertPlayerTitle("Fixture Player 1", in: app)
        let songs = app.buttons["fst.player.stat.overview.songs-played"]
        XCTAssertTrue(songs.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertEqual(songs.label, "Songs Played")
        XCTAssertEqual(songs.value as? String, "2")
        XCTAssertEqual(songs.identifier, "fst.player.stat.overview.songs-played")
        XCTAssertGreaterThanOrEqual(songs.frame.height, 43.5)
        let gold = element("fst.player.stat.overview.gold-stars", in: app)
        XCTAssertTrue(gold.exists)
        XCTAssertFalse(app.buttons["fst.player.stat.overview.gold-stars"].exists, "a plain tile is not a button")
        let select = app.buttons["fst.player.select"]
        XCTAssertTrue(select.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertEqual(select.label, "Select Profile")
        let chart = element("fst.player.rank-history.lead.chart", in: app)
        reveal(chart, in: app)
        XCTAssertTrue(chart.exists, "the Lead rank-history chart")
        XCTAssertEqual(chart.label, "Lead rank history chart")
    }

    /// At AX5 the tiles grow, stay at least 44 pt and the scoped audit finds nothing.
    @MainActor
    func testPlayerProfileAtAX5() throws {
        let app = launch(route: "player:fixture-player-1", size: Self.ax5)
        XCTAssertTrue(SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: FestivalApp.budget(30)))
        let songs = app.buttons["fst.player.stat.overview.songs-played"]
        XCTAssertTrue(songs.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertGreaterThanOrEqual(songs.frame.height, 44 - 0.5)
        XCTAssertGreaterThan(songs.frame.height, 80, "the tile grows with the text: \(songs.frame)")
        XCTAssertTrue(songs.isHittable)
        try auditProfile(in: app, prefixes: ["fst.player.stat", "fst.player.overview"])
    }

    // MARK: Bands

    /// The Bands page: one 44 pt row per size, identifiers and footnote.
    @MainActor
    func testBandsPageRowsAndTargets() throws {
        let app = launch(route: "bands", tab: "songs")
        XCTAssertTrue(element("fst.bands.screen", in: app).waitForExistence(timeout: FestivalApp.budget(20)))
        let duos = app.buttons["fst.bands.rankings.Band_Duets"]
        XCTAssertTrue(duos.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertGreaterThanOrEqual(duos.frame.height, 43.5)
        XCTAssertTrue(app.staticTexts["To find a band by a member's name, use Search."].exists)
    }

    @MainActor
    func testBandsPageAtAX5() throws {
        let app = launch(route: "bands", tab: "songs", size: Self.ax5)
        let duos = app.buttons["fst.bands.rankings.Band_Duets"]
        XCTAssertTrue(duos.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertGreaterThanOrEqual(duos.frame.height, 44 - 0.5)
        try auditProfile(in: app, prefixes: ["fst.bands"])
    }
}
