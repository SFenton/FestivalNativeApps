import XCTest

/// Issue #15: page buttons accept near-miss taps. Since issue #92 the page tools and
/// Notifications live in the tab-bar bottom accessory; since issue #300 Profile is the
/// navigation bar's trailing button.
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

    /// Songs' page tools in the tab-bar accessory accept 44 pt near-miss taps.
    @MainActor
    func testSongsPageToolsAcceptNearMisses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { resetSort(in: app) }
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        try chooseYearSort(in: app)
        // Each accessory item fills its slot, so the reported frame is the hit region.
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open"]
        let frames = ids.map { app.buttons[$0].frame }
        for (id, frame) in zip(ids, frames) {
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(id) \(frame)")
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(id) \(frame)")
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

    /// Issue #92: Songs' page tools, then Notifications, sit left to right in the tab-bar
    /// accessory with 44 pt hit regions on the standard iPhone width; none of them is
    /// left in the navigation bar. Issue #300: Notifications is pinned to the accessory's
    /// trailing edge and Profile is the navigation bar's trailing-most button.
    @MainActor
    func testSongsAccessoryOrderAndHitRegions() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.shell.notifications"]
        let accessory = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        XCTAssertTrue(accessory.waitForExistence(timeout: 15), "Tab-bar accessory missing")
        let controls = ids.map { accessory.buttons[$0] }
        XCTAssertFalse(app.buttons["fst.songs.tools"].exists, "iPhone 17 Pro should not fold Sort and Filter")
        for (id, control) in zip(ids, controls) {
            XCTAssertTrue(control.waitForExistence(timeout: 15), "\(id) missing from the accessory")
            XCTAssertTrue(control.isHittable, "\(id) not hittable")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, "\(id) hit region \(control.frame)")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, "\(id) hit region \(control.frame)")
            XCTAssertFalse(app.navigationBars.buttons[id].exists, "\(id) is still in the navigation bar")
            XCTAssertGreaterThan(control.frame.minY, app.navigationBars.firstMatch.frame.maxY)
        }
        for index in controls.indices.dropLast() {
            XCTAssertLessThan(
                controls[index].frame.minX, controls[index + 1].frame.minX,
                "\(ids[index]) is not before \(ids[index + 1])"
            )
        }
        // The bell keeps its trailing slot whatever the page's tools are.
        XCTAssertEqual(
            controls[controls.count - 1].frame.maxX, accessory.frame.maxX, accuracy: 16,
            "Notifications is not at the accessory's trailing edge"
        )
        let profile = app.navigationBars.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.exists, "Profile is not in the navigation bar")
        XCTAssertFalse(accessory.buttons["fst.shell.profile"].exists, "Profile is still in the accessory")
        XCTAssertTrue(profile.isHittable, "Profile not hittable")
        let trailing = app.navigationBars.firstMatch.buttons.allElementsBoundByIndex
            .filter { $0.frame.minY < app.navigationBars.firstMatch.frame.minY + 50 }
            .map(\.frame.maxX).max() ?? 0
        XCTAssertEqual(profile.frame.maxX, trailing, accuracy: 0.5, "Profile is not the rightmost header button")
    }

    /// The drawer and selected-profile monogram (navigation bar) and the bell (tab-bar
    /// accessory).
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

    /// Choose Profile (anonymous, navigation bar) and Suggestions' Filter in the tab-bar
    /// accessory.
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

    /// Issue #92: scrolling minimizes the tab bar and moves the accessory inline. Issue
    /// #300: it keeps the same items as when expanded (Sort, Filter, Quick Links |
    /// Notifications), each a 44 pt slot without overlap, and they still accept
    /// near-miss taps; Quick Links opens its choices as a sheet (iOS 26 does not open a
    /// `Menu` there).
    @MainActor
    func testSongsToolsStayInTheInlineAccessoryWhileScrolled() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { resetSort(in: app) }
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        try chooseYearSort(in: app)
        let field = app.searchFields["Filter Songs"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.swipeUp()
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open", "fst.shell.notifications"]
        for _ in 0..<100 {
            if ids.allSatisfy({ app.buttons[$0].exists && app.buttons[$0].isHittable }) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard ids.allSatisfy({ app.buttons[$0].exists }) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        XCTAssertFalse(app.buttons["fst.songs.tools"].exists, "Sort and Filter folded while inline")
        XCTAssertTrue(field.exists, "Filter Songs field disappeared while scrolled")
        let frames = ids.map { app.buttons[$0].frame }
        for (id, frame) in zip(ids, frames) {
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(id) \(frame)")
            XCTAssertGreaterThan(frame.minY, app.navigationBars.firstMatch.frame.maxY, "\(id) in the header")
        }
        for index in frames.indices.dropLast() {
            XCTAssertLessThanOrEqual(frames[index].maxX, frames[index + 1].minX, "\(ids[index]) overlaps its neighbour")
        }
        assertNearMissesOpen(app, "fst.songs.filter", opens: app.buttons["fst.songs.filter.done"]) {
            app.buttons["fst.songs.filter.done"].tap()
        }
        assertNearMissesOpen(app, "fst.quick-links.open", opens: quickLinksRow(in: app)) {
            Self.closeQuickLinks(in: app)
        }
    }

    /// Issue #300: at an accessibility text size Sort and Filter fold into one "Sort and
    /// Filter" control both expanded and inline, so the item set never changes while the
    /// accessory morphs. The folded control opens its choices as a sheet, and a choice
    /// runs once the sheet has closed (Filter… opens the Filter sheet).
    @MainActor
    func testAccessibilityTextFoldIsTheSameExpandedAndInline() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        let folded = app.buttons["fst.songs.tools"]
        XCTAssertTrue(folded.waitForExistence(timeout: 15), "Sort and Filter not folded at AX text size")
        XCTAssertFalse(app.buttons["fst.songs.sort"].exists)
        let field = app.searchFields["Filter Songs"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.swipeUp()
        for _ in 0..<30 {
            XCTAssertTrue(folded.exists, "Sort and Filter unfolded while the accessory moved")
            XCTAssertFalse(app.buttons["fst.songs.sort"].exists, "Sort reappeared while the accessory moved")
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertGreaterThanOrEqual(folded.frame.width, 44)
        let menuClose = app.buttons["fst.page-tools.menu.close"]
        assertNearMissesOpen(app, "fst.songs.tools", opens: app.buttons["fst.songs.tools.filter"]) {
            menuClose.tap()
        }
        folded.tap()
        XCTAssertTrue(app.buttons["fst.songs.tools.filter"].waitForExistence(timeout: 5))
        app.buttons["fst.songs.tools.filter"].tap()
        XCTAssertTrue(app.buttons["fst.songs.filter.done"].waitForExistence(timeout: 5))
        app.buttons["fst.songs.filter.done"].tap()
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
        // A closing sheet briefly leaves the accessory's items without a frame.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed, "\(id) not hittable", file: file, line: line)
        // A `Menu` ignores taps while a sheet is still animating away.
        RunLoop.current.run(until: Date().addingTimeInterval(1))
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
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
    }

    /// Any row of the open Quick Links menu.
    @MainActor
    private func quickLinksRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.quick-links.item.'")).firstMatch
    }

    /// Close the Quick Links menu by tapping away from it; the dismissing tap is
    /// consumed. A legacy sheet, or the inline accessory's sheet, closes with its close
    /// button.
    @MainActor
    private static func closeQuickLinks(in app: XCUIApplication) {
        let close = app.buttons["fst.quick-links.close"]
        let inlineClose = app.buttons["fst.page-tools.menu.close"]
        if close.exists {
            close.tap()
        } else if inlineClose.exists {
            inlineClose.tap()
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
