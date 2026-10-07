import XCTest

// MARK: - Shell chrome helpers

/// Shell chrome lookups shared by the phone and iPhone Duo journeys (tabs in a
/// horizontal or system vertical bar, toolbar items that may sit in the bar's overflow).
enum ShellUITestSupport {
    /// On-screen buttons titled `title` that are not in a navigation bar or the drawer.
    ///
    /// The Duo shows its tabs in a vertical bar that XCUITest does not report as a tab
    /// bar, so tabs are the on-screen buttons with a section's title outside navigation
    /// bars (where a back button may carry the previous page's title) and outside the
    /// navigation drawer (whose rows carry the same titles).
    ///
    /// - Parameters:
    ///   - title: The section title.
    ///   - app: The running app.
    /// - Returns: The matching tab buttons.
    @MainActor
    static func tabButtons(_ title: String, in app: XCUIApplication) -> [XCUIElement] {
        let bars = app.navigationBars.allElementsBoundByIndex.map(\.frame)
        return app.buttons.matching(NSPredicate(
            format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "fst.shell.drawer"
        )).allElementsBoundByIndex.filter { button in
            let frame = button.frame
            return frame.width > 1 && frame.height > 1 && !bars.contains { $0.intersects(frame) }
        }
    }

    /// Tap a shell toolbar button, from the toolbar overflow (More) when the vertical bar
    /// has no room for it (the drawer and Profile buttons on a pushed page).
    ///
    /// - Parameters:
    ///   - identifier: The button's accessibility identifier.
    ///   - labels: Titles the overflow menu may list it under (its `Label` title).
    ///   - app: The running app.
    @MainActor
    static func tapToolbarItem(
        _ identifier: String, overflowLabels labels: [String], in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let direct = app.buttons[identifier]
        if direct.waitForExistence(timeout: 3), direct.isHittable {
            direct.tap()
            return
        }
        let more = app.buttons.matching(identifier: "BottomOverflowBarButtonItem").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10), "No \(identifier) or toolbar overflow", file: file, line: line)
        more.tap()
        let entry = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", identifier, labels)).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "The overflow has no \(identifier) entry", file: file, line: line)
        entry.tap()
    }
}
