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

        let display = app.segmentedControls["fst.paths.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        display.buttons["Image"].tap()
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

        display.buttons["Text"].tap()
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

        let difficulty = app.segmentedControls["fst.paths.difficulty"]
        XCTAssertTrue(difficulty.buttons["Expert"].isSelected)
        difficulty.buttons["Hard"].tap()
        for _ in 0..<40 {
            if summary.label.contains("Hard") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(summary.label, "Two synthetic Hard activations")
        difficulty.buttons["Medium"].tap()
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry"].exists)
        difficulty.buttons["Expert"].tap()
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
        let display = app.segmentedControls["fst.paths.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        XCTAssertTrue(display.buttons[changed].isSelected)
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
        let display = app.segmentedControls["fst.paths.display"]
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

    /// Probe an offscreen empty-chart action without inventing a successful score.
    ///
    /// - Throws: A stalled native scroll or missing genuinely empty Bass chart.
    @MainActor
    func testOffscreenEmptyChartActionRemainsReachable() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8775"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let first = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "#1")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let bass = app.buttons["fst.song-detail.leaderboard.Solo_Bass"]
        XCTAssertTrue(bass.waitForExistence(timeout: 15))
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(bass.isHittable, "Bass action did not start offscreen")
        }
        bass.tap()
        XCTAssertTrue(app.staticTexts["0 Bass entries"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons["fst.song-leaderboard.page-next"].waitForExistence(timeout: 10),
            "Bass full chart did not finish loading"
        )
        try await SongsUITestSupport.awaitClosedFixture(port: 8775)
        SongsUITestSupport.record(app, name: "song-detail-offscreen-bass-opened")
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

}
