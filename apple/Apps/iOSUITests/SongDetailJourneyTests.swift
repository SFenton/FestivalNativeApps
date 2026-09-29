import UIKit
import XCTest

/// Fixture-backed native journeys for Song Detail: CHOpt Paths, the Solo score preview/full chart hand-off and accessibility text-size evidence.
///
/// Migrated from the legacy `FestivalMobileUITests` monolith (Wave 3 UX-test triage). Shared
/// fixture-launch, Settings/Filter/Sort scrolling and pixel-accessibility helpers live in
/// ``SongsUITestSupport`` so this file, ``SongDetailJourneyTests`` and ``ShopJourneyTests`` can
/// each carry only their own journeys.
final class SongDetailJourneyTests: XCTestCase {
    /// Public CHOpt paths switch image/text and difficulty without stale content.
    ///
    /// - Throws: Missing selectors, unsafe zoom, stale path, hidden error or unreachable close.
    @MainActor
    func testSongPathsImageTextSwitchAndMissingDifficulty() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        SongsUITestSupport.collapseSidebarOnPad(app)
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: 2) {
            XCTAssertTrue(warning.staticTexts[
                "Karaoke is not available for path visualization yet."
            ].exists)
            warning.buttons["OK"].tap()
        }

        let display = pathsMenu("fst.paths.display", in: app)
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        choose("Image", in: display, app: app)
        let image = app.images["fst.paths.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try SongsUITestSupport.assertHeaderContrast(app.staticTexts["Paths"], in: app)
            try SongsUITestSupport.assertHeaderContrast(app.buttons["fst.paths.close"], in: app)
        }
        let fittedWidth = image.frame.width
        let zoom = app.buttons["fst.paths.zoom-in"]
        XCTAssertTrue(zoom.isHittable)
        zoom.tap()
        XCTAssertGreaterThan(image.frame.width, fittedWidth, "Zoom did not resize the path")
        SongsUITestSupport.record(app, name: "song-path-expert-image")
        zoom.tap()
        zoom.tap()
        XCTAssertFalse(zoom.isEnabled, "Zoom in did not stop at the supported scale")
        let zoomOut = app.buttons["fst.paths.zoom-out"]
        XCTAssertTrue(zoomOut.isEnabled)
        zoomOut.tap()
        XCTAssertTrue(zoom.isEnabled)

        choose("Text", in: display, app: app)
        let summary = app.staticTexts["fst.paths.text-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertEqual(summary.label, "Two synthetic Expert activations")
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "fst.paths.activation.1"
        ).firstMatch.exists)
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try SongsUITestSupport.assertHeaderContrast(summary, in: app)
        }
        SongsUITestSupport.record(app, name: "song-path-expert-text")

        let difficulty = pathsMenu("fst.paths.difficulty", in: app)
        XCTAssertTrue(menuShows("Expert", difficulty), "Difficulty: \(difficulty.label)")
        choose("Hard", in: difficulty, app: app)
        for _ in 0..<40 {
            if summary.label.contains("Hard") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(summary.label, "Two synthetic Hard activations")
        choose("Medium", in: difficulty, app: app)
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry"].exists)
        choose("Expert", in: difficulty, app: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        for _ in 0..<40 {
            if summary.label.contains("Expert") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(summary.label, "Two synthetic Expert activations")
        let instrument = app.descendants(matching: .any).matching(
            identifier: "fst.paths.instrument"
        ).firstMatch
        XCTAssertTrue(instrument.exists)
        instrument.tap()
        let bass = app.buttons["Bass"]
        XCTAssertTrue(bass.waitForExistence(timeout: 10))
        bass.tap()
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(summary.exists, "Lead content remained visible for a missing Bass path")
        instrument.tap()
        app.buttons["Lead"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        app.buttons["fst.paths.close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
    }

    /// A saved Settings path default initializes the next modal without erasing it.
    ///
    /// - Throws: A disconnected setting, unavailable modal or lost original preference.
    @MainActor
    func testSongPathsDefaultViewFollowsSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let setting = app.descendants(matching: .any).matching(
            identifier: "fst.settings.path-default-view"
        ).firstMatch
        XCTAssertTrue(setting.waitForExistence(timeout: 10))
        SongsUITestSupport.reveal(setting, in: app, scrollingUp: false)
        let original = try XCTUnwrap(setting.value as? String)
        XCTAssertTrue(
            ["Image", "Text"].contains(original),
            "Unexpected path picker value \(original); label: \(setting.label)"
        )
        let changed = original == "Image" ? "Text" : "Image"
        setting.tap()
        let option = app.buttons[changed]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        XCTAssertEqual(setting.value as? String, changed)

        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        SongsUITestSupport.collapseSidebarOnPad(app)
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: 2) {
            warning.buttons["OK"].tap()
        }
        let display = pathsMenu("fst.paths.display", in: app)
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        XCTAssertTrue(menuShows(changed, display), "View: \(display.label)")
        if changed == "Text" {
            XCTAssertTrue(app.staticTexts["fst.paths.text-summary"]
                .waitForExistence(timeout: 15))
        } else {
            XCTAssertTrue(app.images["fst.paths.image"].waitForExistence(timeout: 15))
        }
        app.buttons["fst.paths.close"].tap()

        if UIDevice.current.userInterfaceIdiom == .pad {
            let sidebar = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "sidebar")
            ).firstMatch
            XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
            sidebar.tap()
        }
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(setting, in: app, scrollingUp: false)
        setting.tap()
        app.buttons[original].tap()
        XCTAssertEqual(setting.value as? String, original)
    }

    /// Warn once per Paths opening until the explicit persistent choice survives cold launch.
    ///
    /// - Throws: Missing or low-contrast warning, ignored choice or forgotten dismissal.
    @MainActor
    func testPathUnavailableWarningCanPersistAcrossColdLaunch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_PATH_WARNING"] = "1"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let warning = app.alerts["Some Instruments Unavailable"]
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        XCTAssertTrue(warning.staticTexts[
            "Karaoke is not available for path visualization yet."
        ].exists)
        XCTAssertTrue(warning.buttons["OK"].exists)
        XCTAssertTrue(warning.buttons["Don't show again"].exists)
        XCTAssertTrue(warning.buttons["OK"].isHittable)
        XCTAssertTrue(
            warning.buttons.matching(identifier: "fst.paths.warning.dismiss")
                .allElementsBoundByIndex.contains(where: \.isHittable)
        )
        SongsUITestSupport.record(app, name: "song-path-karaoke-warning-first")
        let title = warning.staticTexts["Some Instruments Unavailable"]
        try SongsUITestSupport.assertHeaderContrast(title, in: app)
        var acceptedSystemTitleContrast = false
        try app.performAccessibilityAudit(for: .contrast) { issue in
            let attachment = XCTAttachment(
                string: "\(issue.auditType): \(issue.element?.identifier ?? "unidentified"): "
                    + "\(issue.element?.label ?? "unidentified"): "
                    + "\(String(describing: issue.element?.frame))"
            )
            attachment.name = "paths-warning-audit-node"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            // The rendered system alert title passes 4.5:1, but iOS 26.5 flags its UILabel.
            guard UIDevice.current.userInterfaceIdiom == .phone,
                  UIDevice.current.systemVersion == "26.5",
                  issue.auditType == .contrast,
                  issue.element?.identifier == "",
                  issue.element?.label == title.label,
                  !acceptedSystemTitleContrast else {
                return false
            }
            acceptedSystemTitleContrast = true
            return true
        }
        warning.buttons["OK"].tap()
        let display = pathsMenu("fst.paths.display", in: app)
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        app.buttons["fst.paths.close"].tap()

        open.tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        SongsUITestSupport.record(app, name: "song-path-karaoke-warning-next-opening")
        let permanent = try XCTUnwrap(
            warning.buttons.matching(identifier: "fst.paths.warning.dismiss")
                .allElementsBoundByIndex.first(where: \.isHittable)
        )
        permanent.tap()
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        app.buttons["fst.paths.close"].tap()

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_PATH_WARNING")
        app.launch()
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        XCTAssertFalse(warning.waitForExistence(timeout: 3))
        SongsUITestSupport.record(app, name: "song-path-karaoke-warning-suppressed-after-cold-launch")
        app.buttons["fst.paths.close"].tap()

        app.terminate()
        app.launchEnvironment["FST_UI_TEST_RESET_PATH_WARNING"] = "1"
        app.launch()
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        open.tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        warning.buttons["OK"].tap()
        app.buttons["fst.paths.close"].tap()
        app.terminate()
    }

    /// Show ten real fixture score rows, then open the independent full Solo page.
    ///
    /// - Throws: Missing native top-score rows, incorrect top parameter or hidden action.
    @MainActor
    func testSongDetailShowsTopScorePreviewAndFullChart() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        SongsUITestSupport.collapseSidebarOnPad(app)
        let viewFull = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(viewFull.waitForExistence(timeout: 15))
        let first = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "#1")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Fixture Player 1"].exists)
        let previewNonFC = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "Accuracy 98%")).firstMatch
        let previewFC = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-2"
        ).matching(NSPredicate(
            format: "label == %@", "Full combo, accuracy 98%"
        )).firstMatch
        XCTAssertTrue(previewNonFC.waitForExistence(timeout: 10))
        XCTAssertEqual(previewNonFC.label, "Accuracy 98%")
        XCTAssertTrue(previewFC.exists)
        XCTAssertEqual(previewFC.label, "Full combo, accuracy 98%")
        try SongsUITestSupport.assertScoreAccuracyAccent(previewNonFC, fullCombo: false)
        try SongsUITestSupport.assertScoreAccuracyAccent(previewFC, fullCombo: true)
        let previewScoreOne = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "99,900")).firstMatch
        let previewScoreTwo = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-2"
        ).matching(NSPredicate(format: "label == %@", "99,800")).firstMatch
        SongsUITestSupport.assertAlignedScoreColumn(
            firstScore: previewScoreOne, secondScore: previewScoreTwo,
            firstBadge: previewNonFC, secondBadge: previewFC
        )
        let previewRowThree = "fst.song-detail.preview-row.Solo_Guitar.fixture-player-3"
        let previewRowFour = "fst.song-detail.preview-row.Solo_Guitar.fixture-player-4"
        let previewScoreThree = app.staticTexts.matching(identifier: previewRowThree)
            .matching(NSPredicate(format: "label == %@", "99,700")).firstMatch
        let previewScoreFour = app.staticTexts.matching(identifier: previewRowFour)
            .matching(NSPredicate(format: "label == %@", "99,600")).firstMatch
        SongsUITestSupport.assertAlignedScoreEnds(previewScoreOne, previewScoreThree)
        SongsUITestSupport.assertAlignedScoreEnds(previewScoreOne, previewScoreFour)
        XCTAssertFalse(app.staticTexts.matching(identifier: previewRowThree)
            .matching(NSPredicate(
                format: "label CONTAINS[c] %@", "accuracy"
            )).firstMatch.exists)
        let previewFCWithoutAccuracy = app.staticTexts.matching(identifier: previewRowFour)
            .matching(NSPredicate(
                format: "label == %@", "Full combo; accuracy unavailable"
            )).firstMatch
        XCTAssertTrue(previewFCWithoutAccuracy.exists)
        let previewQuery = try await SongsUITestSupport.latestFixtureScoreQuery()
        XCTAssertEqual(previewQuery.top, 10)
        XCTAssertEqual(previewQuery.offset, 0)
        XCTAssertNil(previewQuery.leeway)
        XCTAssertFalse(app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-11"
        ).matching(NSPredicate(format: "label == %@", "#11")).firstMatch.exists)
        SongsUITestSupport.record(app, name: "song-detail-real-top-scores")
        try SongsUITestSupport.assertHeaderContrast(app.staticTexts["Fixture Player 1"], in: app)

        viewFull.tap()
        XCTAssertTrue(app.buttons["fst.song-leaderboard.page-next"].waitForExistence(timeout: 10))
        let fullQuery = try await SongsUITestSupport.latestFixtureScoreQuery(fullOnly: true)
        XCTAssertEqual(fullQuery.top, 25)
        XCTAssertEqual(fullQuery.offset, 0)
        let fullNonFC = app.staticTexts["fst.score.accuracy.fixture-player-1"]
        let fullFC = app.staticTexts["fst.score.accuracy.fixture-player-2"]
        XCTAssertTrue(fullNonFC.waitForExistence(timeout: 10))
        XCTAssertEqual(fullNonFC.label, "Accuracy 98%")
        XCTAssertTrue(fullFC.exists)
        XCTAssertEqual(fullFC.label, "Full combo, accuracy 98%")
        try SongsUITestSupport.assertScoreAccuracyAccent(fullNonFC, fullCombo: false)
        try SongsUITestSupport.assertScoreAccuracyAccent(fullFC, fullCombo: true)
        let fullRowOne = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-1").firstMatch
        let fullRowTwo = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-2").firstMatch
        let fullScoreOne = fullRowOne.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "99,900")).firstMatch
        let fullScoreTwo = fullRowTwo.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "99,800")).firstMatch
        SongsUITestSupport.assertAlignedScoreColumn(
            firstScore: fullScoreOne, secondScore: fullScoreTwo,
            firstBadge: fullNonFC, secondBadge: fullFC
        )
        let fullRowThree = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-3").firstMatch
        let fullRowFour = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-4").firstMatch
        let fullScoreThree = fullRowThree.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "99,700")).firstMatch
        let fullScoreFour = fullRowFour.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "99,600")).firstMatch
        SongsUITestSupport.assertAlignedScoreEnds(fullScoreOne, fullScoreThree)
        SongsUITestSupport.assertAlignedScoreEnds(fullScoreOne, fullScoreFour)
        XCTAssertFalse(app.staticTexts["fst.score.accuracy.fixture-player-3"].exists)
        let fullFCWithoutAccuracy = app.staticTexts["fst.score.accuracy.fixture-player-4"]
        XCTAssertTrue(fullFCWithoutAccuracy.exists)
        XCTAssertEqual(fullFCWithoutAccuracy.label, "Full combo; accuracy unavailable")
        try SongsUITestSupport.assertScoreAccuracyAccent(fullFCWithoutAccuracy, fullCombo: true)
        XCTAssertLessThanOrEqual(
            abs(fullNonFC.frame.minX - fullFCWithoutAccuracy.frame.minX), 1,
            "FC without accuracy must retain the same badge column"
        )
        SongsUITestSupport.record(app, name: "solo-fc-versus-graded-accuracy")
    }

    /// PWA parity (gaps #6-#8): big instrument card header, the full-leaderboard action
    /// under the rows, the Item Shop action in the toolbar, and the song identity
    /// pinned in the navigation bar only once the hero title scrolls under it.
    ///
    /// - Throws: A missing header, a top-placed link, a duplicated or missing title.
    @MainActor
    func testSongDetailPinnedTitleAndCardLayout() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        SongsUITestSupport.collapseSidebarOnPad(app)

        let header = app.descendants(matching: .any)
            .matching(identifier: "fst.song-detail.card-header.Solo_Guitar").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        XCTAssertTrue(header.label.hasPrefix("Lead"), header.label)
        XCTAssertTrue(
            header.label.contains("26 entries"),
            "Total entries must be the header subtitle: \(header.label)"
        )
        XCTAssertTrue(header.isHittable)
        let shop = app.descendants(matching: .any)
            .matching(identifier: "fst.song-detail.shop").firstMatch
        XCTAssertTrue(shop.waitForExistence(timeout: 10), "Item Shop action missing")
        XCTAssertTrue(shop.isHittable)
        // The pulsing toolbar action carries the status; the hero chip is gone.
        XCTAssertTrue(shop.label.contains("New in the Item Shop"), shop.label)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "fst.song-detail.shop-badge").firstMatch.exists)

        let pinned = app.descendants(matching: .any)
            .matching(identifier: "fst.song-detail.pinned-title").firstMatch
        let pinnedShown = NSPredicate(format: "exists == true AND label == %@", "Fixture Pulse")
        XCTAssertFalse(
            pinned.exists && pinned.label == "Fixture Pulse" && pinned.isHittable,
            "Pinned title announced while the hero title is visible"
        )
        SongsUITestSupport.record(app, name: "song-detail-pinned-title-hidden")

        let tenth = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-10"
        ).matching(NSPredicate(format: "label == %@", "#10")).firstMatch
        XCTAssertTrue(tenth.waitForExistence(timeout: 15))
        app.swipeUp()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [expectation(for: pinnedShown, evaluatedWith: pinned)], timeout: 10
            ),
            .completed, "Song title did not pin to the navigation bar"
        )
        XCTAssertLessThan(
            pinned.frame.minY, app.windows.firstMatch.frame.height * 0.2,
            "Pinned title is not in the navigation bar"
        )
        SongsUITestSupport.record(app, name: "song-detail-pinned-title-shown")

        let viewFull = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(viewFull.waitForExistence(timeout: 10))
        XCTAssertEqual(viewFull.label, "View full Lead leaderboard")
        XCTAssertGreaterThan(
            viewFull.frame.minY, tenth.frame.maxY,
            "View full leaderboard must sit under the ten preview rows"
        )

        app.swipeDown()
        app.swipeDown()
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [expectation(
                    for: NSPredicate(format: "hittable == false OR exists == false"),
                    evaluatedWith: pinned
                )], timeout: 10
            ),
            .completed, "Pinned title stayed after the hero returned"
        )
    }

    /// Probe system accessibility scrolling to the last score in a populated preview.
    ///
    /// - Throws: A stalled offscreen score target or missing painted preview row.
    @MainActor
    func testOffscreenDetailScoreRemainsReachable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8774"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let first = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "#1")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let tenth = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-10"
        ).matching(NSPredicate(format: "label == %@", "#10")).firstMatch
        XCTAssertTrue(tenth.waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(tenth.isHittable, "The last score did not start offscreen")
        }
        tenth.tap()
        XCTAssertTrue(tenth.isHittable, "Offscreen score could not be brought into view")
        SongsUITestSupport.record(app, name: "song-detail-offscreen-score-revealed")
    }

    /// A chart with no scores says so in its header and offers no View full action
    /// (operator batch 3; web shows View All only with rows), without inventing a score.
    ///
    /// - Throws: A missing empty header, a leftover View full action or an unreachable card.
    @MainActor
    func testEmptyChartShowsNoScoresHeaderWithoutViewFull() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 15), "Lead has rows and keeps View full")
        let bassHeader = app.descendants(matching: .any)
            .matching(identifier: "fst.song-detail.card-header.Solo_Bass").firstMatch
        XCTAssertTrue(bassHeader.waitForExistence(timeout: 15))
        for _ in 0..<6 where !bassHeader.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(bassHeader.isHittable)
        let emptyHeader = NSPredicate(format: "label CONTAINS %@", "No scores recorded yet")
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [expectation(for: emptyHeader, evaluatedWith: bassHeader)], timeout: 10
            ),
            .completed, "Empty Bass header: \(bassHeader.label)"
        )
        XCTAssertFalse(
            app.buttons["fst.song-detail.leaderboard.Solo_Bass"].exists,
            "An empty chart must not offer View full leaderboard"
        )
        SongsUITestSupport.record(app, name: "song-detail-empty-bass-header")
    }

    /// Operator rule: changing the score-history sort scrolls back to the top, and the
    /// sort applies live (no Apply button).
    ///
    /// - Throws: A missing history entry point, a sort that needs Apply, or a list that
    ///   stays scrolled after re-sorting.
    @MainActor
    func testHistorySortAppliesLiveAndScrollsToTop() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
        ])
        // Large text makes two history rows taller than the screen, so there is
        // something to scroll away from.
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let history = app.buttons["fst.song-detail.history.Solo_Guitar"]
        XCTAssertTrue(history.waitForExistence(timeout: 15))
        for _ in 0..<20 where !history.isHittable {
            app.swipeUp()
        }
        history.tap()
        let firstRow = app.descendants(matching: .any)
            .matching(identifier: "fst.history.row.0").firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15))
        for _ in 0..<4 { app.swipeUp() }
        let scrolledAway = !firstRow.isHittable
        XCTAssertTrue(scrolledAway, "Precondition: the first history row should scroll away")
        let open = app.buttons["fst.history.sort.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertFalse(app.buttons["fst.history.sort.apply"].exists, "Sort must apply live")
        let date = app.buttons.matching(NSPredicate(format: "label == %@", "Date")).firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 10))
        date.tap()
        app.buttons["fst.history.sort.done"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        let atTop = NSPredicate(format: "hittable == true")
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation(for: atTop, evaluatedWith: firstRow)], timeout: 10),
            .completed, "Re-sorting did not scroll back to the top (scrolled away: \(scrolledAway))"
        )
        SongsUITestSupport.record(app, name: "history-sort-scrolled-to-top")
    }

    /// Traverse Songs, Detail and page two, then verify landscape layout survives.
    ///
    /// - Throws: An XCTest failure for missing accessible actions or screen state.
    @MainActor
    func testSongsDetailScoresInPortraitAndLandscape() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()

        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Fixture song row did not load")
        SongsUITestSupport.record(app, name: "songs-portrait")
        row.tap()

        XCTAssertTrue(app.staticTexts["Intensity"].waitForExistence(timeout: 10))
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10), "Lead leaderboard action is missing")
        SongsUITestSupport.record(app, name: "song-detail-portrait")
        lead.tap()

        let next = app.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Pagination is not reachable")
        SongsUITestSupport.collapseSidebarOnPad(app)
        XCTAssertTrue(app.staticTexts["1 / 2"].exists)
        let first = app.buttons["fst.song-leaderboard.page-first"]
        XCTAssertFalse(first.isEnabled)
        XCTAssertTrue(next.isEnabled)
        try app.performAccessibilityAudit(for: .all) { issue in
            XCTFail(
                "Solo page audit: \(issue.compactDescription); "
                    + "element=\(issue.element?.identifier ?? "unidentified"), "
                    + "label=\(issue.element?.label ?? "unidentified"), "
                    + "frame=\(String(describing: issue.element?.frame))"
            )
            return false
        }
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(first.isEnabled)
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.song-leaderboard.row.fixture-player-26")
                .firstMatch.waitForExistence(timeout: 10)
        )
        try app.performAccessibilityAudit(for: .all)
        SongsUITestSupport.record(app, name: "song-leaderboard-page2-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(
            app.windows.firstMatch.frame.width,
            app.windows.firstMatch.frame.height,
            "App window failed to reflow to landscape"
        )
        let leaderboardLists = [app.collectionViews.firstMatch, app.tables.firstMatch]
        let listWidth = leaderboardLists.filter(\.exists).map { $0.frame.width }.max() ?? 0
        XCTAssertGreaterThan(
            listWidth,
            app.windows.firstMatch.frame.width * 0.6,
            "The actual score list did not expand in landscape"
        )
        SongsUITestSupport.record(app, name: "song-leaderboard-page2-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// Keep solo rows and pagination reachable at the largest native text size.
    ///
    /// - Throws: Missing score text or a page action outside the visible viewport.
    @MainActor
    func testSoloScoresAtLargestTextSize() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        lead.tap()
        SongsUITestSupport.collapseSidebarOnPad(app)
        let next = app.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let accuracy = SongsUITestSupport.revealSoloAccuracy("fixture-player-1", app: app)
        SongsUITestSupport.assertWholeSoloScore("fixture-player-1", rank: 1, score: 99_900, app: app)
        SongsUITestSupport.record(app, name: "solo-largest-text-page1")
        XCTAssertTrue(accuracy.isHittable)
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(app.buttons["fst.song-leaderboard.page-first"].isEnabled)
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        let lastAccuracy = SongsUITestSupport.revealSoloAccuracy(
            "fixture-player-26", fullCombo: true, app: app
        )
        SongsUITestSupport.assertWholeSoloScore("fixture-player-26", rank: 26, score: 97_400, app: app)
        XCTAssertTrue(lastAccuracy.isHittable)
        XCTAssertTrue(app.buttons["fst.song-leaderboard.page-first"].isEnabled)
        XCTAssertFalse(next.isEnabled)
        SongsUITestSupport.record(app, name: "solo-largest-text-page2")
    }


    // MARK: - Paths menu helpers

    /// The Paths sheet's bottom-row menu picker with this identifier.
    ///
    /// - Parameters:
    ///   - identifier: `fst.paths.instrument` / `.difficulty` / `.display`.
    ///   - app: Running app.
    /// - Returns: The picker element (a menu button).
    @MainActor
    private func pathsMenu(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Whether a menu picker currently shows this option.
    ///
    /// - Parameters:
    ///   - option: Option title.
    ///   - menu: Menu picker element.
    /// - Returns: True when its label or value names the option.
    @MainActor
    private func menuShows(_ option: String, _ menu: XCUIElement) -> Bool {
        menu.label.contains(option) || ((menu.value as? String)?.contains(option) ?? false)
    }

    /// Open a menu picker and pick an option.
    ///
    /// - Parameters:
    ///   - option: Option title to tap.
    ///   - menu: Menu picker element.
    ///   - app: Running app.
    @MainActor
    private func choose(_ option: String, in menu: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let item = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", option, menu.identifier)
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Menu option \(option) missing")
        item.tap()
    }
}
