import UIKit
import XCTest

/// Accessibility of iPhone Songs after deselecting a player (#487, for #359).
///
/// #359 made a deselect reset Songs' filters, instrument and player sort like the web's
/// `resetSongSettingsForDeselect`, so no "Player score filters paused until a player is
/// selected" or "Score sort paused until a player is selected" card is left behind. Each
/// test launches fixture Songs with Fixture Player 2 selected (`FST_DEBUG_PROFILE`, which
/// keeps the real saved-settings store), saves player choices through the real sheets,
/// deselects from the drawer and checks what VoiceOver gets: Sort and Filter Songs read
/// the reset state without revisiting the page (HIG VoiceOver: "Update labels when UI
/// changes."), no paused card or text remains, the tools are hittable 44 pt targets (HIG
/// Accessibility, Mobility: 44x44 pt on iOS) and the Filter sheet offers General only. At
/// the largest accessibility text size the folded Sort and Filter menu reaches the same
/// reset sheets. The hosted `SongsDeselectResetAccessibilityTests` pin the tree in `apple-ci`.
///
/// Saved choices are set through the UI, never as launch arguments: the argument domain
/// would mask the reset the app writes.
///
/// Needs `tools/mock_service.py --port 8765`, like `SongsJourneyTests`
/// (`TEST_RUNNER_FST_FIXTURE_URL=<origin>` selects another listener).
final class SongsDeselectAccessibilityJourneyTests: XCTestCase {
    // MARK: - Helpers

    /// Notices #359 removed without a player, and the paused notices sharing their place.
    private static let pausedNotices = [
        "fst.songs.score-filter-paused", "fst.songs.score-filter-hidden",
        "fst.songs.sort-paused", "fst.songs.filter-paused",
    ]

    /// Fixture Songs with Fixture Player 2 selected, optionally at a text size.
    ///
    /// - Parameter contentSize: A `UIContentSizeCategory` raw value, or nil for the default.
    /// - Returns: The launched app showing Songs.
    @MainActor
    private func launchSongs(contentSize: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = SongsUITestSupport.fixtureURL
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-2:Fixture Player 2"
        app.launchArguments += ["-fst.settings.hideShop", "NO"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        XCTAssertTrue(
            app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: FestivalApp.budget(20)),
            "Songs did not load"
        )
        return app
    }

