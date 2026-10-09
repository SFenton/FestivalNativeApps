import UIKit
import XCTest

/// iPhone chrome around the Songs list (operator batch 3, 2026-09-28): the A–Z rail is
/// centred and stable, scrubbing collapses the large title, the last row clears the
/// tab bar, and the bell needs a selected profile. Loopback fixture only.
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

    /// The bell shows only with a selected profile; the Search tab and avatar always show.
    @MainActor
    func testBellNeedsSelectedProfile() throws {
        continueAfterFailure = false
        let anonymous = fixtureApp(profile: false)
        anonymous.launch()
        XCTAssertTrue(anonymous.tabBars.buttons["Search"].waitForExistence(timeout: 15))
        XCTAssertTrue(anonymous.buttons["fst.shell.profile"].exists)
        XCTAssertFalse(anonymous.buttons["fst.shell.notifications"].exists)
        anonymous.terminate()

        let selected = fixtureApp(profile: true)
        selected.launch()
        XCTAssertTrue(selected.buttons["fst.shell.notifications"].waitForExistence(timeout: 15))
    }

    /// Scrolled to the end, the last song row ends above the tab bar.
    @MainActor
    func testLastRowClearsTabBar() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        let list = app.descendants(matching: .any).matching(identifier: "fst.songs.list").firstMatch
        for _ in 0..<4 { list.swipeUp() }
        let last = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            last.frame.maxY, tabBar.frame.minY + 1,
            "Last row \(last.frame) runs under the tab bar \(tabBar.frame)"
        )
    }

    /// The pinned Filter Songs field filters the fixture list as text changes, and
    /// clearing it restores the original rows.
    @MainActor
    func testFilterSongsFieldFiltersAndClears() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: false)
        app.launch()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertTrue(orbit.exists)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        let before = rows.count
        XCTAssertGreaterThanOrEqual(before, 2)

        let field = SongsUITestSupport.songsSearchField(in: app)
        field.tap()
        field.typeText("Pulse")
        for _ in 0..<50 where !(rows.count < before && pulse.exists && !orbit.exists) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertLessThan(rows.count, before)
        XCTAssertTrue(pulse.exists)
        XCTAssertFalse(orbit.exists)

        let clear = field.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Clear text", "Clear")
        ).firstMatch
        if clear.waitForExistence(timeout: 2) {
            clear.tap()
        } else {
            field.tap()
            for _ in 0..<5 { field.typeText(XCUIKeyboardKey.delete.rawValue) }
        }
        for _ in 0..<50 where !(rows.count == before && pulse.exists && orbit.exists) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(rows.count, before)
        XCTAssertTrue(pulse.exists)
        XCTAssertTrue(orbit.exists)
    }

    /// The A–Z rail is centred between the navigation bar and the tab bar, stays put when
    /// the large title collapses, and scrubbing collapses the title like a manual scroll.
    /// The pinned Filter Songs field stays visible and usable.
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
        let field = SongsUITestSupport.songsSearchEntry(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(field.isHittable)
        rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        XCTAssertLessThan(abs(rail.frame.midY - before.midY), 4, "Rail moved when the title collapsed")
        XCTAssertLessThan(
            app.navigationBars.firstMatch.frame.maxY, bar.maxY - 30,
            "Scrubbing did not collapse the large title"
        )
        XCTAssertTrue(field.exists, "Filter Songs field disappeared")
    }

    /// Issue #92: Sort and Filter sit in the tab-bar accessory, not the navigation bar,
    /// and stay reachable while the Songs list scrolls; the pinned Filter Songs field
    /// remains present for local filtering. Issue #300: the inline accessory shows the
    /// same items as the expanded one (no fold mid-morph), and Profile stays the
    /// navigation bar's trailing button.
    ///
    /// Needs a catalogue that scrolls (`TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL`, as for
    /// ``testScrollingBackToTopNearTheTopStaysResponsive``); skips on the two-song fixture.
    @MainActor
    func testToolsStayInTheTabBarAccessoryWhileScrolled() throws {
        continueAfterFailure = false
        try assertToolsWhileScrolled(profile: false, tools: ["fst.songs.sort", "fst.songs.filter"])
        try assertToolsWhileScrolled(profile: true, tools: ["fst.songs.sort", "fst.songs.filter"])
    }

    /// Launch the scrolling catalogue and check the Songs tools stay in the accessory.
    ///
    /// - Parameters:
    ///   - profile: Launch with the fixture player selected.
    ///   - tools: Page tool identifiers.
    @MainActor
    private func assertToolsWhileScrolled(profile: Bool, tools: [String]) throws {
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        var env = [
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ]
        if profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        let app = FestivalApp.makeApp(env)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        guard rail.waitForExistence(timeout: 3) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        let field = app.searchFields["Filter Songs"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let who = profile ? "profile" : "anonymous"
        let accessory = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        XCTAssertTrue(accessory.waitForExistence(timeout: 5), "\(who): tab-bar accessory missing")
        func assertInAccessory(_ ids: [String], _ state: String) {
            let bar = app.navigationBars.firstMatch.frame
            XCTAssertTrue(
                app.navigationBars.buttons["fst.shell.profile"].exists, "\(who): Profile left the header \(state)"
            )
            XCTAssertFalse(accessory.buttons["fst.shell.profile"].exists, "\(who): Profile in the accessory \(state)")
            XCTAssertFalse(accessory.buttons["fst.songs.tools"].exists, "\(who): Sort and Filter folded \(state)")
            for id in ids {
                let tool = accessory.buttons[id]
                XCTAssertTrue(tool.exists, "\(who): \(id) missing from the accessory \(state)")
                XCTAssertTrue(tool.isHittable, "\(who): \(id) not hittable \(state)")
                XCTAssertFalse(app.navigationBars.buttons[id].exists, "\(who): \(id) in the header \(state)")
                XCTAssertGreaterThan(tool.frame.minY, bar.maxY, "\(who): \(id) in the header \(state)")
                XCTAssertGreaterThanOrEqual(tool.frame.width, 44, "\(who): \(id) slot under 44 pt")
            }
        }
        assertInAccessory(tools, "at the top")
        app.swipeUp()
        // Inline beside the minimized tab bar the same items stay (issue #300).
        for _ in 0..<100 {
            if tools.allSatisfy({ accessory.buttons[$0].isHittable }) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        assertInAccessory(tools, "while scrolled")
        XCTAssertTrue(field.exists, "\(who): Filter Songs hid while scrolled")
        SongsUITestSupport.record(app, name: "songs-tools-accessory-\(who)")
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
    /// and then crashed the app. The toolbar and search-field insets changed around the
    /// scroll threshold, flipping the scrolled-away decision back without end. Every
    /// swipe and slow drag must leave the app idle, and back at the top the large title,
    /// filter field, first row and toolbar controls remain available.
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
        let search = SongsUITestSupport.songsSearchEntry(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable, "Songs search did not return")
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-song-1"].isHittable, "First row not shown")
        XCTAssertTrue(
            app.buttons["fst.songs.sort"].isHittable || app.buttons["fst.songs.tools"].isHittable,
            "Sort did not remain available"
        )
    }

    /// Issue #5 accessibility (#388): the scroll-away decision #5 stabilised is what
    /// VoiceOver perceives as the floating section bar. At the top it is absent and the
    /// list starts with its "#" heading; scrolled away it names the current section once,
    /// below the navigation bar, over named full-size rows; back at the top it leaves and
    /// the search field, first row and Sort remain reachable. Each state passes the system
    /// accessibility audit (only the documented open Songs findings are accepted).
    ///
    /// Needs the large fixture like ``testScrollingBackToTopNearTheTopStaysResponsive``.
    @MainActor
    func testScrollAwaySectionBarAccessibility() throws {
        continueAfterFailure = false
        let large = try launchScrollAwayFixture(largeText: true)
        let largeRail = railLetterHeight(large)
        large.terminate()
        let app = try launchScrollAwayFixture(largeText: false)
        let growth = largeRail / railLetterHeight(app)
        let walk = try assertScrollAwayAccessibility(
            in: app, label: "default", railGrowth: growth, predictsClipping: true
        )
        guard walk.clipPredictionsAtTop + walk.clipPredictionsScrolled > 0 else { return }
        // Unattributed "Text clipped" at the default size predicts clipping at larger
        // sizes: disprove it where it pointed, at AX5 (the drawer journey's precedent).
        app.terminate()
        let check = try launchScrollAwayFixture(largeText: true)
        if walk.clipPredictionsAtTop > 0 {
            let clipped = try ax5Clipping(check)
            XCTAssertTrue(
                clipped.isEmpty,
                "\(walk.clipPredictionsAtTop) predicted clippings at the top still clip at AX5: \(clipped)"
            )
        }
        if walk.clipPredictionsScrolled > 0 {
            XCTAssertTrue(scrollAway(check), "Section bar never appeared at AX5")
            waitForListToSettle(check)
            let clipped = try ax5Clipping(check)
            XCTAssertTrue(
                clipped.isEmpty,
                "\(walk.clipPredictionsScrolled) predicted clippings scrolled still clip at AX5: \(clipped)"
            )
        }
    }

    /// Issue #5 accessibility (#388) at AX5: the section bar's heading and the A–Z rail's
    /// letters scale with the text (≥ 1.35× their default height, HIG Accessibility
    /// "Support enlargement up to 200%"), the bar stays below the navigation bar, and the
    /// scroll-away path stays responsive and audits clean (the documented open findings
    /// excepted).
    ///
    /// Needs the large fixture like ``testScrollingBackToTopNearTheTopStaysResponsive``.
    @MainActor
    func testScrollAwaySectionBarAccessibilityAtAX5() throws {
        continueAfterFailure = false
        let regular = try launchScrollAwayFixture(largeText: false)
        let defaultRail = railLetterHeight(regular)
        let defaultBar = regular.staticTexts["fst.songs.section-bar"]
        XCTAssertTrue(scrollAway(regular), "Section bar never appeared")
        let defaultHeight = defaultBar.frame.height
        regular.terminate()

        let app = try launchScrollAwayFixture(largeText: true)
        let largeRail = railLetterHeight(app)
        XCTAssertGreaterThanOrEqual(
            largeRail, defaultRail * 1.35,
            "A–Z rail letters did not scale: \(largeRail) pt at AX5, \(defaultRail) pt default"
        )
        let barHeight = try assertScrollAwayAccessibility(
            in: app, label: "ax5", railGrowth: largeRail / defaultRail
        ).barHeight
        XCTAssertGreaterThanOrEqual(
            barHeight, defaultHeight * 1.35,
            "Section bar heading did not scale: \(barHeight) pt at AX5, \(defaultHeight) pt default"
        )
    }

    /// Launch Songs on the large fixture with a profile selected, as #5 was reported.
    ///
    /// - Parameter largeText: Launch at the largest accessibility text size (AX5).
    /// - Returns: The running app on the Songs root.
    /// - Throws: `XCTSkip` when the catalogue is too short to scroll.
    @MainActor
    private func launchScrollAwayFixture(largeText: Bool) throws -> XCUIApplication {
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ])
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-song-1"].waitForExistence(timeout: FestivalApp.budget(15)))
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        guard rail.waitForExistence(timeout: FestivalApp.budget(3)) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        return app
    }

    /// Walk the #5 path (top → scrolled away → back to the top) and check what VoiceOver
    /// meets at each step.
    ///
    /// - Parameters:
    ///   - app: Songs at the top of the large fixture.
    ///   - label: Names the audit activities.
    ///   - railGrowth: How much taller the A–Z rail's letters are at AX5 than at the
    ///     default size, measured in this test
    ///     (``auditScrollAway(_:_:railGrowth:predictsClipping:)``).
    ///   - predictsClipping: Count unattributed "Text clipped" issues as predictions for
    ///     the caller to disprove at AX5 instead of accepting only one.
    /// - Returns: The section bar heading's height while scrolled away, and the
    ///   unattributed clipping predictions at the top (both visits) and scrolled away.
    /// - Throws: A failed audit.
    @MainActor
    @discardableResult
    private func assertScrollAwayAccessibility(
        in app: XCUIApplication, label: String, railGrowth: CGFloat, predictsClipping: Bool = false
    ) throws -> (barHeight: CGFloat, clipPredictionsAtTop: Int, clipPredictionsScrolled: Int) {
        let bar = app.staticTexts["fst.songs.section-bar"]
        let firstTitle = app.staticTexts["fst.songs.section.0"]
        let firstRow = app.buttons["fst.songs.row.fixture-song-1"]
        // At the top: no bar; the list opens on its "#" heading, then its first row.
        XCTAssertFalse(bar.exists, "Section bar shown at the top")
        XCTAssertTrue(firstTitle.exists)
        XCTAssertEqual(firstTitle.label, "#")
        XCTAssertLessThanOrEqual(firstTitle.frame.maxY, firstRow.frame.minY + 1, "Row read before its heading")
        // The A–Z rail (8 pt outer margin inside its frame) stays clear of the expanded
        // search field, whose clear button sits under its trailing end.
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch.frame
        let topSearch = SongsUITestSupport.songsSearchEntry(in: app).frame
        XCTAssertGreaterThanOrEqual(rail.minY + 8, topSearch.maxY, "Rail \(rail) overlaps search \(topSearch)")
        var atTop = try auditScrollAway(
            app, "\(label) top", railGrowth: railGrowth, predictsClipping: predictsClipping
        )

        // Scrolled away: one bar heading naming a section, below the navigation bar.
        XCTAssertTrue(scrollAway(app), "Section bar never appeared")
        waitForListToSettle(app)
        let letters = Set("#ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init))
        XCTAssertTrue(letters.contains(bar.label), "Section bar reads '\(bar.label)'")
        XCTAssertEqual(app.staticTexts.matching(identifier: "fst.songs.section-bar").count, 1)
        let navigation = app.navigationBars.firstMatch.frame
        XCTAssertGreaterThanOrEqual(bar.frame.minY, navigation.maxY - 1, "Bar \(bar.frame) under \(navigation)")
        let barHeight = bar.frame.height
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        let tabs = app.tabBars.firstMatch.frame
        // At AX5 a row can be taller than the band, so count any row showing ≥ 44 pt of it.
        let visible = rows.allElementsBoundByIndex.filter {
            $0.isHittable && min($0.frame.maxY, tabs.minY) - max($0.frame.minY, bar.frame.maxY) >= 44
        }
        XCTAssertFalse(visible.isEmpty, "No song rows below the section bar")
        for row in visible {
            XCTAssertFalse(row.label.isEmpty, "\(row.identifier) unnamed")
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(row.identifier) is \(row.frame.height) pt")
        }
        let scrolled = try auditScrollAway(
            app, "\(label) scrolled", railGrowth: railGrowth, predictsClipping: predictsClipping
        )

        // The reported path back to the top: the bar leaves, the page stays usable.
        for _ in 0..<12 where bar.exists || !firstRow.isHittable { app.swipeDown() }
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(bar.waitForNonExistence(timeout: FestivalApp.budget(5)), "Section bar stayed at the top")
        waitForListToSettle(app)
        let search = SongsUITestSupport.songsSearchEntry(in: app)
        XCTAssertTrue(
            search.waitForExistence(timeout: FestivalApp.budget(5)) && search.isHittable,
            "Songs search did not return"
        )
        XCTAssertTrue(firstRow.isHittable, "First row not shown")
        XCTAssertEqual(firstTitle.label, "#")
        XCTAssertTrue(
            app.buttons["fst.songs.sort"].isHittable || app.buttons["fst.songs.tools"].isHittable,
            "Sort did not remain available"
        )
        atTop += try auditScrollAway(
            app, "\(label) back at top", railGrowth: railGrowth, predictsClipping: predictsClipping
        )
        return (barHeight, atTop, scrolled)
    }

    /// Scroll the Songs list away from the top until the floating section bar shows.
    ///
    /// A deliberate drag rather than one flick, retried a few times: on the slower CI
    /// virtual machine a synthesized flick was sometimes dropped and the list never
    /// moved (#388).
    ///
    /// - Parameter app: Songs at the top of the large fixture.
    /// - Returns: Whether the section bar appeared.
    @MainActor
    private func scrollAway(_ app: XCUIApplication) -> Bool {
        let bar = app.staticTexts["fst.songs.section-bar"]
        let list = app.descendants(matching: .any)["fst.songs.list"]
        for _ in 0..<4 {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -300)))
            if bar.waitForExistence(timeout: FestivalApp.budget(3)) { return true }
        }
        return bar.exists
    }

    /// Wait for a fling to come to rest, so the audit and its rendered-contrast crops see
    /// the same frame (a moving list measured mid-scroll).
    ///
    /// - Parameter app: Songs right after a swipe.
    @MainActor
    private func waitForListToSettle(_ app: XCUIApplication) {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        var last: [CGRect] = []
        for _ in 0..<Int(FestivalApp.budget(20)) {
            let frames = rows.allElementsBoundByIndex.prefix(4).map(\.frame)
            if !frames.isEmpty, frames == last { return }
            last = frames
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTFail("Songs list kept moving")
    }

    /// The height of the A–Z rail's "#" label (the first one, never condensed away).
    ///
    /// - Parameter app: Songs at the top with the rail shown.
    /// - Returns: The label's frame height.
    @MainActor
    private func railLetterHeight(_ app: XCUIApplication) -> CGFloat {
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        let first = rail.staticTexts["#"]
        XCTAssertTrue(first.waitForExistence(timeout: FestivalApp.budget(5)), "Rail has no # label")
        return first.frame.height
    }

    /// The system audit on the Songs list. Contrast findings on text are measured from
    /// this run's screenshot instead (≥ 4.5:1, the Song Detail band-preview and Shop
    /// empty-state precedent). Text in the 40 pt top ramp under the navigation or
    /// section bar is dimmed on purpose (`scroll-edge` R2/R3), and text overlapping the
    /// Liquid Glass bottom chrome is the open Song Detail finding
    /// (`.agents/testing/apple/accessibility.md`). "Partially
    /// unsupported" Dynamic Type on the A–Z rail's letters, which stop growing at AX2 and
    /// condense as they grow, is accepted only with this run's proof that they are
    /// ≥ 1.35× taller at AX5 (the iPad audit's `dynamic-type-grows` evidence). Otherwise
    /// only the system search placeholder's contrast and the Songs list's one
    /// unattributed "Text clipped" open finding are accepted; with `predictsClipping`
    /// every unattributed "Text clipped" is returned for the caller to disprove at AX5
    /// instead. An audit the slow CI runner reports as not completed in time is run once
    /// more.
    ///
    /// - Parameters:
    ///   - app: Songs in the state to audit.
    ///   - name: Names the activity listing accepted issues.
    ///   - railGrowth: The rail letters' measured AX5 / default height.
    ///   - predictsClipping: Return unattributed "Text clipped" issues as predictions.
    /// - Returns: The number of unattributed "Text clipped" predictions (0 unless
    ///   `predictsClipping`).
    /// - Throws: Any other audit issue.
    @MainActor
    @discardableResult
    private func auditScrollAway(
        _ app: XCUIApplication, _ name: String, railGrowth: CGFloat, predictsClipping: Bool = false
    ) throws -> Int {
        XCTContext.runActivity(named: "Rail letters grow \(railGrowth)× at AX5") { _ in }
        // The audit cycles text sizes, which re-lays out the list, so the reported frames
        // match the page after it, not before: read the page when the first issue comes.
        var page: ScrollAwayAuditPage?
        var accepted: [String] = []
        var failures: [String] = []
        var unattributedClipped = 0
        var unattributedContrast: [String] = []
        try performAuditRetryingTimeout(app, .all, name: name, reset: {
            page = nil
            accepted = []
            failures = []
            unattributedClipped = 0
            unattributedContrast = []
        }) { issue in
            let element = issue.element.map {
                "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)' \($0.frame)"
            } ?? "no element"
            let description = "\(issue.compactDescription) [\(element)]"
            let current = try page ?? ScrollAwayAuditPage(app)
            page = current
            if SongsUITestSupport.isSystemSearchPlaceholderContrast(issue) {
                accepted.append(description)
            } else if issue.auditType == .dynamicType, railGrowth >= 1.35,
                      let letter = issue.element, letter.elementType == .staticText,
                      current.rail.contains(CGPoint(x: letter.frame.midX, y: letter.frame.midY)) {
                accepted.append("rail grows \(railGrowth)×: \(description)")
            } else if issue.auditType == .dynamicType, let text = issue.element,
                      text.elementType == .staticText,
                      current.accessory.contains(CGPoint(x: text.frame.midX, y: text.frame.midY)) {
                // The bell's unread badge (or another accessory label): the fixed-height
                // system accessory caps its text and offers the Large Content Viewer.
                accepted.append("accessory type cap: \(description)")
            } else if issue.auditType == .contrast, let text = issue.element,
                      text.elementType == .staticText, !text.frame.isEmpty {
                let measured = try? self.renderedContrast(
                    of: text.frame, in: current.image, window: current.window
                )
                if text.frame.maxY > current.chromeTop {
                    accepted.append("under bottom chrome (top \(current.chromeTop)): \(description)")
                } else if text.frame.minY < current.rampEnd {
                    accepted.append("in the top ramp (ends \(current.rampEnd)): \(description)")
                } else if let measured, measured.ratio >= 4.5, measured.brightPixels >= 20 {
                    accepted.append("renders \(measured.ratio):1: \(description)")
                } else {
                    failures.append(
                        "\(description) measured \(String(describing: measured)), "
                            + "ramp ends \(current.rampEnd), chrome top \(current.chromeTop)"
                    )
                }
            } else if issue.auditType == .contrast, issue.element == nil {
                unattributedContrast.append(description)
            } else if issue.auditType == .textClipped, issue.element == nil,
                      predictsClipping || unattributedClipped == 0 {
                unattributedClipped += 1
                accepted.append(predictsClipping ? "clipping prediction, checked at AX5: \(description)" : description)
            } else {
                failures.append(description)
            }
            return true
        }
        if !unattributedContrast.isEmpty, let page {
            // No element to measure: accept only when every text in the content band
            // renders ≥ 4.5:1 (the iPad `unattributed-contrast-page-floor` evidence).
            let weak = try pageContrastFloorFailures(in: app, page: page)
            if weak.isEmpty {
                accepted.append("page floor ≥ 4.5:1: \(unattributedContrast)")
            } else {
                failures.append("\(unattributedContrast) with weak page text \(weak)")
            }
        }
        XCTContext.runActivity(named: "Audit \(name): accepted \(accepted)") { _ in }
        if !failures.isEmpty, let image = page?.image {
            let shot = XCTAttachment(image: UIImage(cgImage: image))
            shot.name = "songs-scroll-away-audit-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
        }
        XCTAssertTrue(failures.isEmpty, "Audit \(name): \(failures.joined(separator: "; "))")
        return predictsClipping ? unattributedClipped : 0
    }

    /// Clipping-only audit at AX5, the evidence that disproves default-size predictions.
    ///
    /// - Parameter app: Songs launched at AX5 in the state the predictions came from.
    /// - Returns: Each clipping issue, except a search field's single-line placeholder
    ///   (`system-search-placeholder-clipped`); empty when the page audits clean.
    /// - Throws: An audit that cannot complete.
    @MainActor
    private func ax5Clipping(_ app: XCUIApplication) throws -> [String] {
        var clipped: [String] = []
        try performAuditRetryingTimeout(app, .textClipped, name: "ax5 clipping", reset: { clipped = [] }) { issue in
            if issue.element?.elementType != .searchField {
                clipped.append(issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "no element")
            }
            return true
        }
        XCTContext.runActivity(named: "AX5 clipping: \(clipped)") { _ in }
        return clipped
    }

    /// Run an accessibility audit, once more when it does not complete in time: the CI
    /// runner's virtual machine sometimes exceeds XCTest's audit deadline on this long
    /// list (`com.apple.xcode.xctest.accessibilityAudit` -56, #388).
    ///
    /// - Parameters:
    ///   - app: The app to audit.
    ///   - types: The audit types.
    ///   - name: Names the retry activity.
    ///   - reset: Clears what the handler collected before the retry.
    ///   - handler: The issue handler.
    /// - Throws: The second timeout or any other audit error.
    @MainActor
    private func performAuditRetryingTimeout(
        _ app: XCUIApplication,
        _ types: XCUIAccessibilityAuditType,
        name: String,
        reset: () -> Void,
        _ handler: @escaping (XCUIAccessibilityAuditIssue) throws -> Bool
    ) throws {
        do {
            try app.performAccessibilityAudit(for: types, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            XCTContext.runActivity(named: "Audit \(name) did not complete in time; retrying once") { _ in }
            reset()
            try app.performAccessibilityAudit(for: types, handler)
        }
    }

    /// The static texts between the top ramp and the bottom chrome that do not render
    /// at least 4.5:1 with at least 20 glyph pixels.
    ///
    /// - Parameters:
    ///   - app: Songs, as the audit left it.
    ///   - page: The page read for the audit.
    /// - Returns: A description of each weak or unmeasurable text; empty when the floor holds.
    /// - Throws: A missing screenshot crop.
    @MainActor
    private func pageContrastFloorFailures(
        in app: XCUIApplication, page: ScrollAwayAuditPage
    ) throws -> [String] {
        var weak: [String] = []
        var measured = 0
        for text in app.staticTexts.allElementsBoundByIndex {
            let frame = text.frame
            guard !frame.isEmpty, page.window.contains(frame),
                  frame.minY >= page.rampEnd, frame.maxY <= page.chromeTop else { continue }
            let reading = try? renderedContrast(of: frame, in: page.image, window: page.window)
            measured += 1
            if let reading, reading.ratio >= 4.5, reading.brightPixels >= 20 { continue }
            weak.append("'\(text.label)' \(frame) \(String(describing: reading))")
        }
        if measured == 0 { weak.append("no text measured") }
        return weak
    }

    /// The rendered text contrast inside one frame of a screenshot.
    ///
    /// - Parameters:
    ///   - frame: The text element's frame in points.
    ///   - image: The app screenshot taken before the audit.
    ///   - window: The app window's frame.
    /// - Returns: The ratio and glyph pixel count from
    ///   ``SongsUITestSupport/measuredTextContrast(in:)``.
    /// - Throws: A frame outside the screenshot.
    @MainActor
    private func renderedContrast(
        of frame: CGRect, in image: CGImage, window: CGRect
    ) throws -> (ratio: Double, brightPixels: Int) {
        let scaleX = Double(image.width) / window.width
        let scaleY = Double(image.height) / window.height
        let crop = CGRect(
            x: (frame.minX - window.minX) * scaleX, y: (frame.minY - window.minY) * scaleY,
            width: frame.width * scaleX, height: frame.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try SongsUITestSupport.bitmapPixels(XCTUnwrap(image.cropping(to: crop)))
        let measured = try SongsUITestSupport.measuredTextContrast(in: pixels)
        return (measured.ratio, measured.brightPixels)
    }

    /// Issue #9: a far A–Z rail jump (# → P) showed Q's songs, or P's songs under a "Q"
    /// or "B" section bar, and re-tapping the same letter after scrolling did nothing.
    /// Every tap must land the letter's title on the landing line under the navigation
    /// bar and the bar must name it at once: far down, back up, a re-tap after a manual
    /// scroll, and the last letter, which cannot reach the top, leaving the section above
    /// it named. Issue #298: on iOS 26 the title lands where it pins, exactly under the
    /// section bar's copy of it, with no gap above it (issue #286 had landed it 30 pt
    /// lower), its first row right below the bar, and a small scroll leaves the bar's
    /// title where it is. The row fade ends at that first row (unit-tested in
    /// `SongsScrollChromeTests`).
    ///
    /// Needs the large fixture like the tests above (skips otherwise). With a profile,
    /// as reported: the page tools remain in the navigation bar during the first jump.
    @MainActor
    func testRailFarJumpLandsOnTheLetterAndNamesIt() throws {
        continueAfterFailure = false
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ])
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        guard rail.waitForExistence(timeout: 3),
              rail.staticTexts.matching(NSPredicate(format: "label == 'P'")).firstMatch.exists
        else {
            throw XCTSkip("Catalogue lacks the A–Z sections; use mock_service.py --large-catalogue.")
        }
        let letters = Array("#ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        let sectionBar = app.staticTexts["fst.songs.section-bar"]
        func title(_ letter: String) -> XCUIElement {
            app.staticTexts["fst.songs.section.\(letters.firstIndex(of: letter)!)"]
        }
        func top() -> CGFloat { app.navigationBars.firstMatch.frame.maxY }
        func list() -> XCUIElement { app.descendants(matching: .any)["fst.songs.list"] }
        // iOS 26: the title row lands flush with the bar (`SongsScrollChrome.landingOffset`)
        // and its text is 8 pt inside the row (`inlineTitleTopPadding`).
        let textInset: CGFloat
        let sectionBarShown: Bool
        if #available(iOS 26.0, *) {
            (textInset, sectionBarShown) = (8, true)
        } else {
            (textInset, sectionBarShown) = (0, false)
        }
        func line() -> CGFloat { top() + textInset }
        func tap(_ letter: String) {
            rail.staticTexts.matching(NSPredicate(format: "label == %@", letter)).firstMatch.tap()
        }
        func waitUntil(_ what: String, _ condition: @escaping () -> Bool) {
            let settled = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in condition() }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, what)
        }
        func assertLanded(on letter: String) {
            let target = title(letter)
            waitUntil("\(letter) title not on the line: \(target.frame), line \(line())") {
                target.exists && abs(target.frame.minY - line()) <= 3
            }
            // The section's first row follows the title at once: no dead space.
            func rowFrames(_ node: XCUIElementSnapshot) -> [CGRect] {
                (node.identifier.hasPrefix("fst.songs.row.") ? [node.frame] : [])
                    + node.children.flatMap(rowFrames)
            }
            let list = app.descendants(matching: .any)["fst.songs.list"]
            let titleBottom = target.frame.maxY
            let firstRow = ((try? list.snapshot()).map(rowFrames) ?? [])
                .filter { $0.minY >= titleBottom - 1 }.min { $0.minY < $1.minY }
            XCTAssertLessThanOrEqual(
                (firstRow?.minY ?? .infinity) - titleBottom, 8,
                "\(letter) first row not right below its title: \(String(describing: firstRow))"
            )
            waitUntil("Section bar reads \(sectionBar.label), not \(letter)") {
                sectionBar.exists && sectionBar.label == target.label
            }
            if sectionBarShown {
                // The bar's title sits exactly on the landed title: it has nowhere to slide.
                XCTAssertEqual(
                    sectionBar.frame.minY, target.frame.minY, accuracy: 1,
                    "\(letter) bar title \(sectionBar.frame) off its row \(target.frame)"
                )
            }
            XCTAssertEqual(rail.value as? String, letter, "Rail selection")
        }

        tap("#")
        tap("P")
        assertLanded(on: "P")
        if sectionBarShown {
            // A small scroll after the jump leaves the bar's title pinned (issue #298).
            // P's row leaves the accessibility tree once under the bar: read it first.
            let (pinned, name) = (sectionBar.frame.minY, title("P").label)
            let start = list().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -40)))
            XCTAssertEqual(sectionBar.label, name, "Small scroll left P")
            XCTAssertEqual(sectionBar.frame.minY, pinned, accuracy: 1, "Bar title moved")
        }
        tap("V")
        assertLanded(on: "V")
        tap("A")
        assertLanded(on: "A")
        // Scroll away from A by hand, then pick A again.
        app.swipeUp()
        waitUntil("Manual scroll did not leave A") {
            !title("A").exists || abs(title("A").frame.minY - line()) > 3
        }
        tap("A")
        assertLanded(on: "A")
        tap("P")
        assertLanded(on: "P")
        // Z's few songs cannot lift its title to the top: the bar names Y, still at the top.
        tap("Z")
        let z = title("Z")
        // Issue #288: the bar draws a title over its own row until it pins, so the row is
        // not hit-testable there; check that it is in view below the bar instead.
        waitUntil("Did not reach the end for Z") {
            z.exists && z.frame.minY >= top() - 1
                && z.frame.maxY <= app.windows.firstMatch.frame.maxY
        }
        if abs(z.frame.minY - line()) <= 3 {
            waitUntil("Section bar reads \(sectionBar.label), not Z") { sectionBar.label == "Z" }
        } else {
            waitUntil("Section bar reads \(sectionBar.label), not Y") { sectionBar.label == "Y" }
        }
    }

    /// Issue #8: scrolling near the top changed scroll-driven state on the Songs screen
    /// (scrolled away, passed section titles, section bar edge and toolbar state), and
    /// every change re-ran the whole screen: re-sort, re-diff every List row, re-render
    /// every visible row. Bursts of those passes hung the app near the top of the list.
    ///
    /// The app replays its in-app stress pass (`FST_DEBUG_SONGS_SCROLL_STRESS`: quick
    /// jumps near the top and long trips back to the top, six rounds) while the Debug
    /// stall monitor (`FST_DEBUG_STALL_LOG`) counts Songs body passes and run loop
    /// stalls. XCUITest stays idle meanwhile, so its accessibility snapshots don't add
    /// main-thread work. Before the fix this pass ran the Songs body about 158 times and
    /// re-sorted 147 times; after it, 12 and 1. Needs the large fixture like the test
    /// above (skips otherwise).
    @MainActor
    func testScrollStressNearTheTopDoesNotRebuildTheScreen() throws {
        continueAfterFailure = false
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let log = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("songs-stall-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: log) }
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_SONGS_SCROLL_STRESS": "1",
            "FST_DEBUG_STALL_LOG": log.path,
        ])
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        guard app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
            .waitForExistence(timeout: 3) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }

        struct Report: Decodable {
            var maxStallMs: Double
            var maxAwakeMs: Double
            var counters: [String: Int]
        }
        func read() -> Report? {
            (try? Data(contentsOf: log)).flatMap { try? JSONDecoder().decode(Report.self, from: $0) }
        }
        var started: Report?
        var finished: Report?
        let deadline = Date.now.addingTimeInterval(90)
        while finished == nil, Date.now < deadline {
            Thread.sleep(forTimeInterval: 1)
            guard let report = read() else { continue }
            if started == nil, report.counters["songs.stress.start"] != nil { started = report }
            if report.counters["songs.stress.end"] != nil { finished = report }
        }
        let start = try XCTUnwrap(started, "Stress pass never started")
        let end = try XCTUnwrap(finished, "Stress pass did not finish: hung or crashed")
        XCTAssertEqual(app.state, .runningForeground)

        let bodies = (end.counters["songs.body"] ?? 0) - (start.counters["songs.body"] ?? 0)
        let sorts = (end.counters["songs.sort"] ?? 0) - (start.counters["songs.sort"] ?? 0)
        XCTContext.runActivity(
            named: "bodies \(bodies), sorts \(sorts), max stall \(end.maxStallMs) ms, "
                + "max awake \(end.maxAwakeMs) ms"
        ) { _ in }
        // Sixty jumps change the scroll-driven chrome well over a hundred times; none of
        // those may re-run the screen. Allow a few incidental passes (artwork, scores).
        XCTAssertLessThanOrEqual(bodies, 20, "Scrolling re-ran the Songs screen body")
        XCTAssertLessThanOrEqual(sorts, 10, "Scrolling re-sorted the catalogue")
        // A feedback loop keeps the run loop awake (#5); the pass must keep idling.
        XCTAssertLessThan(end.maxAwakeMs, 2_000, "Main run loop never went idle")

        // The last jump lands on the first section title; flick the rest of the way up.
        app.swipeDown()
        app.swipeDown()
        XCTAssertTrue(SongsUITestSupport.songsSearchEntry(in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["fst.songs.sort"].isHittable || app.buttons["fst.songs.tools"].isHittable,
            "Sort did not return to the tab-bar accessory"
        )
    }

    /// Issue #390 (accessibility backfill for #8): at the largest text size (AX5), once
    /// the list scrolls, the floating section bar names the current section as one
    /// element: its spoken label, grown to AX5 and as large as the in-list title it
    /// stands for (not truncated or clipped), below the navigation bar, beside the A–Z
    /// rail and above the tab bar, and first in the list region's layout order.
    /// VoiceOver order itself is the macOS hosted tree's (`SongsSectionBarAccessibilityTests`)
    /// and the operator walkthrough's: XCUITest lists descendants depth first.
    ///
    /// Needs a catalogue with sections, like the tests above (`mock_service.py
    /// --large-catalogue`); skips otherwise.
    @MainActor
    func testSectionBarHeadingAtLargestText() throws {
        continueAfterFailure = false
        guard #available(iOS 26.0, *) else { throw XCTSkip("The section bar is iOS 26+.") }
        XCUIDevice.shared.orientation = .portrait
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ])
        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", ax5.rawValue]
        app.launch()
        let list = app.descendants(matching: .any)["fst.songs.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        let firstTitle = app.staticTexts["fst.songs.section.0"]
        guard firstTitle.waitForExistence(timeout: 5), rail.exists else {
            throw XCTSkip("Catalogue lacks sections; use mock_service.py --large-catalogue.")
        }
        let titleLabel = firstTitle.label
        let titleFrame = firstTitle.frame
        let sectionBar = app.staticTexts["fst.songs.section-bar"]
        XCTAssertFalse(sectionBar.exists, "At the top the bar names nothing")

        // Drag a little at a time: the first section is several AX5 rows tall, so the bar
        // still names it when it first shows.
        for _ in 0..<6 where !sectionBar.exists {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -250)))
        }
        XCTAssertTrue(sectionBar.waitForExistence(timeout: 5), "Scrolled, the bar shows no title")
        XCTAssertEqual(app.staticTexts.matching(identifier: "fst.songs.section-bar").count, 1)
        XCTAssertEqual(sectionBar.label, titleLabel, "The bar does not name the current section")

        // Text scaling: grown to AX5, and the same size as its in-list title.
        let bar = sectionBar.frame
        let line = UIFont.preferredFont(
            forTextStyle: .subheadline,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: ax5)
        ).lineHeight
        XCTAssertGreaterThanOrEqual(bar.height, line - 2, "Bar title \(bar) not at AX5 (\(line) pt line)")
        XCTAssertEqual(bar.height, titleFrame.height, accuracy: 1, "Bar title clipped: \(bar) vs \(titleFrame)")
        XCTAssertEqual(bar.width, titleFrame.width, accuracy: 1, "Bar title truncated: \(bar) vs \(titleFrame)")

        // Clear of the surrounding chrome.
        let navigation = app.navigationBars.firstMatch.frame
        let tabBar = app.tabBars.firstMatch.frame
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(bar.minY, navigation.maxY - 1, "Under the navigation bar: \(bar) \(navigation)")
        XCTAssertLessThanOrEqual(bar.maxY, tabBar.minY, "Under the tab bar: \(bar) \(tabBar)")
        XCTAssertTrue(window.contains(bar), "Off screen: \(bar)")
        XCTAssertFalse(bar.intersects(rail.frame), "Under the A–Z rail: \(bar) \(rail.frame)")

        // Reading order from the layout, top to bottom then leading to trailing (XCUITest
        // lists descendants depth first, not in VoiceOver's order; as `DuoDrawerJourneyTests`):
        // no later section title is above the bar, and the bar is leading of the rail.
        let titles = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.songs.section.'"))
            .allElementsBoundByIndex.filter { $0.identifier != "fst.songs.section.0" && window.intersects($0.frame) }
        for title in titles {
            XCTAssertGreaterThanOrEqual(title.frame.minY, bar.maxY, "\(title.label) is above the bar: \(title.frame) \(bar)")
        }
        XCTAssertLessThanOrEqual(bar.maxX, rail.frame.minX, "The bar is not leading of the rail: \(bar) \(rail.frame)")

        // The system audit, for the bar only (other regions have their own journeys).
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription]
        ) { issue in
            issue.element?.identifier != "fst.songs.section-bar"
        }
    }

    /// Issue #383: on iOS 26 and 27, slow drags a little way down from the top and back
    /// made the large title jump back and forth and come to rest part-way collapsed. The
    /// List carried an alpha mask (the row fade under the section bar), and SwiftUI then
    /// drove its insets from a safe area that lagged UIKit's: when the tab bar expanded on
    /// release near the top, the List briefly took the collapsed title's inset again and
    /// the title snapped closed. With a mask band that fell to 0 pt the List also counted
    /// its top inset twice (170 → 344 pt). Each row now masks itself.
    ///
    /// Back at the top after every drag, the large title is expanded again and no section
    /// title is pinned; past the scroll-away threshold the title is collapsed and the
    /// section bar names a section. Across the whole pass the List's largest top inset
    /// (`FST_DEBUG_STALL_LOG` peak `songs.topInset`) never exceeds the expanded title's,
    /// the scroll-away state flips at most once per threshold crossing, and the screen
    /// never re-renders or re-sorts. Needs the large fixture like the tests above (skips
    /// otherwise).
    @MainActor
    func testSlowDragsNearTheTopKeepTheLargeTitleSteady() throws {
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let log = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("songs-near-top-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: log) }
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
            "FST_DEBUG_STALL_LOG": log.path,
        ])
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        guard app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
            .waitForExistence(timeout: 3) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("The section bar and its row mask exist on iOS 26 and later.")
        }

        struct Report: Decodable {
            var counters: [String: Int]
            var peaks: [String: Double]?
        }
        func read() -> Report? {
            (try? Data(contentsOf: log)).flatMap { try? JSONDecoder().decode(Report.self, from: $0) }
        }
        /// The report once it has stopped changing (counters flush at idle).
        func settledReport() throws -> Report {
            var last = read()
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 0.6)
                let next = read()
                if let next, let previous = last, next.counters == previous.counters,
                   next.peaks == previous.peaks { return next }
                last = next
            }
            return try XCTUnwrap(last, "No stall report at \(log.path)")
        }
        let sectionBar = app.staticTexts["fst.songs.section-bar"]
        func barBottom() -> CGFloat { app.navigationBars.firstMatch.frame.maxY }
        func waitUntil(_ what: String, _ condition: @escaping () -> Bool) {
            let settled = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in condition() }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed, what)
        }
        func drag(_ from: Double, _ to: Double) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }

        // At rest at the top: the expanded large title, nothing pinned.
        Thread.sleep(forTimeInterval: 2)
        let expanded = barBottom()
        XCTAssertFalse(sectionBar.exists, "A section title is pinned at the top")
        let start = try settledReport()
        let restingInset = try XCTUnwrap(start.peaks?["songs.topInset"], "No top inset traced")
        func assertAtTheTop(_ step: String) {
            waitUntil("\(step): large title stayed collapsed at the top (\(barBottom()) vs \(expanded))") {
                abs(barBottom() - expanded) <= 2
            }
            XCTAssertFalse(sectionBar.exists, "\(step): a section title stayed pinned at the top")
        }
        func assertScrolledAway(_ step: String) {
            waitUntil("\(step): large title did not collapse (\(barBottom()) vs \(expanded))") {
                barBottom() < expanded - 30
            }
            waitUntil("\(step): no section title pinned once scrolled") { sectionBar.exists }
        }

        // The reported path: a few points to about 100 pt down and back, slowly.
        // Every drag back up is longer than the drag down, so it ends pulled past the top.
        let cycles: [(down: (Double, Double), up: (Double, Double), away: Bool)] = [
            ((0.60, 0.52), (0.52, 0.62), false),
            ((0.60, 0.50), (0.50, 0.64), false),
            ((0.60, 0.55), (0.55, 0.62), false),
            ((0.60, 0.45), (0.45, 0.64), true),
            ((0.60, 0.40), (0.40, 0.70), true),
        ]
        for (index, cycle) in cycles.enumerated() {
            drag(cycle.down.0, cycle.down.1)
            if cycle.away { assertScrolledAway("Drag \(index + 1) down") }
            drag(cycle.up.0, cycle.up.1)
            assertAtTheTop("Drag \(index + 1) back up")
        }
        // Small reversals around the threshold.
        drag(0.60, 0.55)
        drag(0.55, 0.57)
        drag(0.57, 0.53)
        drag(0.53, 0.62)
        assertAtTheTop("Reversals")

        let end = try settledReport()
        XCTAssertEqual(app.state, .runningForeground)
        func delta(_ name: String) -> Int { (end.counters[name] ?? 0) - (start.counters[name] ?? 0) }
        let peak = end.peaks?["songs.topInset"] ?? 0
        let flips = delta("songs.scrolled.flip")
        let bodies = delta("songs.body")
        XCTContext.runActivity(
            named: "top inset at rest \(restingInset), peak \(peak); flips \(flips); "
                + "bodies \(bodies), sorts \(delta("songs.sort"))"
        ) { _ in }
        XCTAssertLessThanOrEqual(
            peak, restingInset + 1,
            "The List counted its top inset twice (\(peak) pt, expanded title \(restingInset) pt)"
        )
        // Each drag crosses the scroll-away threshold at most once, plus its release.
        XCTAssertLessThanOrEqual(flips, 2 * (cycles.count * 2 + 4), "Scroll-away state oscillated")
        XCTAssertEqual(bodies, 0, "Scrolling near the top re-rendered the Songs screen")
        XCTAssertEqual(delta("songs.sort"), 0, "Scrolling near the top re-sorted the catalogue")
    }
}

