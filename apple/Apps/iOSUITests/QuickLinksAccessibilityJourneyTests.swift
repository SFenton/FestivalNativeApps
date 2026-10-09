import UIKit
import XCTest

/// Accessibility of the iPhone Quick Links chooser (#389, for #6's fixed menu order).
///
/// On iPhone (iOS 26.1+) Quick Links sits in the tab-bar accessory and lists the page's
/// sections in a compact sheet (`PageToolInlineMenuSheet`). Each test opens Settings'
/// sheet against the fixture service, audits it with `performAccessibilityAudit`, and
/// checks what the audit cannot: rows in page order with section names, the current
/// section selected, and 44 pt targets (HIG Accessibility, Mobility: "Strive for the
/// platform's recommended minimum control size", 44x44 pt on iOS), at the default text
/// size and the largest accessibility size. The hosted
/// `QuickLinksAccessibilityTests` pin the same contract in `apple-ci`.
///
/// Needs `tools/mock_service.py --port 18790`, like `SettingsJourneyTests`.
final class QuickLinksAccessibilityJourneyTests: XCTestCase {
    // MARK: - Helpers

    private static let itemPrefix = "fst.quick-links.item."

    /// Settings' sections in page order, with the names VoiceOver reads.
    private static let settingsSections: [(id: String, title: String)] = [
        ("app-settings", "App Settings"), ("accessibility", "Accessibility"), ("item-shop", "Item Shop"),
        ("show-instruments", "Show Instruments"), ("show-metadata", "Show Instrument Metadata"),
        ("version", "Festival Score Tracker Version"), ("service-info", "Service Info"),
        ("first-run", "First Run Guides"), ("licenses", "Licenses"), ("privacy-policy", "Privacy Policy"),
        ("reset", "Reset Settings"),
    ]

    /// Fixture Settings with no persisted profile, optionally at a Dynamic Type size.
    ///
    /// - Parameter contentSize: A `UIContentSizeCategory` raw value, or nil for the default.
    /// - Returns: The launched app.
    @MainActor
    private func launchSettings(contentSize: String? = nil) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_API_BASE_URL": "http://127.0.0.1:18790",
            "FST_DEBUG_TAB": "settings",
        ])
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    /// Open the Quick Links sheet and return its row buttons.
    ///
    /// - Parameter app: Launched app on a page with Quick Links.
    /// - Returns: The entry button and the sheet's row query.
    @MainActor
    private func openSheet(
        _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) -> (open: XCUIElement, rows: XCUIElementQuery) {
        let open = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "No Quick Links button", file: file, line: line)
        XCTAssertEqual(open.label, "Quick Links", file: file, line: line)
        XCTAssertEqual(open.value as? String, "App Settings", "The entry names the current section", file: file, line: line)
        XCTAssertGreaterThanOrEqual(open.frame.width, 44, "Entry target width", file: file, line: line)
        XCTAssertGreaterThanOrEqual(open.frame.height, 44, "Entry target height", file: file, line: line)
        open.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.itemPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "The sheet did not open", file: file, line: line)
        return (open, rows)
    }

    /// The sheet's on-screen rows, top to bottom.
    ///
    /// - Parameters:
    ///   - app: App with the sheet open.
    ///   - rows: The sheet's row query.
    /// - Returns: Each on-screen row's section id, label, frame and selected state.
    @MainActor
    private func visibleRows(
        _ app: XCUIApplication, _ rows: XCUIElementQuery
    ) -> [(id: String, label: String, frame: CGRect, selected: Bool)] {
        let screen = app.windows.firstMatch.frame
        return rows.allElementsBoundByIndex
            .filter { $0.exists && screen.contains($0.frame) }
            .map { (String($0.identifier.dropFirst(Self.itemPrefix.count)), $0.label, $0.frame, $0.isSelected) }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    /// Assert the on-screen rows are a page-order run of Settings' sections, named by
    /// section, at least 44 pt tall and hittable, with only the first section selected.
    @MainActor
    private func assertRows(
        _ app: XCUIApplication, _ rows: XCUIElementQuery, file: StaticString = #filePath, line: UInt = #line
    ) -> [(id: String, label: String, frame: CGRect, selected: Bool)] {
        let visible = visibleRows(app, rows)
        XCTAssertGreaterThanOrEqual(visible.count, 2, "Too few rows on screen", file: file, line: line)
        let expected = Array(Self.settingsSections.prefix(visible.count))
        XCTAssertEqual(visible.map(\.id), expected.map(\.id), "Rows in page order", file: file, line: line)
        XCTAssertEqual(visible.map(\.label), expected.map(\.title), "Rows named by section", file: file, line: line)
        XCTAssertEqual(visible.filter(\.selected).map(\.id), ["app-settings"], "Only the current section is selected",
                       file: file, line: line)
        for row in visible {
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(row.id) target height", file: file, line: line)
            XCTAssertGreaterThanOrEqual(row.frame.width, 44, "\(row.id) target width", file: file, line: line)
        }
        return visible
    }

    // MARK: - Tests

    /// Default text size: the open sheet passes the full audit and its rows read in page
    /// order, named, selected and at least 44 pt tall.
    @MainActor
    func testQuickLinksSheetPassesAccessibilityAudit() throws {
        continueAfterFailure = false
        let app = launchSettings()
        let (_, rows) = openSheet(app)
        _ = assertRows(app, rows)
        SongsUITestSupport.record(app, name: "quick-links-sheet-a11y-default")
        try app.performAccessibilityAudit(for: .all)
    }

    /// Largest accessibility text size: the rows' text grows (rows taller than at the
    /// default size), stays unclipped and in page order, and the entry and rows keep their
    /// 44 pt targets.
    @MainActor
    func testQuickLinksSheetScalesToTheLargestTextSize() throws {
        continueAfterFailure = false
        let regular = launchSettings()
        let regularHeight = assertRows(regular, openSheet(regular).rows).first?.frame.height ?? 0
        regular.terminate()

        let app = launchSettings(contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        let (_, rows) = openSheet(app)
        let large = assertRows(app, rows)
        SongsUITestSupport.record(app, name: "quick-links-sheet-a11y-ax5")
        let largeHeight = large.first?.frame.height ?? 0
        XCTAssertGreaterThan(largeHeight, regularHeight * 1.35, "Rows grow with text: \(regularHeight) → \(largeHeight)")
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped, .hitRegion])
    }
}
