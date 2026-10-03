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

    /// Sort and Filter stay in the navigation bar while the Songs list scrolls; the
    /// pinned Filter Songs field remains present for local filtering.
    ///
    /// Needs a catalogue that scrolls (`TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL`, as for
    /// ``testScrollingBackToTopNearTheTopStaysResponsive``); skips on the two-song fixture.
    @MainActor
    func testToolsRemainInTheNavigationBarWhileScrolled() throws {
        continueAfterFailure = false
        try assertToolsWhileScrolled(profile: false, tools: ["fst.songs.sort", "fst.songs.filter"])
        try assertToolsWhileScrolled(profile: true, tools: ["fst.songs.sort", "fst.songs.filter"])
    }

    /// Launch the scrolling catalogue and check the Songs tools remain in the top bar.
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
        func assertInTopBar(_ state: String) {
            let bar = app.navigationBars.firstMatch.frame
            for id in tools {
                let tool = app.buttons[id]
                XCTAssertTrue(tool.exists, "\(who): \(id) missing \(state)")
                XCTAssertTrue(tool.isHittable, "\(who): \(id) not hittable \(state)")
                XCTAssertLessThanOrEqual(tool.frame.maxY, bar.maxY + 1, "\(who): \(id) left the bar \(state)")
                XCTAssertGreaterThanOrEqual(tool.frame.height, 36, "\(who): \(id) glass capsule under 36 pt")
            }
        }
        assertInTopBar("at the top")
        app.swipeUp()
        for _ in 0..<100 {
            let bar = app.navigationBars.firstMatch.frame
            if tools.allSatisfy({ id in
                let tool = app.buttons[id]
                return tool.exists && tool.isHittable && tool.frame.maxY <= bar.maxY + 1
            }) {
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        assertInTopBar("while scrolled")
        XCTAssertTrue(field.exists, "\(who): Filter Songs hid while scrolled")
        SongsUITestSupport.record(app, name: "songs-tools-top-bar-\(who)")
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
        XCTAssertTrue(app.buttons["fst.songs.sort"].isHittable, "Sort did not remain available")
    }

    /// Issue #9: a far A–Z rail jump (# → P) showed Q's songs, or P's songs under a "Q"
    /// or "B" section bar, and re-tapping the same letter after scrolling did nothing.
    /// Every tap must land the letter's title just under the navigation bar and the bar
    /// must name it at once: far down, back up, a re-tap after a manual scroll, and the
    /// last letter, which cannot reach the top, leaving the section above it named.
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
            waitUntil("\(letter) title not at the top: \(target.frame), bar ends \(top())") {
                target.exists && abs(target.frame.minY - top()) <= 3
            }
            waitUntil("Section bar reads \(sectionBar.label), not \(letter)") {
                sectionBar.exists && sectionBar.label == target.label
            }
            XCTAssertEqual(rail.value as? String, letter, "Rail selection")
        }

        tap("#")
        tap("P")
        assertLanded(on: "P")
        tap("V")
        assertLanded(on: "V")
        tap("A")
        assertLanded(on: "A")
        // Scroll away from A by hand, then pick A again.
        app.swipeUp()
        waitUntil("Manual scroll did not leave A") {
            !title("A").exists || abs(title("A").frame.minY - top()) > 3
        }
        tap("A")
        assertLanded(on: "A")
        tap("P")
        assertLanded(on: "P")
        // Z's few songs cannot lift its title to the top: the bar names Y, still at the top.
        tap("Z")
        let z = title("Z")
        waitUntil("Did not reach the end for Z") { z.exists && z.isHittable }
        if abs(z.frame.minY - top()) <= 3 {
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
        XCTAssertTrue(app.buttons["fst.songs.sort"].isHittable, "Floating Sort did not return")
    }
}
