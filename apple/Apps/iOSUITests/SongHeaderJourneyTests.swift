import XCTest

/// The pinned song title (pattern `song-header` R4, issue #315): once the in-page header
/// scrolls under the bar, the Song Leaderboard and the Band Song Leaderboard show the
/// title in the navigation bar across all the room the bar leaves between its leading
/// and trailing items, with no fixed cap, and keep every action.
///
/// Song Details shows the same ``SongBarTitleToolbarItem``, but XCUITest cannot query
/// its pinned title after a swipe: the title draws, yet the element never appears (also
/// on master's `SongDetailJourneyTests.testSongDetailPinnedTitleAndCardLayout`,
/// 2026-10-06). `SongHeaderTextTests` cover the shared title's width instead.
///
/// Needs a fixture service whose `fixture-pulse` title is wider than any bar:
///
///     python3 tools/mock_service.py --long-titles --port 18950
///
/// Each test skips (not fails) when that service isn't listening. On iPad it runs in
/// landscape, where the bar's title slot is far wider than the former 240 pt cap; the
/// portrait-only iPhone checks the title pins and fits its narrower slot.
final class SongHeaderJourneyTests: XCTestCase {
    private static let origin = "http://127.0.0.1:18950"
    /// `mock_service.LONG_TITLE`.
    private static let longTitle =
        "Fixture Pulse: An Extraordinarily Long Synthetic Encore Title That Keeps Going Well Past Any Navigation Bar"
    /// Largest gap the bar may leave between the title and its neighbouring items.
    private static let slack: CGFloat = 32

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    /// Skip unless the long-titles fixture answers its publication read.
    private func requireLongTitlesFixture() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.origin)/api/publication"))
        let done = expectation(description: "fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --long-titles --port 18950`")
    }

    @MainActor
    func testSongLeaderboardPinnedTitleUsesTheBarsWidth() throws {
        try assertPinnedTitleFillsTheBar(
            "fst.song-leaderboard.pinned-title", route: ["FST_DEBUG_SONG_INSTRUMENT": "Solo_Guitar"]
        )
    }

    @MainActor
    func testBandSongLeaderboardPinnedTitleUsesTheBarsWidth() throws {
        try assertPinnedTitleFillsTheBar(
            "fst.song-band-leaderboard.pinned-title", route: ["FST_DEBUG_SONG_BAND": "Band_Duets"]
        )
    }

    /// Issue #542: at a large accessibility text size the Song Leaderboard's pinned title,
    /// now with the instrument icon before its caption, still reads the song and "Lead"
    /// once as one element (the icon is decorative and hidden) and stays inside the bar.
    ///
    /// No `performAccessibilityAudit(for: .dynamicType)` here: the bar caps its title's
    /// text size (the title offers the Large Content Viewer instead), so the audit
    /// reports the song title itself; the hidden icon is never audited.
    @MainActor
    func testSongLeaderboardPinnedCaptionIconScalesAtLargeText() throws {
        continueAfterFailure = false
        try requireLongTitlesFixture()
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_SONG": "fixture-pulse",
            "FST_DEBUG_SONG_INSTRUMENT": "Solo_Guitar",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch()
        SongsUITestSupport.collapseSidebarOnPad(app)

        let pinned = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.pinned-title").firstMatch
        var attempts = 0
        repeat {
            sleep(2)
            app.swipeUp()
            attempts += 1
        } while !(pinned.exists && pinned.isHittable) && attempts < 6
        XCTAssertTrue(pinned.waitForExistence(timeout: 10), "The song title did not pin to the bar")
        XCTAssertTrue(pinned.label.hasPrefix(Self.longTitle), pinned.label)
        XCTAssertEqual(pinned.label.components(separatedBy: "Fixture Pulse").count, 2, pinned.label)
        XCTAssertEqual(pinned.label.components(separatedBy: "Lead").count, 2, "Instrument once: \(pinned.label)")
        SongsUITestSupport.record(app, name: "song-leaderboard-pinned-caption-icon-axm")

        let bar = app.navigationBars.firstMatch.frame
        XCTAssertTrue(bar.insetBy(dx: 0, dy: -2).contains(pinned.frame), "The pinned title \(pinned.frame) left the bar \(bar)")
        XCTAssertLessThanOrEqual(app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.pinned-title").count, 1, "One pinned title")
    }

    /// Open `fixture-pulse` on a page, scroll its header away, then check the pinned
    /// title spans the bar between its nearest leading and trailing items.
    ///
    /// - Parameters:
    ///   - identifier: The page's pinned-title identifier.
    ///   - route: Extra `FST_DEBUG_SONG_*` launch keys that pick the page.
    @MainActor
    private func assertPinnedTitleFillsTheBar(_ identifier: String, route: [String: String]) throws {
        continueAfterFailure = false
        try requireLongTitlesFixture()
        // Landscape only where the app rotates (the iPhone app is portrait-only).
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_SONG": "fixture-pulse",
        ].merging(route) { $1 })
        app.launch()
        SongsUITestSupport.collapseSidebarOnPad(app)

        let pinned = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let shown = NSPredicate(format: "exists == true AND hittable == true")
        var attempts = 0
        repeat {
            sleep(2)
            app.swipeUp()
            attempts += 1
        } while !(pinned.exists && pinned.isHittable) && attempts < 5
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation(for: shown, evaluatedWith: pinned)], timeout: 10),
            .completed, "The song title did not pin to the bar on \(identifier)"
        )
        XCTAssertTrue(pinned.label.hasPrefix(Self.longTitle), "Read the full title once: \(pinned.label)")
        XCTAssertEqual(pinned.label.components(separatedBy: "Fixture Pulse").count, 2, pinned.label)
        SongsUITestSupport.record(app, name: "\(identifier)-landscape")

        let title = pinned.frame
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.exists)
        XCTAssertLessThan(title.minY, bar.frame.maxY, "The pinned title is not in the bar")
        let items = bar.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && $0.frame.width > 0 }
            .map(\.frame)
            .filter { $0.midY > bar.frame.minY && $0.midY < bar.frame.maxY && !$0.intersects(title) }
        let leading = try XCTUnwrap(
            items.filter { $0.maxX <= title.minX }.map(\.maxX).max(), "No leading bar item"
        )
        let trailing = try XCTUnwrap(
            items.filter { $0.minX >= title.maxX }.map(\.minX).min(), "No trailing bar item"
        )
        XCTAssertGreaterThan(title.width, 240, "Still capped: \(title) in \(bar.frame)")
        XCTAssertLessThanOrEqual(title.minX - leading, Self.slack, "Room left before the title: \(title)")
        XCTAssertLessThanOrEqual(trailing - title.maxX, Self.slack, "Room left after the title: \(title)")
    }
}
