import XCTest

/// iPhone chrome around the Songs list (operator batch 3, 2026-09-28): the A–Z rail is
/// centred and stable, scrubbing collapses the large title, the last row clears the
/// floating tools, and the bell needs a selected profile. Loopback fixture only.
final class SongsChromeJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp(profile: Bool) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ]
        if profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        return FestivalApp.makeApp(env)
    }

    /// The bell shows only with a selected profile; Search and the avatar always show.
    @MainActor
    func testBellNeedsSelectedProfile() throws {
        continueAfterFailure = false
        let anonymous = fixtureApp(profile: false)
        anonymous.launch()
        XCTAssertTrue(anonymous.buttons["fst.global-search.open"].waitForExistence(timeout: 15))
        XCTAssertTrue(anonymous.buttons["fst.shell.profile"].exists)
        XCTAssertFalse(anonymous.buttons["fst.shell.notifications"].exists)
        anonymous.terminate()

        let selected = fixtureApp(profile: true)
        selected.launch()
        XCTAssertTrue(selected.buttons["fst.shell.notifications"].waitForExistence(timeout: 15))
    }

    /// Scrolled to the end, the last song row ends above the floating Filter/Sort buttons.
    @MainActor
    func testLastRowClearsFloatingTools() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        let list = app.descendants(matching: .any).matching(identifier: "fst.songs.list").firstMatch
        for _ in 0..<4 { list.swipeUp() }
        let last = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(
            last.frame.maxY, sort.frame.minY + 1,
            "Last row \(last.frame) runs under the floating Sort button \(sort.frame)"
        )
    }

    /// The A–Z rail is centred between the navigation bar and the tab bar, stays put when
    /// the large title collapses, and scrubbing collapses the title like a manual scroll.
    ///
    /// Needs a catalogue with at least two initial letters; the loopback fixture's two
    /// songs both start with "F", so this skips there (evidence: lane screenshots).
    @MainActor
    func testRailCentredStableAndCollapsesTitle() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: false)
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        guard rail.waitForExistence(timeout: 3) else {
            throw XCTSkip("Fixture catalogue has a single section; the A–Z rail is hidden.")
        }
        let bar = app.navigationBars.firstMatch.frame
        let tabs = app.tabBars.firstMatch.frame
        let before = rail.frame
        let centre = (bar.maxY + tabs.minY) / 2
        XCTAssertLessThan(abs(before.midY - centre), (tabs.minY - bar.maxY) * 0.2)
        let filter = app.searchFields["Filter Songs"]
        XCTAssertTrue(filter.isHittable)
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertLessThan(abs(rail.frame.midY - before.midY), 4, "Rail moved when the title collapsed")
        XCTAssertFalse(filter.isHittable, "Scrubbing did not collapse the large title")
    }

    /// Reversing the sort re-orders the list and shows it from the top: the new first
    /// row sits above the old one and is fully visible under the header.
    @MainActor
    func testReorderShowsNewOrderFromTop() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: false)
        app.launch()
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(orbit.waitForExistence(timeout: 15) && pulse.exists)
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)
        app.buttons["fst.songs.sort"].tap()
        let descending = app.buttons["fst.songs.sort.direction.descending"]
        XCTAssertTrue(descending.waitForExistence(timeout: 10))
        descending.tap()
        app.buttons["fst.songs.sort.done"].tap()
        let reordered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in pulse.frame.minY < orbit.frame.minY }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 10), .completed)
        XCTAssertTrue(pulse.isHittable, "The new first row is not visible at the top")
        // Restore the default for later journeys sharing the simulator.
        app.buttons["fst.songs.sort"].tap()
        app.buttons["fst.songs.sort.reset"].tap()
        app.buttons["fst.songs.sort.done"].tap()
    }

    /// Issue #5: with a profile selected, scrolling down and back up near the top froze
    /// and then crashed the app. Moving Filter/Sort into the bar changed the top inset,
    /// which flipped the scrolled-away decision back, without end. Every swipe and
    /// slow drag must leave the app idle, and back at the top the large title, filter
    /// field, first row and floating tools return.
    ///
    /// Needs a catalogue that scrolls: run against `tools/mock_service.py
    /// --large-catalogue` and pass its URL as `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL`
    /// (the default two-song fixture on 8765 has nothing to scroll, so this skips).
    @MainActor
    func testScrollingBackToTopNearTheTopStaysResponsive() throws {
        continueAfterFailure = false
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ])
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        guard rail.waitForExistence(timeout: 3) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        func drag(_ from: Double, _ to: Double) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                withVelocity: .slow, thenHoldForDuration: 0.3
            )
        }
        // The reported path: down a little, then back up to the top.
        app.swipeUp()
        app.swipeUp()
        for _ in 0..<3 { app.swipeDown() }
        // Slow drags across the threshold just below the collapsed title.
        drag(0.7, 0.5)
        drag(0.5, 0.6)
        drag(0.7, 0.55)
        drag(0.55, 0.68)
        drag(0.7, 0.4)
        drag(0.4, 0.7)
        // Fast flicks in both directions, ending at the top.
        for _ in 0..<3 {
            app.swipeUp()
            app.swipeDown()
        }
        for _ in 0..<4 { app.swipeDown() }

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.searchFields["Filter Songs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields["Filter Songs"].isHittable, "Large title header did not return")
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-song-1"].isHittable, "First row not shown")
        XCTAssertTrue(app.buttons["fst.songs.sort"].isHittable, "Floating Sort did not return")
    }
}
