import XCTest

/// Song pages under the iPhone Duo vertical bar (issue #363, owner-approved exception to
/// pattern page-tools-and-nav-chrome R14): no title at the top while the song header is
/// on screen, the pinned song title (`song-header` R4) once it scrolls away, and none
/// again when it returns, as on iPhone. Covers Song Details, the Song Leaderboard, the
/// Band Song Leaderboard and Player History.
///
/// Run folded (vertical bar) against the long-titles fixture, whose boards scroll:
///
/// ```
/// python3 tools/mock_service.py --long-titles --port 18363 &
/// python3 tools/ios_sim.py uitest --device duo --pose folded --only DuoSongTitleJourneyTests
/// ```
///
/// Each test skips when the fixture isn't listening or the app isn't in the vertical
/// bar; `SongHeaderJourneyTests` cover the horizontal bar.
final class DuoSongTitleJourneyTests: XCTestCase {
    private static let origin = "http://127.0.0.1:18363"
    /// Every fixture title of `fixture-pulse` (plain and `--long-titles`) starts so.
    private static let titlePrefix = "Fixture Pulse"

    @MainActor
    func testSongDetailTitleWaitsForTheHeader() throws {
        let app = try launch([:])
        try assertTitleFollowsTheHeader(
            in: app, header: "fst.song-detail.hero-title", pinned: "fst.song-detail.pinned-title"
        )
    }

    @MainActor
    func testSongLeaderboardTitleWaitsForTheHeader() throws {
        let app = try launch(["FST_DEBUG_SONG_INSTRUMENT": "Solo_Guitar"])
        try assertTitleFollowsTheHeader(
            in: app, header: "fst.song-leaderboard.header", pinned: "fst.song-leaderboard.pinned-title"
        )
    }

    @MainActor
    func testBandSongLeaderboardTitleWaitsForTheHeader() throws {
        let app = try launch(["FST_DEBUG_SONG_BAND": "Band_Duets"])
        try assertTitleFollowsTheHeader(
            in: app, header: "fst.song-band-leaderboard.header", pinned: "fst.song-band-leaderboard.pinned-title"
        )
    }

    /// Player History opens from Song Details' View All Scores for the fixture's
    /// eight-score player. The song opens from its row, as in `SongDetailJourneyTests`:
    /// with a debug player the `FST_DEBUG_SONG` route is re-applied and pops the page.
    /// Eight rows fit the folded Duo at the default size, so the page runs at an
    /// accessibility text size, where they overflow and the header can scroll away.
    @MainActor
    func testPlayerHistoryTitleWaitsForTheHeader() throws {
        let app = try launch(
            ["FST_DEBUG_PROFILE": "fixture-history-multi:Multi History", "FST_DEBUG_SONG": ""],
            arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        )
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15), "No fixture-pulse row")
        song.tap()
        let viewAll = element("fst.song-detail.history.view-all", in: app)
        XCTAssertTrue(element("fst.song-detail.hero-title", in: app).waitForExistence(timeout: 20))
        for _ in 0..<8 where !(viewAll.exists && viewAll.isHittable) { app.swipeUp() }
        XCTAssertTrue(viewAll.waitForExistence(timeout: 10), "No View All Scores")
        viewAll.tap()
        XCTAssertTrue(element("fst.history.row.0", in: app).waitForExistence(timeout: 15), "No history page")
        try assertTitleFollowsTheHeader(in: app, header: "fst.history.header", pinned: "fst.history.pinned-title")
    }

    // MARK: - Helpers

    /// Launch `fixture-pulse` with extra route keys; skip off the fixture or the vertical bar.
    ///
    /// - Parameters:
    ///   - route: Extra launch environment that picks the page; an empty value removes a
    ///     default key.
    ///   - arguments: Extra launch arguments.
    /// - Returns: The launched app.
    @MainActor
    private func launch(_ route: [String: String], arguments: [String] = []) throws -> XCUIApplication {
        continueAfterFailure = false
        try requireFixture()
        var environment = [
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_SONG": "fixture-pulse",
        ]
        if route["FST_DEBUG_PROFILE"] == nil { environment["FST_DEBUG_ANONYMOUS"] = "1" }
        let app = FestivalApp.makeApp(environment.merging(route) { $1 }.filter { !$0.value.isEmpty })
        app.launchArguments += arguments
        app.launch()
        try XCTSkipUnless(isVerticalBar(app), "Needs the iPhone Duo vertical bar (fold the Duo)")
        return app
    }

    /// Skip unless the fixture answers its publication read.
    private func requireFixture() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.origin)/api/publication"))
        let done = expectation(description: "fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --long-titles --port 18363`")
    }

    /// The rail stacks the section buttons vertically (as `PlayerIdentityRailJourneyTests`).
    @MainActor
    private func isVerticalBar(_ app: XCUIApplication) -> Bool {
        func section(_ label: String) -> XCUIElement? {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
            _ = matches.firstMatch.waitForExistence(timeout: 15)
            return matches.allElementsBoundByIndex.first { $0.frame.width > 0 && $0.frame.height > 0 }
        }
        guard let songs = section("Songs"), let settings = section("Settings") else { return false }
        return abs(songs.frame.midX - settings.frame.midX) < 4
            && abs(songs.frame.midY - settings.frame.midY) > 20
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Any song title drawn in a navigation bar (wider than the 1 pt placeholder).
    @MainActor
    private func visibleBarTitles(in app: XCUIApplication) -> [CGRect] {
        app.navigationBars.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", Self.titlePrefix))
            .allElementsBoundByIndex
            .map(\.frame)
            .filter { $0.width > 2 && $0.height > 2 }
    }

    /// At rest: header on screen, no title in the bar. Scrolled: the pinned title at the
    /// top. Back at the top: no title again.
    ///
    /// - Parameters:
    ///   - app: The app on the song page, scrolled to the top.
    ///   - header: Identifier of an element in the page's song header.
    ///   - pinned: The page's pinned-title identifier.
    @MainActor
    private func assertTitleFollowsTheHeader(in app: XCUIApplication, header: String, pinned: String) throws {
        let headerElement = element(header, in: app)
        XCTAssertTrue(headerElement.waitForExistence(timeout: 20), "No song header \(header)")
        sleep(1)
        XCTAssertTrue(visibleBarTitles(in: app).isEmpty,
                      "A title shows above the song header: \(visibleBarTitles(in: app))")
        XCTAssertFalse(element(pinned, in: app).exists, "The pinned title shows with the header")
        SongsUITestSupport.record(app, name: "\(pinned)-rest")

        let title = element(pinned, in: app)
        var attempts = 0
        repeat {
            app.swipeUp()
            attempts += 1
        } while !(title.exists && title.isHittable) && attempts < 5
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The title never appeared once \(header) scrolled away")
        XCTAssertTrue(title.label.hasPrefix(Self.titlePrefix), title.label)
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(title.frame.minY, window.minY + window.height / 4, "The title is not at the top: \(title.frame)")
        XCTAssertTrue(window.contains(title.frame), "The title leaves the window: \(title.frame)")
        SongsUITestSupport.record(app, name: "\(pinned)-scrolled")

        for _ in 0..<8 where !(headerElement.exists && headerElement.isHittable) { app.swipeDown() }
        app.swipeDown()
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: gone, evaluatedWith: title)], timeout: 5),
                       .completed, "The title stayed with the header back on screen")
        XCTAssertTrue(visibleBarTitles(in: app).isEmpty, "A bar title stayed: \(visibleBarTitles(in: app))")
    }
}
