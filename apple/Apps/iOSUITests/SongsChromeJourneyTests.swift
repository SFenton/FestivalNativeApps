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

    /// Issue #288 accessibility (#452), at the largest text size: while the next section's
    /// title pushes the floating one out, there is one floating title naming the current
    /// section, grown with the text and as tall as its in-list title, the incoming in-list
    /// title stays a named element, and the audit finds no Dynamic Type, clipping,
    /// description or trait issue on the section titles. The macOS-hosted counterpart that
    /// `apple-ci` runs, `SongsSectionPushAccessibilityTests`, covers the hidden moving
    /// copies and reading order (macOS does not scale fonts with Dynamic Type). Needs the
    /// large fixture like the tests above (skips otherwise); `apple-ci` runs it as a CI
    /// journey, so its waits and settle holds use `FestivalApp.budget(_:)`.
    @MainActor
    func testSectionPushIsAccessibleAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ])
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        // At this size the page tools fold out of the navigation bar, so wait for the rail.
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        guard #available(iOS 26.0, *), rail.waitForExistence(timeout: FestivalApp.budget(20)),
              rail.staticTexts.matching(NSPredicate(format: "label == 'P'")).firstMatch.exists
        else {
            throw XCTSkip("Needs iOS 26's section bar and mock_service.py --large-catalogue.")
        }
        let letters = Array("#ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        let sectionBar = app.staticTexts["fst.songs.section-bar"]
        func title(_ letter: String) -> XCUIElement {
            app.staticTexts["fst.songs.section.\(letters.firstIndex(of: letter)!)"]
        }
        // M sits mid-rail: at this size the expanded search field's hit area covers the
        // rail's first letters until the large title collapses.
        rail.staticTexts.matching(NSPredicate(format: "label == 'M'")).firstMatch.tap()
        let landed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in sectionBar.exists && sectionBar.label == "M" }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: FestivalApp.budget(5)), .completed, "Did not land on M")
        let pinned = sectionBar.frame
        // Subheadline at AX XXXL is about 4× its default line (~18 pt): the title grew.
        XCTAssertGreaterThanOrEqual(pinned.height, 40, "Floating M did not grow: \(pinned)")

        // Drags with a hold (no momentum) until N pushes M up out of its pin: long ones
        // while N's in-list title is far below the bar, short ones once it is close.
        let list = app.descendants(matching: .any)["fst.songs.list"]
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.7))
        var pushed = false
        for _ in 0..<60 where !pushed {
            let next = title("N")
            let gap = next.exists ? next.frame.minY - sectionBar.frame.maxY : .infinity
            start.press(
                forDuration: 0.05,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: gap > 200 ? -150 : -30)),
                withVelocity: .slow, thenHoldForDuration: FestivalApp.budget(0.3)
            )
            XCTAssertTrue(sectionBar.exists, "The floating title disappeared")
            pushed = sectionBar.label == "M" && sectionBar.frame.minY < pinned.minY - 2
            if sectionBar.label == "N" { break }
        }
        XCTAssertTrue(pushed, "Never caught N pushing M out (bar \(sectionBar.label) \(sectionBar.frame))")
        SongsUITestSupport.record(app, name: "songs-section-push-ax5")

        // One floating title, grown and as tall as its in-list title; the incoming N stays
        // in the tree under its own identifier. XCUITest also lists SwiftUI views hidden
        // with `accessibilityHidden` (the bar's moving copies, row artwork), so the
        // hosted `SongsSectionPushAccessibilityTests` checks that those stay hidden.
        XCTAssertGreaterThanOrEqual(sectionBar.frame.height, 40, "\(sectionBar.frame)")
        XCTAssertEqual(app.staticTexts.matching(identifier: "fst.songs.section-bar").count, 1)
        let incoming = title("N")
        XCTAssertTrue(incoming.exists, "Incoming N left the accessibility tree mid-push")
        XCTAssertEqual(incoming.label, "N")
        XCTAssertEqual(incoming.frame.height, sectionBar.frame.height, accuracy: 1,
                       "N \(incoming.frame) not sized like the floating title \(sectionBar.frame)")

        var issues: [String] = []
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .trait]
        ) { issue in
            let id = issue.element?.identifier ?? ""
            guard id == "fst.songs.section-bar" || id.hasPrefix("fst.songs.section.") else {
                return true
            }
            issues.append("\(id): \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Section title audit issues mid-push at AX XXXL")
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
