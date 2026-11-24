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
    private static let leadChart = "fst.player.rank-history.Solo_Guitar.chart"

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

    // MARK: Profile picker

    /// The native AX5 segments respond at either edge of a 44 pt target.
    @MainActor
    func testProfileScopeRespondsAtTouchTargetEdgesAtAX5() {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": SongsUITestSupport.fixtureURL, "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "settings", "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", Self.ax5]
        app.launch()
        defer { app.terminate() }
        let profile = app.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: FestivalApp.budget(15)))
        profile.tap()

        let scope = app.segmentedControls["fst.profile.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertEqual(scope.buttons.allElementsBoundByIndex.map(\.label), ["All", "Players", "Bands"])
        XCTAssertTrue(scope.buttons["All"].isSelected)

        let hint = app.staticTexts["fst.profile.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        for (name, offset) in [("Bands", -20.0), ("Players", 20.0)] {
            let segment = scope.buttons[name]
            segment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 0, dy: offset)).tap()
            XCTAssertTrue(segment.isSelected, "The \(name) scope missed a tap 20 pt from its center")
            XCTAssertGreaterThanOrEqual(segment.frame.height, 43.5)
            XCTAssertEqual(hint.label, "Enter at least two characters to search for \(name.lowercased()).")
        }
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
        let select = app.buttons.matching(NSPredicate(
            format: "identifier IN %@", ["fst.player.select", "fst.player.select.rail"]
        )).firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertEqual(select.label, "Select Profile")
        let chart = element(Self.leadChart, in: app)
        reveal(chart, in: app)
        XCTAssertTrue(chart.exists, "the Lead rank-history chart")
        XCTAssertEqual(chart.label, "Lead rank history chart")
    }

    /// Short ticks leave room for the bars at standard size. The gutters grow with text
    /// without losing the adjustable chart or the separate axis summaries.
    @MainActor
    func testPlayerRankHistoryKeepsReadableAxisGutters() throws {
        var standardWidths: [CGFloat] = []
        var standardDateHeight: CGFloat = 0
        for size in [nil, Self.ax5] {
            let app = launch(route: "player:fixture-player-1", size: size ?? UIContentSizeCategory.large.rawValue)
            let quickLinks = app.buttons["fst.quick-links.open"]
            XCTAssertTrue(quickLinks.waitForExistence(timeout: FestivalApp.budget(20)))
            quickLinks.tap()
            let lead = app.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label == %@",
                "fst.quick-links.item.rank-history:Solo_Guitar", "Lead Rank History"
            )).firstMatch
            XCTAssertTrue(lead.waitForExistence(timeout: FestivalApp.budget(10)))
            lead.tap()
            let chart = element(Self.leadChart, in: app)
            XCTAssertTrue(chart.waitForExistence(timeout: FestivalApp.budget(20)))
            XCTAssertEqual(chart.label, "Lead rank history chart")
            let summary = try XCTUnwrap(chart.value as? String)
            XCTAssertTrue(summary.contains(": Rank ") && summary.contains("total score"))
            XCTAssertGreaterThanOrEqual(chart.frame.width, 44 - 0.5)
            let nodes = ["Total Score scale,", "Rank scale,", "Dates,"].map {
                app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", $0)).firstMatch
            }
            XCTAssertTrue(nodes.allSatisfy(\.exists))
            let widths = nodes.prefix(2).map(\.frame.width)
            let dateHeight = nodes[2].frame.height
            if size == nil {
                XCTAssertEqual(widths[0], 28, accuracy: 1, "Match the Swift Charts score gutter")
                XCTAssertEqual(widths[1], 24, accuracy: 1, "Match the Swift Charts rank gutter")
                XCTAssertEqual(dateHeight, 18, accuracy: 1, "One line of dates, not a reserved 22 pt band")
                XCTAssertEqual(nodes[0].frame.height, 202, accuracy: 1, "No extra space above the plot")
                try assertRankLinePaint(in: chart)
                standardWidths = widths
                standardDateHeight = dateHeight
                let backPage = app.buttons["fst.player.rank-history.Solo_Guitar.back-page"]
                let back = app.buttons["fst.player.rank-history.Solo_Guitar.back-entry"]
                let forward = app.buttons["fst.player.rank-history.Solo_Guitar.forward-entry"]
                let forwardPage = app.buttons["fst.player.rank-history.Solo_Guitar.forward-page"]
                let up = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.81))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.57))
                for _ in 0..<4 where !back.isHittable { up.press(forDuration: 0, thenDragTo: end) }
                XCTAssertTrue(back.isHittable)
                for (button, label) in [
                    (backPage, "Back one page"), (back, "Back one entry"),
                    (forward, "Forward one entry"), (forwardPage, "Forward one page"),
                ] {
                    XCTAssertEqual(button.label, label)
                    XCTAssertEqual(button.frame.width, 44, accuracy: 0.5)
                    XCTAssertGreaterThanOrEqual(button.frame.height, 43.5)
                }
                XCTAssertFalse(forward.isEnabled)
                let disabledPlate = try pagerPlateRed(forward)
                back.tap()
                XCTAssertNotEqual(chart.value as? String, summary)
                XCTAssertTrue(forward.isEnabled)
                let enabledPlate = try pagerPlateRed(forward)
                XCTAssertGreaterThan(enabledPlate - disabledPlate, 6, "The same plate dims only while disabled")
                forward.tap()
                XCTAssertEqual(chart.value as? String, summary)
                XCTAssertFalse(forward.isEnabled)
                XCTAssertEqual(try pagerPlateRed(forward), disabledPlate, accuracy: 1.5)
            } else {
                XCTAssertEqual(standardWidths.count, widths.count)
                for (standard, scaled) in zip(standardWidths, widths) { XCTAssertGreaterThan(scaled, standard) }
                XCTAssertGreaterThan(dateHeight, standardDateHeight, "The whole date line fits at AX5")
            }
            app.terminate()
        }
    }

    /// Samples the plate above the glyph, inside the rim.
    @MainActor
    private func pagerPlateRed(_ button: XCUIElement) throws -> Double {
        let image = button.screenshot().image
        let bitmap = try XCTUnwrap(ButtonFillPixels(image: XCTUnwrap(image.cgImage), pointWidth: button.frame.width))
        let x = bitmap.width / 2, y = bitmap.height / 4
        let red = (y - 2...y + 2).flatMap { row in
            (x - 2...x + 2).map { Int(bitmap.pixels[(row * bitmap.width + $0) * 4]) }
        }
        return Double(red.reduce(0, +)) / Double(red.count)
    }

    /// The green fixture bars tint the line beneath them; dots stay blue above the bars.
    @MainActor
    private func assertRankLinePaint(in chart: XCUIElement) throws {
        let screenshot = chart.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Rank History overlap"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = screenshot.image
        let bitmap = try XCTUnwrap(ButtonFillPixels(image: XCTUnwrap(image.cgImage), pointWidth: image.size.width))
        let area = CGRect(origin: .zero, size: image.size)
        let overlap = try XCTUnwrap(bitmap.fraction(in: area) { r, g, b in
            r <= 65 && (176...200).contains(g) && (125...160).contains(b) && b - r >= 74
        })
        XCTAssertGreaterThan(overlap, 0.0002, "The rank line should show through the green bars, not over them")
        let opaqueRank = try XCTUnwrap(bitmap.fraction(in: area) { r, g, b in
            (68...84).contains(r) && (117...133).contains(g) && b >= 247
        })
        XCTAssertGreaterThan(opaqueRank, 0, "The rank chart keeps opaque blue marks")
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

    /// The Bands page reads one 44 pt button per size, and its row padding opens the board.
    @MainActor
    func testBandsPageRowsAndTargets() throws {
        let app = launch(route: "bands", tab: "songs")
        XCTAssertTrue(element("fst.bands.screen", in: app).waitForExistence(timeout: FestivalApp.budget(20)))
        let duos = app.buttons["fst.bands.rankings.Band_Duets"]
        XCTAssertTrue(duos.waitForExistence(timeout: FestivalApp.budget(10)))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.bands.rankings."))
            .allElementsBoundByIndex
        XCTAssertEqual(rows.map(\.label), ["Duos", "Trios", "Quads"])
        for row in rows {
            XCTAssertGreaterThanOrEqual(row.frame.height, 43.5, row.label)
        }
        XCTAssertTrue(app.staticTexts["To find a band by a member's name, use Search."].exists)
        duos.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.06)).tap()
        XCTAssertTrue(app.buttons["fst.band-rankings.row.fixture-team-1"].waitForExistence(timeout: 15))
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