/// What ``SongsChromeJourneyTests`` reads of the Songs page to judge an audit issue:
/// the A–Z rail, the scroll-edge bands and a screenshot for rendered contrast.
@MainActor
private struct ScrollAwayAuditPage {
    /// The A–Z rail's frame.
    let rail: CGRect
    /// The top of the bottom chrome: the tab bar, or the page tools above it.
    let chromeTop: CGFloat
    /// The page-tools tab-bar accessory's frame (`.null` when it is not shown). Its text
    /// stops growing at `PageToolsAccessoryBar.maxTypeSize` (`page-tools-and-nav-chrome`).
    let accessory: CGRect
    /// Where the 40 pt top ramp under the section or navigation bar ends
    /// (`scroll-edge` R2/R3).
    let rampEnd: CGFloat
    /// The app window's frame.
    let window: CGRect
    /// The page as rendered now.
    let image: CGImage

    /// Read the page.
    ///
    /// - Parameter app: Songs, as the audit left it.
    /// - Throws: A missing screenshot.
    init(_ app: XCUIApplication) throws {
        rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch.frame
        window = app.windows.firstMatch.frame
        let tabs = app.tabBars.firstMatch
        let accessory = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        var chromeTop = tabs.exists ? tabs.frame.minY : window.maxY
        if accessory.exists, accessory.frame.minY > window.midY {
            chromeTop = min(chromeTop, accessory.frame.minY)
            self.accessory = accessory.frame
        } else {
            self.accessory = .null
        }
        self.chromeTop = chromeTop
        let sectionBar = app.staticTexts["fst.songs.section-bar"]
        rampEnd = (sectionBar.exists
            ? sectionBar.frame.maxY : app.navigationBars.firstMatch.frame.maxY) + 40
        image = try XCTUnwrap(app.screenshot().image.cgImage)
    }
}
