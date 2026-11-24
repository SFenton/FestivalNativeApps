import XCTest

/// Song Detail in the UIKit port (`UIKit/Features/SongDetail`), reached through the
/// Debug-only `FST_UIKIT_DEBUG_SONGDETAIL` hook (so it does not depend on the Songs list; on the
/// SwiftUI app, which has no hook, every test skips). The backdrop test needs the UIKit app's
/// background probe (`FST_DEBUG_BACKGROUND_PROBE`, see ``UKBackgroundJourneyTests``) and skips
/// on the SwiftUI app; the page tests run on both apps, so a port difference shows up as a
/// failure on one of them only.
///
/// Run with `python3 tools/ios_sim.py uitest --app uikit --only UKSongDetailJourneyTests`.
final class UKSongDetailJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func openSongDetail(
        _ env: [String: String] = [:], contentSize: String? = nil
    ) throws -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_BACKGROUND_PROBE": "1",
            "FST_UIKIT_DEBUG_SONGDETAIL": "fixture-pulse",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ]
        environment.merge(env) { $1 }
        let app = FestivalApp.makeApp(environment)
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        let hero = app.descendants(matching: .any)["fst.song-detail.hero-title"]
        try XCTSkipUnless(
            hero.waitForExistence(timeout: FestivalApp.budget(25)), "Song Detail did not open (no debug hook in this app?)"
        )
        return app
    }

    @MainActor
    private func probeState(_ app: XCUIApplication) throws -> [String: String] {
        let probe = app.descendants(matching: .any)["fst.debug.backgroundProbe"]
        try XCTSkipUnless(probe.waitForExistence(timeout: 10), "This app has no background probe.")
        let value = (probe.value as? String) ?? ""
        return Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        })
    }

    // MARK: - Journeys

    /// Pushing a song takes its cover as the backdrop; popping returns to the carousel, which
    /// resumes without the loader or the backdrop view being rebuilt.
    @MainActor
    func testBackdropFollowsTheCoverAndTheCarouselResumes() throws {
        let app = try openSongDetail()
        let beforePush = try probeState(app)
        Thread.sleep(forTimeInterval: 1.5)
        let onSong = try probeState(app)
        XCTAssertEqual(onSong["mode"], "song", "the backdrop did not take the song's cover")
        XCTAssertNotEqual(onSong["cover"], "none")
        app.buttons["BackButton"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["fst.song-detail.hero-title"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.5)
        let back = try probeState(app)
        // The carousel returns only if the page underneath claims it: the Songs root does
        // (its list is on screen); the placeholder shown before the Songs lane merges does not.
        try XCTSkipUnless(
            app.buttons["fst.songs.row.fixture-pulse"].exists || back["mode"] == "carousel",
            "the page under Song Detail does not register the carousel backdrop in this build"
        )
        XCTAssertEqual(back["mode"], "carousel")
        XCTAssertEqual(back["views"], beforePush["views"], "the backdrop view was rebuilt")
        let plays = (Int(back["plays"] ?? "") ?? 0) - (Int(beforePush["plays"] ?? "") ?? 0)
        XCTAssertLessThanOrEqual(plays, 2, "the carousel restarted instead of resuming")
    }

    /// Identifiers, labels and traits of the page's landmarks, and 44 pt targets.
    @MainActor
    func testPageLandmarksAndTargets() throws {
        let app = try openSongDetail()
        let hero = app.descendants(matching: .any)["fst.song-detail.hero-title"]
        XCTAssertTrue(hero.label.hasPrefix("Fixture Pulse"))
        for id in ["fst.song-detail.intensity", "fst.song-detail.card.Solo_Guitar", "fst.song-detail.card-header.Solo_Guitar"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].waitForExistence(timeout: 5), "missing \(id)")
        }
        let row = app.buttons["fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Your rank, 1st, Fixture Player 1, 99,900, Accuracy 98%")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        let paths = app.buttons["fst.song-detail.paths"]
        let window = app.windows.firstMatch.frame.size
        if #available(iOS 27.0, *), window == CGSize(width: 466, height: 678) {
            ShellUITestSupport.tapToolbarItem("fst.song-detail.paths", overflowLabels: ["Paths"], in: app)
        } else {
            XCTAssertTrue(paths.waitForExistence(timeout: 5))
            XCTAssertEqual(paths.label, "Paths")
            XCTAssertTrue(paths.isHittable)
            XCTAssertGreaterThanOrEqual(paths.frame.width, 44)
            XCTAssertGreaterThanOrEqual(paths.frame.height, 44)
            paths.tap()
        }
        XCTAssertTrue(PathsUITestSupport.element("fst.paths.display", in: app).waitForExistence(timeout: 10))
    }

    /// The meters speak their levels in row order and use the reference column pitch.
    @MainActor
    func testIntensityGridOrderAndSpacing() throws {
        let app = try openSongDetail()
        let intensity = app.descendants(matching: .any)["fst.song-detail.intensity"]
        XCTAssertTrue(intensity.waitForExistence(timeout: 5))
        let meters = intensity.descendants(matching: .any).matching(identifier: "fst.songs.difficulty-meter").allElementsBoundByIndex
        XCTAssertEqual(meters.count, 4)
        let first = try XCTUnwrap(meters.first)
        let second = try XCTUnwrap(meters.dropFirst().first)
        let last = try XCTUnwrap(meters.last)
        XCTAssertTrue(meters.allSatisfy { $0.label.hasPrefix("Difficulty ") })
        XCTAssertLessThan(first.frame.minX, second.frame.minX, "the first two meters read across the top row")
        XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 1)
        let window = app.windows.firstMatch.frame.size
        if #available(iOS 27.0, *), window == CGSize(width: 402, height: 874) {
            XCTAssertEqual(second.frame.minX - first.frame.minX, 175, accuracy: 0.34,
                           "the horizontal column gap matches the SwiftUI Intensity grid")
        } else if #available(iOS 27.0, *), window == CGSize(width: 466, height: 678) {
            XCTAssertEqual(second.frame.minX - first.frame.minX, 165, accuracy: 0.34,
                           "the Intensity columns match the folded SwiftUI rail layout")
        }
        XCTAssertEqual(last.frame.midY - first.frame.midY - first.frame.height, 12, accuracy: 1,
                       "the grid leaves the same space between meters as the SwiftUI card")
    }

    /// Compact Paths hugs its outer icons, fills the middle and keeps the modal confirmation visible.
    @MainActor
    func testCompactPathsKeepsSelectorsAndCloseReachable() throws {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765", "FST_DEBUG_ANONYMOUS": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1", "FST_UI_TEST_RESET_VISUALS": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        app.launchArguments += ["-fst.settings.pathDefaultView", "image"]
        app.launch()
        PathsUITestSupport.openPaths(in: app)
        let buttons = app.descendants(matching: .any)
        let instrument = buttons.matching(identifier: "fst.paths.instrument").firstMatch
        let difficulty = buttons.matching(identifier: "fst.paths.difficulty").firstMatch
        let view = buttons.matching(identifier: "fst.paths.display").firstMatch
        let close = buttons.matching(identifier: "fst.paths.close").firstMatch
        XCTAssertTrue(instrument.waitForExistence(timeout: 10))
        XCTAssertTrue(close.exists && close.isHittable)
        XCTAssertEqual(close.label, "Close")
        for (selector, label) in [(instrument, "Instrument"), (difficulty, "Difficulty"), (view, "View")] {
            XCTAssertTrue(selector.isHittable)
            XCTAssertEqual(selector.label, label)
            XCTAssertGreaterThanOrEqual(selector.frame.width, 44)
            XCTAssertGreaterThanOrEqual(selector.frame.height, 44)
        }
        XCTAssertEqual(instrument.value as? String, "Lead")
        XCTAssertEqual(difficulty.value as? String, "Expert")
        XCTAssertGreaterThan(view.frame.width, 48, "the symbol and chevron both have room")
        XCTAssertLessThan(instrument.frame.maxX, difficulty.frame.minX)
        XCTAssertLessThan(difficulty.frame.maxX, view.frame.minX)
        XCTAssertGreaterThan(difficulty.frame.width, instrument.frame.width + view.frame.width)
        let image = try XCTUnwrap(close.screenshot().image.cgImage)
        let pixels = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: close.frame.width))
        let blue = try XCTUnwrap(pixels.fraction(in: CGRect(origin: .zero, size: close.frame.size),
                                                  matching: ButtonFillPixels.accentBlue))
        XCTAssertGreaterThan(blue, 0.2, "the system Close button uses the modal's confirmation accent")
        XCTAssertEqual(view.value as? String, "Image")
        close.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["fst.song-detail.paths"].isHittable)
    }

    /// At the largest accessibility text size the page lays out in one column and its rows
    /// grow instead of clipping; the scoped audit finds no hit-area or clipping problems.
    @MainActor
    func testAccessibilityTextSizeGrowthAndAudit() throws {
        let app = try openSongDetail(contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let scroll = app.scrollViews["fst.song-detail.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "Song Detail did not register its page scroller")
        let hero = app.descendants(matching: .any)["fst.song-detail.hero-title"]
        XCTAssertFalse(app.descendants(matching: .any)["fst.song-detail.pinned-title"].exists)
        let row = app.buttons["fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(row.frame.height, 80, "the row did not grow at AX5")
        XCTAssertLessThanOrEqual(row.frame.maxX, app.windows.firstMatch.frame.maxX + 1)
        try app.performAccessibilityAudit(for: [.hitRegion, .textClipped, .sufficientElementDescription])

        let window = app.windows.firstMatch.frame
        if window.height > window.width {
            let bar = app.navigationBars.firstMatch.frame
            XCTAssertEqual(hero.frame.minY - bar.maxY, 16, accuracy: 2, "The stack margin, not an added inset, follows the bar")
        } else {
            XCTAssertLessThan(hero.frame.minY, 64, "Unfolded Duo has no second adjusted-inset gap above the hero")
        }
        for _ in 0..<5 where !app.descendants(matching: .any)["fst.song-detail.pinned-title"].exists {
            scroll.swipeUp(velocity: .slow)
        }
        let pinned = app.descendants(matching: .any)["fst.song-detail.pinned-title"]
        XCTAssertTrue(pinned.waitForExistence(timeout: 5), "The song identity did not pin after the hero")
        XCTAssertEqual(pinned.label, "Fixture Pulse, Synthetic Quartet · 2026")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(pinned.frame))
        try app.performAccessibilityAudit(for: [.hitRegion, .textClipped, .sufficientElementDescription])
    }
}
