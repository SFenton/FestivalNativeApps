import XCTest

/// Issue #15: navigation-bar and floating page buttons accept near-miss taps.
///
/// Each button is tapped 20 pt off-centre in every direction and 15 pt diagonally, all
/// inside a 44 × 44 pt square centred on it (HIG Buttons: "the hit region is at least
/// 44x44 pt"), and must open its own sheet or menu. Neighbours are probed the same way,
/// so a tap that opened the wrong one (overlapping hit regions) fails too.
///
/// Before the fix the floating Quick Links menu answered only ~12 pt either side of its
/// glyph and nowhere above or below it, and the selected-profile monogram only inside
/// its 36 pt-tall capsule. Runs against `tools/mock_service.py --large-catalogue`,
/// exported as `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL`; the in-bar and Quick Links
/// checks skip on the two-song fixture, which has a single Year section and no scroll.
final class NavButtonHitRegionJourneyTests: XCTestCase {
    /// Offsets from a button's centre, all inside a 44 × 44 pt square.
    private static let nearMisses: [CGVector] = [
        CGVector(dx: -20, dy: 0), CGVector(dx: 20, dy: 0),
        CGVector(dx: 0, dy: -20), CGVector(dx: 0, dy: 20),
        CGVector(dx: -15, dy: -15), CGVector(dx: 15, dy: 15),
    ]

