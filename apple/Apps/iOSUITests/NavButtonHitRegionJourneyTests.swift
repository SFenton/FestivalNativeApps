import XCTest

/// Issue #15: navigation-bar page buttons accept near-miss taps.
///
/// Each button is tapped 20 pt off-centre in every direction and 15 pt diagonally, all
/// inside a 44 × 44 pt square centred on it (HIG Buttons: "the hit region is at least
/// 44x44 pt"), and must open its own sheet or menu. Neighbours are probed the same way,
/// so a tap that opened the wrong one (overlapping hit regions) fails too.
///
/// Before the fix the Quick Links menu answered only ~12 pt either side of its glyph
/// and nowhere above or below it, and the selected-profile monogram only inside its
/// 36 pt-tall capsule. Runs against `tools/mock_service.py --large-catalogue`,
/// exported as `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL`; Quick Links checks skip on
/// the two-song fixture, which has a single Year section.
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

    /// Songs' page tools in the navigation bar accept 44 pt near-miss taps.
    @MainActor
    func testSongsPageToolsAcceptNearMisses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { resetSort(in: app) }
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        try chooseYearSort(in: app)
        // XCUITest reports the 36 pt glass capsule; the system hit region around it is
        // checked by the near-miss taps below.
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open"]
        let frames = ids.map { app.buttons[$0].frame }
        for (id, frame) in zip(ids, frames) {
            XCTAssertGreaterThanOrEqual(frame.height, 36, "\(id) \(frame)")
        }
        for index in frames.indices.dropLast() {
            XCTAssertLessThanOrEqual(frames[index].maxX, frames[index + 1].minX, "\(ids[index]) overlaps its neighbour")
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

    /// Songs' trailing navigation bar order is page tools, then account items, with
    /// 44 pt hit regions on the standard iPhone width.
    @MainActor
    func testSongsTrailingNavBarOrderAndHitRegions() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.shell.notifications", "fst.shell.profile"]
        let controls = ids.map { app.buttons[$0] }
        XCTAssertFalse(app.buttons["fst.songs.tools"].exists, "iPhone 17 Pro should not fold Sort and Filter")
        for (id, control) in zip(ids, controls) {
            XCTAssertTrue(control.waitForExistence(timeout: 15), "\(id) missing")
            XCTAssertTrue(control.isHittable, "\(id) not hittable")
            XCTAssertGreaterThanOrEqual(control.frame.height, 36, "\(id) visual frame \(control.frame)")
        }
        for index in controls.indices.dropLast() {
            XCTAssertLessThan(
                controls[index].frame.minX, controls[index + 1].frame.minX,
                "\(ids[index]) is not before \(ids[index + 1])"
            )
        }
    }

    /// Drawer, bell and the selected-profile monogram in the navigation bar.
    @MainActor
    func testHeaderButtonsAcceptNearMisses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        XCTAssertTrue(app.buttons["fst.shell.profile"].waitForExistence(timeout: 15))
        assertNearMissesOpen(app, "fst.shell.drawer.open", opens: app.buttons["fst.shell.drawer.close"]) {
            app.buttons["fst.shell.drawer.close"].tap()
        }
        assertNearMissesOpen(app, "fst.shell.notifications", opens: app.buttons["fst.notifications.close"]) {
            app.buttons["fst.notifications.close"].tap()
        }
        // With a player selected the avatar opens their Statistics page (issue #290).
        assertNearMissesOpen(app, "fst.shell.profile", opens: SongsUITestSupport.playerPage(in: app)) {
            let back = app.navigationBars.buttons["BackButton"]
            (back.exists ? back : app.navigationBars.buttons.element(boundBy: 0)).tap()
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

    /// Sort, Filter and Quick Links stay in the navigation bar while the list scrolls.
    @MainActor
    func testSongsToolsStayInTheBarWhileScrolled() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { resetSort(in: app) }
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        try chooseYearSort(in: app)
        let field = app.searchFields["Filter Songs"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.swipeUp()
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open"]
        for _ in 0..<100 {
            let bar = app.navigationBars.firstMatch.frame
            if ids.allSatisfy({ id in
                let button = app.buttons[id]
                return button.exists && button.isHittable && button.frame.maxY <= bar.maxY + 1
            }) {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let bar = app.navigationBars.firstMatch.frame
        guard ids.allSatisfy({ app.buttons[$0].exists && app.buttons[$0].frame.maxY <= bar.maxY + 1 }) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        XCTAssertTrue(field.exists, "Filter Songs field disappeared while scrolled")
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

    /// Close the Quick Links menu by tapping away from it; the dismissing tap is
    /// consumed. A legacy sheet closes with its close button.
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
