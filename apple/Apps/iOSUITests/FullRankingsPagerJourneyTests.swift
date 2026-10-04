import XCTest

/// Full Rankings' shared pinned pager (`RankingsPagerView`) across many pages (gap #10, Lane PB).
///
/// Needs a second fixture service with padded rosters (1,200 accounts = 48 pages of
/// 25; `fixture-rank-{n}` rows), separate from the default `:8765` fixture:
///
///     python3 tools/mock_service.py --large-rankings --port 8766
///
/// Each test skips (not fails) when that service isn't listening, so the default
/// journey batch stays green on hosts that only run the `:8765` fixture.
final class FullRankingsPagerJourneyTests: XCTestCase {
    private static let origin = "http://127.0.0.1:8766"

    /// Skip unless the large-rankings fixture answers its publication read.
    private func requireLargeRankingsFixture() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.origin)/api/publication"))
        let done = expectation(description: "fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --large-rankings --port 8766`")
    }

    @MainActor
    private func launchLeadBoard() -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_ROUTE": "fullRankings:Solo_Guitar",
        ])
        app.launch()
        return app
    }

    /// Next, Last, Previous and First move the board and the `page / total` value,
    /// with the edge buttons disabling at page 1 and page 48.
    @MainActor
    func testSharedPagerStepsThroughPages() throws {
        continueAfterFailure = false
        try requireLargeRankingsFixture()
        let app = launchLeadBoard()
        let info = app.descendants(matching: .any)
            .matching(identifier: "fst.full-rankings.page-info").firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 20))
        XCTAssertEqual(info.value as? String, "1 of 48")
        XCTAssertTrue(app.staticTexts["1,200 ranked players"].exists)
        let first = app.buttons["fst.full-rankings.page-first"]
        let previous = app.buttons["fst.full-rankings.page-previous"]
        let next = app.buttons["fst.full-rankings.page-next"]
        let last = app.buttons["fst.full-rankings.page-last"]
        XCTAssertFalse(first.isEnabled)
        XCTAssertFalse(previous.isEnabled)
        XCTAssertTrue(next.isEnabled)

        next.tap()
        XCTAssertTrue(app.buttons["fst.rankings.row.fixture-rank-26"].waitForExistence(timeout: 15))
        XCTAssertEqual(info.value as? String, "2 of 48")
        XCTAssertTrue(previous.isEnabled)

        last.tap()
        XCTAssertTrue(app.buttons["fst.rankings.row.fixture-rank-1176"].waitForExistence(timeout: 15))
        XCTAssertEqual(info.value as? String, "48 of 48")
        XCTAssertFalse(next.isEnabled)
        XCTAssertFalse(last.isEnabled)

        previous.tap()
        XCTAssertTrue(app.buttons["fst.rankings.row.fixture-rank-1151"].waitForExistence(timeout: 15))
        XCTAssertEqual(info.value as? String, "47 of 48")

        first.tap()
        XCTAssertTrue(app.buttons["fst.rankings.row.fixture-player-1"].waitForExistence(timeout: 15))
        XCTAssertEqual(info.value as? String, "1 of 48")
    }

    /// Switching instrument from the toolbar menu resets to page 1 of the new board.
    @MainActor
    func testInstrumentSwitchResetsToFirstPage() throws {
        continueAfterFailure = false
        try requireLargeRankingsFixture()
        let app = launchLeadBoard()
        let info = app.descendants(matching: .any)
            .matching(identifier: "fst.full-rankings.page-info").firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 20))
        app.buttons["fst.full-rankings.page-next"].tap()
        XCTAssertTrue(app.buttons["fst.rankings.row.fixture-rank-26"].waitForExistence(timeout: 15))

        app.buttons["fst.full-rankings.instrument-menu"].tap()
        let drums = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Drums'")).firstMatch
        XCTAssertTrue(drums.waitForExistence(timeout: 10))
        drums.tap()
        XCTAssertTrue(app.navigationBars["Drums Rankings"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fst.rankings.row.fixture-player-1"].waitForExistence(timeout: 15))
        XCTAssertEqual(info.value as? String, "1 of 48")
    }
}