    @MainActor
    private func fixtureApp(profile: Bool, tab: String? = nil) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        if let tab { env["FST_DEBUG_TAB"] = tab }
        return FestivalApp.makeApp(env)
    }

    // MARK: - Journeys

    /// Sort, Filter and Quick Links above the tab bar, floating or in the iOS 26.1+
    /// page-tools row beside search (issues #42, #89; Year sort adds Quick Links).
    @MainActor
    func testFloatingToolsAcceptNearMisses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { resetSort(in: app) }
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        try chooseYearSort(in: app)
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open"]
        let frames = ids.map { app.buttons[$0].frame }
        for (id, frame) in zip(ids, frames) {
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(id) \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(id) \(frame)")
        }
        for index in frames.indices.dropLast() {
            XCTAssertLessThan(frames[index].maxX, frames[index + 1].minX, "\(ids[index]) touches its neighbour")
        }

        assertNearMissesOpen(app, "fst.songs.filter", opens: app.buttons["fst.songs.filter.done"]) {
            app.buttons["fst.songs.filter.done"].tap()
        }
        assertNearMissesOpen(app, "fst.songs.sort", opens: app.buttons["fst.songs.sort.done"]) {
            app.buttons["fst.songs.sort.done"].tap()
        }
        assertNearMissesOpen(app, "fst.quick-links.open", opens: quickLinksRow(in: app)) {
            Self.closeQuickLinks(in: app)
        }
    }

    /// Drawer, Search, bell and the selected-profile monogram in the navigation bar.
    @MainActor
    func testHeaderButtonsAcceptNearMisses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        XCTAssertTrue(app.buttons["fst.shell.profile"].waitForExistence(timeout: 15))
        assertNearMissesOpen(app, "fst.shell.drawer.open", opens: app.buttons["fst.shell.drawer.close"]) {
            app.buttons["fst.shell.drawer.close"].tap()
        }
        assertNearMissesOpen(app, "fst.global-search.open", opens: app.buttons["fst.global-search.close"]) {
            app.buttons["fst.global-search.close"].tap()
        }
        assertNearMissesOpen(app, "fst.shell.notifications", opens: app.buttons["fst.notifications.close"]) {
            app.buttons["fst.notifications.close"].tap()
        }
        assertNearMissesOpen(app, "fst.shell.profile", opens: app.buttons["fst.profile.close"]) {
            app.buttons["fst.profile.close"].tap()
        }
    }

    /// Choose Profile (anonymous) and Suggestions' Filter in the navigation bar.
    @MainActor
    func testChooseProfileAndSuggestionsFilterAcceptNearMisses() throws {
        continueAfterFailure = false
        let anonymous = fixtureApp(profile: false)
        anonymous.launch()
        XCTAssertTrue(anonymous.buttons["fst.shell.profile"].waitForExistence(timeout: 15))
        assertNearMissesOpen(anonymous, "fst.shell.profile", opens: anonymous.buttons["fst.profile.close"]) {
            anonymous.buttons["fst.profile.close"].tap()
        }
        anonymous.terminate()

        let app = fixtureApp(profile: true, tab: "suggestions")
        app.launch()
        assertNearMissesOpen(
            app, "fst.suggestions.filter-button", opens: app.buttons["fst.suggestions.filter.done"]
        ) {
            app.buttons["fst.suggestions.filter.done"].tap()
        }
    }

    /// Sort, Filter and Quick Links after they rise into the navigation bar (issue #13).
    @MainActor
    func testToolsInTheBarAcceptNearMisses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { resetSort(in: app) }
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        if app.buttons["fst.songs.search.open"].waitForExistence(timeout: 3) {
            throw XCTSkip("iOS 26.1+: the tools stay in the bottom page-tools row while scrolled (issues #42, #89).")
        }
        try chooseYearSort(in: app)
        app.swipeUp()
        let inBar = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated {
                app.buttons["fst.quick-links.open"].frame.maxY
                    <= app.navigationBars.firstMatch.frame.maxY + 1
            }
        }, object: nil)
        guard XCTWaiter.wait(for: [inBar], timeout: 10) == .completed else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        assertNearMissesOpen(app, "fst.songs.sort", opens: app.buttons["fst.songs.sort.done"]) {
            app.buttons["fst.songs.sort.done"].tap()
        }
        assertNearMissesOpen(app, "fst.songs.filter", opens: app.buttons["fst.songs.filter.done"]) {
            app.buttons["fst.songs.filter.done"].tap()
        }
        assertNearMissesOpen(app, "fst.quick-links.open", opens: quickLinksRow(in: app)) {
            Self.closeQuickLinks(in: app)
        }
    }

    // MARK: - Helpers

    /// Tap each near miss around button `id`, expect `opens` to appear, then close it.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - id: Accessibility identifier of the button under test.
    ///   - opens: An element only that button's sheet or menu shows.
    ///   - close: Dismisses the sheet or menu again.
    @MainActor
    private func assertNearMissesOpen(
        _ app: XCUIApplication, _ id: String, opens: XCUIElement, close: () -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let button = app.buttons.matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "\(id) missing", file: file, line: line)
        let frame = button.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for offset in Self.nearMisses {
            origin.withOffset(CGVector(dx: frame.midX + offset.dx, dy: frame.midY + offset.dy)).tap()
            XCTAssertTrue(
                opens.waitForExistence(timeout: 3),
                "\(id) \(frame) ignored a tap at (\(Int(offset.dx)), \(Int(offset.dy))) pt from its centre",
                file: file, line: line
            )
            close()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: opens)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, file: file, line: line)
        }
    }

    /// Any row of the open Quick Links menu.
    @MainActor
    private func quickLinksRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.quick-links.item.'")).firstMatch
    }

    /// Close the Quick Links menu (floating or in the bar) by tapping away from it; the
    /// dismissing tap is consumed. A legacy sheet closes with its close button.
    @MainActor
    private static func closeQuickLinks(in app: XCUIApplication) {
        let close = app.buttons["fst.quick-links.close"]
        if close.exists {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        }
    }

    /// Switch Songs to the Year sort, whose sections bring Quick Links.
    @MainActor
    private func chooseYearSort(in app: XCUIApplication) throws {
        app.buttons["fst.songs.sort"].tap()
        let year = app.buttons.matching(identifier: "fst.songs.sort.mode")
            .matching(NSPredicate(format: "label == %@", "Year")).firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 10))
        year.tap()
        app.buttons["fst.songs.sort.done"].tap()
        guard app.buttons["fst.quick-links.open"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Fixture catalogue has one Year section; Quick Links stays hidden.")
        }
    }

    /// Restore the default sort for later journeys sharing the simulator.
    @MainActor
    private func resetSort(in app: XCUIApplication) {
        guard app.state == .runningForeground else { return }
        let sort = app.buttons["fst.songs.sort"]
        guard sort.waitForExistence(timeout: 3) else { return }
        sort.tap()
        let reset = app.buttons["fst.songs.sort.reset"]
        if reset.waitForExistence(timeout: 5) { reset.tap() }
        app.buttons["fst.songs.sort.done"].tap()
    }
}
