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

    /// Issue #544: after Back from Song Detail, the Filter Songs field is ready at once.
    /// It exists, can be tapped, keeps its "Filter Songs" label and keeps the text typed
    /// before the song opened, and the list stays where it was (`back-keeps-place`
    /// R1–R3). The capsule drawn during the pop (``SearchDrawerTransitionFill``) is
    /// checked in recordings; XCUITest cannot sample a frame mid-transition.
    ///
    /// The list is scrolled first when the catalogue is long enough (the CI
    /// large-catalogue fixture), which is when the field shows glass; the two-song
    /// fixture checks the same readiness at the top.
    @MainActor
    func testFilterFieldReadyAfterBackFromSongDetail() throws {
        continueAfterFailure = false
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ])
        app.launch()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(15)))
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Songs", "Back")
        ).firstMatch
        let detail = app.descendants(matching: .any)["fst.song-detail.hero-title"]

        func hittableRow() -> XCUIElement? {
            SongsUITestSupport.songsRows(in: app, limit: 12)
                .first { $0.isHittable && $0.frame.midY > app.frame.height * 0.3 }
        }

        func openAndReturn(_ row: XCUIElement) -> CGRect {
            let identifier = row.identifier
            row.tap()
            XCTAssertTrue(detail.waitForExistence(timeout: FestivalApp.budget(10)), "Song Detail did not open")
            XCTAssertTrue(back.waitForExistence(timeout: FestivalApp.budget(5)))
            back.tap()
            // Ready at once: no settling wait beyond the pop itself.
            let field = SongsUITestSupport.songsSearchEntry(in: app)
            XCTAssertTrue(field.waitForExistence(timeout: FestivalApp.budget(2)), "Filter Songs field missing after Back")
            XCTAssertTrue(field.isHittable, "Filter Songs field not tappable right after Back")
            XCTAssertEqual(field.placeholderValue, "Filter Songs")
            XCTAssertEqual(field.elementType, .searchField)
            // The system capsule is 36 pt; its 44 pt target is proven in
            // testFilterFieldIsGlassAtTopAndScrolled.
            XCTAssertGreaterThanOrEqual(field.frame.height, 36, "Filter Songs capsule collapsed after Back")
            let returned = app.buttons[identifier]
            XCTAssertTrue(returned.waitForExistence(timeout: FestivalApp.budget(2)))
            return returned.frame
        }

        // Scrolled (the glass state) when the catalogue scrolls; Back keeps the place.
        let rail = app.descendants(matching: .any).matching(identifier: "fst.songs.section-index").firstMatch
        if rail.waitForExistence(timeout: FestivalApp.budget(3)) {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1.5)))
        }
        let row = try XCTUnwrap(hittableRow(), "No song row on screen")
        let frameBefore = row.frame
        let frameAfter = openAndReturn(row)
        XCTAssertEqual(frameAfter.minY, frameBefore.minY, accuracy: 1, "The list moved on Back")
        XCTAssertTrue(
            app.buttons["fst.songs.sort"].isHittable || app.buttons["fst.songs.tools"].isHittable,
            "Sort did not stay available on Back"
        )

        // Text typed before a song opens is still in the field after Back.
        let field = SongsUITestSupport.songsSearchField(in: app)
        field.tap()
        let query = rail.exists ? "Signal" : "Pulse"
        field.typeText(query)
        var filtered: XCUIElement?
        for _ in 0..<Int(FestivalApp.budget(50)) {
            filtered = SongsUITestSupport.songsRows(in: app, limit: 6).first { $0.isHittable }
            if filtered != nil { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        _ = openAndReturn(try XCTUnwrap(filtered, "No filtered row"))
        let kept = SongsUITestSupport.songsSearchField(in: app)
        XCTAssertEqual(kept.value as? String, query, "Filter text was lost on Back")
    }

    /// The Filter Songs drawer field is Liquid Glass at the top of the list and scrolled
    /// (issue #559): UIKit used to draw it as a flat fill at the top edge and as glass
    /// only once rows scrolled under the bar. Glass draws a bright specular rim just
    /// inside the capsule's top edge; the flat fill has none. Under the app's Reduce
    /// Transparency toggle it is the opaque `cardBackground` capsule instead (R4). The
    /// field stays the system search field: role, label and a 44 × 44 pt tappable target
    /// with either backing (``assertSearchFieldTarget(_:_:line:)``), and stays glass after
    /// a search ends (UIKit then restores its flat fill, which the backing clears).
    @MainActor
    func testFilterFieldIsGlassAtTopAndScrolled() throws {
        continueAfterFailure = false
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let environment = [
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ]
        let app = FestivalApp.makeApp(environment)
        app.launch()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(15)))
        let field = SongsUITestSupport.songsSearchEntry(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: FestivalApp.budget(5)))
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1)))
        assertSearchFieldContract(field)
        let top = try fieldPixels(app, field, "Filter Songs at the top")
        XCTAssertGreaterThan(top.rim, 6, "Filter Songs is flat at the top of the list (rim \(top.rim))")
        try assertSearchFieldTarget(app, field)
        // UIKit restores its flat fill when a search ends; the backing must clear it.
        let ended = try fieldPixels(app, field, "Filter Songs after a search ends")
        XCTAssertGreaterThan(ended.rim, 6, "Filter Songs turned flat after Cancel (rim \(ended.rim))")

        let rail = app.descendants(matching: .any).matching(identifier: "fst.songs.section-index").firstMatch
        if rail.waitForExistence(timeout: FestivalApp.budget(3)) {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1.5)))
            assertSearchFieldContract(field)
            let scrolled = try fieldPixels(app, field, "Filter Songs scrolled")
            // iOS 26.x draws glass under the scrolled bar without its specular rim (with or
            // without the backing); iOS 27, which the report came from, keeps it.
            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
                XCTAssertGreaterThan(scrolled.rim, 6, "Filter Songs is flat scrolled (rim \(scrolled.rim))")
            }
        }
        app.terminate()

        let reduced = FestivalApp.makeApp(environment)
        reduced.launchArguments += ["-fst.accessibility.lessTransparency", "YES"]
        reduced.launch()
        let opaqueField = SongsUITestSupport.songsSearchEntry(in: reduced)
        XCTAssertTrue(opaqueField.waitForExistence(timeout: FestivalApp.budget(15)))
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1)))
        assertSearchFieldContract(opaqueField)
        let opaque = try fieldPixels(reduced, opaqueField, "Filter Songs, Reduce Transparency")
        // BrandTokens.cardBackground is sRGB 11, 18, 32.
        XCTAssertLessThan(opaque.interiorDistance, 12, "Filter Songs is not the opaque card capsule (Δ \(opaque.interiorDistance))")
        try assertSearchFieldTarget(reduced, opaqueField)
    }

    /// The system search field contract the backing must not change.
    @MainActor
    private func assertSearchFieldContract(_ field: XCUIElement, line: UInt = #line) {
        XCTAssertEqual(field.elementType, .searchField, line: line)
        XCTAssertEqual(field.placeholderValue, "Filter Songs", line: line)
        XCTAssertTrue(field.isHittable, "Filter Songs not tappable", line: line)
        // HIG Buttons: "the hit region is at least 44x44 pt".
        let tolerance: CGFloat = 0.01
        XCTAssertGreaterThanOrEqual(field.frame.height + tolerance, 44, "Filter Songs \(field.frame) under 44 pt tall", line: line)
        XCTAssertGreaterThanOrEqual(field.frame.width + tolerance, 44, "Filter Songs \(field.frame) under 44 pt wide", line: line)
    }

    /// Offsets from the Filter Songs field's centre near the edges of a 44 × 44 pt square
    /// (the field's top and bottom edges and two corners of the square).
    private static let filterFieldNearMisses: [CGVector] = [
        CGVector(dx: 0, dy: -21), CGVector(dx: 0, dy: 21),
        CGVector(dx: -21, dy: -21), CGVector(dx: 21, dy: 21),
    ]

    /// HIG Buttons: "the hit region is at least 44x44 pt". The backing capsule takes no
    /// touches, so taps 21 pt from the field's centre, at the edges of its 44 pt target,
    /// must still focus the system field, and XCUITest's hit-region audit must report
    /// nothing for it. Each tap ends the search with the system's end-search button.
    ///
    /// - Parameters:
    ///   - app: Foreground app on the Songs root with the field at rest (not focused).
    ///   - field: The Filter Songs search field.
    @MainActor
    private func assertSearchFieldTarget(
        _ app: XCUIApplication, _ field: XCUIElement, line: UInt = #line
    ) throws {
        try app.performAccessibilityAudit(for: [.hitRegion]) { issue in
            guard let element = issue.element, element.elementType == .searchField else { return true }
            return false
        }
        let frame = field.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        let unfocused = NSPredicate(format: "hasKeyboardFocus == false")
        for offset in Self.filterFieldNearMisses {
            origin.withOffset(CGVector(dx: frame.midX + offset.dx, dy: frame.midY + offset.dy)).tap()
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)],
                               timeout: FestivalApp.budget(3)),
                .completed,
                "Filter Songs \(frame) ignored a tap at (\(Int(offset.dx)), \(Int(offset.dy))) pt from its centre",
                line: line
            )
            // iOS 26+ ends search with a close button trailing the field (older: "Cancel").
            let active = field.frame
            let barButtons = app.navigationBars.firstMatch.buttons.allElementsBoundByIndex
            let end = barButtons.first {
                $0.isHittable && $0.frame.minX >= active.maxX - 1
                    && $0.frame.midY > active.minY && $0.frame.midY < active.maxY
            }
            let labels = barButtons.map { "\($0.label) \($0.frame)" }.joined(separator: "; ")
            try XCTUnwrap(end, "No end-search button beside Filter Songs \(active): \(labels)", line: line).tap()
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: unfocused, object: field)],
                               timeout: FestivalApp.budget(3)),
                .completed, "Filter Songs kept focus after Cancel", line: line
            )
            RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(0.6)))
            XCTAssertEqual(field.frame.minY, frame.minY, accuracy: 1, "Filter Songs moved after Cancel", line: line)
        }
    }

    /// Sample a search field's capsule in a screenshot.
    ///
    /// - Returns: `rim`, the brightest luminance just inside the capsule's top edge minus
    ///   the mean luminance across its middle (over 60–90% of its width, clear of the
    ///   prompt), and `interiorDistance`, the largest channel distance of that middle from
    ///   `cardBackground`.
    @MainActor
    private func fieldPixels(
        _ app: XCUIApplication, _ field: XCUIElement, _ name: String
    ) throws -> (rim: Double, interiorDistance: Double) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(shot.image.cgImage)
        let bitmap = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: app.frame.width))
        let frame = field.frame
        let xs = stride(
            from: Int((frame.minX + frame.width * 0.6) * bitmap.scale),
            to: Int((frame.minX + frame.width * 0.9) * bitmap.scale), by: 3
        ).map { $0 }
        func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let offset = (y * bitmap.width + x) * 4
            return (Double(bitmap.pixels[offset]), Double(bitmap.pixels[offset + 1]), Double(bitmap.pixels[offset + 2]))
        }
        func luminance(_ x: Int, _ y: Int) -> Double {
            let (r, g, b) = rgb(x, y)
            return 0.299 * r + 0.587 * g + 0.114 * b
        }
        let top = Int(frame.minY * bitmap.scale)
        let middle = Int(frame.midY * bitmap.scale)
        let rimRows = (top + Int(bitmap.scale * 0.6))...(top + Int(bitmap.scale * 4))
        let rimPeak = rimRows.map { y in xs.map { luminance($0, y) }.max() ?? 0 }.max() ?? 0
        let middleMean = xs.map { luminance($0, middle) }.reduce(0, +) / Double(max(xs.count, 1))
        let distance = xs.map { x -> Double in
            let (r, g, b) = rgb(x, middle)
            return max(abs(r - 11), abs(g - 18), abs(b - 32))
        }.max() ?? .infinity
        return (rimPeak - middleMean, distance)
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

    /// Issue #92, #632: Sort and Filter float above the tab bar, not in the navigation
    /// bar, and stay reachable while the Songs list scrolls; the pinned Filter Songs field
    /// remains present for local filtering. Issue #300: the row shows the same items
    /// while the tab bar minimizes (no fold mid-scroll), and Profile stays the navigation
    /// bar's trailing button.
    ///
    /// Needs a catalogue that scrolls (`TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL`, as for
    /// ``testScrollingBackToTopNearTheTopStaysResponsive``); skips on the two-song fixture.
    @MainActor
    func testToolsStayFloatingWhileScrolled() throws {
        continueAfterFailure = false
        try assertToolsWhileScrolled(profile: false, tools: ["fst.songs.sort", "fst.songs.filter"])
        try assertToolsWhileScrolled(profile: true, tools: ["fst.songs.sort", "fst.songs.filter"])
    }

    /// Launch the scrolling catalogue and check the Songs tools stay in the floating row.
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
        guard rail.waitForExistence(timeout: FestivalApp.budget(10)) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        let field = app.searchFields["Filter Songs"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let who = profile ? "profile" : "anonymous"
        let accessory = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        XCTAssertTrue(accessory.waitForExistence(timeout: 5), "\(who): floating page tools missing")
        func assertFloating(_ ids: [String], _ state: String) {
            let bar = app.navigationBars.firstMatch.frame
            XCTAssertTrue(
                app.navigationBars.buttons["fst.shell.profile"].exists, "\(who): Profile left the header \(state)"
            )
            XCTAssertFalse(accessory.buttons["fst.shell.profile"].exists, "\(who): Profile in the floating row \(state)")
            XCTAssertFalse(accessory.buttons["fst.songs.tools"].exists, "\(who): Sort and Filter folded \(state)")
            for id in ids {
                let tool = accessory.buttons[id]
                XCTAssertTrue(tool.exists, "\(who): \(id) missing from the floating row \(state)")
                XCTAssertTrue(tool.isHittable, "\(who): \(id) not hittable \(state)")
                XCTAssertFalse(app.navigationBars.buttons[id].exists, "\(who): \(id) in the header \(state)")
                XCTAssertGreaterThan(tool.frame.minY, bar.maxY, "\(who): \(id) in the header \(state)")
                XCTAssertGreaterThanOrEqual(tool.frame.width, 44, "\(who): \(id) slot under 44 pt")
            }
        }
        assertFloating(tools, "at the top")
        app.swipeUp()
        // Above the minimized tab bar the same items stay put (issues #300, #632).
        for _ in 0..<100 {
            if tools.allSatisfy({ accessory.buttons[$0].isHittable }) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        assertFloating(tools, "while scrolled")
        XCTAssertTrue(field.exists, "\(who): Filter Songs hid while scrolled")
        SongsUITestSupport.record(app, name: "songs-tools-floating-\(who)")
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

    /// Issue #553 accessibility: the Songs row card's rim (`CardRim`) and the pinned
    /// section bar's row mask (`pinnedHeaderEdgeFadeRowMask`) are decoration only. One
    /// row, read clear of the fade, then dragged into the fade band and then across the
    /// bar's edge so the mask cuts it, keeps the same button, label, frame size and
    /// descendants; no state exposes any other element inside the row; the row stays
    /// hittable; the one bar heading stays above it in reading (top-to-bottom) order; no
    /// row shows behind the bar, even once wholly in the cut (`scroll-edge` R7, #459;
    /// that it is then no VoiceOver stop is proved by the hosted
    /// `SongsSectionBarAccessibilityTests/composedSongsWhollyUnderTheBarAreNoStop`, as
    /// XCUITest lists hidden views); and the masked state passes the system audit (the
    /// scroll-away audit's documented open findings excepted).
    ///
    /// Needs the large fixture like ``testScrollAwaySectionBarAccessibility``.
    @MainActor
    func testRowUnderTheSectionBarFadeKeepsItsAccessibility() throws {
        continueAfterFailure = false
        let large = try launchScrollAwayFixture(largeText: true)
        let largeRail = railLetterHeight(large)
        large.terminate()
        let app = try launchScrollAwayFixture(largeText: false)
        let railGrowth = largeRail / railLetterHeight(app)
        try assertRowUnderTheSectionBar(in: app, label: "row under fade", railGrowth: railGrowth, hardEdge: false)
    }

    /// Issue #627 (accessibility backfill for #10, which fades Songs rows under the pinned
    /// section bar like under the page header): the same row walk as
    /// ``testRowUnderTheSectionBarFadeKeepsItsAccessibility`` at the largest text size
    /// (AX5) with the in-app Less Transparency and Increase Contrast on, which turn the
    /// fade into a hard edge (`scroll-edge` R7). The bar stays one heading above the rows,
    /// its title renders at least 4.5:1, a row under it keeps its name, button and
    /// ≥ 44 pt frame, no row content shows behind the bar (also once wholly in the cut,
    /// which the hosted `composedSongsWhollyUnderTheBarAreNoStop` AX5 hard-edge case
    /// proves is no VoiceOver stop), and the audit accepts no contrast issue in a ramp
    /// (there is none).
    ///
    /// Needs the large fixture like ``testScrollAwaySectionBarAccessibility``.
    @MainActor
    func testRowUnderTheSectionBarAtLargestTextWithHardEdge() throws {
        continueAfterFailure = false
        let regular = try launchScrollAwayFixture(largeText: false)
        let defaultRail = railLetterHeight(regular)
        regular.terminate()
        let app = try launchScrollAwayFixture(largeText: true, hardEdge: true)
        let railGrowth = railLetterHeight(app) / defaultRail
        try assertRowUnderTheSectionBar(in: app, label: "ax5 hard edge", railGrowth: railGrowth, hardEdge: true)
    }

    /// Drag one Songs row from clear of the section bar's fade into the fade band, across
    /// the bar's edge and then wholly into the cut above it, and check what VoiceOver, the
    /// hit-tester and the screen show at each step (#553, #627).
    ///
    /// - Parameters:
    ///   - app: Songs on the large fixture, at the top.
    ///   - label: Names the states, attachments and the audit.
    ///   - railGrowth: The rail letters' measured AX5 / default height
    ///     (``auditScrollAway(_:_:railGrowth:predictsClipping:ramp:)``).
    ///   - hardEdge: Less Transparency and Increase Contrast are on, so the fade is a hard
    ///     cut at the bar's edge (R7): the bar's title must render ≥ 4.5:1 and the audit
    ///     gets no ramp to accept contrast issues in.
    /// - Throws: A missing row, snapshot or screenshot, or a failed audit.
    @MainActor
    private func assertRowUnderTheSectionBar(
        in app: XCUIApplication, label: String, railGrowth: CGFloat, hardEdge: Bool
    ) throws {
        XCTAssertTrue(scrollAway(app), "\(label): section bar never appeared")
        waitForListToSettle(app)
        let bar = app.staticTexts["fst.songs.section-bar"]
        let list = app.descendants(matching: .any)["fst.songs.list"]
        let window = app.windows.firstMatch.frame
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch.frame
        let tabs = app.tabBars.firstMatch.frame
        let accessory = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        let chromeTop = accessory.exists && accessory.frame.minY > window.midY
            ? min(tabs.minY, accessory.frame.minY) : tabs.minY
        let heading = try isHeading(bar)
        XCTContext.runActivity(named: "\(label): bar '\(bar.label)' header trait \(String(describing: heading))") { _ in }
        XCTAssertNotEqual(heading, false, "\(label): the section bar is not a heading")

        // A drag first spends the pan's slop, so a short one never moves the list: back
        // off first, and lengthen each drag by the slop the last one lost.
        func move(_ element: XCUIElement, to target: () -> CGFloat) {
            var slop: CGFloat = 0
            func drag(_ length: CGFloat) {
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.6))
                start.press(
                    forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: length)),
                    withVelocity: .slow, thenHoldForDuration: 0.3
                )
                waitForListToSettle(app)
            }
            for _ in 0..<6 where abs(element.frame.minY - target()) > 6 {
                if abs(element.frame.minY - target()) < 40 { drag(80) }
                let before = element.frame.minY
                let delta = target() - before
                let length = delta + (delta > 0 ? slop : -slop)
                drag(length)
                slop = max(0, abs(length) - abs(element.frame.minY - before))
            }
        }

        // A row well below the fade, its top on screen, whose previous neighbour is a row,
        // not an in-list title, so the bar (not a passing title) is what masks it once
        // dragged up. At AX5 a row is tall, so scroll until one's top is below the fade
        // (as `NotificationsAccessibilityJourneyTests`). One snapshot each: the lazy list
        // recycles rows (#572).
        func clearRow() throws -> String? {
            let edge = bar.frame.maxY
            let nodes = try FestivalApp.snapshotNodes(in: app) {
                SongsUITestSupport.isSongsRow($0)
                    || ($0.elementType == .staticText && $0.identifier.hasPrefix("fst.songs.section."))
            }
            let titles = nodes.filter { $0.elementType == .staticText }.map(\.frame)
            return nodes.first { row in
                let frame = row.frame
                return row.elementType == .button
                    && frame.minY >= edge + 2 * PinnedRowProbe.fade && frame.minY <= chromeTop - 120
                    && !titles.contains { $0.maxY <= frame.minY + 1 && $0.maxY >= frame.minY - 80 }
            }?.identifier
        }
        var candidate = try clearRow()
        for _ in 0..<6 where candidate == nil {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            waitForListToSettle(app)
            candidate = try clearRow()
        }
        let identifier = try XCTUnwrap(candidate, "\(label): no song row clear of the fade")
        let row = app.buttons[identifier]
        let clear = try PinnedRowProbe(row: row, in: app, visibleBottom: chromeTop)
        XCTAssertFalse(clear.label.isEmpty, "\(label): \(identifier) unnamed")
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44, "\(label): \(identifier) is \(clear.frame.height) pt")
        XCTAssertTrue(clear.strays.isEmpty, "\(label): clear row exposes \(clear.strays)")

        // XCUITest frames only the title's glyphs; the bar's band reaches its padding
        // above and below them (`SongsScrollChrome.barTitleTopPadding` 8 pt and
        // `barTitleBottomPadding` 2 pt), from the leading edge to the A–Z rail.
        func band(_ title: CGRect) -> CGRect {
            CGRect(x: window.minX + 1, y: title.minY - 7, width: rail.minX - 4 - window.minX - 1, height: title.height + 8)
        }

        // Two mask states: the row's top in the fade band below the bar's edge, then just
        // above the edge, where the mask cuts the row's top off.
        var backdrops: [(state: String, label: String, pixels: [UInt8], image: CGImage)] = []
        for (state, offset) in [("in the band", PinnedRowProbe.fade / 4), ("cut", -PinnedRowProbe.fade / 4)] {
            move(row) { bar.frame.maxY + offset }
            let barFrame = bar.frame
            let masked = try PinnedRowProbe(row: row, in: app, visibleBottom: chromeTop)
            XCTContext.runActivity(named: "\(label) \(state): bar \(barFrame), row \(masked.frame)") { _ in }
            XCTAssertLessThan(masked.frame.minY, barFrame.maxY + PinnedRowProbe.fade / 2, "\(label) \(state): row not under the fade")
            XCTAssertGreaterThan(masked.frame.maxY, barFrame.maxY + 8, "\(label) \(state): row hidden under the bar")
            XCTAssertEqual(masked.label, clear.label, "\(label) \(state): mask changed the row's label")
            XCTAssertEqual(masked.frame.height, clear.frame.height, accuracy: 0.5, "\(label) \(state): mask cut the row's frame")
            XCTAssertEqual(masked.frame.width, clear.frame.width, accuracy: 0.5, "\(label) \(state): mask cut the row's frame")
            XCTAssertEqual(masked.descendants, clear.descendants, "\(label) \(state): mask changed the row's descendants")
            XCTAssertTrue(masked.strays.isEmpty, "\(label) \(state): masked row exposes \(masked.strays)")
            XCTContext.runActivity(named: "Row containers clear \(clear.containers), \(state) \(masked.containers)") { _ in }
            XCTAssertEqual(masked.containers, clear.containers, "\(label) \(state): mask added containers to the row")
            XCTAssertTrue(row.isHittable, "\(label) \(state): masked row not hittable")
            // XCUITest lists the List's rows before its overlays, not in VoiceOver order
            // (songs/ios.md #390; the hosted `SongsSectionBarAccessibilityTests` prove
            // the tree order), so check the top-to-bottom layout VoiceOver reads by.
            XCTAssertEqual(app.staticTexts.matching(identifier: "fst.songs.section-bar").count, 1)
            XCTAssertLessThan(barFrame.minY, masked.frame.minY, "\(label) \(state): row starts above the section bar")
            if offset > 0 {
                XCTAssertLessThanOrEqual(barFrame.maxY, masked.frame.minY + 1, "\(label) \(state): row overlaps the bar")
            }
            let image = try XCTUnwrap(app.screenshot().image.cgImage)
            backdrops.append((state, bar.label, try pixels(of: band(barFrame), in: image, window: window), image))
            if hardEdge {
                let title = try renderedContrast(of: barFrame, in: image, window: window)
                XCTContext.runActivity(named: "\(label) \(state): bar title renders \(title)") { _ in }
                XCTAssertGreaterThanOrEqual(title.ratio, 4.5, "\(label) \(state): bar title \(title.ratio):1")
                XCTAssertGreaterThanOrEqual(title.brightPixels, 20, "\(label) \(state): bar title not drawn")
            }
        }

        // No row content behind the bar: what the bar's band shows does not change while
        // a row slides from below its edge to across it (R2 clear at the edge, R7 never a
        // leak). The bar's own title is the same in each state compared.
        func expectSameBackdrop(_ first: Int, _ second: Int) {
            guard backdrops[first].label == backdrops[second].label else {
                XCTFail("\(label): the bar changed section between states: \(backdrops.map(\.label))")
                return
            }
            let (one, two) = (backdrops[first].pixels, backdrops[second].pixels)
            let changed = stride(from: 0, to: min(one.count, two.count), by: 4).filter { offset in
                (0..<3).contains { abs(Int(one[offset + $0]) - Int(two[offset + $0])) > 16 }
            }.count
            let share = Double(changed) / Double(max(1, one.count / 4))
            let states = "\(backdrops[first].state) → \(backdrops[second].state)"
            XCTContext.runActivity(named: "\(label) \(states): \(changed) of \(one.count / 4) pixels behind the bar changed") { _ in }
            if share >= 0.01 {
                for shot in [backdrops[first], backdrops[second]] {
                    let attachment = XCTAttachment(image: UIImage(cgImage: shot.image))
                    attachment.name = "songs-row-under-bar-\(label)-\(shot.state)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
            XCTAssertLessThan(share, 0.01, "\(label) \(states): a row shows behind the section bar (\(changed) pixels changed)")
        }
        XCTAssertEqual(backdrops.count, 2)
        expectSameBackdrop(0, 1)

        // Wholly in the cut: the row's bottom above the bar's edge but still on screen.
        // Track the next row down, whose frame stays readable once the row leaves the tree.
        let below = try FestivalApp.snapshotNodes(in: app, where: SongsUITestSupport.isSongsRow)
            .filter { $0.frame.minY >= row.frame.maxY - 1 }
            .min { $0.frame.minY < $1.frame.minY }
        let reference = app.buttons[try XCTUnwrap(below?.identifier, "\(label): no row below \(identifier)")]
        let gap = reference.frame.minY - row.frame.minY
        let height = row.frame.height
        move(reference) { bar.frame.maxY - 16 - height + gap }
        let edge = bar.frame.maxY
        let rowBottom = reference.frame.minY - gap + height
        XCTContext.runActivity(named: "\(label) wholly cut: edge \(edge), row bottom \(rowBottom), next row \(reference.frame)") { _ in }
        XCTAssertLessThanOrEqual(rowBottom, edge - 2, "\(label): row not wholly in the cut")
        XCTAssertGreaterThan(rowBottom, window.minY + 2, "\(label): row left the screen")
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        backdrops.append(("wholly cut", bar.label, try pixels(of: band(bar.frame), in: image, window: window), image))
        if backdrops[2].label == backdrops[0].label {
            expectSameBackdrop(0, 2)
        }
        // XCUITest also lists views hidden by the mask (`testing/apple/accessibility.md`),
        // so the hosted `composedSongsWhollyUnderTheBarAreNoStop` proves the cut row is
        // no stop; here the row partly under the bar stays one named, ≥ 44 pt button read
        // after the bar.
        let next = try PinnedRowProbe(row: reference, in: app, visibleBottom: chromeTop)
        XCTAssertFalse(next.label.isEmpty, "\(label): the row below is unnamed")
        XCTAssertGreaterThanOrEqual(next.frame.height, 44, "\(label): the row below is \(next.frame.height) pt")
        XCTAssertTrue(next.strays.isEmpty, "\(label): the row below exposes \(next.strays)")
        XCTAssertLessThan(bar.frame.minY, next.frame.minY, "\(label): the row below starts above the section bar")
        XCTAssertTrue(reference.isHittable, "\(label): the row below is not hittable")

        try auditScrollAway(app, label, railGrowth: railGrowth, ramp: hardEdge ? 0 : PinnedRowProbe.fade)
    }

    /// Whether an element carries the header trait, as VoiceOver's rotor finds headings.
    ///
    /// - Parameter element: The element to read.
    /// - Returns: The trait, or nil when the snapshot does not expose traits.
    /// - Throws: A snapshot failure.
    @MainActor
    private func isHeading(_ element: XCUIElement) throws -> Bool? {
        let object = try element.snapshot() as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")),
              let traits = (object.value(forKey: "traits") as? NSNumber)?.uint64Value else { return nil }
        return traits & UIAccessibilityTraits.header.rawValue != 0
    }

    /// The RGBA pixels inside one frame of a screenshot.
    ///
    /// - Parameters:
    ///   - frame: The region in points.
    ///   - image: The app screenshot.
    ///   - window: The app window's frame.
    /// - Returns: Four bytes per pixel.
    /// - Throws: A frame outside the screenshot.
    @MainActor
    private func pixels(of frame: CGRect, in image: CGImage, window: CGRect) throws -> [UInt8] {
        let scaleX = Double(image.width) / window.width
        let scaleY = Double(image.height) / window.height
        let crop = CGRect(
            x: (frame.minX - window.minX) * scaleX, y: (frame.minY - window.minY) * scaleY,
            width: frame.width * scaleX, height: frame.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try SongsUITestSupport.bitmapPixels(XCTUnwrap(image.cropping(to: crop)))
    }

    /// Launch Songs on the large fixture with a profile selected, as #5 was reported.
    ///
    /// - Parameters:
    ///   - largeText: Launch at the largest accessibility text size (AX5).
    ///   - hardEdge: Turn on the in-app Less Transparency and Increase Contrast, which
    ///     make every scroll-edge ramp a hard edge (`scroll-edge` R7).
    ///   - extra: More launch environment (e.g. `FST_UI_TEST_PAGE_ANCHOR`).
    /// - Returns: The running app on the Songs root.
    /// - Throws: `XCTSkip` when the catalogue is too short to scroll.
    @MainActor
    private func launchScrollAwayFixture(
        largeText: Bool, hardEdge: Bool = false, environment extra: [String: String] = [:]
    ) throws -> XCUIApplication {
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ].merging(extra) { _, new in new })
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        if hardEdge {
            app.launchArguments += [
                "-fst.accessibility.lessTransparency", "YES", "-fst.accessibility.moreContrast", "YES",
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
        // The bar's drawn bottom, not its accessibility frame, which overstates (#678).
        let navigationBottom = try FestivalApp.navigationBarContentBottom(in: app)
        XCTAssertGreaterThanOrEqual(
            bar.frame.minY, navigationBottom - 1, "Bar \(bar.frame) under navigation chrome ending \(navigationBottom)"
        )
        let barHeight = bar.frame.height
        let barBottom = bar.frame.maxY
        let tabs = app.tabBars.firstMatch.frame
        let window = app.windows.firstMatch.frame
        // At AX5 a row can be taller than the band, so count any row showing ≥ 44 pt of it
        // between the bar and the tab bar. One snapshot: the lazy list recycles rows (#572).
        let visible = try FestivalApp.snapshotNodes(in: app, where: SongsUITestSupport.isSongsRow).filter {
            window.intersects($0.frame) && min($0.frame.maxY, tabs.minY) - max($0.frame.minY, barBottom) >= 44
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
        var last: [CGRect] = []
        for _ in 0..<Int(FestivalApp.budget(20)) {
            let rows = (try? FestivalApp.snapshotNodes(in: app, where: SongsUITestSupport.isSongsRow)) ?? []
            let frames = rows.prefix(4).map(\.frame)
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
    ///   - ramp: Depth of the top ramp in which dimmed text is accepted; 0 with a hard
    ///     edge (`scroll-edge` R7), where only text the bar's edge cuts is.
    /// - Returns: The number of unattributed "Text clipped" predictions (0 unless
    ///   `predictsClipping`).
    /// - Throws: Any other audit issue.
    @MainActor
    @discardableResult
    private func auditScrollAway(
        _ app: XCUIApplication, _ name: String, railGrowth: CGFloat, predictsClipping: Bool = false,
        ramp: CGFloat = PinnedRowProbe.fade
    ) throws -> Int {
        XCTContext.runActivity(named: "Rail letters grow \(railGrowth)× at AX5") { _ in }
        // The audit cycles text sizes, which re-lays out the list, so the reported frames
        // match the page after it, not before: read the page when the first issue comes.
        var page: ScrollAwayAuditPage?
        var accepted: [String] = []
        var failures: [String] = []
        var unattributedClipped = 0
        var unattributedContrast: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(app, .all, name: name, reset: {
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
            let current = try page ?? ScrollAwayAuditPage(app, ramp: ramp)
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
                // A floating page tool's label: the fixed 44 pt circles cap their text
                // and offer the Large Content Viewer (#632).
                accepted.append("floating tools type cap: \(description)")
            } else if issue.auditType == .contrast, let text = issue.element,
                      text.elementType == .staticText, !text.frame.isEmpty {
                // Measured only when neither chrome nor ramp accounts for it: a text the
                // audit reports off screen has no crop, and `XCTUnwrap` records that even
                // under `try?` (#678).
                if text.frame.maxY > current.chromeTop {
                    accepted.append("under bottom chrome (top \(current.chromeTop)): \(description)")
                } else if text.frame.minY < current.rampEnd, ramp > 0 || text.identifier != "fst.songs.section-bar" {
                    accepted.append("\(ramp > 0 ? "in the top ramp" : "cut by the edge") (ends \(current.rampEnd)): \(description)")
                } else {
                    let measured = try? self.renderedContrast(
                        of: text.frame, in: current.image, window: current.window
                    )
                    if let measured, measured.ratio >= 4.5, measured.brightPixels >= 20 {
                        accepted.append("renders \(measured.ratio):1: \(description)")
                    } else {
                        failures.append(
                            "\(description) measured \(String(describing: measured)), "
                                + "ramp ends \(current.rampEnd), chrome top \(current.chromeTop)"
                        )
                    }
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
        try SongsUITestSupport.performAuditRetryingTimeout(app, .textClipped, name: "ax5 clipping", reset: { clipped = [] }) { issue in
            if issue.element?.elementType != .searchField {
                clipped.append(issue.element.map { "\($0.elementType.rawValue) '\($0.label)'" } ?? "no element")
            }
            return true
        }
        XCTContext.runActivity(named: "AX5 clipping: \(clipped)") { _ in }
        return clipped
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
        // One snapshot: after the audit's text-size cycle the lazy list is still recycling
        // rows, and a bound-by-index walk failed on a vanished last text (#572).
        for text in try FestivalApp.snapshotNodes(in: app, where: { $0.elementType == .staticText }) {
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
        // A mid-rail letter: at this size the expanded search field's hit area covers the
        // rail's first letters until the large title collapses, and the rail condenses
        // (#388), so take the first of M–T it still shows (the guard proved P is shown).
        func railLetter(_ letter: String) -> XCUIElement {
            rail.staticTexts.matching(NSPredicate(format: "label == %@", letter)).firstMatch
        }
        let from = ["M", "N", "O", "P", "Q", "R", "S", "T"].first { railLetter($0).exists } ?? "P"
        let to = letters[letters.firstIndex(of: from)! + 1]
        railLetter(from).tap()
        let landed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in sectionBar.exists && sectionBar.label == from }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: FestivalApp.budget(5)), .completed, "Did not land on \(from)")
        let pinned = sectionBar.frame
        // Subheadline at AX XXXL is about 4× its default line (~18 pt): the title grew.
        XCTAssertGreaterThanOrEqual(pinned.height, 40, "Floating \(from) did not grow: \(pinned)")

        // Drags with a hold (no momentum) until the next section pushes the floating one up
        // out of its pin: long ones while the incoming in-list title is far below the bar,
        // short ones once it is close, and a short one back when a drag on a loaded
        // simulator overshot the push (the bar already names the next section).
        let list = app.descendants(matching: .any)["fst.songs.list"]
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.7))
        var pushed = false
        for _ in 0..<80 where !pushed {
            let next = title(to)
            let gap = next.exists ? next.frame.minY - sectionBar.frame.maxY : .infinity
            let dy: CGFloat = sectionBar.label == to ? 20 : gap > 200 ? -150 : gap > 60 ? -30 : -15
            start.press(
                forDuration: 0.05,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)),
                withVelocity: .slow, thenHoldForDuration: FestivalApp.budget(0.3)
            )
            XCTAssertTrue(sectionBar.exists, "The floating title disappeared")
            pushed = sectionBar.label == from && sectionBar.frame.minY < pinned.minY - 2
        }
        XCTAssertTrue(pushed, "Never caught \(to) pushing \(from) out (bar \(sectionBar.label) \(sectionBar.frame))")
        SongsUITestSupport.record(app, name: "songs-section-push-ax5")

        // One floating title, grown and as tall as its in-list title; the incoming title stays
        // in the tree under its own identifier. XCUITest also lists SwiftUI views hidden
        // with `accessibilityHidden` (the bar's moving copies, row artwork), so the
        // hosted `SongsSectionPushAccessibilityTests` checks that those stay hidden.
        XCTAssertGreaterThanOrEqual(sectionBar.frame.height, 40, "\(sectionBar.frame)")
        XCTAssertEqual(app.staticTexts.matching(identifier: "fst.songs.section-bar").count, 1)
        let incoming = title(to)
        XCTAssertTrue(incoming.exists, "Incoming \(to) left the accessibility tree mid-push")
        XCTAssertEqual(incoming.label, to)
        XCTAssertEqual(incoming.frame.height, sectionBar.frame.height, accuracy: 1,
                       "\(to) \(incoming.frame) not sized like the floating title \(sectionBar.frame)")

        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.dynamicType, .textClipped, .sufficientElementDescription, .trait],
            name: "section push", reset: { issues = [] }
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

    /// Issue #451 (accessibility for #286), at the largest text size: a jump from the A–Z
    /// index lands the letter's grown title on the section bar's line, below the
    /// navigation bar, with its first row (a named button at least 44 pt tall) right
    /// under it; the bar names the landed section and the index's spoken value follows
    /// it. Mid-alphabet, far back and far forward; then the system audit on the landed
    /// section titles and rows. The macOS-hosted counterpart that `apple-ci` runs on
    /// every change, `SongsSectionJumpAccessibilityTests`, covers reading order, Quick
    /// Links on grouped sorts and Reduce Motion/Transparency. Needs the large fixture
    /// like the tests above (skips otherwise).
    @MainActor
    func testSectionJumpIsAccessibleAtLargestText() throws {
        try assertSectionJumpAccessibleAtLargestText(duoWindow: nil)
    }

    /// The same on the folded iPhone Duo's outer display (simulated on an iPhone; the
    /// vertical system bar trails the rail).
    @MainActor
    func testSectionJumpIsAccessibleAtLargestTextDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertSectionJumpAccessibleAtLargestText(duoWindow: "folded")
    }

    /// Launch Songs at AX5, jump with the A–Z index and check each landing.
    ///
    /// - Parameter duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Throws: A skip without iOS 26's section bar or the large fixture; audit failures.
    @MainActor
    private func assertSectionJumpAccessibleAtLargestText(duoWindow: String?) throws {
        continueAfterFailure = false
        guard #available(iOS 26.0, *) else { throw XCTSkip("The section bar is iOS 26+.") }
        XCUIDevice.shared.orientation = .portrait
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        var environment = [
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ]
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        }
        let app = FestivalApp.makeApp(environment)
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let rail = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
        guard rail.waitForExistence(timeout: FestivalApp.budget(20)),
              rail.staticTexts.matching(NSPredicate(format: "label == 'P'")).firstMatch.exists
        else {
            throw XCTSkip("Catalogue lacks the A–Z sections; use mock_service.py --large-catalogue.")
        }
        if let duoWindow {
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "\(duoWindow) "), object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
                           "The app never simulated \(duoWindow)")
        }
        // The index: one named, adjustable element whose value is the current letter.
        XCTAssertEqual(rail.label, "Jump to section")
        XCTAssertEqual(rail.value as? String, "#")
        XCTAssertGreaterThanOrEqual(rail.frame.height, 44, "Index target \(rail.frame)")

        let letters = Array("#ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        let sectionBar = app.staticTexts["fst.songs.section-bar"]
        let list = app.descendants(matching: .any)["fst.songs.list"]
        func title(_ letter: String) -> XCUIElement {
            app.staticTexts["fst.songs.section.\(letters.firstIndex(of: letter)!)"]
        }
        // The rail condenses at this size (#388): take the first letter of a run it shows.
        func shown(_ run: String) -> String? {
            run.map(String.init).first {
                rail.staticTexts.matching(NSPredicate(format: "label == %@", $0)).firstMatch.exists
            }
        }
        func waitUntil(_ what: @autoclosure () -> String, _ condition: @escaping () -> Bool) {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: FestivalApp.budget(8)), .completed, what())
        }
        func jump(to letter: String) throws {
            rail.staticTexts.matching(NSPredicate(format: "label == %@", letter)).firstMatch.tap()
            let target = title(letter)
            waitUntil("Did not land on \(letter): bar \(sectionBar.label) \(sectionBar.frame), title \(target.frame)") {
                sectionBar.exists && sectionBar.label == letter && target.exists
                    && abs(target.frame.minY - sectionBar.frame.minY) <= 1
            }
            // Grown with the text, below the top chrome (the #286 symptom), and read once.
            XCTAssertGreaterThanOrEqual(sectionBar.frame.height, 40, "\(letter) bar not grown: \(sectionBar.frame)")
            XCTAssertEqual(app.staticTexts.matching(identifier: "fst.songs.section-bar").count, 1)
            let navigation = app.navigationBars.firstMatch
            if navigation.exists {
                XCTAssertGreaterThanOrEqual(target.frame.minY, navigation.frame.maxY - 1,
                                            "\(letter) title under the navigation bar: \(target.frame) \(navigation.frame)")
            }
            XCTAssertEqual(target.label, letter)
            // Its first row follows at once, named, full size and in view.
            let titleBottom = target.frame.maxY
            let window = app.windows.firstMatch.frame
            let rows = try FestivalApp.snapshotNodes(in: list) {
                $0.identifier.hasPrefix("fst.songs.row.") && $0.frame.minY >= titleBottom - 1
            }
            let first = try XCTUnwrap(rows.min { $0.frame.minY < $1.frame.minY }, "\(letter): no row below its title")
            XCTAssertLessThanOrEqual(first.frame.minY - titleBottom, 8, "\(letter) first row \(first.frame) far from its title")
            XCTAssertTrue(first.label.hasPrefix(letter), "\(letter) first row is '\(first.label)'")
            XCTAssertGreaterThanOrEqual(first.frame.height, 44, "\(letter) first row \(first.frame)")
            XCTAssertTrue(window.intersects(first.frame), "\(letter) first row off screen: \(first.frame)")
            waitUntil("Index value \(String(describing: rail.value)), not \(letter)") {
                rail.value as? String == letter
            }
        }

        let mid = try XCTUnwrap(shown("MNOPQRST"), "The index shows none of M–T")
        try jump(to: mid)
        try jump(to: try XCTUnwrap(shown("BCDEFGH"), "The index shows none of B–H"))
        try jump(to: try XCTUnwrap(shown("UVW"), "The index shows none of U–W"))
        SongsUITestSupport.record(app, name: "songs-section-jump-ax5\(duoWindow.map { "-duo-\($0)" } ?? "")")

        // The system audit on the landed section titles, the bar and the rows (the rail's
        // condensed letters and the rest of the page have their own journeys).
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.dynamicType, .textClipped, .sufficientElementDescription, .trait],
            name: "section jump", reset: { issues = [] }
        ) { issue in
            let id = issue.element?.identifier ?? ""
            let titles = id == "fst.songs.section-bar" || id.hasPrefix("fst.songs.section.")
            let rows = id.hasPrefix("fst.songs.row.")
                && [.sufficientElementDescription, .trait].contains(issue.auditType)
            guard titles || rows else { return true }
            issues.append("\(id): \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Landed section audit issues at AX XXXL")
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
            "Sort did not return to the floating page tools"
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
        let titles = try FestivalApp.snapshotNodes(in: app) {
            $0.elementType == .staticText && $0.identifier.hasPrefix("fst.songs.section.")
                && $0.identifier != "fst.songs.section.0" && window.intersects($0.frame)
        }
        for title in titles {
            XCTAssertGreaterThanOrEqual(title.frame.minY, bar.maxY, "\(title.label) is above the bar: \(title.frame) \(bar)")
        }
        XCTAssertLessThanOrEqual(bar.maxX, rail.frame.minX, "The bar is not leading of the rail: \(bar) \(rail.frame)")

        // The system audit, for the bar only (other regions have their own journeys).
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.dynamicType, .textClipped, .sufficientElementDescription],
            name: "section bar", reset: {}
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

    /// Issue #631: a slow scroll from the top showed the first section title ("#") ride
    /// up past its pin line under the collapsed navigation bar, then jump back down when
    /// the section bar appeared 24 pt later (``ScrollAwayGate``'s old threshold). Scrolling
    /// back, the bar left 8 pt early and the in-list title reappeared above it.
    ///
    /// Drags from the top end at several depths through and just past the large title's
    /// collapse, then back up from further down. At every rest the one visible "#" (the
    /// section bar's copy when it exists, else the in-list title) sits where a native
    /// sticky header would: on its own row while that row is at or below the pin line
    /// (the navigation bar's bottom), else pinned on the line. It never rides above the
    /// line uncopied, and the bar never pops in below the row (section-headers R4/R5).
    /// At every rest the in-list title stays a heading with its name, and a shown bar is
    /// the one bar, a heading with the same name, below the navigation bar (R6). Needs the
    /// large fixture (skips otherwise).
    @MainActor
    func testSlowScrollFromTheTopPinsTheFirstTitleWithoutAJump() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("The section bar exists on iOS 26 and later.")
        }
        XCUIDevice.shared.orientation = .portrait
        let app = try launchScrollAwayFixture(largeText: false)
        defer { app.terminate() }
        let first = app.staticTexts["fst.songs.section.0"]
        let bar = app.staticTexts["fst.songs.section-bar"]
        func pinLine() -> CGFloat { app.navigationBars.firstMatch.frame.maxY }
        func drag(_ from: Double, _ to: Double) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }
        func backToTop() {
            drag(0.40, 0.80)
            Thread.sleep(forTimeInterval: 1)
        }

        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(bar.exists, "A section title is pinned at the top")
        // The title text's distance below its row's top, which rests on the pin line.
        let textInset = first.frame.minY - pinLine()
        let firstLabel = first.label
        var pinnedSamples = 0
        func check(_ step: String) {
            Thread.sleep(forTimeInterval: 1)
            let line = pinLine()
            let row = first.frame.minY
            let expected = max(row, line + textInset)
            let barTop: CGFloat? = bar.exists ? bar.frame.minY : nil
            let visible = barTop ?? row
            print("FST631 \(step): line \(line) row \(row) bar \(barTop.map { "\($0)" } ?? "-")")
            if row < line + textInset - 1.5 { pinnedSamples += 1 }
            XCTAssertEqual(
                visible, expected, accuracy: 1.5,
                "\(step): \"#\" drawn at \(visible), a sticky header sits at \(expected) "
                    + "(pin line \(line), in-list title \(row), bar \(String(describing: barTop)))"
            )
            // Accessibility (section-headers R6): the in-list title stays a named heading
            // at every step; once the bar takes over it is the one bar, a heading with the
            // same spoken name, and it is not drawn under the navigation bar.
            XCTAssertNotEqual(try? isHeading(first), false, "\(step): the in-list title lost its heading")
            XCTAssertEqual(first.label, firstLabel, "\(step): the in-list title changed its name")
            if barTop != nil {
                XCTAssertEqual(
                    app.staticTexts.matching(identifier: "fst.songs.section-bar").count, 1,
                    "\(step): more than one section bar"
                )
                XCTAssertNotEqual(try? isHeading(bar), false, "\(step): the section bar is not a heading")
                XCTAssertEqual(bar.label, firstLabel, "\(step): the bar names another section")
                XCTAssertGreaterThanOrEqual(bar.frame.minY, line, "\(step): the bar is under the navigation bar")
            }
        }

        // Down from the top: ending inside the collapse, at its end and just past it.
        for (index, end) in stride(from: 0.54, through: 0.48, by: -0.006).enumerated() {
            drag(0.60, end)
            check("Down \(index + 1) to \(end)")
            backToTop()
        }
        // Back up from further down, ending just past the collapse and at the top.
        for (index, end) in stride(from: 0.50, through: 0.56, by: 0.012).enumerated() {
            drag(0.60, 0.42)
            drag(0.42, end)
            check("Up \(index + 1) to \(end)")
            backToTop()
        }
        XCTAssertGreaterThan(pinnedSamples, 2, "No drag ended with the first title past its pin line")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Issue #471 (accessibility backfill for #325): #325 moved the publication refresh
    /// spinner, the VoiceOver page anchor and their `@AccessibilityFocusState` into an
    /// always-mounted overlay over Songs, so focus-store updates during slow drags near
    /// the top no longer rebuild the list. With focus tracking on as under VoiceOver
    /// (`FST_UI_TEST_PAGE_ANCHOR=inside`), after #325's slow drags a little way down and
    /// back: the large title is open again and the "#" heading and first row are back
    /// where they started; the overlay adds no element at rest; the heading reads "#"
    /// above the first row; visible rows are named 44 pt targets; the filter field and
    /// Sort stay hittable; a tap on the top of the first row (inside the anchor's strip)
    /// opens it; and the system audit finds nothing on that region. Hosted overlay
    /// semantics (spinner, order, pass-through, Reduce Motion) are
    /// `PublicationRefreshAccessibilityTests`. Needs the large fixture (skips otherwise).
    @MainActor
    func testSlowDragsNearTheTopKeepTheTopOfSongsAccessible() throws {
        try assertTopOfSongsAccessibleAfterSlowDrags(largeText: false)
    }

    /// Issue #471 at the largest text size (AX5): the same checks, with the "#" heading
    /// grown to the AX5 subheadline line after the drags.
    @MainActor
    func testSlowDragsNearTheTopKeepTheTopOfSongsAccessibleAtAX5() throws {
        try assertTopOfSongsAccessibleAfterSlowDrags(largeText: true)
    }

    /// Run #325's slow near-top drags and check the top of Songs (#471).
    ///
    /// - Parameter largeText: Launch at AX5.
    /// - Throws: `XCTSkip` without the large fixture or before iOS 26; a failed audit.
    @MainActor
    private func assertTopOfSongsAccessibleAfterSlowDrags(largeText: Bool) throws {
        continueAfterFailure = false
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("The near-top title transition of #325 is iOS 26 and later.")
        }
        XCUIDevice.shared.orientation = .portrait
        let app = try launchScrollAwayFixture(
            largeText: largeText, environment: ["FST_UI_TEST_PAGE_ANCHOR": "inside"]
        )
        defer { app.terminate() }
        let firstTitle = app.staticTexts["fst.songs.section.0"]
        let firstRow = app.buttons["fst.songs.row.fixture-song-1"]
        let sectionBar = app.staticTexts["fst.songs.section-bar"]
        let overlay = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.publication."))
        func barBottom() -> CGFloat { app.navigationBars.firstMatch.frame.maxY }
        func waitUntil(_ what: @autoclosure () -> String, _ condition: @escaping () -> Bool) {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
            if XCTWaiter.wait(for: [settled], timeout: FestivalApp.budget(5)) != .completed { XCTFail(what()) }
        }
        func drag(_ from: Double, _ to: Double) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)),
                withVelocity: .slow, thenHoldForDuration: 0.5
            )
        }

        // At rest at the top.
        waitForListToSettle(app)
        XCTAssertTrue(firstTitle.waitForExistence(timeout: FestivalApp.budget(5)))
        let expanded = barBottom()
        let titleFrame = firstTitle.frame
        let rowFrame = firstRow.frame
        XCTAssertEqual(overlay.count, 0, "The refresh overlay exposes an element at rest")

        // #325's reported path: slow drags a little way down and back past the top.
        for (index, cycle) in [((0.60, 0.52), (0.52, 0.62)), ((0.60, 0.50), (0.50, 0.64)), ((0.60, 0.45), (0.45, 0.66))]
            .enumerated() {
            drag(cycle.0.0, cycle.0.1)
            drag(cycle.1.0, cycle.1.1)
            waitUntil("Drag \(index + 1): large title not open again (\(barBottom()) vs \(expanded))") {
                abs(barBottom() - expanded) <= 2
            }
            waitUntil("Drag \(index + 1): first row moved (\(firstRow.frame) vs \(rowFrame))") {
                abs(firstRow.frame.minY - rowFrame.minY) <= 2
            }
            XCTAssertFalse(sectionBar.exists, "Drag \(index + 1): a section title stayed pinned at the top")
        }
        waitForListToSettle(app)
        XCTAssertEqual(app.state, .runningForeground)

        // Labels, order and targets of the top region; nothing from the overlay.
        XCTAssertEqual(overlay.count, 0, "The refresh overlay exposes an element after the drags")
        XCTAssertEqual(firstTitle.label, "#")
        XCTAssertEqual(firstTitle.frame.minY, titleFrame.minY, accuracy: 2, "The # heading moved: \(firstTitle.frame)")
        XCTAssertLessThanOrEqual(firstTitle.frame.maxY, firstRow.frame.minY + 1, "Row read before its heading")
        XCTAssertGreaterThanOrEqual(firstTitle.frame.minY, barBottom() - 1, "The # heading is under the navigation bar")
        let tabs = app.tabBars.firstMatch.frame
        let window = app.windows.firstMatch.frame
        let visible = try FestivalApp.snapshotNodes(in: app, where: SongsUITestSupport.isSongsRow).filter {
            window.intersects($0.frame) && $0.frame.minY < tabs.minY
        }
        XCTAssertFalse(visible.isEmpty, "No song rows at the top")
        for row in visible {
            XCTAssertFalse(row.label.isEmpty, "\(row.identifier) unnamed")
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(row.identifier) is \(row.frame.height) pt")
        }
        let tops = visible.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "Rows are not listed top to bottom")
        XCTAssertTrue(SongsUITestSupport.songsSearchEntry(in: app).isHittable, "Filter Songs not hittable")
        XCTAssertTrue(
            app.buttons["fst.songs.sort"].isHittable || app.buttons["fst.songs.tools"].isHittable,
            "Sort is not available"
        )
        if largeText {
            let line = UIFont.preferredFont(
                forTextStyle: .subheadline,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            ).lineHeight
            XCTAssertGreaterThanOrEqual(firstTitle.frame.height, line - 2, "The # heading is not at AX5: \(firstTitle.frame)")
        }

        // The system audit on the top region: the heading, the visible rows and anything
        // the overlay exposes (the rest of the page has its own journeys).
        let rowIDs = Set(visible.map(\.identifier))
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.dynamicType, .textClipped, .sufficientElementDescription, .trait, .hitRegion],
            name: "top of Songs after slow drags", reset: { issues = [] }
        ) { issue in
            let id = issue.element?.identifier ?? ""
            let region = id == "fst.songs.section.0" || id.hasPrefix("fst.publication.")
                || (rowIDs.contains(id) && issue.auditType != .dynamicType)
            if region { issues.append("\(id): \(issue.compactDescription)") }
            return true
        }
        XCTAssertEqual(issues, [], "Top of Songs audit issues")

        // A tap on the top of the first row, inside the page anchor's 44 pt strip, opens it.
        let row = firstRow.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: row.midX, dy: row.minY + min(10, row.height / 4)))
            .tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["fst.song-detail.hero-title"].waitForExistence(timeout: FestivalApp.budget(10)),
            "A tap on the top of the first row did not open it"
        )
    }

    /// Issue #560: a programmatic scroll (a landing correction, a `.top` jump while the
    /// inset changes) could leave the List resting part-way through the large title's
    /// collapse; UIKit snaps the title only when a drag ends. The large title then sat
    /// behind Open Navigation and the "#" title under the Filter field.
    ///
    /// After one scroll down and back (so the collapse band is known), the journey
    /// creates `FST_DEBUG_SONGS_PARK_TOP`'s trigger file and the app moves the List 15 pt
    /// up programmatically, the way a landing correction does (a trigger, not a timer, so
    /// a slow CI host cannot park it mid-preparation). The List must settle at the nearer end of the collapse:
    /// back at its top with the title open. Accessibility: the large title never overlaps
    /// the toolbar buttons, Open Navigation and Choose Profile stay hittable with their
    /// 36 pt glass targets, and the first section title is not hidden under the Filter
    /// field. Needs the large fixture (skips otherwise). Runs on every supported iOS.
    ///
    /// Since #632 the iPhone's own pose floats its page tools and gives Songs the leading
    /// inline title, which never collapses, so the journey runs in the simulated folded
    /// Duo window (`FST_DEBUG_DUO_WINDOW=folded`), where the same build keeps the system
    /// large title, Open Navigation and Profile (#678).
    @MainActor
    func testProgrammaticScrollNeverRestsPartWayThroughTheLargeTitle() throws {
        try assertProgrammaticParkSettles(legacyScrollGeometry: false)
    }

    /// Issue #560 on the iOS 17 path: there `onScrollGeometryChange` and the scroll phase
    /// are missing, so the rest watch reads the List's platform scroll view
    /// (`PlatformScrollObserver`) and waits out touches and deceleration itself.
    /// `FST_DEBUG_LEGACY_SCROLL_GEOMETRY=1` forces that path on a newer simulator; the
    /// same programmatic park must settle once, with the same accessibility checks.
    @MainActor
    func testProgrammaticScrollNeverRestsPartWayOnTheLegacyScrollPath() throws {
        try assertProgrammaticParkSettles(legacyScrollGeometry: true)
    }

    /// Park the List 15 pt into the large title's collapse band and require it to settle
    /// once at the open top, with the toolbar and the first section title uncovered.
    ///
    /// - Parameter legacyScrollGeometry: Force the iOS 17 scroll-reading path.
    @MainActor
    private func assertProgrammaticParkSettles(legacyScrollGeometry: Bool) throws {
        let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let log = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("songs-title-rest-\(UUID().uuidString).json")
        let trigger = log.deletingPathExtension().appendingPathExtension("park")
        defer {
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: trigger)
        }
        var environment = [
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
            "FST_DEBUG_STALL_LOG": log.path,
            "FST_DEBUG_SONGS_PARK_TOP": "15@\(trigger.path)",
        ]
        if legacyScrollGeometry { environment["FST_DEBUG_LEGACY_SCROLL_GEOMETRY"] = "1" }
        // The large title lives where page tools do not float (standard placement): on an
        // iPhone, the simulated folded window (#632, #678).
        let simulatesFolded = UIDevice.current.userInterfaceIdiom == .phone
        if simulatesFolded {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = "folded"
        }
        let app = FestivalApp.makeApp(environment)
        app.launch()
        defer { app.terminate() }
        if simulatesFolded {
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let folded = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "folded "), object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [folded], timeout: FestivalApp.budget(10)), .completed,
                           "The app never simulated the folded window")
        }
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: FestivalApp.budget(15)))
        // The Sort button shows before the catalogue loads: wait for a row before judging
        // the catalogue's length by the A–Z rail.
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-song-1"].waitForExistence(timeout: FestivalApp.budget(15)))
        guard app.descendants(matching: .any)
            .matching(identifier: "fst.songs.section-index").firstMatch
            .waitForExistence(timeout: FestivalApp.budget(3)) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }

        // Runs on iOS 17 too: the first section title keeps its identifier as an opaque
        // pinned List header there, and the Filter field still sits above it.
        let title = app.navigationBars.staticTexts["Songs"]
        let first = app.staticTexts["fst.songs.section.0"]
        let drawer = app.buttons["fst.shell.drawer.open"]
        let profile = app.buttons["fst.shell.profile"]
        XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertTrue(first.waitForExistence(timeout: FestivalApp.budget(5)))
        Thread.sleep(forTimeInterval: FestivalApp.budget(1))
        let restTitle = title.frame
        let restFirst = first.frame
        func atRest() -> Bool {
            abs(title.frame.minY - restTitle.minY) <= 1 && abs(first.frame.minY - restFirst.minY) <= 1
        }
        func waitUntil(_ what: String, timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) {
            let met = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in condition() }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [met], timeout: FestivalApp.budget(timeout)), .completed, what)
        }

        // Collapse the title once, then come back to the open top before the park.
        let list = app.descendants(matching: .any).matching(identifier: "fst.songs.list").firstMatch
        list.swipeUp()
        waitUntil("The large title did not collapse") { restTitle.minY - title.frame.minY > 30 }
        for _ in 0..<3 where !atRest() {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
            )
            Thread.sleep(forTimeInterval: FestivalApp.budget(1))
        }
        waitUntil("Songs did not return to its open top before the park", atRest)

        struct Report: Decodable { var counters: [String: Int] }
        func settles() -> Int {
            (try? Data(contentsOf: log))
                .flatMap { try? JSONDecoder().decode(Report.self, from: $0) }?
                .counters["songs.largeTitle.settle"] ?? 0
        }
        XCTAssertEqual(settles(), 0, "A settle ran before the park")
        XCTAssertTrue(FileManager.default.createFile(atPath: trigger.path, contents: nil))
        waitUntil("The parked List never settled the large title", timeout: 10) { settles() > 0 }
        waitUntil(
            "Rested part-way: title \(title.frame) vs \(restTitle), # \(first.frame) vs \(restFirst)",
            atRest
        )

        // Accessibility: nothing the title or a row covers loses its target.
        for button in [drawer, profile] {
            XCTAssertTrue(button.isHittable, "\(button.identifier) is covered")
            XCTAssertGreaterThanOrEqual(button.frame.height, 36, "\(button.identifier) target shrank")
            XCTAssertFalse(
                title.frame.intersects(button.frame),
                "Large title \(title.frame) overlaps \(button.identifier) \(button.frame)"
            )
        }
        // The first section title sits below everything the navigation bar draws: the
        // large title, and the Filter field where it is the bar's search.
        let chromeBottom = try FestivalApp.navigationBarContentBottom(in: app)
        XCTAssertGreaterThanOrEqual(
            first.frame.minY, chromeBottom - 1,
            "The first section title \(first.frame) sits under the navigation bar (ends \(chromeBottom))"
        )
        let field = SongsUITestSupport.songsSearchField(in: app)
        if field.frame.minY < first.frame.minY {
            XCTAssertTrue(field.isHittable)
            XCTAssertGreaterThanOrEqual(
                first.frame.minY, field.frame.maxY - 1,
                "The first section title \(first.frame) sits under the Filter field \(field.frame)"
            )
        } else {
            // The folded window's bottom field (#633), under the list, not over it; its
            // hit region is `DuoFilterFieldAccessibilityJourneyTests`' (on a plain iPhone
            // the simulation keeps the phone's tab bar over it).
            XCTAssertGreaterThanOrEqual(field.frame.minY, first.frame.maxY, "Filter field \(field.frame) above #")
        }
        XCTAssertEqual(first.label, "#")
        XCTAssertEqual(settles(), 1, "The settle repeated: the List kept moving")
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
    /// The floating page-tools row's frame (`.null` when it is not shown). Its text
    /// stops growing at `FloatingPageToolsBar.maxTypeSize` (`page-tools-and-nav-chrome`).
    let accessory: CGRect
    /// Where the top ramp under the section or navigation bar ends (`scroll-edge`
    /// R2/R3): 40 pt below its edge, or the edge itself with a hard edge (R7).
    let rampEnd: CGFloat
    /// The app window's frame.
    let window: CGRect
    /// The page as rendered now.
    let image: CGImage

    /// Read the page.
    ///
    /// - Parameters:
    ///   - app: Songs, as the audit left it.
    ///   - ramp: Depth of the top ramp (0 with a hard edge).
    /// - Throws: A missing screenshot.
    init(_ app: XCUIApplication, ramp: CGFloat) throws {
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
            ? sectionBar.frame.maxY : app.navigationBars.firstMatch.frame.maxY) + ramp
        image = try XCTUnwrap(app.screenshot().image.cgImage)
    }
}

