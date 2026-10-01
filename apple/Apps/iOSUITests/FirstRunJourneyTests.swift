import XCTest

/// First-run carousel journeys (operator batch 6 item 6.7, batch 7): Next first, Skip while
/// pages remain, no disabled Back, Back only after the first page, dismissal by swiping down or tapping
/// outside, and "only pages actually seen count" across a relaunch.
///
/// Hosted (macOS) snapshot coverage for individual carousel states lives in
/// `FirstRunHostedTests.swift`; the viewed-page bookkeeping is unit-tested in
/// `FestivalCoreTests/SettingsBatch6Tests.swift` (`FirstRunViewing`). Needs
/// `tools/mock_service.py --port 8765`.
final class FirstRunJourneyTests: XCTestCase {
    /// A Songs row, found by identifier regardless of accessibility role.
    ///
    /// - Parameters:
    ///   - app: The running application.
    ///   - songId: Fixture song id.
    /// - Returns: The row element, whatever its role.
    @MainActor
    private func songsRow(_ app: XCUIApplication, _ songId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "fst.songs.row.\(songId)").firstMatch
    }

    /// The fixture app with the given first-run mode.
    ///
    /// - Parameter mode: `force` (every gate-passing slide, every launch) or `on` (real
    ///   seen-state).
    /// - Returns: An unlaunched app.
    @MainActor
    private func fixtureApp(mode: String = "force") -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": mode,
        ])
    }

    /// The carousel slide whose combined label starts with `title`.
    @MainActor
    private func slide(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(title). ")).firstMatch
    }

    /// Wait until the carousel has closed and Songs is interactive again.
    @MainActor
    private func assertCarouselClosed(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["fst.first-run.close"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, file: file, line: line)
        XCTAssertTrue(songsRow(app, "fixture-pulse").waitForExistence(timeout: 15), file: file, line: line)
    }

    /// The first page offers Next and Skip but no Back; after Next, Back appears beneath
    /// Next and returns to the first page; Skip closes the guide.
    @MainActor
    func testNextFirstThenBackAppears() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fst.first-run.skip"].exists, "Skip while pages remain")
        XCTAssertFalse(app.buttons["fst.first-run.back"].exists, "No Back on the first page")
        XCTAssertTrue(app.otherElements["fst.first-run.dots"].exists || app.descendants(matching: .any)
            .matching(identifier: "fst.first-run.dots").firstMatch.exists)
        SongsUITestSupport.record(app, name: "first-run-first-page")

        next.tap()
        let back = app.buttons["fst.first-run.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(back.isHittable)
        XCTAssertLessThan(next.frame.minY, back.frame.minY, "Next/Done sits before Back")
        SongsUITestSupport.record(app, name: "first-run-second-page")
        back.tap()
        let backGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: back
        )
        XCTAssertEqual(XCTWaiter.wait(for: [backGone], timeout: 10), .completed)
        app.buttons["fst.first-run.skip"].tap()
        assertCarouselClosed(app)
    }

    /// Issue #4: the carousel carries the same native toolbar "Close" as the Profile search
    /// sheet (a navigation-bar button labelled "Close", not a small ✕ glyph), and tapping
    /// it closes the guide.
    @MainActor
    func testCloseIsNativeToolbarButton() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15), "Close lives in the sheet's navigation bar")
        XCTAssertEqual(close.label, "Close")
        XCTAssertTrue(close.isHittable)
        SongsUITestSupport.record(app, name: "first-run-native-close")
        close.tap()
        assertCarouselClosed(app)
    }

    /// Swiping the carousel down dismisses it, like any sheet.
    @MainActor
    func testSwipeDownDismissesCarousel() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let window = app.windows.firstMatch
        // Start on the sheet's top edge (grabber / close row), not on the dimmed page.
        let top = close.frame.midY
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: top))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            )
        assertCarouselClosed(app)
    }

    /// Tapping the dimmed page above the carousel dismisses it (the web's overlay click).
    @MainActor
    func testTapOutsideDismissesCarousel() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "first-run-outside-area")
        // Below the status bar (a status-bar tap is the system's scroll-to-top) and above the
        // sheet's top edge.
        let window = app.windows.firstMatch
        let sheetTop = close.frame.minY - 40
        let y = min(130, sheetTop - 10)
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: y)).tap()
        assertCarouselClosed(app)
    }

    /// Only viewed pages count as seen: a Settings replay closed after two pages leaves the
    /// rest unseen, so the next launch's Songs guide starts at the third slide.
    @MainActor
    func testOnlyViewedPagesAreMarkedSeen() throws {
        continueAfterFailure = false
        let app = fixtureApp(mode: "on")
        app.launch()
        // A previous run may have left Songs slides unseen; close whatever shows.
        let close = app.buttons["fst.first-run.close"]
        if close.waitForExistence(timeout: 6) { close.tap() }
        XCTAssertTrue(songsRow(app, "fixture-pulse").waitForExistence(timeout: 15))

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let replay = app.buttons["fst.settings.first-run.songs"]
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        replay.tap()
        XCTAssertTrue(slide(app, titled: "Song List").waitForExistence(timeout: 10))
        app.buttons["fst.first-run.next"].tap()
        XCTAssertTrue(slide(app, titled: "Sort Songs").waitForExistence(timeout: 10))
        app.buttons["fst.first-run.close"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        app.terminate()

        let relaunched = fixtureApp(mode: "on")
        relaunched.launch()
        let navigation = slide(relaunched, titled: "Navigation")
        XCTAssertTrue(navigation.waitForExistence(timeout: 15), "Unviewed pages must show next time")
        XCTAssertTrue(navigation.isHittable, "The guide resumes at the first unviewed page")
        XCTAssertFalse(slide(relaunched, titled: "Song List").isHittable, "Viewed pages stay seen")
        SongsUITestSupport.record(relaunched, name: "first-run-resumes-unseen")
        relaunched.buttons["fst.first-run.close"].tap()
    }
}