    /// Wait until an element's accessibility value is `value`.
    @MainActor
    private func waitForValue(
        _ element: XCUIElement, _ value: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
            "\(element.identifier) reads \(element.exists ? element.value as? String ?? "<none>" : "<missing>")"
                + ", expected \(value)",
            file: file, line: line
        )
    }

    /// Assert an element is a hittable target of at least 44x44 pt.
    @MainActor
    private func assertTarget(
        _ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.isHittable, "\(name) is not hittable", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, "\(name) target \(element.frame)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(name) target \(element.frame)", file: file, line: line)
    }

    /// No paused card, and no text naming a pause or a missing player, anywhere on Songs.
    @MainActor
    private func assertNoPausedState(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for id in Self.pausedNotices {
            XCTAssertFalse(app.descendants(matching: .any)[id].exists, "\(id) after deselect", file: file, line: line)
        }
        for phrase in ["until a player is selected", "paused"] {
            let text = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", phrase)).firstMatch
            XCTAssertFalse(text.exists, "'\(text.label)' after deselect", file: file, line: line)
        }
    }

    /// Open Filter from the floating tools, or from the folded Sort and Filter menu.
    @MainActor
    private func openFilter(_ app: XCUIApplication) {
        let folded = app.buttons["fst.songs.tools"]
        if folded.exists {
            folded.tap()
            let item = app.buttons["fst.songs.tools.filter"]
            XCTAssertTrue(item.waitForExistence(timeout: FestivalApp.budget(5)), "Filter… missing")
            item.tap()
        } else {
            app.buttons["fst.songs.filter"].tap()
        }
        XCTAssertTrue(app.buttons["fst.songs.filter.done"].waitForExistence(timeout: FestivalApp.budget(10)))
    }

    /// Open Sort from the floating tools, or from the folded Sort and Filter menu.
    @MainActor
    private func openSort(_ app: XCUIApplication) {
        let folded = app.buttons["fst.songs.tools"]
        if folded.exists {
            folded.tap()
            let item = app.buttons["fst.songs.tools.sort"]
            XCTAssertTrue(item.waitForExistence(timeout: FestivalApp.budget(5)), "Sort… missing")
            item.tap()
        } else {
            app.buttons["fst.songs.sort"].tap()
        }
        XCTAssertTrue(app.buttons["fst.songs.sort.done"].waitForExistence(timeout: FestivalApp.budget(10)))
    }

    /// Save an Item Shop filter (and, at the default size, the Lead instrument) through
    /// the Filter sheet.
    @MainActor
    private func saveFilters(_ app: XCUIApplication, instrument: Bool) {
        openFilter(app)
        let unavailable = app.switches["fst.songs.filter.shop-unavailable"]
        if !unavailable.exists {
            let group = app.descendants(matching: .any).matching(identifier: "fst.songs.filter.shop").firstMatch
            SongsUITestSupport.revealFilterOption(group, in: app).tap()
        }
        SongsUITestSupport.setSwitch(SongsUITestSupport.revealFilterOption(unavailable, in: app), to: "0")
        if instrument {
            let form = app.descendants(matching: .any).matching(identifier: "fst.songs.filter.form").firstMatch
            let lead = form.buttons["Lead"]
            SongsUITestSupport.revealFilterOption(lead, in: app).tap()
            let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: lead)
            XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: FestivalApp.budget(5)), .completed, "Lead not chosen")
        }
        app.buttons["fst.songs.filter.done"].tap()
        XCTAssertTrue(app.buttons["fst.songs.filter.done"].waitForNonExistence(timeout: FestivalApp.budget(10)))
    }

    /// The Filter sheet without a player: General's groups only, collapsed, then Reset.
    @MainActor
    private func assertResetFilterSheet(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let general = app.descendants(matching: .any).matching(identifier: "fst.songs.filter.general").firstMatch
        XCTAssertTrue(general.waitForExistence(timeout: FestivalApp.budget(10)), "No General heading",
                      file: file, line: line)
        for id in ["score-sections", "instrument"] {
            XCTAssertFalse(app.descendants(matching: .any)["fst.songs.filter.\(id)"].exists,
                           "\(id) without a player", file: file, line: line)
        }
        // A saved Item Shop filter opens its group by itself; the reset leaves it closed.
        XCTAssertFalse(app.switches["fst.songs.filter.shop-unavailable"].exists, "Item Shop still filtered",
                       file: file, line: line)
        let reset = SongsUITestSupport.revealFilterReset(in: app)
        XCTAssertEqual(reset.label, "Reset Filters", file: file, line: line)
        assertTarget(reset, "Reset Filters", file: file, line: line)
    }

    // MARK: - Tests

    /// Default text size: Item Shop filter, Lead and a descending Score sort, then a
    /// drawer deselect. Sort and Filter Songs read the reset state at once, stay named
    /// 44 pt targets, the page shows no paused card, the rows read A to Z, and Filter
    /// opens a General-only sheet. Songs' audit then finds nothing on the tools.
    @MainActor
    func testDeselectResetsSongsToolsForVoiceOver() throws {
        let app = launchSongs()
        let sort = app.buttons["fst.songs.sort"]
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(sort.waitForExistence(timeout: FestivalApp.budget(10)) && filter.exists)
        saveFilters(app, instrument: true)
        XCTAssertTrue((filter.value as? String)?.contains("Item Shop filter") == true, "\(filter.value ?? "")")

        openSort(app)
        let score = app.buttons.matching(NSPredicate(format: "label == %@", "Score")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: FestivalApp.budget(5)), "No Score sort with Lead")
        score.tap()
        app.buttons["fst.songs.sort.direction.descending"].tap()
        app.buttons["fst.songs.sort.done"].tap()
        waitForValue(sort, "Score, descending")
        SongsUITestSupport.record(app, name: "songs-deselect-before")

        try SongsUITestSupport.deselectFixturePlayer(in: app)
        // No `reshowSongsToolbar`: VoiceOver must hear the reset without leaving the page.
        waitForValue(sort, "Title, ascending")
        waitForValue(filter, "No filters")
        SongsUITestSupport.record(app, name: "songs-deselect-after")
        XCTAssertEqual(sort.label, "Sort")
        XCTAssertEqual(filter.label, "Filter Songs")
        assertTarget(sort, "Sort")
        assertTarget(filter, "Filter Songs")
        assertNoPausedState(app)

        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(orbit.waitForExistence(timeout: FestivalApp.budget(10)) && pulse.exists)
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY, "Title order: Orbit reads before Pulse")
        let rows = try FestivalApp.snapshotNodes(in: app, where: SongsUITestSupport.isSongsRow)
        XCTAssertEqual(rows.first?.identifier, "fst.songs.row.fixture-orbit", "first row VoiceOver reaches")

        // The tools and rows: named, distinct and big enough. The Songs list's open
        // nil-element "Text clipped" finding (accessibility.md) is outside this region.
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .contrast]) { issue in
            let id = issue.element?.identifier ?? ""
            let inRegion = id == "fst.songs.sort" || id == "fst.songs.filter" || id.hasPrefix("fst.songs.row.")
            if inRegion {
                XCTFail("\(issue.auditType) on \(id): \(issue.compactDescription)")
            }
            return !inRegion
        }

        openFilter(app)
        assertResetFilterSheet(app)
        app.buttons["fst.songs.filter.done"].tap()
    }

    /// The largest accessibility text size: an Item Shop filter saved through the folded
    /// Sort and Filter menu, then a drawer deselect. The menu stays a named 44 pt target,
    /// no paused card or text appears, Filter… opens the General-only sheet and Sort…
    /// shows Title ascending.
    @MainActor
    func testDeselectResetIsReachableAtLargestText() throws {
        let app = launchSongs(contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        saveFilters(app, instrument: false)
        try SongsUITestSupport.deselectFixturePlayer(in: app)
        let folded = app.buttons["fst.songs.tools"]
        if folded.waitForExistence(timeout: FestivalApp.budget(5)) {
            XCTAssertEqual(folded.label, "Sort and Filter")
            assertTarget(folded, "Sort and Filter")
        } else {
            waitForValue(app.buttons["fst.songs.filter"], "No filters")
            assertTarget(app.buttons["fst.songs.filter"], "Filter Songs")
        }
        assertNoPausedState(app)
        SongsUITestSupport.record(app, name: "songs-deselect-after-ax5")

        openFilter(app)
        assertResetFilterSheet(app)
        app.buttons["fst.songs.filter.done"].tap()
        XCTAssertTrue(app.buttons["fst.songs.filter.done"].waitForNonExistence(timeout: FestivalApp.budget(10)))

        openSort(app)
        let ascending = app.buttons["fst.songs.sort.direction.ascending"]
        XCTAssertTrue(ascending.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertTrue(ascending.isSelected, "Sort reads Ascending after the reset")
        XCTAssertFalse(app.buttons["fst.songs.sort.direction.descending"].isSelected)
        app.buttons["fst.songs.sort.done"].tap()
    }
}
