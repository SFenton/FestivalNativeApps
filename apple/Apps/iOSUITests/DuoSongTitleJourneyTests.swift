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

    /// A pushed board keeps Band Size on the cover rail and both account actions in More.
    @MainActor
    func testSelectedBandBoardKeepsBandSizeOnTheFoldedRail() throws {
        try XCTSkipUnless((ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
                          "Needs a folded iPhone Duo")
        let origin = try loopbackOrigin()
        continueAfterFailure = false
        for size in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let app = FestivalApp.makeApp([
                "FST_API_BASE_URL": origin,
                "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
                "FST_DEBUG_SONG": "fixture-pulse",
                "FST_DEBUG_SONG_BAND": "Band_Duets",
            ])
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
            app.launch()
            defer { app.terminate() }
            let window = app.windows.firstMatch
            try XCTSkipUnless(abs(window.frame.width - 466) < 1 && abs(window.frame.height - 678) < 1,
                              "Needs the portrait cover window")
            let bandSize = app.buttons["fst.song-band-leaderboard.band-type-menu"]
            let more = app.buttons["BottomOverflowBarButtonItem"]
            let row = app.buttons["fst.song-band-leaderboard.row.fixture-band-1:1"]
            XCTAssertTrue(row.waitForExistence(timeout: 15), "Expected the selected session's Duos board")
            SongsUITestSupport.record(app, name: "band-selected-rail-\(size)")
            XCTAssertTrue(bandSize.exists && bandSize.isHittable, "Band Size is hidden in More")
            XCTAssertEqual(bandSize.label, "Band size: Duos")
            XCTAssertTrue(more.exists && more.isHittable)
            XCTAssertLessThan(bandSize.frame.midY, more.frame.midY)
            XCTAssertFalse(app.buttons["fst.shell.notifications"].exists)
            XCTAssertFalse(app.buttons["fst.shell.profile"].exists)

            // The system may report the artwork's bounds instead of the full rail hit region.
            bandSize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 20, dy: 0)).tap()
            let trios = app.buttons["Trios"].firstMatch
            XCTAssertTrue(trios.waitForExistence(timeout: 10))
            trios.tap()
            XCTAssertTrue(FeedbackJourney.waitUntil { bandSize.exists && bandSize.label == "Band size: Trios" })

            more.tap()
            SongsUITestSupport.record(app, name: "band-selected-more-\(size)")
            let notifications = app.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label BEGINSWITH %@", "fst.shell.notifications", "Notifications"
            )).firstMatch
            XCTAssertTrue(notifications.exists && notifications.isHittable)
            notifications.tap()
            let close = app.buttons["fst.notifications.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 10))
            XCTAssertTrue(FeedbackJourney.waitUntil { bandSize.exists && bandSize.label == "Band size: Trios" })

            ShellUITestSupport.tapToolbarItem(
                "fst.shell.profile", overflowLabels: ["Profile: Fixture Player 1", "Fixture Player 1", "FP"], in: app
            )
            XCTAssertTrue(SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: 15))
            SongsUITestSupport.assertPlayerTitle("Fixture Player 1", in: app)
        }
    }

    /// The folded Band Size action uses accent blue normally and white with Increase Contrast.
    @MainActor
    func testFoldedBandSizeRailTintAndSelection() throws {
        try XCTSkipUnless((ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
                          "Needs a folded iPhone Duo")
        let origin = try loopbackOrigin()
        continueAfterFailure = false
        for contrast in [false, true] {
            let app = FestivalApp.makeApp([
                "FST_API_BASE_URL": origin,
                "FST_DEBUG_ANONYMOUS": "1",
                "FST_DEBUG_SONG": "fixture-pulse",
                "FST_DEBUG_SONG_BAND": "Band_Duets",
            ])
            app.launchArguments += ["-fst.accessibility.moreContrast", contrast ? "YES" : "NO"]
            app.launch()
            defer { app.terminate() }
            let window = app.windows.firstMatch.frame
            try XCTSkipUnless(abs(window.width - 466) < 1 && abs(window.height - 678) < 1,
                              "Needs the portrait cover window")
            let menu = app.buttons["fst.song-band-leaderboard.band-type-menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 15))
            XCTAssertTrue(menu.isHittable, "Band Size must be reachable on the rail")
            XCTAssertEqual(menu.label, "Band size: Duos")

            let screenshot = menu.screenshot()
            let image = try XCTUnwrap(screenshot.image.cgImage)
            let frame = CGRect(origin: .zero, size: menu.frame.size).insetBy(dx: 5, dy: 5)
            let pixels = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: menu.frame.width))
            let blue = try XCTUnwrap(pixels.fraction(in: frame, matching: ButtonFillPixels.accentBlue))
            let white = try XCTUnwrap(pixels.fraction(in: frame) { red, green, blue in
                min(red, green, blue) >= 185 && max(red, green, blue) - min(red, green, blue) <= 18
            })
            let capture = XCTAttachment(screenshot: screenshot)
            capture.name = contrast ? "band-size-rail-contrast" : "band-size-rail"
            capture.lifetime = .keepAlways
            add(capture)
            XCTAssertGreaterThan(contrast ? white : blue, 0.10, "Band Size glyph: blue \(blue), white \(white)")
            XCTAssertLessThan(contrast ? blue : white, 0.05, "Unexpected competing glyph tint")

            menu.tap()
            let trios = app.buttons["Trios"].firstMatch
            XCTAssertTrue(trios.waitForExistence(timeout: 10), "Band Size did not offer Trios")
            trios.tap()
            XCTAssertTrue(FeedbackJourney.waitUntil { menu.exists && menu.label == "Band size: Trios" },
                          "Band Size did not speak the new size")
        }
    }

    // The Xcode 27.1 CI SDK doesn't declare XCUIHinge.
    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    /// The same Song Detail action opens one named board beside the song on both renderers.
    @MainActor
    func testDuosBoardOpensBesideSongAndClosesOnInnerLandscape() throws {
        try exerciseDuosSplit(book: false)
    }

    /// The physical book transition preserves the highlighted board page; Close remains
    /// reachable at the edges of its hit target.
    @MainActor
    func testDuosBoardSurvivesPhysicalBookPoseAndCloseEdgeTaps() throws {
        try exerciseDuosSplit(book: true)
    }

    /// Keep the Solo board's named, painted accuracy badges aligned through a real pane resize.
    @MainActor
    func testSoloAccuracyStaysInsidePhysicalDuoSplit() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["FST_DUO_SPLIT_TEST"] == "1"
                && (environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Opt in on a dedicated iPhone Duo with the loopback fixture"
        )
        guard #available(iOS 27.3, *) else { throw XCTSkip("Needs the iOS 27.3 hinge runtime") }
        continueAfterFailure = false
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": try loopbackOrigin(),
            "FST_DEBUG_ANONYMOUS": "1",
            "FST_DEBUG_TAB": "songs",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        let device = XCUIDevice.shared
        let hinge = try XCTUnwrap(device.hinge)
        let originalAngle = hinge.angle
        let originalOrientation = device.orientation
        defer {
            app.terminate()
            device.orientation = originalOrientation
            hinge.angle = originalAngle
        }
        device.orientation = .portrait
        hinge.angle = .pi
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 15) {
            abs(hinge.angle - .pi) < 0.05 && abs(window.frame.width - 951) < 1 && abs(window.frame.height - 669) < 1
        }, "Expected the live inner landscape window")

        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(25)))
        song.tap()
        let action = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        SongsUITestSupport.reveal(action, in: app, scrollingUp: true)
        action.tap()
        XCTAssertTrue(SplitBandUITestSupport.waitForPane(app, open: true))
        let flat = try XCTUnwrap(SplitBandUITestSupport.trailingPane(app))

        for (pose, angle) in [("flat", CGFloat.pi), ("book", CGFloat.pi / 2), ("flat-restored", CGFloat.pi)] {
            hinge.angle = angle
            XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 15) {
                guard abs(hinge.angle - angle) < 0.05,
                      let pane = SplitBandUITestSupport.trailingPane(app) else { return false }
                return pose == "book"
                    ? pane.minX > flat.minX + 30 && abs(pane.minX - window.frame.midX) < 30
                    : abs(pane.minX - flat.minX) < 1
            }, "The Solo pane did not settle in \(pose)")
            let pane = try XCTUnwrap(SplitBandUITestSupport.trailingPane(app))
            let rows = app.descendants(matching: .any)
            let graded = rows["fst.song-leaderboard.row.fixture-player-1"].firstMatch
                .staticTexts["fst.score.accuracy.fixture-player-1"].firstMatch
            let fullCombo = rows["fst.song-leaderboard.row.fixture-player-2"].firstMatch
                .staticTexts["fst.score.accuracy.fixture-player-2"].firstMatch
            XCTAssertTrue(graded.waitForExistence(timeout: 15))
            XCTAssertTrue(fullCombo.waitForExistence(timeout: 15))
            XCTAssertEqual(graded.label, "Accuracy 98%")
            XCTAssertEqual(fullCombo.label, "Full combo, accuracy 98%")
            SongsUITestSupport.record(app, name: "solo-accuracy-split-\(pose)")
            let geometry = XCTAttachment(string:
                "\(pose): \(hinge.angle) rad, window \(window.frame), pane \(pane), graded \(graded.frame), FC \(fullCombo.frame)"
            )
            geometry.name = "solo-accuracy-split-\(pose)-geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
            XCTAssertTrue(
                pane.contains(graded.frame) && pane.contains(fullCombo.frame),
                "\(pose): graded \(graded.frame) or FC \(fullCombo.frame) outside \(pane)"
            )
            XCTAssertEqual(graded.frame.midX, fullCombo.frame.midX, accuracy: 1, "\(pose): badge column shifted")
            for badge in [graded, fullCombo] {
                let reading = RecognizedText.recognize(badge, label: "98%", frame: badge.frame)
                XCTAssertNotNil(reading.text?.range(of: #"98\s*%"#, options: .regularExpression), "\(pose): must paint 98%")
            }
            try SongsUITestSupport.assertScoreAccuracyAccent(graded, fullCombo: false)
            try SongsUITestSupport.assertScoreAccuracyAccent(fullCombo, fullCombo: true)
        }
    }

    #if FST_UIKIT_PORT
    /// The selected band's rank and score stay on one line at the largest standard text size.
    @MainActor
    func testDuosBoardKeepsPaintedScoreThroughPhysicalBookPoseAtXXXL() throws {
        try exerciseDuosSplit(book: true, largestStandardText: true)
    }
    #endif

    /// Open the same fixture board at the flat Duo width before testing Close.
    ///
    /// - Parameters:
    ///   - book: Reposition the hinge without relaunching before testing Close.
    ///   - largestStandardText: Launch at XXXL and verify the selected card's painted footer.
    @MainActor
    private func exerciseDuosSplit(book: Bool, largestStandardText: Bool = false) throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["FST_DUO_SPLIT_TEST"] == "1"
                && (environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Opt in on a dedicated iPhone Duo with the loopback fixture"
        )
        guard #available(iOS 27.3, *) else { throw XCTSkip("Needs the iOS 27.3 hinge runtime") }
        let origin = try loopbackOrigin()
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let hinge = try XCTUnwrap(device.hinge, "The Duo simulator has no XCUIHinge")
        let originalAngle = hinge.angle
        let originalOrientation = device.orientation
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": origin,
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        if largestStandardText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.extraExtraExtraLarge.rawValue,
            ]
        }
        defer {
            app.terminate()
            device.orientation = originalOrientation
            hinge.angle = originalAngle
        }

        // The Duo's physical portrait direction opens its inner panel in interface landscape.
        device.orientation = .portrait
        hinge.angle = .pi
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 15) {
            abs(hinge.angle - .pi) < 0.05 && abs(window.frame.width - 951) < 1 && abs(window.frame.height - 669) < 1
        }, "Expected the actual flat inner landscape window; angle \(hinge.angle), window \(window.frame)")

        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(25)))
        song.tap()
        let hero = element("fst.song-detail.hero-title", in: app)
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        let fullWidth = hero.frame.width
        XCTAssertNil(SplitBandUITestSupport.trailingPane(app))
        let openID = "fst.song-detail.band-leaderboard.Band_Duets"
        let open = app.buttons[openID]
        let lower = window.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.74))
        let upper = window.coordinate(withNormalizedOffset: CGVector(dx: 0.025, dy: 0.33))
        // A drag through the middle can scrub Score History instead of scrolling the page.
        for _ in 0..<10 where !(open.exists && open.isHittable) {
            lower.press(forDuration: 0.05, thenDragTo: upper)
        }
        XCTAssertTrue(open.exists && open.isHittable, "No hittable Duos leaderboard action")
        XCTAssertTrue(open.label.localizedCaseInsensitiveContains("Duos"), open.label)
        XCTAssertGreaterThanOrEqual(open.frame.height, 43.5)
        open.tap()

        let titleID = "fst.song-band-leaderboard.board-title"
        let titles = app.descendants(matching: .any).matching(identifier: titleID)
        let title = titles.firstMatch
        let row = app.buttons["fst.song-band-leaderboard.row.fixture-band-1:1"]
        let opened = SplitBandUITestSupport.waitForPane(app, open: true)
        let loaded = opened && row.waitForExistence(timeout: 15)
        recordDuosSplit(in: app, hinge: hinge, phase: "open")
        XCTAssertTrue(opened, "Duos must open in a trailing pane, not push a full page")
        XCTAssertTrue(loaded, "The fixture's first Duos row did not load")
        let pane = try XCTUnwrap(SplitBandUITestSupport.trailingPane(app))
        XCTAssertEqual(titles.count, 1)
        XCTAssertTrue(title.label.hasPrefix("Duos"), title.label)
        XCTAssertTrue(pane.contains(title.frame), "The title is outside the trailing pane")
        XCTAssertFalse(element("fst.song-band-leaderboard.header", in: app).exists)
        XCTAssertTrue(open.isSelected, "Song Detail must keep the open Duos board selected")
        let close = app.buttons.matching(identifier: SplitBandUITestSupport.closeID)
        XCTAssertEqual(close.count, 1)
        XCTAssertTrue(close.firstMatch.isHittable)
        XCTAssertEqual(close.firstMatch.label, "Close")
        XCTAssertTrue(pane.contains(CGPoint(x: close.firstMatch.frame.midX, y: close.firstMatch.frame.midY)))
        #if FST_UIKIT_PORT
        let bandSize = app.buttons.matching(identifier: "fst.song-band-leaderboard.band-type-menu")
        func assertBandSizeRail(in pane: CGRect) {
            XCTAssertEqual(bandSize.count, 1)
            let action = bandSize.firstMatch
            XCTAssertTrue(action.isHittable)
            XCTAssertEqual(action.label, "Band size: Duos")
            XCTAssertTrue(pane.contains(CGPoint(x: action.frame.midX, y: action.frame.midY)))
            XCTAssertLessThan(close.firstMatch.frame.midY, action.frame.midY, "Close leads the Duo rail")
        }
        assertBandSizeRail(in: pane)
        #endif
        let jump = app.buttons.matching(identifier: "fst.song-band-leaderboard.spotlight-jump")
        XCTAssertEqual(jump.count, 1)
        let footer = jump.firstMatch
        XCTAssertTrue(footer.isHittable)
        XCTAssertEqual(footer.label, "Your band's rank, 29th. Jump to your band's position.")
        XCTAssertGreaterThan(footer.frame.height, 68, "The narrow footer leaves a full line for the band's names")
        XCTAssertTrue(pane.contains(footer.frame))
        footer.tap()
        let band = app.buttons["fst.song-band-leaderboard.row.fixture-band-fixture-player-1:29"]
        XCTAssertTrue(band.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(band.isHittable)
        XCTAssertTrue(band.label.hasPrefix("Your band, Rank 29"), band.label)
        XCTAssertTrue(open.isSelected, "Paging within the board must not clear the Song Detail selection")
        func assertPagerStaysCenteredInPane() {
            let board = "fst.song-band-leaderboard."
            let badge = element(board + "page-info", in: app)
            let footer = app.buttons[board + "spotlight-open"]
            XCTAssertEqual(badge.value as? String, "2 of 2")
            XCTAssertEqual(footer.label, "Your band's rank, 29th. Open band.")
            XCTAssertEqual(badge.frame.midX, footer.frame.midX, accuracy: 1, "A single pane must not shift its pager")
        }
        func assertLastRowClearsFooter() {
            let footer = app.buttons["fst.song-band-leaderboard.spotlight-open"]
            let clearsFooter = FeedbackJourney.waitUntil(timeout: 5) {
                footer.isHittable && band.isHittable && band.frame.maxY <= footer.frame.minY - 5
            }
            if !clearsFooter { recordDuosSplit(in: app, hinge: hinge, phase: "selected-row-obscured") }
            XCTAssertTrue(clearsFooter, "The last card must finish above the footer fade: row \(band.frame), footer \(footer.frame)")
        }
        assertPagerStaysCenteredInPane()
        if book {
            assertLastRowClearsFooter()
            let selectedFooter = app.buttons["fst.song-band-leaderboard.spotlight-open"]
            let flatFooterHeight = selectedFooter.frame.height
            recordDuosSplit(in: app, hinge: hinge, phase: "flat-focused")
            func moveHinge(
                to angle: CGFloat, phase: String, paneMatches: @escaping (CGRect, CGRect) -> Bool
            ) -> XCUIScreenshot {
                hinge.angle = angle
                let settled = FeedbackJourney.waitUntil(timeout: 15) {
                    guard abs(hinge.angle - angle) < 0.05 else { return false }
                    let bounds = window.frame
                    guard abs(bounds.width - 951) < 1, abs(bounds.height - 669) < 1,
                          let moved = SplitBandUITestSupport.trailingPane(app) else { return false }
                    return paneMatches(moved, bounds)
                }
                let screenshot = recordDuosSplit(in: app, hinge: hinge, phase: phase)
                XCTAssertTrue(settled, "\(phase): unexpected split at angle \(hinge.angle), window \(window.frame)")
                return screenshot
            }

            func checkHighlightedRow(phase: String) throws {
                let currentPane = try XCTUnwrap(SplitBandUITestSupport.trailingPane(app))
                XCTAssertTrue(open.isSelected, "Reflow must preserve the selected Song Detail action")
                XCTAssertTrue(band.isHittable, "Reflow must preserve the rank-29 row's position on page 2")
                XCTAssertTrue(currentPane.contains(band.frame), "The selected row must clear the hinge and rail")
                assertPagerStaysCenteredInPane()
                assertLastRowClearsFooter()
                recordDuosSplit(in: app, hinge: hinge, phase: "\(phase)-clear")
            }

            if largestStandardText { try assertPaintedBandScore(in: band, phase: "flat") }
            func isBookPane(_ frame: CGRect, _ window: CGRect) -> Bool {
                abs(frame.minX - window.midX) < 30 && frame.minX > pane.minX + 30
            }

            _ = moveHinge(to: .pi / 2, phase: "book", paneMatches: isBookPane)
            try checkHighlightedRow(phase: "book")
            if largestStandardText {
                try assertPaintedBandScore(in: band, phase: "book")
            } else {
                XCTAssertEqual(selectedFooter.frame.height, flatFooterHeight, accuracy: 1,
                               "This roster fits on one line in both panes; the rank and score keep their own line")
            }
            XCTAssertEqual(close.count, 1)
            #if FST_UIKIT_PORT
            assertBandSizeRail(in: try XCTUnwrap(SplitBandUITestSupport.trailingPane(app)))
            #endif
            let nodes = try FestivalApp.snapshotNodes(in: app) { _ in true }
            SplitBandUITestSupport.assertBandIsSilent(nodes, "physical book pose")
            let selectionIndex = try XCTUnwrap(nodes.firstIndex { $0.identifier == openID })
            let paneIndex = try XCTUnwrap(nodes.firstIndex { $0.identifier == SplitBandUITestSupport.paneID })
            XCTAssertLessThan(selectionIndex, paneIndex, "The selected Song Detail action reads before its board")

            let flatReturn = moveHinge(to: .pi, phase: "flat-return") { frame, _ in abs(frame.minX - pane.minX) < 1 }
            if !largestStandardText {
                let bitmap = try XCTUnwrap(flatReturn.image.cgImage)
                let lines = RecognizedText.lines(in: flatReturn, orientation: bitmap.width < bitmap.height ? .right : .up)
                    .map(\.text)
                for name in ["Band 26 Member A", "Band 26 Member B", "Fixture Player 1 + Band 29 Member B"] {
                    XCTAssertTrue(lines.contains(name), "Flat layout clips '\(name)' after accessibility has settled: \(lines)")
                }
            }
            try checkHighlightedRow(phase: "flat-return")
            func titleClearsChrome() -> Bool {
                title.exists && title.isHittable && title.frame.minY >= 0
                    && title.frame.maxY < selectedFooter.frame.minY
            }
            if largestStandardText {
                try assertPaintedBandScore(in: band, phase: "flat-return")
                let top = window.coordinate(withNormalizedOffset: CGVector(dx: pane.midX / window.frame.width, dy: 0.18))
                let lower = top.withOffset(CGVector(dx: 0, dy: 280))
                for _ in 0..<4 where !titleClearsChrome() {
                    top.press(forDuration: 0.05, thenDragTo: lower)
                }
                XCTAssertTrue(titleClearsChrome(), "The user must be able to scroll away from the last row")
            }
            _ = moveHinge(to: .pi / 2, phase: "book-before-close", paneMatches: isBookPane)
            if largestStandardText {
                XCTAssertTrue(titleClearsChrome(), "Book reflow must not jump back to the last row")
                assertPagerStaysCenteredInPane()
            }
            SplitBandUITestSupport.assertCloseHitRegion(app, "Duos, physical book pose") {
                for _ in 0..<6 where !(open.exists && open.isHittable) {
                    lower.press(forDuration: 0.05, thenDragTo: upper)
                }
                return SplitBandUITestSupport.reopen(app, row: openID)
            }
        } else {
            close.firstMatch.tap()
        }

        XCTAssertTrue(SplitBandUITestSupport.waitForPane(app, open: false))
        XCTAssertFalse(title.exists)
        XCTAssertFalse(close.firstMatch.exists)
        XCTAssertTrue(open.exists && !open.isSelected, "Closing must clear the selection, not leave Song Detail")
        recordDuosSplit(in: app, hinge: hinge, phase: "closed")
        for _ in 0..<10 where !(hero.exists && hero.isHittable) {
            upper.press(forDuration: 0.05, thenDragTo: lower)
        }
        XCTAssertTrue(hero.exists && hero.isHittable, "Close didn't return to Song Detail")
        XCTAssertTrue(hero.label.hasPrefix(Self.titlePrefix))
        XCTAssertEqual(hero.frame.width, fullWidth, accuracy: 1)
    }

    /// Verify pixels as well as the selected row's spoken values; its AX label alone cannot reveal clipping.
    @MainActor
    private func assertPaintedBandScore(in row: XCUIElement, phase: String) throws {
        XCTAssertTrue(row.label.contains("score 80,500"))
        XCTAssertTrue(row.label.contains("5 stars"))
        XCTAssertTrue(row.label.contains("accuracy 96.5%"))
        let screenshot = row.screenshot()
        let capture = XCTAttachment(screenshot: screenshot)
        capture.name = "duo-duos-xxxl-\(phase)-selected-score"
        capture.lifetime = .keepAlways
        add(capture)
        let bitmap = try XCTUnwrap(screenshot.image.cgImage)
        let lines = RecognizedText.lines(in: screenshot, orientation: bitmap.width < bitmap.height ? .right : .up)
        func line(_ pattern: String) throws -> CGRect {
            try XCTUnwrap(
                lines.first { $0.text.range(of: pattern, options: .regularExpression) != nil }?.frame,
                "\(phase) is missing \(pattern): \(lines.map(\.text))"
            )
        }
        let rank = try line(#"#\s*29(?!\d)"#)
        let score = try line(#"(?<!\d)80[ ,]?500(?!\d)"#)
        _ = try line(#"(?<!\d)96[. ]5\s*%"#)
        XCTAssertLessThan(abs(rank.midY - score.midY), min(rank.height, score.height) / 2,
                          "\(phase): rank and score are not on the same line")
    }

    /// Attach the lit inner display and fresh accessibility hierarchy at a settled state.
    @MainActor
    @discardableResult
    private func recordDuosSplit(in app: XCUIApplication, hinge: XCUIHinge, phase: String) -> XCUIScreenshot {
        let screenshot = XCUIScreen.main.screenshot()
        let size = screenshot.image.size
        XCTAssertEqual(min(size.width, size.height) / max(size.width, size.height), 669.0 / 951.0,
                       accuracy: 0.002, "The active panel must be the inner display")
        let capture = XCTAttachment(screenshot: screenshot)
        capture.name = "duo-duos-split-\(phase)-inner-framebuffer"
        capture.lifetime = .keepAlways
        add(capture)
        let hierarchy = XCTAttachment(string: "angle=\(hinge.angle); window=\(app.windows.firstMatch.frame)\n"
            + app.debugDescription)
        hierarchy.name = "duo-duos-split-\(phase)-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        return screenshot
    }
    #endif

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

    /// Return the configured fixture origin, not a public endpoint.
    private func loopbackOrigin() throws -> String {
        let origin = SongsUITestSupport.fixtureURL
        let url = try XCTUnwrap(URLComponents(string: origin))
        try XCTSkipUnless(url.scheme == "http" && url.host == "127.0.0.1" && url.port != nil,
                          "The comparison requires a loopback fixture")
        return origin
    }

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
