import XCTest

/// The Rivals, Compete and Suggestions pages in the UIKit port (`UIKit/Features/Rivals`):
/// identifiers, element types, 44 pt targets, Dynamic Type growth at AX5 and a scoped audit.
/// Every test runs on both apps (the page contract is the SwiftUI one), so a port difference
/// fails on one app only. Fixture: `tools/mock_service.py` as `fixture-riv`.
///
/// Run with `python3 tools/ios_sim.py uitest --app uikit --only UKRivalsJourneyTests`.
final class UKRivalsJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ env: [String: String], contentSize: String? = nil) -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
        ]
        environment.merge(env) { $1 }
        let app = FestivalApp.makeApp(environment)
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue

    // MARK: - Hub

    /// The hub's Song/Leaderboard picker is a segmented control, every rival row is one
    /// button of at least 44 pt that speaks its name and both counts, and each card's View All
    /// Rivals is a button naming its card.
    @MainActor
    func testRivalsHubRowsAreButtonsWithSpokenCounts() throws {
        let app = launch(["FST_DEBUG_ROUTE": "rivals"])
        XCTAssertTrue(app.segmentedControls["fst.rivals.tab"].waitForExistence(timeout: FestivalApp.budget(20)))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.rivals.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(20)), "rival rows are buttons")
        XCTAssertTrue(row.label.contains(" songs ahead, "), "a row speaks both counts: \(row.label)")
        XCTAssertTrue(row.label.hasSuffix(" songs behind"), row.label)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "a rival row is at least 44 pt tall: \(row.frame)")
        let viewAll = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "View All Rivals, ")).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: FestivalApp.budget(10)), "View All Rivals names its card")
        // The six fixture rows in the first section use the native single-line text metric.
        // At the iPhone's default size their visual drift should be less than one point by row six.
        if app.windows.firstMatch.frame.width.rounded() == 402 {
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.rivals.row."))
                .allElementsBoundByIndex.filter { $0.frame.minY >= row.frame.minY && $0.frame.maxY <= viewAll.frame.minY }
                .sorted { $0.frame.minY < $1.frame.minY }
            XCTAssertEqual(rows.count, 6)
            let last = try XCTUnwrap(rows.last)
            XCTAssertEqual(last.frame.minY - row.frame.minY, 293.33, accuracy: 1)
        }
    }

    /// Switching to the Leaderboard tab shows the leaderboard rivals cards.
    @MainActor
    func testRivalsHubLeaderboardTabShowsLeaderboardCards() throws {
        let app = launch(["FST_DEBUG_ROUTE": "rivals"])
        let picker = app.segmentedControls["fst.rivals.tab"]
        XCTAssertTrue(picker.waitForExistence(timeout: FestivalApp.budget(20)))
        picker.buttons["Leaderboard"].tap()
        let viewAll = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fst.rivals.leaderboard.")
        ).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: FestivalApp.budget(20)), "leaderboard rivals cards load")
    }

    // MARK: - Find Rival

    /// Find Rival is a sheet with a labelled search field and the system Close in the bar.
    @MainActor
    func testFindRivalSheetHasLabelledFieldAndBarClose() throws {
        let app = launch(["FST_DEBUG_ROUTE": "rivals"])
        let find = app.buttons["fst.rivals.findRival"]
        XCTAssertTrue(find.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertEqual(find.label, "Find Rival")
        find.tap()
        let field = app.textFields["fst.rivals.findRival.search"]
        XCTAssertTrue(field.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertEqual(field.label, "Find Rival")
        let close = app.navigationBars.buttons["fst.rivals.findRival.close"]
        XCTAssertTrue(close.exists, "Close is a navigation-bar button")
        XCTAssertEqual(close.label, "Close")
        XCTAssertTrue(app.staticTexts["Enter at least two characters to search for a rival."].exists)
    }

    // MARK: - Comparison

    /// Rank pills use separate lines when they would crowd the delta badge. The comparison
    /// stays one named button and its row ends before the folded rail.
    @MainActor
    func testCompactRivalSongPillsLeaveRoomForDelta() throws {
        let app = launch([
            "FST_DEBUG_ROUTE": "rivalDetail:f1c749eb07c32578cfa3e59ec38c03a8:song:Solo_Guitar",
            "FST_DEBUG_STILL_BACKGROUND": "1",
        ])
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Pulse, Lead, you rank 12")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("Fixture Rival Golf ranks 13, you lead"), row.label)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        let lines = RecognizedText.lines(in: row.screenshot())
        let player = try XCTUnwrap(lines.first { $0.text.contains("#12 Fixture Riv") })
        let rival = try XCTUnwrap(lines.first { $0.text.contains("#13 Fixture Rival Golf") })
        XCTAssertLessThan(player.frame.maxY, rival.frame.minY, "the two standing pills need separate lines")
        let window = app.windows.firstMatch.frame
        if [window.width.rounded(), window.height.rounded()] == [466, 678] {
            let settings = app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).allElementsBoundByIndex
            let rail = try XCTUnwrap(settings.first { $0.frame.midX > window.maxX - 80 && $0.frame.width > 0 })
            XCTAssertLessThanOrEqual(row.frame.maxX, rail.frame.minX)
        }
    }

    // MARK: - Suggestions

    /// The filter sheet's switches carry their identifiers and are switches.
    @MainActor
    func testSuggestionsFilterSwitchesAreSwitches() throws {
        let app = launch(["FST_DEBUG_TAB": "suggestions"])
        let filter = app.buttons["fst.suggestions.filter-button"]
        XCTAssertTrue(filter.waitForExistence(timeout: FestivalApp.budget(25)))
        filter.tap()
        let toggle = app.switches["fst.suggestions.filter.instrument.Solo_Guitar"]
        XCTAssertTrue(toggle.waitForExistence(timeout: FestivalApp.budget(15)), "instrument toggles are switches")
        XCTAssertTrue(app.buttons["fst.suggestions.filter.reset"].exists)
        XCTAssertTrue(app.navigationBars.buttons["fst.suggestions.filter.done"].exists, "Close is a bar button")
    }

    // MARK: - Dynamic Type

    /// At AX5 a rival row still wraps its name and stacks its pills inside the screen.
    @MainActor
    func testRivalRowStaysOnScreenAtAX5() throws {
        let app = launch(["FST_DEBUG_ROUTE": "rivals"], contentSize: Self.ax5)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.rivals.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(25)))
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(row.frame.minX, window.minX - 0.5, "starts on screen: \(row.frame)")
        XCTAssertLessThanOrEqual(row.frame.maxX, window.maxX + 0.5, "ends on screen: \(row.frame)")
        XCTAssertGreaterThan(row.frame.height, 80, "the row grows with the text: \(row.frame)")
    }
}
