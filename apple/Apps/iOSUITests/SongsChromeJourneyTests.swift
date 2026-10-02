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

    /// At the top the tools float above the tab bar and the rows clear them; once
    /// scrolled (profile selected) they move into the navigation bar (operator batch 7).
    @MainActor
    func testToolsFloatAtTopAndMoveIntoTheBarOnScroll() throws {
        try requireLargeCatalogue()
        continueAfterFailure = false
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8781",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ])
        app.launch()
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        let tabs = app.tabBars.firstMatch
        XCTAssertGreaterThan(sort.frame.midY, tabs.frame.minY - 80, "Sort floats above the tab bar")
        let list = app.descendants(matching: .any).matching(identifier: "fst.songs.list").firstMatch
        list.swipeUp()
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in sort.exists && sort.frame.midY < 160 }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 5), .completed, "Sort moved into the bar")
        XCTAssertTrue(app.buttons["fst.songs.filter"].exists)
        for _ in 0..<12 { list.swipeDown() }
        let back = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in sort.exists && sort.frame.midY > tabs.frame.minY - 80 },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 5), .completed, "Sort returned to the dock")
    }

    /// The large catalogue (`mock_service.py --large-catalogue`: 108 extra songs over
    /// #, A–Z), separate from the default `:8765` fixture whose two songs share one
    /// letter and hide the rail:
    ///
    ///     python3 tools/mock_service.py --large-catalogue --port 8781
    private static let largeCatalogueOrigin = "http://127.0.0.1:8781"

    /// Skip unless the large-catalogue fixture answers.
    private func requireLargeCatalogue() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.largeCatalogueOrigin)/api/songs"))
        let done = expectation(description: "large catalogue probe")
        let reachable = LockedFlag()
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            // The default fixture has 2 songs; the large one well over 100.
            reachable.set(ok && (data?.count ?? 0) > 20_000)
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        try XCTSkipUnless(reachable.value, "Start `mock_service.py --large-catalogue --port 8781`")
    }

    /// The A–Z rail is centred between the navigation bar and the tab bar, stays put when
    /// the large title collapses, scrubbing collapses the title like a manual scroll, and
    /// a scrub near the bottom jumps to a late letter's section.
    @MainActor
    func testRailCentredStableAndCollapsesTitle() throws {
        try requireLargeCatalogue()
        continueAfterFailure = false
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.largeCatalogueOrigin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ])
        app.launchArguments += ["-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 10), "Multi-letter catalogue shows the rail")
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
        let lateHeader = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'fst.songs.section.' AND label IN %@",
            ["U", "V", "W", "X", "Y", "Z"]
        )).firstMatch
        XCTAssertTrue(lateHeader.waitForExistence(timeout: 5), "Scrub did not reach a late section")
        XCTAssertTrue(lateHeader.isHittable)
        XCTAssertFalse(
            app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH 'fst.songs.section.' AND label == 'A'"
            )).firstMatch.isHittable,
            "The A section should have scrolled away"
        )
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
}

/// A thread-safe Bool for URLSession callbacks.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set(_ newValue: Bool) { lock.withLock { stored = newValue } }
}
