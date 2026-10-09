import XCTest

/// The iPad Songs Filter sheet without a profile (#432, for #77) with a hardware keyboard.
///
/// Without Full Keyboard Access, iPadOS Tab never stops on buttons or switches, by design
/// (HIG Keyboards: iPadOS should "avoid keyboard navigation for controls (buttons,
/// segmented controls, switches); leave controls … to Full Keyboard Access"; Focus and
/// selection: "you only need focus for content like list items, text fields and search
/// fields, not buttons, sliders or toggles"). Automation cannot turn Full Keyboard Access on
/// in the simulator, and `XCUIElement.hasFocus` reports nothing there. The sheet is the
/// shared SwiftUI `SongsFilterSheet`; the hosted `SongsFilterKeyboardTests` prove its Tab
/// and Shift-Tab order and Space activation of the Filter entry, General disclosures,
/// Select All / Clear All, switches, Reset Filters and Close with Keyboard navigation on
/// (the Mac's Full Keyboard Access). Here the iPad's own default keyboard command is
/// proved: ⌘. ("Cancel an operation", HIG Keyboards) closes the sheet without changing the
/// filter, and Songs is back afterwards. UIKit sheets do not take bare Escape on iPadOS
/// (checked with the menu bar's Escape command removed, 2026-10), so it is not asserted.
///
/// Needs `tools/mock_service.py` on 127.0.0.1:8765
/// (`TEST_RUNNER_FST_SONGS_FILTER_FIXTURE_PORT=<port>` selects another listener).
final class SongsFilterKeyboardJourneyTests: XCTestCase {
    override func setUpWithError() throws {
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad, "iPad hardware-keyboard journey")
        continueAfterFailure = false
    }

    /// Fixture Songs with no profile.
    @MainActor
    private func launchSongs() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        let port = ProcessInfo.processInfo.environment["FST_SONGS_FILTER_FIXTURE_PORT"] ?? "8765"
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:\(port)"
        app.launch()
        XCTAssertTrue(app.collectionViews["fst.songs.list"].waitForExistence(timeout: 20), "Songs did not load")
        return app
    }

    /// Open Filter from its toolbar button and wait for the sheet.
    @MainActor
    private func openFilter(_ app: XCUIApplication) -> XCUIElement {
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10), "Filter Songs is offered without a profile")
        filter.tap()
        let year = app.descendants(matching: .any).matching(identifier: "fst.songs.filter.year").firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 10), "Filter did not open on its General section")
        return app.buttons["fst.songs.filter.done"]
    }

    /// ⌘. closes the Filter sheet, leaving the filter unchanged, and Filter reopens after it.
    @MainActor
    func testCommandPeriodClosesFilter() throws {
        let app = launchSongs()
        let filter = app.buttons["fst.songs.filter"]
        let before = filter.value as? String ?? ""
        for round in 1...2 {
            let close = openFilter(app)
            XCTAssertTrue(close.exists, "Close is offered beside the keyboard command")
            app.typeKey(".", modifierFlags: .command)
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "⌘. closes Filter (round \(round))")
            XCTAssertTrue(filter.waitForExistence(timeout: 5), "Songs is back after ⌘. (round \(round))")
            XCTAssertEqual(filter.value as? String ?? "", before, "⌘. leaves the filter unchanged")
        }
    }
}