/// One list row's accessibility as XCUITest reads it, for comparing the row clear of
/// a pinned title's fade with the same row under it: Songs' section bar (issue #553) and
/// the Notifications sheet's pinned "New" title (`NotificationsAccessibilityJourneyTests`,
/// #469).
struct PinnedRowProbe {
    /// The pinned title's full fade depth (`ScrollEdgeFade.topDistance`).
    static let fade: CGFloat = 40

    /// The row button's label.
    let label: String
    /// The row button's frame.
    let frame: CGRect
    /// Each descendant of the row button, as type and label, in tree order.
    let descendants: [String]
    /// Labelled, identified or typed elements inside the row's frame that are neither the
    /// row, its descendants, its containers nor the A–Z rail overlapping its trailing
    /// edge: what a card rim or mask exposing itself to VoiceOver would add.
    let strays: [String]
    /// Unlabelled `.other` containers drawn over most of the row (UIKit-backed
    /// backgrounds such as the material's effect view), which VoiceOver does not read; a
    /// mask must not add one.
    let containers: [String]

    /// Read the row from one snapshot of the app.
    ///
    /// - Parameters:
    ///   - row: The row button.
    ///   - app: The running app.
    ///   - visibleBottom: Where page chrome (the tab bar and its accessory) starts over a
    ///     row taller than the space above it (AX5): strays below it are the chrome's.
    /// - Throws: A snapshot failure or a row missing from it.
    @MainActor
    init(row: XCUIElement, in app: XCUIApplication, visibleBottom: CGFloat = .infinity) throws {
        let identifier = row.identifier
        var flat: [XCUIElementSnapshot] = []
        var ends: [Int] = []
        func walk(_ node: XCUIElementSnapshot) {
            let index = flat.count
            flat.append(node)
            ends.append(index + 1)
            node.children.forEach(walk)
            ends[index] = flat.count
        }
        walk(try app.snapshot())
        let index = try XCTUnwrap(
            flat.firstIndex { $0.elementType == .button && $0.identifier == identifier },
            "\(identifier) missing from the snapshot"
        )
        let node = flat[index]
        let own = index..<ends[index]
        label = node.label
        frame = node.frame
        descendants = flat[own].dropFirst().map { "\($0.elementType.rawValue) '\($0.label)'" }
        let inside = node.frame.insetBy(dx: -1, dy: -1)
        let shown = CGRect(
            x: inside.minX, y: inside.minY, width: inside.width,
            height: max(0, min(inside.maxY, visibleBottom) - inside.minY)
        )
        let rail = flat.firstIndex { $0.identifier == "fst.songs.section-index" }.map { $0..<ends[$0] } ?? 0..<0
        let overlapping = flat.indices.filter { other in
            let element = flat[other]
            let isContainer = other < index && ends[other] > index
            return !own.contains(other) && !isContainer && !rail.contains(other)
                && element.elementType != .cell && !element.frame.isEmpty && inside.contains(element.frame)
        }
        func describe(_ element: XCUIElementSnapshot) -> String {
            "\(element.elementType.rawValue) '\(element.identifier)' '\(element.label)' \(element.frame)"
        }
        let isStructural = { (element: XCUIElementSnapshot) in
            element.elementType == .other && element.label.isEmpty && element.identifier.isEmpty
        }
        strays = overlapping.map { flat[$0] }.filter { !isStructural($0) && shown.contains($0.frame) }.map(describe)
        // At least half the row each way: a rim or mask view spans the card, while the
        // scroll indicator shown after a drag (3 pt wide) only overlaps the row's edge.
        let isRowSized = { (element: XCUIElementSnapshot) in
            element.frame.width >= node.frame.width / 2 && element.frame.height >= node.frame.height / 2
        }
        // Sizes to 0.1 pt: a 130⅔ pt row reads as …63 or …69 from one snapshot to the next.
        containers = overlapping.map { flat[$0] }.filter { isStructural($0) && isRowSized($0) }.map {
            "\($0.elementType.rawValue) " + String(format: "%.1f × %.1f", $0.frame.width, $0.frame.height)
        }
    }
}
