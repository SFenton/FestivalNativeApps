import XCTest

/// The Rivals, Compete and Suggestions pages in the UIKit port (`UIKitPort/Features/Rivals`):
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
