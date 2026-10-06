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
        assertPathImageCentered(image, in: app, "at fit zoom")
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
        // Zoomed wider than the sheet, the path still pans sideways; zooming back to
        // fit re-centres it rather than keeping the panned offset (issue #87).
        let zoomedMinX = image.frame.minX
        image.swipeLeft()
        XCTAssertLessThan(image.frame.minX, zoomedMinX, "Zoomed path did not scroll horizontally")
        while zoomOut.isEnabled { zoomOut.tap() }
        assertPathImageCentered(image, in: app, "after zooming back out")

        choose("Text", in: display, app: app)
        // Web mobile table: no path summary or max score above the activation cards.
        func pathText(_ difficulty: String, _ instrument: String = "Solo_Guitar") -> XCUIElement {
            app.descendants(matching: .any)
                .matching(identifier: "fst.paths.text.\(instrument).\(difficulty)").firstMatch
        }
        let summary = pathText("expert")
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["fst.paths.text-summary"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "fst.paths.activation.1"
        ).firstMatch.exists)
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try SongsUITestSupport.assertHeaderContrast(app.staticTexts["Paths"], in: app)
        }
        SongsUITestSupport.record(app, name: "song-path-expert-text")

        let difficulty = pathsMenu("fst.paths.difficulty", in: app)
        XCTAssertTrue(menuShows("Expert", difficulty), "Difficulty: \(difficulty.label)")
        choose("Hard", in: difficulty, app: app)
        XCTAssertTrue(pathText("hard").waitForExistence(timeout: 15))
        choose("Medium", in: difficulty, app: app)
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry"].exists)
        choose("Expert", in: difficulty, app: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        // The instrument is a native menu picker like Difficulty and View (issue #88).
        let instrument = pathsMenu("fst.paths.instrument", in: app)
        XCTAssertTrue(instrument.exists)
        XCTAssertEqual(instrument.label, "Instrument")
        XCTAssertTrue(menuShows("Lead", instrument), "Instrument: \(String(describing: instrument.value))")
        XCTAssertGreaterThanOrEqual(instrument.frame.height, 44)
        choose("Bass", in: instrument, app: app)
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(summary.exists, "Lead content remained visible for a missing Bass path")
        XCTAssertTrue(menuShows("Bass", instrument), "Instrument: \(String(describing: instrument.value))")
        choose("Lead", in: instrument, app: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        // Back to the image after instrument and view switches, then a difficulty switch.
        choose("Image", in: display, app: app)
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        assertPathImageCentered(image, in: app, "after instrument and view switches")
        choose("Hard", in: difficulty, app: app)
        XCTAssertTrue(menuShows("Hard", difficulty), "Difficulty: \(difficulty.label)")
        let hardImage = app.images.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "fst.paths.image", "Hard"
        )).firstMatch
        XCTAssertTrue(hardImage.waitForExistence(timeout: 15))
        assertPathImageCentered(hardImage, in: app, "after a difficulty switch")
        app.buttons["fst.paths.close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
    }

    /// Assert the fitted path image has equal left and right margins in its scroll area (issue #87).
    ///
    /// The viewport, not the window, is the reference: on iPhone it spans the sheet
    /// inside its 16 pt margins, while on iPhone Duo the sheet can leave a trailing
    /// column for the toolbar and status bar.
    ///
    /// - Parameters:
    ///   - image: The `fst.paths.image` element, at a zoom no wider than the sheet.
    ///   - app: The running app showing the Paths sheet.
    ///   - context: When the check ran, for the failure message.
    private func assertPathImageCentered(_ image: XCUIElement, in app: XCUIApplication, _ context: String) {
        let viewport = app.descendants(matching: .any)
            .matching(identifier: "fst.paths.image-viewport").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 10), "No path image viewport \(context)")
        XCTAssertEqual(viewport.elementType, .scrollView, "Viewport ID must name the scroll view")
        XCTAssertEqual(
            image.frame.midX, viewport.frame.midX, accuracy: 1,
            "Path image off centre \(context): \(image.frame) in \(viewport.frame)"
        )
    }

    /// Swiping the Paths sheet down closes it in text and image modes (issue #96), while
    /// pinch zoom on the image still works (HIG sheets: "Support swiping vertically to
    /// dismiss").
    ///
    /// - Throws: A sheet that bounces back, or a pinch the sheet swallows.
    @MainActor
    func testSongPathsSwipeDownDismisses() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        let display = pathsMenu("fst.paths.display", in: app)

        /// Open the sheet on one view, past the optional Karaoke notice.
        func openPaths(_ view: String) {
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            open.tap()
            let warning = app.alerts["Some Instruments Unavailable"]
            if warning.waitForExistence(timeout: 2) { warning.buttons["OK"].tap() }
            XCTAssertTrue(display.waitForExistence(timeout: 10))
            if !menuShows(view, display) { choose(view, in: display, app: app) }
        }

        /// Drag from an element's upper area to the bottom of the window and expect the
        /// sheet to close.
        func swipeDismiss(from element: XCUIElement, _ context: String) {
            let window = app.windows.firstMatch
            let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            XCTAssertTrue(display.waitForNonExistence(timeout: 10), "Paths sheet bounced back \(context)")
            XCTAssertTrue(open.waitForExistence(timeout: 10))
        }

        openPaths("Text")
        let text = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.paths.text.")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15))
        swipeDismiss(from: text, "in text mode")

        openPaths("Image")
        let image = app.images["fst.paths.image"]
        let viewport = app.descendants(matching: .any)
            .matching(identifier: "fst.paths.image-viewport").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        let fittedWidth = image.frame.width
        // The viewport's centre lies on the fitted image, where the magnify gesture is.
        viewport.pinch(withScale: 2, velocity: 2)
        XCTAssertGreaterThan(image.frame.width, fittedWidth, "Pinch did not zoom the path")
        XCTAssertTrue(display.exists, "Pinching closed the Paths sheet")
        swipeDismiss(from: app.navigationBars.staticTexts["Paths"], "from the title bar")

        openPaths("Image")
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        swipeDismiss(from: viewport, "with the image at its top edge")
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
        // Inline accordion: the header speaks "<choice>, Collapsed|Expanded" and expands
        // in place; options stay on Settings and mark the current one Selected.
        let collapsedValue = try XCTUnwrap(setting.value as? String)
        let original = try XCTUnwrap(collapsedValue.components(separatedBy: ", ").first)
        XCTAssertTrue(
            ["Image", "Text"].contains(original) && collapsedValue.hasSuffix(", Collapsed"),
            "Unexpected path setting value \(collapsedValue); label: \(setting.label)"
        )
        let changed = original == "Image" ? "Text" : "Image"
        setting.tap()
        XCTAssertEqual(setting.value as? String, "\(original), Expanded")
        let current = app.buttons["fst.settings.path-default-view.\(original.lowercased())"]
        XCTAssertTrue(current.waitForExistence(timeout: 10))
        XCTAssertTrue(current.isSelected)
        let option = app.buttons["fst.settings.path-default-view.\(changed.lowercased())"]
        XCTAssertFalse(option.isSelected)
        option.tap()
        XCTAssertEqual(setting.value as? String, "\(changed), Expanded")
        XCTAssertTrue(option.isSelected)
        XCTAssertTrue(app.navigationBars["Settings"].exists, "Choosing must not navigate away")

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
            XCTAssertTrue(app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.paths.text."))
                .firstMatch.waitForExistence(timeout: 15))
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
        if (setting.value as? String)?.hasSuffix(", Collapsed") == true { setting.tap() }
        app.buttons["fst.settings.path-default-view.\(original.lowercased())"].tap()
        XCTAssertEqual(setting.value as? String, "\(original), Expanded")
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
        let first = previewText("fixture-player-1", "#1", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Fixture Player 1"].exists)
        let previewNonFC = previewText("fixture-player-1", "Accuracy 98%", in: app)
        let previewFC = previewText("fixture-player-2", "Full combo, accuracy 98%", in: app)
        XCTAssertTrue(previewNonFC.waitForExistence(timeout: 10))
        XCTAssertEqual(previewNonFC.label, "Accuracy 98%")
        XCTAssertTrue(previewFC.exists)
        XCTAssertEqual(previewFC.label, "Full combo, accuracy 98%")
        try SongsUITestSupport.assertScoreAccuracyAccent(previewNonFC, fullCombo: false)
        try SongsUITestSupport.assertScoreAccuracyAccent(previewFC, fullCombo: true)
        let previewScoreOne = previewText("fixture-player-1", "99,900", in: app)
        let previewScoreTwo = previewText("fixture-player-2", "99,800", in: app)
        SongsUITestSupport.assertAlignedScoreColumn(
            firstScore: previewScoreOne, secondScore: previewScoreTwo,
            firstBadge: previewNonFC, secondBadge: previewFC
        )
        let previewScoreThree = previewText("fixture-player-3", "99,700", in: app)
        let previewScoreFour = previewText("fixture-player-4", "99,600", in: app)
        SongsUITestSupport.assertAlignedScoreEnds(previewScoreOne, previewScoreThree)
        SongsUITestSupport.assertAlignedScoreEnds(previewScoreOne, previewScoreFour)
        XCTAssertFalse(previewRow("fixture-player-3", in: app)
            .descendants(matching: .staticText)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "accuracy")).firstMatch.exists)
        let previewFCWithoutAccuracy = previewText(
            "fixture-player-4", "Full combo; accuracy unavailable", in: app
        )
        XCTAssertTrue(previewFCWithoutAccuracy.exists)
        let previewQuery = try await SongsUITestSupport.latestFixtureScoreQuery()
        XCTAssertEqual(previewQuery.top, 10)
        XCTAssertEqual(previewQuery.offset, 0)
        XCTAssertNil(previewQuery.leeway)
        XCTAssertFalse(previewRow("fixture-player-11", in: app).exists)
        SongsUITestSupport.record(app, name: "song-detail-real-top-scores")
        try SongsUITestSupport.assertHeaderContrast(app.staticTexts["Fixture Player 1"], in: app)

        // Issue #33: a top-ten row is one button that opens that player's profile.
        let secondRow = previewRow("fixture-player-2", in: app)
        XCTAssertEqual(secondRow.elementType, .button)
        XCTAssertEqual(
            secondRow.label, "#2, Fixture Player 2, 99,800, Full combo, accuracy 98%"
        )
        secondRow.tap()
        XCTAssertTrue(
            SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: 10),
            "Row did not open the profile"
        )
        SongsUITestSupport.assertPlayerTitle("Fixture Player 2", in: app)
        SongsUITestSupport.record(app, name: "song-detail-preview-row-opens-profile")
        app.buttons["BackButton"].tap()
        XCTAssertTrue(viewFull.waitForExistence(timeout: 10))

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

        let tenth = previewText("fixture-player-10", "#10", in: app)
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

    /// Probe system accessibility scrolling to the last score in a populated preview,
    /// then confirm the row is a button that opens another page (issue #33).
    ///
    /// - Throws: A stalled offscreen score target, missing preview row or profile.
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
        let first = previewText("fixture-player-1", "#1", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let tenthRow = previewRow("fixture-player-10", in: app)
        XCTAssertTrue(tenthRow.waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(tenthRow.isHittable, "The last score did not start offscreen")
        }
        // Each row is one button (issue #33): VoiceOver hears it as a button, and
        // activating the offscreen row scrolls it into view and opens the profile.
        XCTAssertEqual(
            tenthRow.label, "#10, Fixture Player 10, 99,000, Full combo, accuracy 98%"
        )
        // This listener closes after its first score read, so only the push itself
        // is asserted here; the profile content is covered on the 8765 service.
        tenthRow.tap()
        XCTAssertTrue(
            app.buttons["BackButton"].waitForExistence(timeout: 10) && !tenthRow.isHittable,
            "Activating the revealed preview row did not open another page"
        )
        app.buttons["BackButton"].tap()
        XCTAssertTrue(
            tenthRow.waitForExistence(timeout: 10) && tenthRow.isHittable,
            "Back did not return to the revealed preview row"
        )
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

    /// Band leaderboard previews (issue #34): Duos, Trios and Quads follow the solo
    /// cards; each band row is one drill-down button to Band Detail, the selected
    /// player's band outside the top rows is appended, an empty size explains itself
    /// and View full opens that size's song band leaderboard.
    ///
    /// Needs a fixture service started from this revision (the shared `:8765`
    /// listener may predate the `/bands/all` route):
    ///
    ///     python3 tools/mock_service.py --port 18934
    ///
    /// - Throws: A missing section, row, appended band or destination.
    @MainActor
    func testSongBandPreviewsLinkToBandsAndFullBandLeaderboard() throws {
        continueAfterFailure = false
        let origin = "http://127.0.0.1:18934"
        let probe = expectation(description: "band fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: URL(string: "\(origin)/api/leaderboard/fixture-pulse/bands/all")!) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --port 18934` from this revision")
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_API_BASE_URL": origin,
        ])
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        func any(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        XCTAssertTrue(any("fst.song-detail.intensity").waitForExistence(timeout: 20))
        let first = app.buttons["fst.song-detail.band-row.Band_Duets.0"]
        for _ in 0..<12 where !(first.exists && first.isHittable) { app.swipeUp() }
        XCTAssertTrue(first.isHittable, "No Duos band preview row")
        XCTAssertEqual(
            first.label,
            "Rank 1, Band 1 Member A + Band 1 Member B, score 94,500, 5 stars, full combo, accuracy 96.5%"
        )
        let selected = app.buttons["fst.song-detail.band-selected.Band_Duets"]
        XCTAssertTrue(selected.exists, "The selected player's rank-29 band was not appended")
        XCTAssertTrue(selected.label.hasPrefix("Your band, Rank 29, "), selected.label)
        let viewFull = app.buttons["fst.song-detail.band-leaderboard.Band_Duets"]
        for _ in 0..<4 where !viewFull.isHittable { app.swipeUp() }
        XCTAssertEqual(viewFull.label, "View full Duos leaderboard")
        if UIDevice.current.userInterfaceIdiom == .phone {
            // Text scrolled under a bar's scroll-edge fade is intentionally dimmed. The
            // auditor also flags wrapped text on translucent glass cards that renders
            // well above 4.5:1, so measure the composited pixels instead for those.
            let barBottom = app.navigationBars.firstMatch.frame.maxY
            let tabTop = app.tabBars.firstMatch.exists
                ? app.tabBars.firstMatch.frame.minY : app.windows.firstMatch.frame.maxY
            try app.performAccessibilityAudit(for: .all) { issue in
                // The shared toolbar (profile avatar) and text under its scroll-edge
                // fade are outside this feature and covered by their own journeys.
                if let frame = issue.element?.frame, frame.minY < barBottom { return true }
                if issue.auditType == .contrast, let element = issue.element {
                    let frame = element.frame
                    if frame.maxY > tabTop { return true }
                    try SongsUITestSupport.assertHeaderContrast(element, in: app)
                    return true
                }
                XCTFail(
                    "Band preview audit: \(issue.compactDescription); "
                        + "element=\(issue.element?.identifier ?? "unidentified"), "
                        + "label=\(issue.element?.label ?? "unidentified"), "
                        + "frame=\(String(describing: issue.element?.frame))"
                )
                return false
            }
        }
        SongsUITestSupport.record(app, name: "song-detail-band-previews")

        viewFull.tap()
        XCTAssertTrue(
            any("fst.song-band-leaderboard.band-type-menu").waitForExistence(timeout: 15),
            "View full did not open the song band leaderboard"
        )
        app.buttons["BackButton"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        for _ in 0..<4 where !first.isHittable { app.swipeDown() }
        first.tap()
        XCTAssertTrue(
            app.buttons["BackButton"].waitForExistence(timeout: 10) && !first.isHittable,
            "A band preview row did not open Band Detail"
        )
        app.buttons["BackButton"].tap()

        let quads = any("fst.song-detail.band-empty.Band_Quad")
        for _ in 0..<8 where !(quads.exists && quads.isHittable) { app.swipeUp() }
        XCTAssertTrue(quads.exists, "Quads has no rows and must show its empty state")
        XCTAssertFalse(app.buttons["fst.song-detail.band-leaderboard.Band_Quad"].exists)
    }

    /// Selected-row rule (issue #307): the selected player's band appended after the
    /// Duos preview jumps to its page of the full band board (rank 29 → page 2) with
    /// the row highlighted and scrolled into view, like the solo spotlight row. The
    /// board's pinned band footer then follows the Solo footer: "Open band" while the
    /// row is on screen, "Jump to your band's position" from another page.
    ///
    /// Reaches the Duos section through Quick Links rather than swiping, so the
    /// journey never drags Song Detail (repeated drags there can trip the known
    /// main-thread render loop). Needs `python3 tools/mock_service.py --port 18934`.
    ///
    /// - Throws: A missing row, footer, label or destination.
    @MainActor
    func testSelectedBandRowAndFooterJumpOrOpenLikeTheSoloSpotlight() throws {
        continueAfterFailure = false
        let origin = "http://127.0.0.1:18934"
        let probe = expectation(description: "band fixture probe")
        var reachable = false
        let board = "\(origin)/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=25&accountId=fixture-player-1"
        URLSession.shared.dataTask(with: URL(string: board)!) { data, response, _ in
            // A listener from an older revision has no rank-29 selected band.
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
                && data.map { String(decoding: $0, as: UTF8.self).contains("\"selectedPlayerEntry\":{") } == true
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --port 18934` from this revision")
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_API_BASE_URL": origin,
        ])
        app.launch()
        func any(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        func waitHittable(_ element: XCUIElement, _ message: String) {
            expectation(for: NSPredicate(format: "exists == true AND isHittable == true"), evaluatedWith: element)
            waitForExpectations(timeout: 15) { error in
                if error != nil { XCTFail(message) }
            }
        }
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        XCTAssertTrue(any("fst.song-detail.intensity").waitForExistence(timeout: 20))
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        quickLinks.tap()
        let duos = app.buttons["fst.quick-links.item.band-Band_Duets"]
        XCTAssertTrue(duos.waitForExistence(timeout: 10), "Quick Links has no Duos section")
        duos.tap()

        // Song Detail: the appended selected band names its destination.
        let selected = app.buttons["fst.song-detail.band-selected.Band_Duets"]
        waitHittable(selected, "Quick Links did not bring the appended Duos band into view")
        XCTAssertTrue(selected.label.hasPrefix("Your band, Rank 29, "), selected.label)
        selected.tap()

        // Full board, page 2: the band's row is revealed and highlighted ("Your band").
        let focused = app.buttons["fst.song-band-leaderboard.row.fixture-band-fixture-player-1:29"]
        waitHittable(focused, "The selected band row did not open the full board on its row")
        XCTAssertTrue(any("fst.song-band-leaderboard.band-type-menu").exists)
        XCTAssertTrue(focused.label.hasPrefix("Your band, Rank 29, "), focused.label)
        SongsUITestSupport.record(app, name: "song-band-leaderboard-focused")

        // The row is on screen, so the pinned footer opens the band.
        let open = app.buttons["fst.song-band-leaderboard.spotlight-open"]
        waitHittable(open, "The band footer does not offer Open band while its row is visible")
        XCTAssertEqual(open.label, "Your band's rank, 29th. Open band.")

        // From page 1 the same footer jumps back to the band's page and row.
        let firstPage = app.buttons["fst.song-band-leaderboard.page-first"]
        waitHittable(firstPage, "No first-page pager button")
        firstPage.tap()
        let jump = app.buttons["fst.song-band-leaderboard.spotlight-jump"]
        waitHittable(jump, "The band footer does not offer a jump from page 1")
        XCTAssertEqual(jump.label, "Your band's rank, 29th. Jump to your band's position.")
        XCTAssertFalse(focused.exists, "Page 1 must not list rank 29")
        SongsUITestSupport.record(app, name: "song-band-leaderboard-footer-jump")
        jump.tap()
        waitHittable(focused, "The band footer did not jump to its row")
        waitHittable(open, "After the jump the footer must open the band")

        // Open band leaves the board for Band Detail.
        open.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: open)
        waitForExpectations(timeout: 15) { error in
            if error != nil { XCTFail("Open band did not leave the full band board") }
        }
        XCTAssertTrue(app.buttons["BackButton"].waitForExistence(timeout: 10))
    }

    /// Score history lives on the song page (operator batch 6.39): with a selected
    /// player the Score History section appears after Intensity with the shared
    /// instrument selector, the chart and the best scores; there is no per-card history
    /// link and no separate page.
    ///
    /// - Throws: A missing section, selector, chart or row, or a navigation away.
    @MainActor
    func testScoreHistoryLivesOnTheSongPage() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
        ])
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        func any(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        XCTAssertTrue(any("fst.song-detail.intensity").waitForExistence(timeout: 20))
        let chart = any("fst.song-detail.history.chart")
        for _ in 0..<6 where !chart.exists { app.swipeUp() }
        XCTAssertTrue(chart.waitForExistence(timeout: 10), "No Score History chart on the song page")
        let selector = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fst.song-detail.history.instrument.")
        ).firstMatch
        XCTAssertTrue(selector.exists, "The Score History instrument selector is missing")
        XCTAssertTrue(any("fst.song-detail.history.row.0").exists, "No best-score row")
        XCTAssertFalse(app.buttons["fst.song-detail.history.Solo_Guitar"].exists, "The old per-card history link is back")
        XCTAssertTrue(any("fst.song-detail.intensity").exists, "Score history navigated away from the song page")
        SongsUITestSupport.record(app, name: "song-detail-score-history")
    }

    /// Switching the Score History instrument (issue #31) swaps the graph inside a card of
    /// one size: Lead pages and Bass fits one page, yet the best-scores list under the card
    /// does not move, and the space kept for the pager is not exposed to VoiceOver.
    /// Needs `tools/mock_service.py --port 18831` (its `fixture-history-multi` account).
    ///
    /// - Throws: A missing section, a swap that never lands or a card that resizes.
    @MainActor
    func testScoreHistoryInstrumentSwitchKeepsTheCardSize() throws {
        try assertScoreHistorySwitchKeepsTheCardSize(reduceMotion: false)
    }

    /// The same switch with the app's Reduce Motion setting on: the swap is instant and the
    /// card still keeps its size (issue #31).
    ///
    /// - Throws: A missing section, a swap that never lands or a card that resizes.
    @MainActor
    func testScoreHistoryInstrumentSwitchUnderReduceMotion() throws {
        try assertScoreHistorySwitchKeepsTheCardSize(reduceMotion: true)
    }

    /// Open `fixture-pulse` as `fixture-history-multi`, then switch Lead → Bass → Lead.
    ///
    /// - Parameter reduceMotion: Launch with the app's Reduce Motion setting on.
    /// - Throws: An XCTest failure for a missing element, swap or a moved list.
    @MainActor
    private func assertScoreHistorySwitchKeepsTheCardSize(reduceMotion: Bool) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_PROFILE": "fixture-history-multi:Multi History",
            "FST_API_BASE_URL": "http://127.0.0.1:18831",
        ])
        app.launchArguments += ["-fst.accessibility.reduceMotion", reduceMotion ? "YES" : "NO"]
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        func any(_ identifier: String) -> XCUIElement {
            app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        }
        XCTAssertTrue(any("fst.song-detail.intensity").waitForExistence(timeout: 20))
        let chart = any("fst.song-detail.history.chart")
        for _ in 0..<6 where !chart.exists { app.swipeUp() }
        XCTAssertTrue(chart.waitForExistence(timeout: 10), "No Score History chart (is the 18831 fixture running?)")
        let row = any("fst.song-detail.history.row.0")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(chart.label.hasPrefix("Lead"), chart.label)
        XCTAssertTrue(app.buttons["Back one page"].exists, "Lead's eight scores should page")
        let listTop = row.frame.minY

        func choose(_ instrument: String, label: String) {
            app.buttons["fst.song-detail.history.instrument.\(instrument)"].tap()
            let landed = expectation(for: NSPredicate(format: "label BEGINSWITH %@", label), evaluatedWith: chart)
            wait(for: [landed], timeout: 5)
            XCTAssertEqual(row.frame.minY, listTop, accuracy: 0.5, "The Score History card changed size")
        }
        choose("Solo_Bass", label: "Bass")
        XCTAssertFalse(app.buttons["Back one page"].exists, "The reserved pager space is exposed for Bass")
        SongsUITestSupport.record(app, name: reduceMotion ? "song-detail-history-switch-reduced" : "song-detail-history-switch")
        choose("Solo_Guitar", label: "Lead")
        XCTAssertTrue(app.buttons["Back one page"].exists, "Lead lost its pager")
    }

    /// Page a song leaderboard and verify the song header stays while only the rows
    /// reload (issue #316; web `SongInfoHeader` sits outside its LoadGate).
    ///
    /// - Throws: An XCTest failure when the header leaves with the rows.
    @MainActor
    func testSoloLeaderboardHeaderStaysWhilePaging() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()

        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Fixture song row did not load")
        row.tap()
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10), "Lead leaderboard action is missing")
        lead.tap()

        let next = app.buttons["fst.song-leaderboard.page-next"]
        let previous = app.buttons["fst.song-leaderboard.page-previous"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Pagination is not reachable")
        SongsUITestSupport.collapseSidebarOnPad(app)
        let header = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.header").firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), "The song header is missing on page 1")
        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.song-leaderboard.row."))
            .firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "Page 1 rows did not load")

        next.tap()
        XCTAssertTrue(header.exists, "The song header left with the rows on the next page")
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.song-leaderboard.row.fixture-player-26")
                .firstMatch.waitForExistence(timeout: 10),
            "Page 2 rows did not load"
        )
        XCTAssertTrue(header.exists, "The song header is missing on page 2")

        previous.tap()
        XCTAssertTrue(header.exists, "The song header left with the rows on the previous page")
        XCTAssertTrue(app.staticTexts["1 / 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "Page 1 rows did not return")
        XCTAssertTrue(header.exists, "The song header is missing after paging back")
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
        try auditSoloPage(app, pagerTop: first.frame.minY)
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(first.isEnabled)
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.song-leaderboard.row.fixture-player-26")
                .firstMatch.waitForExistence(timeout: 10)
        )
        try auditSoloPage(app, pagerTop: first.frame.minY)
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


    // MARK: - Solo page audit

    /// Run the full accessibility audit on the song leaderboard, accepting only the
    /// contrast of rows intentionally dimmed by the bottom scroll-edge fade (issue #93).
    ///
    /// Rows fade over ``ScrollEdgeFade``'s 36 pt above the floating pager/footer (web
    /// `useScrollFade`), so a row inside that band reads below 4.5:1 by design, as
    /// text under a bar's top scroll-edge effect does. Every other issue fails.
    ///
    /// - Parameters:
    ///   - app: Running app on the song leaderboard.
    ///   - pagerTop: Top of the floating pager's first control.
    /// - Throws: An audit failure outside the fade band.
    @MainActor
    private func auditSoloPage(_ app: XCUIApplication, pagerTop: CGFloat) throws {
        // Pager row: 4 pt top padding without a footer (issue #293); fade: up to
        // 36 pt above the chrome's top.
        let fadeTop = pagerTop - 4 - 36
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fst.song-leaderboard.row.")
        ).allElementsBoundByIndex
        let rowInFade = rows.contains { $0.frame.maxY > fadeTop && $0.frame.minY < pagerTop }
        try app.performAccessibilityAudit(for: .all) { issue in
            let attachment = XCTAttachment(
                string: "\(issue.auditType): \(issue.detailedDescription); "
                    + "element=\(issue.element?.identifier ?? "unidentified"), "
                    + "label=\(issue.element?.label ?? "unidentified"), "
                    + "frame=\(String(describing: issue.element?.frame)), "
                    + "fadeTop=\(fadeTop), rowInFade=\(rowInFade)"
            )
            attachment.name = "solo-page-audit-node"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            if issue.auditType == .contrast {
                if let frame = issue.element?.frame, !frame.isEmpty {
                    if frame.maxY > fadeTop { return true }
                } else if rowInFade {
                    return true
                }
            }
            XCTFail(
                "Solo page audit: \(issue.compactDescription); "
                    + "element=\(issue.element?.identifier ?? "unidentified"), "
                    + "label=\(issue.element?.label ?? "unidentified"), "
                    + "frame=\(String(describing: issue.element?.frame))"
            )
            return false
        }
    }

    // MARK: - Paths menu helpers

    /// One Lead top-ten preview row: a single navigation button (issue #33).
    ///
    /// - Parameters:
    ///   - player: Fixture account ID.
    ///   - app: Running app on Song Detail.
    /// - Returns: The row's button element.
    @MainActor
    private func previewRow(_ player: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["fst.song-detail.preview-row.Solo_Guitar.\(player)"]
    }

    /// One text inside a Lead preview row button.
    ///
    /// - Parameters:
    ///   - player: Fixture account ID.
    ///   - label: Exact text label (rank, score or accuracy).
    ///   - app: Running app on Song Detail.
    /// - Returns: The matching static text.
    @MainActor
    private func previewText(_ player: String, _ label: String, in app: XCUIApplication) -> XCUIElement {
        previewRow(player, in: app).descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

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
