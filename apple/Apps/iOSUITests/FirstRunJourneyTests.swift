import XCTest

/// First-run carousel journeys (operator batch 6 item 6.7, batch 7; Apple's onboarding layout
/// since issue #25): Next/Done at the bottom with Skip beneath it while pages remain, Back in
/// the navigation bar only after the first page (never disabled), 44 pt hit regions,
/// dismissal by swiping down or tapping outside, and "only pages actually seen count" across
/// a relaunch.
///
/// Hosted (macOS) snapshot coverage for individual carousel states lives in
/// `FirstRunHostedTests.swift`; the viewed-page bookkeeping is unit-tested in
/// `FestivalCoreTests/SettingsBatch6Tests.swift` (`FirstRunViewing`). Needs
/// `tools/mock_service.py --port 8765`.
final class FirstRunJourneyTests: XCTestCase {
    /// A Songs row, found by identifier regardless of accessibility role.
    ///
    /// - Parameters:
    ///   - app: The running application.
    ///   - songId: Fixture song id.
    /// - Returns: The row element, whatever its role.
    @MainActor
    private func songsRow(_ app: XCUIApplication, _ songId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "fst.songs.row.\(songId)").firstMatch
    }

    /// The fixture app with the given first-run mode.
    ///
    /// - Parameter mode: `force` (every gate-passing slide, every launch) or `on` (real
    ///   seen-state).
    /// - Returns: An unlaunched app.
    @MainActor
    private func fixtureApp(mode: String = "force") -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": mode,
        ])
    }

    /// The carousel slide whose combined label starts with `title`.
    @MainActor
    private func slide(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(title). ")).firstMatch
    }

    /// The Songs guide renders real fixture songs while only the slide's narration is exposed.
    @MainActor
    func testSongListGuideRendersRealRowsWithoutDemoActions() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launch()
        let page = slide(app, titled: "Song List")
        XCTAssertTrue(page.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertEqual(page.elementType, .staticText)
        XCTAssertTrue(page.label.contains("Tap a song to see leaderboards"))
        for title in ["Fixture Pulse", "Fixture Orbit"] {
            let reading = RecognizedText.recognizeLine(title, in: page)
            XCTAssertTrue(RecognizedText.showsWhole(title, in: reading.text), "Expected guide row for \(title)")
        }
        XCTAssertFalse(page.buttons.firstMatch.exists, "Preview rows must not be separate actions")
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)
    }

    /// The selected Songs guide shows native Sort, Navigation and Filter previews without exposing their controls.
    @MainActor
    func testSongsGuideShowsReadOnlySortAndFilterForms() {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: FestivalApp.budget(15)))
        next.tap()
        waitForPage(app, "2 of 9")
        let sort = slide(app, titled: "Sort Songs")
        XCTAssertTrue(sort.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(sort.elementType, .staticText)
        let dots = app.descendants(matching: .any)["fst.first-run.dots"]
        XCTAssertEqual(sort.frame.midX, next.frame.midX, accuracy: 3, "The slide stays inside the footer's safe column")
        XCTAssertEqual(dots.frame.midX, next.frame.midX, accuracy: 3)
        XCTAssertNotNil(RecognizedText.recognizeLine("Item Shop", in: sort).text, "The Sort preview draws its Item Shop option")
        XCTAssertFalse(app.buttons["fst.songs.sort.mode"].exists)
        next.tap()
        waitForPage(app, "3 of 9")
        let navigation = slide(app, titled: "Navigation")
        XCTAssertTrue(navigation.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(navigation.elementType, .staticText)
        XCTAssertFalse(navigation.buttons.firstMatch.exists, "Example tabs must not be separate actions")
        if app.windows.firstMatch.frame.size == CGSize(width: 402, height: 874) {
            XCTAssertNotNil(RecognizedText.recognizeLine("Compete", in: navigation).text, "The preview draws the native tabs")
        }
        next.tap()
        waitForPage(app, "4 of 9")
        let filter = slide(app, titled: "Filter Songs")
        XCTAssertTrue(filter.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(filter.elementType, .staticText)
        XCTAssertNotNil(RecognizedText.recognizeLine("Duration", in: filter).text)
        XCTAssertFalse(app.descendants(matching: .any)["fst.songs.filter.duration"].exists)
        XCTAssertTrue(next.isHittable)
    }

    /// Score examples are visible without exposing the guide's decorative status controls.
    @MainActor
    func testSongsGuideShowsReadOnlyInstrumentAndMetadataExamples() {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: FestivalApp.budget(15)))
        for index in 2...5 {
            next.tap()
            waitForPage(app, "\(index) of 9")
        }
        let icons = slide(app, titled: "Instrument Icons")
        XCTAssertTrue(icons.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(icons.elementType, .staticText)
        let size = app.windows.firstMatch.frame.size
        if size == CGSize(width: 466, height: 678) {
            XCTAssertNotNil(RecognizedText.recognizeLine("Synthetic Quartet", in: icons).text)
        } else {
            for title in ["Fixture Pulse", "Fixture Orbit"] {
                XCTAssertNotNil(RecognizedText.recognizeLine(title, in: icons).text)
            }
        }
        XCTAssertFalse(icons.descendants(matching: .any)["fst.songs.instrument-status.fixture-pulse"].exists)
        SongsUITestSupport.record(app, name: "guide-songs-instrument-icons")

        next.tap()
        waitForPage(app, "6 of 9")
        let metadata = slide(app, titled: "Song Metadata")
        XCTAssertTrue(metadata.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(metadata.elementType, .staticText)
        XCTAssertNotNil(RecognizedText.recognizeLine("191,200", in: metadata).text)
        XCTAssertFalse(metadata.descendants(matching: .any)["fst.songs.metadata.score.fixture-pulse"].exists)
        XCTAssertTrue(next.isHittable)
        SongsUITestSupport.record(app, name: "guide-songs-metadata")

        let window = app.windows.firstMatch
        if #available(iOS 27.0, *),
           size == CGSize(width: 402, height: 874) || size == CGSize(width: 466, height: 678) {
            XCTAssertEqual(next.frame.height, 50, accuracy: 2, "Filling the demo does not stretch Next")
            let dots = app.descendants(matching: .any)["fst.first-run.dots"]
            let screenshot = window.screenshot()
            guard let title = RecognizedText.lines(in: screenshot).first(where: { $0.text == "Song Metadata" }) else {
                XCTFail("Expected the rendered Song Metadata title")
                return
            }
            let top = title.frame.minY * window.frame.height / screenshot.image.size.height + window.frame.minY
            XCTAssertEqual(dots.frame.minY - top, 112, accuracy: 4, "The demo fills the reference's narration viewport")
        }
    }

    /// All three Songs Shop slides show catalogue rows behind one accessible narration.
    @MainActor
    func testSongsShopGuidesShowReadOnlySongRows() {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: FestivalApp.budget(15)))
        for index in 2...7 {
            next.tap()
            waitForPage(app, "\(index) of 9")
        }

        for (offset, title) in ["Item Shop Highlights", "New in the Item Shop", "Leaving Tomorrow"].enumerated() {
            if offset > 0 {
                next.tap()
                waitForPage(app, "\(7 + offset) of 9")
            }
            let page = slide(app, titled: title)
            XCTAssertTrue(page.waitForExistence(timeout: FestivalApp.budget(5)))
            XCTAssertEqual(page.elementType, .staticText)
            let lines = RecognizedText.lines(in: page.screenshot())
            XCTAssertTrue(lines.contains { RecognizedText.showsWhole("Fixture Pulse", in: $0.text) })
            XCTAssertFalse(lines.contains { $0.text.localizedCaseInsensitiveContains("scores paused") },
                           "The Shop examples do not include the selected player's score status")
            assertDecorativeCatalogueRows(page)
        }
        XCTAssertTrue(app.buttons["fst.first-run.done"].isHittable)
    }

    /// The Item Shop teaches its three statuses with native rows while the preview stays read-only.
    @MainActor
    func testItemShopGuideShowsReadOnlyCatalogueExamples() {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        replayGuide("shop", in: app)

        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: FestivalApp.budget(15)))
        waitForPage(app, "1 of 4")
        let overview = slide(app, titled: "Item Shop")
        XCTAssertTrue(overview.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(overview.elementType, .staticText)
        XCTAssertFalse(overview.buttons.firstMatch.exists)
        SongsUITestSupport.record(app, name: "item-shop-guide-overview")

        for (index, title) in ["Shop Highlighting", "New Shop Songs", "Leaving Tomorrow"].enumerated() {
            next.tap()
            waitForPage(app, "\(index + 2) of 4")
            let page = slide(app, titled: title)
            XCTAssertTrue(page.waitForExistence(timeout: FestivalApp.budget(5)))
            XCTAssertEqual(page.elementType, .staticText)
            let lines = RecognizedText.lines(in: page.screenshot())
            XCTAssertTrue(lines.contains { line in
                ["Fixture Pulse", "Fixture Orbit"].contains { RecognizedText.showsWhole($0, in: line.text) }
            }, "The preview shows a real fixture catalogue row, not a stand-in")
            XCTAssertFalse(lines.contains { $0.text.localizedCaseInsensitiveContains("scores paused") })
            assertDecorativeCatalogueRows(page)
            SongsUITestSupport.record(app, name: "item-shop-guide-\(index + 2)")
        }
        let done = app.buttons["fst.first-run.done"]
        XCTAssertTrue(done.isHittable)
        XCTAssertGreaterThanOrEqual(done.frame.height, 44)
    }

    /// The visible example rows add neither actions nor duplicate narration.
    @MainActor
    private func assertDecorativeCatalogueRows(_ page: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(page.buttons.firstMatch.exists, file: file, line: line)
        let descendants = page.descendants(matching: .any)
        let demoSong = descendants.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Fixture Pulse", "Fixture Orbit"
        )).firstMatch
        if demoSong.exists {
            XCTFail("Unexpected guide preview element: \(demoSong.debugDescription)", file: file, line: line)
        }
        let badge = descendants.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.shop-badge."))
        XCTAssertFalse(badge.firstMatch.exists, file: file, line: line)
    }

    /// The Item Shop slides keep one narration stop before the controls at maximum text size.
    @MainActor
    func testItemShopGuideReadsInOrderAtLargestText() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        replayGuide("shop", in: app)

        let titles = ["Item Shop", "Shop Highlighting", "New Shop Songs", "Leaving Tomorrow"]
        for (index, title) in titles.enumerated() {
            let page = index + 1
            let last = page == titles.count
            let narration = slide(app, titled: title)
            XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(15)))
            waitForPage(app, "\(page) of \(titles.count)")
            XCTAssertEqual(narration.elementType, .staticText)
            try assertGuidePageAccessible(app, slide: narration, page: page, last: last, form: "Item Shop AX5")
            if !last { app.buttons["fst.first-run.next"].tap() }
        }
        app.buttons["fst.first-run.done"].tap()
        XCTAssertTrue(app.buttons["fst.first-run.close"].waitForNonExistence(timeout: FestivalApp.budget(5)))
    }

    /// The top-rank and Your Rank illustrations draw synthetic scores without exposing
    /// a ranked profile or View All action, including when an actual profile is selected.
    @MainActor
    func testRankingGuidesShowReadOnlySampleRows() {
        continueAfterFailure = false
        for guide in ["leaderboards", "compete"] {
            let app = guideReplayApp()
            app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
            replayGuide(guide, in: app)
            waitForPage(app, "1 of 3")
            if guide == "compete" {
                app.buttons["fst.first-run.next"].tap()
                waitForPage(app, "2 of 3")
            }
            let title = guide == "compete" ? "Leaderboards" : "Global Rankings"
            assertRankingDemo(title, score: "2,275,100", hiddenName: "BeatLegend", in: app)
            if guide == "leaderboards" {
                let next = app.buttons["fst.first-run.next"]
                next.tap()
                waitForPage(app, "2 of 3")
                next.tap()
                waitForPage(app, "3 of 3")
                assertRankingDemo("Your Rank", score: "1,250,000", hiddenName: "DrumSurge", in: app)
            }
            app.terminate()
        }
    }

    /// The Your Rank narration precedes the controls at AX5; its decorative board
    /// never becomes a layout or accessibility obstacle.
    @MainActor
    func testYourRankGuideReadsInOrderAtLargestText() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        replayGuide("leaderboards", in: app)
        waitForPage(app, "1 of 3")
        for page in 2...3 {
            app.buttons["fst.first-run.next"].tap()
            waitForPage(app, "\(page) of 3")
        }
        let narration = slide(app, titled: "Your Rank")
        XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
        try assertGuidePageAccessible(app, slide: narration, page: 3, last: true, form: "Your Rank AX5")
    }

    /// The opt-in metrics lesson illustrates Rank By without a live menu.
    @MainActor
    func testExperimentalRankingGuideUsesReadOnlyChoices() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += ["-fst.settings.experimentalRanks", "NO"]
        replayGuide("leaderboards", in: app)
        waitForPage(app, "1 of 3")
        app.buttons["fst.first-run.next"].tap()
        waitForPage(app, "2 of 3")
        let narration = slide(app, titled: "Experimental Ranking Metrics")
        XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
        SongsUITestSupport.record(app, name: "leaderboards-guide-experimental-metrics")
        let lines = RecognizedText.lines(in: narration.screenshot()).map(\.text)
        XCTAssertTrue(lines.contains { $0.hasSuffix("Adjusted Percentile") }, "The illustration needs its first choice: \(lines)")
        XCTAssertTrue(lines.contains { $0.contains("Estimated skill") }, "The choice needs its own explanation: \(lines)")
        XCTAssertFalse(narration.buttons.firstMatch.exists)
        let window = app.windows.firstMatch.frame
        if window.height >= 800, window.width < 450 {
            let capture = app.screenshot()
            let lastLine = try XCTUnwrap(RecognizedText.lines(in: capture).first {
                RecognizedText.showsWhole("the toolbar", in: $0.text)
            })
            let bottom = lastLine.frame.maxY * window.height / capture.image.size.height
            let dots = app.descendants(matching: .any).matching(identifier: "fst.first-run.dots").firstMatch
            XCTAssertGreaterThan(dots.frame.minY - bottom, 25, "The illustration must not crowd the narration into the pager.")
        }
    }

    /// The automatic anonymous guide admits experimental metrics only when enabled.
    @MainActor
    func testAutomaticRankingGuideFollowsExperimentalRanks() {
        continueAfterFailure = false
        for enabled in [false, true] {
            let app = fixtureApp()
            app.launchEnvironment["FST_DEBUG_TAB"] = "leaderboards"
            app.launchEnvironment["FST_DEBUG_ANONYMOUS"] = "1"
            app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
            app.launchArguments += ["-fst.settings.experimentalRanks", enabled ? "YES" : "NO"]
            app.launch()
            XCTAssertTrue(slide(app, titled: "Global Rankings").waitForExistence(timeout: FestivalApp.budget(5)))
            if enabled {
                waitForPage(app, "1 of 2")
                app.buttons["fst.first-run.next"].tap()
                waitForPage(app, "2 of 2")
                XCTAssertTrue(slide(app, titled: "Experimental Ranking Metrics").exists)
            } else {
                XCTAssertFalse(app.descendants(matching: .any)["fst.first-run.dots"].exists)
                XCTAssertFalse(app.buttons["fst.first-run.next"].exists)
            }
            XCTAssertTrue(app.buttons["fst.first-run.done"].isHittable)
            app.terminate()
        }
    }

    /// Compete and Rivals use sample boards and rival rows rather than the selected account.
    @MainActor
    func testCompetitionGuidesShowReadOnlySampleMatchups() {
        continueAfterFailure = false
        for (guide, lessons) in [
            ("compete", [
                (1, "Compete Hub", ["GoldStreak", "NoteHunter", "BeatLegend", "VocalStorm"]),
                (3, "Rivals", ["Above You", "KeyDrifter", "DeepGroove", "DrumSurge"]),
            ]),
            ("rivals", [
                (1, "Your Rivals", ["KeyDrifter", "DeepGroove", "SonicRush", "DrumSurge"]),
                (2, "Per-Instrument Rivals", ["StageKnight", "FretBlaze", "BeatLegend", "RhythmEdge"]),
                (3, "Head-to-Head", ["Closest Battles"]),
            ]),
        ] {
            let app = guideReplayApp()
            app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
            replayGuide(guide, in: app)
            var current = 1
            for (page, title, samples) in lessons {
                while current < page {
                    app.buttons["fst.first-run.next"].tap()
                    current += 1
                    waitForPage(app, "\(current) of 3")
                }
                let narration = slide(app, titled: title)
                XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
                SongsUITestSupport.record(app, name: "\(guide)-guide-\(page)")
                let illustration = RecognizedText.lines(in: narration.screenshot()).map(\.text).joined(separator: " ")
                XCTAssertTrue(samples.contains { illustration.localizedCaseInsensitiveContains($0) },
                              "\(title) should show at least one of \(samples): \(illustration)")
                XCTAssertFalse(narration.buttons.firstMatch.exists)
                XCTAssertFalse(narration.descendants(matching: .any).matching(
                    NSPredicate(format: "label IN %@", samples)
                ).firstMatch.exists, "The sample is outside the narration")
                if title == "Head-to-Head" {
                    XCTAssertNotNil(RecognizedText.recognizeLine("Fixture Pulse", in: narration).text)
                }
            }
            app.terminate()
        }
    }

    /// Rivals keeps samples out of the reading order, even with redacted titles and no motion.
    @MainActor
    func testRivalsGuideReadsInOrderWithUnavailableCatalogueAtLargestText() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchEnvironment.removeValue(forKey: "FST_DEBUG_STILL_BACKGROUND")
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            "-fst.accessibility.reduceMotion", "YES",
        ]
        replayGuide("rivals", in: app)
        let titles = ["Your Rivals", "Per-Instrument Rivals", "Head-to-Head"]
        for (index, title) in titles.enumerated() {
            let page = index + 1
            if page > 1 { app.buttons["fst.first-run.next"].tap() }
            waitForPage(app, "\(page) of 3")
            let narration = slide(app, titled: title)
            XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
            try assertGuidePageAccessible(app, slide: narration, page: page, last: page == 3, form: "Rivals AX5")
            if page == 3 {
                // The combined SwiftUI narration frame does not include the decorative preview.
                let capture = app.screenshot()
                let lines = RecognizedText.lines(in: capture)
                let close = app.buttons["fst.first-run.close"].frame
                let heading = lines.filter { $0.frame.maxX < close.minX }.map(\.text).joined(separator: " ")
                if !RecognizedText.showsWhole("Closest Battles", in: heading) {
                    add(XCTAttachment(screenshot: capture))
                    XCTFail("The category heading should be fully visible: \(heading)")
                }
                let text = lines.map(\.text).joined(separator: " ")
                XCTAssertFalse(text.localizedCaseInsensitiveContains("placeholder") ||
                    text.localizedCaseInsensitiveContains("Fixture Pulse"), text)
            }
        }
    }

    /// Both Song Info chart lessons draw sample bars; the still selection rests on the first bar.
    @MainActor
    func testSongInfoGuideShowsReadOnlySampleCharts() {
        continueAfterFailure = false
        let app = guideReplayApp()
        replayGuide("songinfo", in: app)
        waitForPage(app, "1 of 8")
        let chart = slide(app, titled: "Score History Chart")
        XCTAssertTrue(chart.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertNotNil(RecognizedText.recognizeLine("347,100", in: chart).text)
        XCTAssertNotNil(RecognizedText.recognizeLine("Today", in: chart).text)

        app.buttons["fst.first-run.next"].tap()
        waitForPage(app, "2 of 8")
        let selection = slide(app, titled: "Select a Bar for Details")
        XCTAssertTrue(selection.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertNotNil(RecognizedText.recognizeLine("9/12", in: selection).text)
        if app.windows.firstMatch.frame.height >= 800 {
            XCTAssertNotNil(RecognizedText.recognizeLine("218,400", in: selection).text)
            XCTAssertNotNil(RecognizedText.recognizeLine("62%", in: selection).text)
        }
        app.buttons["fst.first-run.back"].tap()
        waitForPage(app, "1 of 8")
        XCTAssertNotNil(RecognizedText.recognizeLine("347,100", in: chart).text)
    }

    /// The sheet's scrim dims Settings, but the exposed Show capsule does not turn gray.
    @MainActor
    func testGuideReplayKeepsItsBlueFillBehindTheSheet() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launch()
        let window = app.windows.firstMatch
        guard window.frame.height >= 800, window.frame.width < 450 else {
            throw XCTSkip("The exposed Settings button is measured in the iPhone portrait layout.")
        }
        let show = app.buttons["fst.settings.first-run.songs"]
        XCTAssertTrue(show.waitForExistence(timeout: FestivalApp.budget(5)))
        let fill = show.frame.insetBy(dx: 10, dy: 0)
        app.buttons["fst.settings.first-run.songinfo"].tap()
        waitForPage(app, "1 of 8")
        XCTAssertFalse(show.isHittable, "The visible backdrop is still modal.")
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let pixels = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: window.frame.width))
        let blue = try XCTUnwrap(pixels.fraction(in: fill) { red, green, blue in
            blue - red >= 45 && blue - green >= 20 && green > red
        })
        XCTAssertGreaterThan(blue, 0.25, "The exposed capsule keeps its blue hue through the sheet's scrim.")
        app.buttons["fst.first-run.close"].tap()
        XCTAssertTrue(show.isHittable, "Close restores the Settings controls.")
    }

    /// Sample marks and detail values never become separate accessibility stops at AX5.
    @MainActor
    func testSongInfoChartGuideReadsInOrderAtLargestText() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        replayGuide("songinfo", in: app)
        waitForPage(app, "1 of 8")
        let lessons = [
            ("Score History Chart", "instruments to see more data!"),
            ("Select a Bar for Details", "season, score, and accuracy."),
        ]
        for (index, lesson) in lessons.enumerated() {
            if index != 0 {
                app.buttons["fst.first-run.next"].tap()
                waitForPage(app, "2 of 8")
            }
            let narration = slide(app, titled: lesson.0)
            XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
            XCTAssertEqual(narration.elementType, .staticText)
            XCTAssertTrue(narration.label.hasSuffix(lesson.1), "Expected complete narration: \(narration.label)")
            try assertGuidePageAccessible(app, slide: narration, page: index + 1, last: false, form: "Song Info chart AX5")
        }
    }

    /// The Paths illustration shows the local placeholder and Expert selector; each Shop
    /// lesson shows a catalogue header. On a short cover the action is titled, not a disc.
    @MainActor
    func testSongInfoGuideShowsReadOnlyPathsAndShopPreviews() {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += ["-fst.settings.disableShopHighlighting", "NO"]
        openSongInfoPathsGuide(in: app)
        let paths = slide(app, titled: "Optimal Paths")
        XCTAssertTrue(paths.waitForExistence(timeout: FestivalApp.budget(5)))
        for label in ["Path Preview", "Expert"] {
            XCTAssertNotNil(RecognizedText.recognizeLine(label, in: paths).text)
        }
        for id in ["fst.paths.instrument", "fst.paths.difficulty", "fst.paths.display"] {
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists)
        }
        for (page, title, _) in Self.songInfoActionLessons.dropFirst() {
            app.buttons["fst.first-run.next"].tap()
            waitForPage(app, "\(page) of 8")
            let shop = slide(app, titled: title)
            XCTAssertTrue(shop.waitForExistence(timeout: FestivalApp.budget(5)))
            XCTAssertNotNil(RecognizedText.recognizeLine("Fixture Pulse", in: shop).text)
            let illustration = shopIllustrationLines(title: title, in: shop, app: app)
            let showsTitledAction = showsTitledShopAction(in: illustration)
            if app.windows.firstMatch.frame.height < 800 {
                XCTAssertTrue(showsTitledAction, "\(illustration)")
                XCTAssertTrue(illustration.contains("Item") && illustration.contains("Shop"),
                              "Wrap the folded action instead of taking space from the song header: \(illustration)")
            } else {
                XCTAssertFalse(showsTitledAction, "\(illustration)")
            }
            XCTAssertFalse(shop.buttons.firstMatch.exists)
        }
    }

    /// A missing catalogue does not invent song content, and disabling highlighting
    /// still draws the plain action on the final lesson.
    @MainActor
    func testSongInfoShopGuideRedactsUnavailableCatalogueWithHighlightingOff() {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += ["-fst.settings.disableShopHighlighting", "YES"]
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        openSongInfoPathsGuide(in: app)
        for page in 6...8 {
            app.buttons["fst.first-run.next"].tap()
            waitForPage(app, "\(page) of 8")
        }
        let title = "Leaving Tomorrow"
        let shop = slide(app, titled: title)
        XCTAssertTrue(shop.waitForExistence(timeout: FestivalApp.budget(5)))
        let illustration = shopIllustrationLines(title: title, in: shop, app: app)
        XCTAssertTrue(showsTitledShopAction(in: illustration), "\(illustration)")
        XCTAssertFalse(illustration.contains { $0.localizedCaseInsensitiveContains("placeholder") }, "\(illustration)")
        XCTAssertFalse(illustration.contains { $0.localizedCaseInsensitiveContains("fixture") }, "\(illustration)")
    }

    /// Inert Paths selectors and Shop actions stay out of the reading order, even at AX5.
    @MainActor
    func testSongInfoPathsAndShopGuideReadsInOrderAtLargestText() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        openSongInfoPathsGuide(in: app)
        for (page, title, ending) in Self.songInfoActionLessons {
            if page != 5 {
                app.buttons["fst.first-run.next"].tap()
                waitForPage(app, "\(page) of 8")
            }
            let narration = slide(app, titled: title)
            XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
            XCTAssertEqual(narration.elementType, .staticText)
            XCTAssertTrue(narration.label.hasSuffix(ending), narration.label)
            try assertGuidePageAccessible(app, slide: narration, page: page, last: page == 8, form: "Song Info actions AX5")
        }
    }

    private static let songInfoActionLessons = [
        (5, "Optimal Paths", "instrument and difficulty."),
        (6, "Item Shop Link", "straight to the store."),
        (7, "New Shop Songs", "instead of green."),
        (8, "Leaving Tomorrow", "act fast."),
    ]

    /// Opens the fifth Song Info replay page without depending on account-specific gates.
    @MainActor
    private func openSongInfoPathsGuide(in app: XCUIApplication) {
        replayGuide("songinfo", in: app)
        waitForPage(app, "1 of 8")
        for page in 2...5 {
            app.buttons["fst.first-run.next"].tap()
            waitForPage(app, "\(page) of 8")
        }
    }

    /// Reads the full window before selecting the illustration lines. The element screenshot
    /// can lose the leading letter of a short word next to the folded capsule's glyph.
    ///
    /// - Returns: Individual lines within the slide above its narration.
    @MainActor
    private func shopIllustrationLines(title: String, in slide: XCUIElement, app: XCUIApplication) -> [String] {
        let window = app.windows.firstMatch
        let frame = window.frame
        let capture = window.screenshot()
        let size = capture.image.size
        let bounds = slide.frame.offsetBy(dx: -frame.minX, dy: -frame.minY).applying(
            CGAffineTransform(scaleX: size.width / frame.width, y: size.height / frame.height)
        )
        let lines = RecognizedText.lines(in: capture).filter {
            bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        guard let narration = lines.firstIndex(where: { $0.text == title }) else {
            XCTFail("Could not locate \(title) in \(lines.map(\.text))")
            return []
        }
        let adornments = CharacterSet.symbols.union(.punctuationCharacters).union(.whitespaces)
        return lines.prefix(narration).map { $0.text.trimmingCharacters(in: adornments) }
    }

    /// The folded SwiftUI capsule can place each word on its own line.
    private func showsTitledShopAction(in lines: [String]) -> Bool {
        lines.contains { RecognizedText.showsWhole("Item Shop", in: $0) }
            || (lines.contains("Item") && lines.contains("Shop"))
    }

    /// Both Song Info score lessons show their sample rows and CTA, not the selected player's scores.
    @MainActor
    func testSongInfoGuideShowsReadOnlyScoreCards() {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        openSongInfoScoreGuide(in: app)
        // The folded reference crops the decorative CTA; the tall reference shows its label.
        let tallPreview = app.windows.firstMatch.frame.height >= 800
        let history = ["412,300", "347,100"] + (tallPreview ? ["View All Scores"] : [])
        let leaderboard = ["RiffMaster", "ChordKing"] + (tallPreview ? ["View Full Leaderboard"] : [])
        assertSongInfoScoreDemo(
            "View Player Scores", visibleTexts: history, in: app
        )
        app.buttons["fst.first-run.next"].tap()
        waitForPage(app, "4 of 8")
        assertSongInfoScoreDemo(
            "Top Scores Per Instrument", visibleTexts: leaderboard, in: app
        )
        app.buttons["fst.first-run.back"].tap()
        waitForPage(app, "3 of 8")
        assertSongInfoScoreDemo("View Player Scores", visibleTexts: history, in: app)
    }

    /// The score cards remain decorative at AX5; the narration and pager keep their order and targets.
    @MainActor
    func testSongInfoScoreGuideReadsInOrderAtLargestText() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        openSongInfoScoreGuide(in: app)
        let lessons = [
            (3, "View Player Scores", "user, score, and instrument."),
            (4, "Top Scores Per Instrument", "the selected song."),
        ]
        for (page, title, ending) in lessons {
            if page == 4 {
                app.buttons["fst.first-run.next"].tap()
                waitForPage(app, "4 of 8")
            }
            let narration = slide(app, titled: title)
            XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
            XCTAssertEqual(narration.elementType, .staticText)
            XCTAssertTrue(narration.label.hasSuffix(ending), "Expected complete narration: \(narration.label)")
            try assertGuidePageAccessible(app, slide: narration, page: page, last: false, form: "Song Info AX5")
        }
    }

    @MainActor
    private func openSongInfoScoreGuide(in app: XCUIApplication) {
        replayGuide("songinfo", in: app)
        waitForPage(app, "1 of 8")
        for page in 2...3 {
            app.buttons["fst.first-run.next"].tap()
            waitForPage(app, "\(page) of 8")
        }
    }

    @MainActor
    private func assertSongInfoScoreDemo(_ title: String, visibleTexts: [String], in app: XCUIApplication) {
        let narration = slide(app, titled: title)
        XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(narration.elementType, .staticText)
        let lines = RecognizedText.lines(in: narration.screenshot()).map(\.text)
        for text in visibleTexts {
            XCTAssertTrue(lines.contains { $0.localizedCaseInsensitiveContains(text) }, "Expected \(text) in \(lines)")
        }
        for label in ["View All Scores", "View Full Leaderboard", "AceSolo", "486,500"] {
            XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@", label
            )).firstMatch.exists, "\(label) is illustrative, not a separate element")
        }
    }

    /// Statistics draws the illustrative Select card, tiles and percentile rows without
    /// exposing the real page's selectors or drill-down actions.
    @MainActor
    func testStatisticsGuideShowsReadOnlySampleTilesAndRanks() {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        replayGuide("statistics", in: app)
        waitForPage(app, "1 of 6")

        let previews = [
            (title: "Select Player Profile", anchors: ["GoldStreak"]),
            (title: "Drill Into Your Data", anchors: ["142", "96.2%", "38 (26.8%)"]),
            (title: "Global Statistics", anchors: ["96.2%"]),
            (title: "Per-Instrument Stats", anchors: ["Avg Accuracy"]),
            (title: "Percentile Rankings", anchors: ["Top 5%", "Top 10%", "Top 25%", "Top 50%"]),
        ]
        for (index, preview) in previews.enumerated() {
            if index > 0 {
                app.buttons["fst.first-run.next"].tap()
                waitForPage(app, "\(index + 1) of 6")
            }
            let narration = slide(app, titled: preview.title)
            XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
            XCTAssertEqual(narration.elementType, .staticText)
            let text = RecognizedText.lines(in: narration.screenshot()).map(\.text)
            XCTAssertTrue(text.contains { line in preview.anchors.contains(where: line.localizedCaseInsensitiveContains) },
                          "\(preview.title) draws its illustrative data; recognized \(text)")
            XCTAssertFalse(narration.buttons.firstMatch.exists, "\(preview.title) exposes a sample as a button")
            XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR label == %@",
                "fst.player.stat.first-run.", "fst.player.percentile", "GoldStreak"
            )).firstMatch.exists, "\(preview.title) exposes decorative Statistics data")
            XCTAssertFalse(app.buttons["fst.player.select"].exists)
            SongsUITestSupport.record(app, name: "statistics-guide-\(index + 1)")
        }
    }

    /// The Top Songs lesson shows actual catalogue songs with sample ranks but no song actions.
    @MainActor
    func testStatisticsTopSongsGuideShowsReadOnlyCatalogueRanks() {
        continueAfterFailure = false
        let app = guideReplayApp()
        let page = openStatisticsTopSongsGuide(in: app)
        for text in ["Fixture Pulse", "Top 1.2%", "Fixture Orbit", "Top 3.5%"] {
            XCTAssertNotNil(RecognizedText.recognizeLine(text, in: page).text, "Missing \(text) in the artwork preview")
        }
        assertStatisticsTopSongsAreDecorative(in: app, page: page)
        SongsUITestSupport.record(app, name: "statistics-guide-top-songs")
    }

    /// Without a catalogue the song content stays redacted while the sample ranks remain.
    @MainActor
    func testStatisticsTopSongsGuideRedactsUnavailableCatalogue() {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        let page = openStatisticsTopSongsGuide(in: app)
        XCTAssertNotNil(RecognizedText.recognizeLine("Top 3.5%", in: page).text)
        let lines = RecognizedText.lines(in: page.screenshot()).map(\.text)
        XCTAssertFalse(lines.contains { $0.localizedCaseInsensitiveContains("Placeholder") || $0.contains("Fixture") },
                       "An unavailable catalogue must not show song or placeholder text: \(lines)")
        assertStatisticsTopSongsAreDecorative(in: app, page: page)
        SongsUITestSupport.record(app, name: "statistics-guide-top-songs-redacted")
    }

    /// Opens the final Statistics lesson and returns its settled narration.
    @MainActor
    private func openStatisticsTopSongsGuide(in app: XCUIApplication) -> XCUIElement {
        replayGuide("statistics", in: app)
        waitForPage(app, "1 of 6")
        for page in 2...6 {
            app.buttons["fst.first-run.next"].tap()
            waitForPage(app, "\(page) of 6")
        }
        let narration = slide(app, titled: "Highest and Lowest Rank Breakdown")
        XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
        return narration
    }

    /// The preview's illustrative songs and percentile labels are not separate reading stops.
    @MainActor
    private func assertStatisticsTopSongsAreDecorative(in app: XCUIApplication, page: XCUIElement) {
        XCTAssertEqual(page.elementType, .staticText)
        XCTAssertFalse(page.buttons.firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(
            format: "label IN %@", ["Fixture Pulse", "Fixture Orbit", "Top 1.2%", "Top 3.5%", "Top 7.8%", "Top 14.2%"]
        )).firstMatch.exists)
    }

    /// At AX5 the Statistics lessons still read as narration followed by the pager.
    @MainActor
    func testStatisticsPercentileGuideReadsInOrderAtLargestText() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        replayGuide("statistics", in: app)
        waitForPage(app, "1 of 6")
        #if FST_UIKIT_PORT
        let selection = slide(app, titled: "Select Player Profile")
        XCTAssertTrue(selection.waitForExistence(timeout: FestivalApp.budget(5)))
        try assertGuidePageAccessible(app, slide: selection, page: 1, last: false, form: "Select Player Profile AX5")
        #endif
        for page in 2...5 {
            app.buttons["fst.first-run.next"].tap()
            waitForPage(app, "\(page) of 6")
            #if FST_UIKIT_PORT
            if page == 2 {
                let drillDown = slide(app, titled: "Drill Into Your Data")
                XCTAssertTrue(drillDown.waitForExistence(timeout: FestivalApp.budget(5)))
                try assertGuidePageAccessible(app, slide: drillDown, page: page, last: false, form: "Drill Into Your Data AX5")
            }
            #endif
        }
        let narration = slide(app, titled: "Percentile Rankings")
        XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
        try assertGuidePageAccessible(app, slide: narration, page: 5, last: false, form: "Percentile Rankings AX5")
        #if FST_UIKIT_PORT
        app.buttons["fst.first-run.next"].tap()
        waitForPage(app, "6 of 6")
        let rankedSongs = slide(app, titled: "Highest and Lowest Rank Breakdown")
        XCTAssertTrue(rankedSongs.waitForExistence(timeout: FestivalApp.budget(5)))
        try assertGuidePageAccessible(app, slide: rankedSongs, page: 6, last: true, form: "Top Songs AX5")
        #endif
    }

    /// A swiped-to preview settles as one narration; Back restores the preceding lesson.
    @MainActor
    func testStatisticsGuideSwipeAndBackExposeOnlyTheSettledLesson() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        replayGuide("statistics", in: app)
        waitForPage(app, "1 of 6")
        for page in 2...4 {
            app.buttons["fst.first-run.next"].tap()
            waitForPage(app, "\(page) of 6")
        }
        let instrument = slide(app, titled: "Per-Instrument Stats")
        let percentile = slide(app, titled: "Percentile Rankings")
        XCTAssertTrue(instrument.waitForExistence(timeout: FestivalApp.budget(5)))
        instrument.swipeLeft()
        waitForPage(app, "5 of 6")
        XCTAssertTrue(percentile.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertFalse(instrument.exists)
        #if FST_UIKIT_PORT
        try assertGuidePageAccessible(app, slide: percentile, page: 5, last: false, form: "swiped Statistics guide")
        #endif

        app.buttons["fst.first-run.back"].tap()
        waitForPage(app, "4 of 6")
        XCTAssertTrue(instrument.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertFalse(percentile.exists)
    }

    @MainActor
    private func assertRankingDemo(
        _ title: String, score: String, hiddenName: String, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let page = slide(app, titled: title)
        XCTAssertTrue(page.waitForExistence(timeout: FestivalApp.budget(5)), file: file, line: line)
        XCTAssertEqual(page.elementType, .staticText, file: file, line: line)
        SongsUITestSupport.record(app, name: "ranking-guide-\(title)")
        let lines = RecognizedText.lines(in: page.screenshot())
        XCTAssertTrue(lines.contains { $0.text.contains(score) },
                      "\(title) draws its sample board; recognized \(lines.map(\.text))", file: file, line: line)
        XCTAssertFalse(page.buttons.firstMatch.exists, file: file, line: line)
        XCTAssertFalse(page.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label == %@",
                        score, hiddenName, "View all rankings (12,480)")
        ).firstMatch.exists, "the sample is decorative", file: file, line: line)
    }

    /// - Returns: The app opening the First Run Guides settings without automatic tours.
    @MainActor
    private func guideReplayApp() -> XCUIApplication {
        let app = fixtureApp(mode: "off")
        app.launchEnvironment["FST_DEBUG_TAB"] = "settings"
        app.launchEnvironment["FST_DEBUG_ROUTE"] = "settingsTopic:firstRun"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        return app
    }

    /// - Parameters:
    ///   - guide: The settings row's guide identifier.
    ///   - app: An unlaunched app configured by ``guideReplayApp()``.
    @MainActor
    private func replayGuide(_ guide: String, in app: XCUIApplication) {
        app.launch()
        let replay = app.buttons["fst.settings.first-run.\(guide)"]
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        XCTAssertTrue(replay.isHittable)
        replay.tap()
    }

    /// The category and scrolling lessons show sample categories over the catalogue, never live player results.
    @MainActor
    func testSuggestionsGuideShowsReadOnlySampleCards() {
        continueAfterFailure = false
        let app = guideReplayApp()
        visitSuggestionsCardLessons(in: app) { narration, page in
            SongsUITestSupport.record(app, name: "suggestions-guide-card-\(page)")
            XCTAssertNotNil(RecognizedText.recognizeLine("Finish the Lead FCs", in: narration).text,
                            "The opening category heading must fit on page \(page)")
            XCTAssertNotNil(RecognizedText.recognizeLine("Fixture Pulse", in: narration).text,
                            "The first song title must fit on page \(page)")
            XCTAssertFalse(narration.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Finish the Lead FCs")
            ).firstMatch.exists, "The illustration's category heading is not a second stop")
            XCTAssertFalse(app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "fst.suggestions.row.")
            ).firstMatch.exists)
        }
    }

    /// At accessibility text sizes the illustration stays out of narration and page controls.
    @MainActor
    func testSuggestionsGuideCardsAreDecorativeAtLargestText() throws {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        try visitSuggestionsCardLessons(in: app) { narration, page in
            try assertGuidePageAccessible(app, slide: narration, page: page, last: page == 4, form: "Suggestions cards AX5")
        }
    }

    /// Catalogue failure retains the sample categories but never prints invented song names.
    @MainActor
    func testSuggestionsGuideRedactsCatalogueUnderReduceMotion() {
        continueAfterFailure = false
        let app = guideReplayApp()
        app.launchEnvironment.removeValue(forKey: "FST_DEBUG_STILL_BACKGROUND")
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        app.launchArguments += ["-fst.accessibility.reduceMotion", "YES", "-fst.accessibility.lessTransparency", "YES"]
        visitSuggestionsCardLessons(in: app) { narration, page in
            SongsUITestSupport.record(app, name: "suggestions-guide-redacted-\(page)")
            XCTAssertNotNil(RecognizedText.recognizeLine("Finish the Lead FCs", in: narration).text,
                            "The opening category heading must fit on page \(page)")
            let text = RecognizedText.lines(in: narration.screenshot()).map(\.text).joined(separator: " ")
            XCTAssertFalse(text.localizedCaseInsensitiveContains("placeholder"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("fixture"), text)
        }
    }

    /// - Parameters:
    ///   - app: The unlaunched app configured for replay in Settings.
    ///   - verify: The assertions for each sample-card slide and its page number.
    @MainActor
    private func visitSuggestionsCardLessons(
        in app: XCUIApplication, verify: (XCUIElement, Int) throws -> Void
    ) rethrows {
        replayGuide("suggestions", in: app)
        for (page, title) in [(1, "Suggestion Cards"), (4, "More Suggestions")] {
            if page == 4 {
                for index in 2...4 {
                    app.buttons["fst.first-run.next"].tap()
                    waitForPage(app, "\(index) of 4")
                }
            } else {
                waitForPage(app, "1 of 4")
            }
            let narration = slide(app, titled: title)
            XCTAssertTrue(narration.waitForExistence(timeout: FestivalApp.budget(5)))
            try verify(narration, page)
        }
    }

    /// Suggestions shows the global category switches and the four instrument switches
    /// in separate guide previews, without letting the user activate them.
    @MainActor
    func testSuggestionsGuideShowsReadOnlyGlobalAndInstrumentFilters() {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_TAB"] = "suggestions"
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: FestivalApp.budget(15)))
        next.tap()
        waitForPage(app, "2 of 4")
        let global = slide(app, titled: "Filter Suggestions")
        XCTAssertTrue(global.waitForExistence(timeout: 5))
        XCTAssertEqual(global.elementType, .staticText)
        XCTAssertNotNil(RecognizedText.recognizeLine("Star Progress", in: global).text)
        XCTAssertFalse(app.switches["fst.suggestions.filter.type.starProgress"].exists)

        next.tap()
        waitForPage(app, "3 of 4")
        let instruments = slide(app, titled: "Per-Instrument Filters")
        XCTAssertTrue(instruments.waitForExistence(timeout: 5))
        XCTAssertEqual(instruments.elementType, .staticText)
        XCTAssertNotNil(RecognizedText.recognizeLine("Drums", in: instruments).text)
        XCTAssertFalse(app.switches["fst.suggestions.filter.instrument.Solo_Drums"].exists)
        XCTAssertTrue(next.isHittable)
    }

    /// The Score History guide uses sample scores and the local sort form without interactive controls.
    @MainActor
    func testHistoryGuideShowsReadOnlySortForm() {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-history-multi:Multi History"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launch()
        let close = app.buttons["fst.first-run.close"]
        XCTAssertTrue(slide(app, titled: "Song List").waitForExistence(timeout: FestivalApp.budget(15)))
        close.tap()
        let song = songsRow(app, "fixture-pulse")
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        song.tap()
        XCTAssertTrue(close.waitForExistence(timeout: FestivalApp.budget(15)))
        close.tap()
        let viewAll = app.descendants(matching: .any).matching(identifier: "fst.song-detail.history.view-all").firstMatch
        for _ in 0..<8 where !viewAll.isHittable { app.swipeUp() }
        XCTAssertTrue(viewAll.isHittable, "The fixture needs more than five tracked scores")
        viewAll.tap()

        let next = app.buttons["fst.first-run.next"]
        let scores = slide(app, titled: "Score History")
        XCTAssertTrue(scores.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertEqual(scores.elementType, .staticText)
        for score in ["486,500", "412,300", "289,600"] {
            XCTAssertTrue(
                RecognizedText.showsWhole(score, in: RecognizedText.recognizeLine(score, in: scores).text),
                "The preview draws the sample score \(score)"
            )
        }
        XCTAssertFalse(scores.descendants(matching: .any)["fst.first-run.history.0"].exists)
        XCTAssertFalse(scores.buttons.firstMatch.exists)
        SongsUITestSupport.record(app, name: "first-run-history-sample-scores")
        XCTAssertTrue(next.isHittable)
        next.tap()
        waitForPage(app, "2 of 2")
        let sort = slide(app, titled: "Sort Scores")
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertEqual(sort.elementType, .staticText)
        XCTAssertNotNil(RecognizedText.recognizeLine("Accuracy", in: sort).text)
        XCTAssertFalse(app.descendants(matching: .any)["fst.history.sort.mode"].exists)
        XCTAssertTrue(app.buttons["fst.first-run.done"].isHittable)
    }

    /// Wait until the carousel has closed and Songs is interactive again.
    @MainActor
    private func assertCarouselClosed(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["fst.first-run.close"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, file: file, line: line)
        XCTAssertTrue(songsRow(app, "fixture-pulse").waitForExistence(timeout: 15), file: file, line: line)
    }

    /// The page dots' "n of m" value.
    @MainActor
    private func pageValue(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(identifier: "fst.first-run.dots").firstMatch.value as? String ?? ""
    }

    /// Wait until the page dots read `value`.
    @MainActor
    private func waitForPage(
        _ app: XCUIApplication, _ value: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let dots = app.descendants(matching: .any).matching(identifier: "fst.first-run.dots").firstMatch
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: dots)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 5), .completed,
                       "Expected page \(value), saw \(pageValue(app))", file: file, line: line)
    }

    /// Issue #25 (Apple's onboarding layout): the first page offers Next with Skip beneath it
    /// and no Back; from page two Back sits at the leading edge of the guide's navigation
    /// bar, before the title and Close, and returns to the first page; Skip closes the guide.
    @MainActor
    func testNextFirstThenBackAppears() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        let skip = app.buttons["fst.first-run.skip"]
        XCTAssertTrue(skip.exists, "Skip while pages remain")
        XCTAssertGreaterThan(skip.frame.minY, next.frame.maxY - 1, "Skip sits beneath Next")
        XCTAssertFalse(app.buttons["fst.first-run.back"].exists, "No Back on the first page")
        XCTAssertTrue(app.otherElements["fst.first-run.dots"].exists || app.descendants(matching: .any)
            .matching(identifier: "fst.first-run.dots").firstMatch.exists)
        SongsUITestSupport.record(app, name: "first-run-first-page")
        let nextFrame = next.frame

        next.tap()
        let back = app.navigationBars.buttons["fst.first-run.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back lives in the guide's navigation bar")
        XCTAssertTrue(back.isHittable)
        XCTAssertEqual(back.label, "Back")
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertLessThan(back.frame.maxX, close.frame.minX, "Back leads, Close trails")
        let bar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        let title = bar.staticTexts["Songs"]
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(back.frame.maxX, title.frame.minX, "Back comes before the title")
        XCTAssertEqual(app.buttons["fst.first-run.next"].frame.minY, nextFrame.minY, accuracy: 1,
                       "Next stays in place when Back appears")
        SongsUITestSupport.record(app, name: "first-run-second-page")
        back.tap()
        let backGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: back
        )
        XCTAssertEqual(XCTWaiter.wait(for: [backGone], timeout: 10), .completed)
        app.buttons["fst.first-run.skip"].tap()
        assertCarouselClosed(app)
    }

    /// Issue #25: on the last page Done replaces Next in the same place and Skip goes away
    /// (its row keeps its space); Done closes the guide.
    @MainActor
    func testLastPageShowsDoneInPlaceOfNext() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        let nextFrame = next.frame
        while app.buttons["fst.first-run.next"].exists {
            app.buttons["fst.first-run.next"].tap()
            _ = app.buttons["fst.first-run.done"].waitForExistence(timeout: 1)
        }
        let done = app.buttons["fst.first-run.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.frame.minY, nextFrame.minY, accuracy: 1, "Done takes Next's place")
        XCTAssertFalse(app.buttons["fst.first-run.skip"].exists, "No Skip on the last page")
        let back = app.buttons.matching(identifier: "fst.first-run.back")
        XCTAssertEqual(back.count, 1, "Back on the last page")
        let backButton = back.firstMatch
        XCTAssertTrue(backButton.isHittable, "Back remains reachable when the native bar moves it onto the rail")
        XCTAssertEqual(backButton.label, "Back")
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let pixels = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: app.windows.firstMatch.frame.width))
        let glyph = backButton.frame.insetBy(dx: backButton.frame.width / 4, dy: backButton.frame.height / 4)
        let blue = try XCTUnwrap(pixels.fraction(in: glyph, matching: ButtonFillPixels.accentBlue))
        XCTAssertGreaterThan(blue, 0.01, "The Back chevron keeps its tint when the native bar moves it onto the rail.")
        SongsUITestSupport.record(app, name: "first-run-last-page")
        done.tap()
        assertCarouselClosed(app)
    }

    /// Issue #25: every control answers taps within a 44 × 44 pt square centred on it (HIG
    /// Buttons: "the hit region is at least 44x44 pt") and VoiceOver reads it as a button
    /// with its name. Next/Back are probed by the page they reach, Skip/Close by closing the
    /// guide (reopened from Settings between probes).
    @MainActor
    func testControlsAcceptNearMissesAndReadAsButtons() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertEqual(next.label, "Next")
        XCTAssertGreaterThanOrEqual(next.frame.height, 44, "Next \(next.frame)")
        let skip = app.buttons["fst.first-run.skip"]
        XCTAssertEqual(skip.label, "Skip")
        XCTAssertGreaterThanOrEqual(skip.frame.height, 44, "Skip \(skip.frame)")
        XCTAssertGreaterThanOrEqual(skip.frame.width, 44, "Skip \(skip.frame)")
        XCTAssertEqual(app.navigationBars.buttons["fst.first-run.close"].label, "Close")

        let origin = app.coordinate(withNormalizedOffset: .zero)
        func tapNear(_ element: XCUIElement, _ offset: CGVector) {
            let frame = element.frame
            origin.withOffset(CGVector(dx: frame.midX + offset.dx, dy: frame.midY + offset.dy)).tap()
        }
        waitForPage(app, "1 of 6")
        for offset in Self.nearMisses {
            tapNear(app.buttons["fst.first-run.next"], offset)
            waitForPage(app, "2 of 6")
            let back = app.navigationBars.buttons["fst.first-run.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertEqual(back.label, "Back")
            tapNear(back, offset)
            waitForPage(app, "1 of 6")
        }

        // Skip and Close: each probe closes the guide; Settings reopens it.
        let probes: [(String, CGVector)] = Self.nearMisses.map { ("fst.first-run.skip", $0) }
            + Self.nearMisses.map { ("fst.first-run.close", $0) }
        for (index, probe) in probes.enumerated() {
            if index > 0 { reopenSongsGuide(app) }
            let control = app.buttons[probe.0]
            XCTAssertTrue(control.waitForExistence(timeout: 10), probe.0)
            tapNear(control, probe.1)
            let gone = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: app.buttons["fst.first-run.close"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed,
                           "\(probe.0) ignored a tap at (\(Int(probe.1.dx)), \(Int(probe.1.dy))) pt from its centre")
        }
    }

    /// Offsets from a control's centre, all inside a 44 × 44 pt square (as in
    /// `NavButtonHitRegionJourneyTests`).
    private static let nearMisses: [CGVector] = [
        CGVector(dx: -20, dy: 0), CGVector(dx: 20, dy: 0),
        CGVector(dx: 0, dy: -20), CGVector(dx: 0, dy: 20),
        CGVector(dx: -15, dy: -15), CGVector(dx: 15, dy: 15),
    ]

    /// Open the Songs guide again from Settings → First Run Guides.
    @MainActor
    private func reopenSongsGuide(_ app: XCUIApplication) {
        let replay = app.buttons["fst.settings.first-run.songs"]
        if !replay.exists {
            SongsUITestSupport.rootControl("Settings", app: app).tap()
        }
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        replay.tap()
    }

    /// Issue #25: slides that show a real sheet (Sort Songs, Filter Songs) draw its header
    /// inside the demo. The guide's bar keeps its own title and its single Close on every
    /// page, and VoiceOver finds no second Close.
    @MainActor
    func testEmbeddedSheetDemosKeepOneCloseAndTheGuideTitle() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.buttons["fst.first-run.next"].waitForExistence(timeout: 15))
        var page = 1
        while true {
            let bar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
            XCTAssertTrue(bar.staticTexts["Songs"].exists, "Page \(page) keeps the guide title")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Close'")).count, 1,
                           "Page \(page) has exactly one Close")
            XCTAssertFalse(app.buttons["fst.songs.sort.done"].exists, "Page \(page): no Sort sheet Close")
            XCTAssertFalse(app.buttons["fst.songs.filter.done"].exists, "Page \(page): no Filter sheet Close")
            if page == 2 { SongsUITestSupport.record(app, name: "first-run-sort-demo") }
            let next = app.buttons["fst.first-run.next"]
            guard next.exists else { break }
            next.tap()
            page += 1
            waitForPage(app, "\(page) of 6")
        }
        XCTAssertEqual(page, 6)
        app.buttons["fst.first-run.done"].tap()
        assertCarouselClosed(app)
    }

    /// Issue #4: the carousel carries the same native toolbar "Close" as the Profile search
    /// sheet (a navigation-bar button labelled "Close", not a small ✕ glyph), and tapping
    /// it closes the guide.
    @MainActor
    func testCloseIsNativeToolbarButton() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15), "Close lives in the sheet's navigation bar")
        XCTAssertEqual(close.label, "Close")
        XCTAssertTrue(close.isHittable)
        SongsUITestSupport.record(app, name: "first-run-native-close")
        close.tap()
        assertCarouselClosed(app)
    }

    /// Issue #24: like the app's other modals, each guide names its page in an inline
    /// navigation title beside Close: the launch Songs guide and a Settings replay alike.
    @MainActor
    func testGuideShowsPageTitleInNavigationBar() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let sheetBar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        XCTAssertTrue(sheetBar.staticTexts["Songs"].exists, "The Songs guide is titled Songs")
        close.tap()
        assertCarouselClosed(app)

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let replay = app.buttons["fst.settings.first-run.playerhistory"]
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        replay.tap()
        let replayClose = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(replayClose.waitForExistence(timeout: 10))
        let replayBar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        let title = replayBar.staticTexts["Score History"]
        XCTAssertTrue(title.exists, "A Settings replay is titled with its page")
        XCTAssertTrue(replayClose.isHittable, "The title leaves Close reachable")
        XCTAssertFalse(title.frame.intersects(replayClose.frame), "The title does not overlap Close")
        XCTAssertTrue(app.buttons["fst.first-run.next"].isHittable)
        SongsUITestSupport.record(app, name: "first-run-replay-title")
        replayClose.tap()
    }

    /// Swiping the carousel down dismisses it, like any sheet.
    @MainActor
    func testSwipeDownDismissesCarousel() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let window = app.windows.firstMatch
        // Start on the sheet's top edge (grabber / close row), not on the dimmed page.
        let top = close.frame.midY
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: top))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            )
        assertCarouselClosed(app)
    }

    /// Tapping the dimmed page above the carousel dismisses it (the web's overlay click).
    @MainActor
    func testTapOutsideDismissesCarousel() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "first-run-outside-area")
        // Below the status bar (a status-bar tap is the system's scroll-to-top) and above the
        // sheet's top edge.
        let window = app.windows.firstMatch
        let sheetTop = close.frame.minY - 40
        let y = min(130, sheetTop - 10)
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: y)).tap()
        assertCarouselClosed(app)
    }

    /// Only viewed pages count as seen: a Settings replay closed after two pages leaves the
    /// rest unseen, so the next launch's Songs guide starts at the third slide.
    @MainActor
    func testOnlyViewedPagesAreMarkedSeen() throws {
        continueAfterFailure = false
        let app = fixtureApp(mode: "on")
        app.launch()
        // A previous run may have left Songs slides unseen; close whatever shows.
        let close = app.buttons["fst.first-run.close"]
        if close.waitForExistence(timeout: 6) { close.tap() }
        XCTAssertTrue(songsRow(app, "fixture-pulse").waitForExistence(timeout: 15))

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let replay = app.buttons["fst.settings.first-run.songs"]
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        replay.tap()
        XCTAssertTrue(slide(app, titled: "Song List").waitForExistence(timeout: 10))
        app.buttons["fst.first-run.next"].tap()
        XCTAssertTrue(slide(app, titled: "Sort Songs").waitForExistence(timeout: 10))
        app.buttons["fst.first-run.close"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        app.terminate()

        let relaunched = fixtureApp(mode: "on")
        relaunched.launch()
        let navigation = slide(relaunched, titled: "Navigation")
        XCTAssertTrue(navigation.waitForExistence(timeout: 15), "Unviewed pages must show next time")
        XCTAssertTrue(navigation.isHittable, "The guide resumes at the first unviewed page")
        XCTAssertFalse(slide(relaunched, titled: "Song List").isHittable, "Viewed pages stay seen")
        SongsUITestSupport.record(relaunched, name: "first-run-resumes-unseen")
        relaunched.buttons["fst.first-run.close"].tap()
    }

    // MARK: - Guide title (issue #24, accessibility backfill #429)

    /// Issue #24 gave each guide an inline navigation title naming its page, and left
    /// VoiceOver's first focus to the system so that title is read first. On the launch Songs
    /// guide and the Leaderboards guide (the longest tab-root title), launched at the default
    /// size and again at the largest accessibility text size (AX5):
    /// - **name and role:** the title is a heading named exactly by its page, the bar's only text;
    ///   Close keeps its name, button role and a hittable target;
    /// - **reading order:** across the whole presented guide (the sheet's subtree of the
    ///   accessibility snapshot, not just its bar) the first elements read are the title, Close,
    ///   then the first slide (`modal-shell` R2), with nothing of the page behind the sheet
    ///   reachable; the bar itself reads title then Close, and the frames follow that order;
    /// - **text scaling:** the title's drawn glyphs (ink height in pixels,
    ///   `SongsUITestSupport.brightGlyphHeight`) grow from the default size to AX5 by at least
    ///   ``guideTitleMinimumGrowth``, and at both sizes the title reads back whole from its
    ///   capture (Vision, ``RecognizedText``: no ellipsis), wholly on screen and clear of Close;
    ///   the scoped AX5 audit (Dynamic Type, clipped text, hit region, descriptions, element
    ///   detection) finds nothing in the guide's bar.
    ///
    /// The title is the system inline navigation title (`FestivalModal`, `modal-shell` R2), whose
    /// size UIKit caps (measured 1.22× for "Leaderboards", 1.23× for "Songs"; bar titles offer the
    /// Large Content Viewer instead, `testing/apple/accessibility.md` `system-bar-title-size`),
    /// so its floor is ``guideTitleMinimumGrowth``, not the 1.35× rule for page text; Apple's
    /// Dynamic Type audit accepts it.
    /// It is navigation-bar chrome a macOS-hosted view cannot reproduce, so this journey is the
    /// evidence (`FirstRunGuideTitleTests` unit-tests every page's title;
    /// `FirstRunDemoSongsAccessibilityTests` the content order). HIG VoiceOver: "Use titles and
    /// headings to convey hierarchy"; HIG Accessibility: 44×44 pt default control size.
    @MainActor
    func testGuideTitleIsReadFirstAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        for (tab, title, firstSlide) in [
            ("songs", "Songs", "Song List"), ("leaderboards", "Leaderboards", "Global Rankings"),
        ] {
            let standard = launchGuide(tab: tab, contentSize: .large)
            let baseline = try assertGuideTitle(standard, title: title, firstSlide: firstSlide, size: "default")
            standard.terminate()

            let app = launchGuide(tab: tab, contentSize: .accessibilityExtraExtraExtraLarge)
            let enlarged = try assertGuideTitle(app, title: title, firstSlide: firstSlide, size: "AX5")
            let ratio = enlarged / baseline
            let growth = XCTAttachment(string: String(format: "%@ %.0f → %.0f px (%.2f×)", title, baseline, enlarged, ratio))
            growth.name = "first-run-title-growth-\(tab)"
            growth.lifetime = .keepAlways
            add(growth)
            XCTAssertGreaterThanOrEqual(ratio, Self.guideTitleMinimumGrowth,
                                        "'\(title)' glyphs grow at AX5: \(enlarged) vs \(baseline) px")
            try auditGuideBar(app, title: title)
            app.terminate()
        }
    }

    /// Minimum growth of the guide's title glyphs from the default size to AX5.
    ///
    /// UIKit caps the inline navigation title (`system-bar-title-size`): its ink measured
    /// 36 → 44 px ("Leaderboards") and 43 → 53 px ("Songs") on an iPhone 17 Pro, 1.22–1.23×.
    /// The floor fails a title drawn at a fixed size (1.0×) with room for a pixel of rounding.
    static let guideTitleMinimumGrowth: CGFloat = RecognizedText.minimumBarTitleGrowth

    /// Launch the fixture app at `contentSize` with the guide of `tab` forced open.
    ///
    /// - Parameters:
    ///   - tab: The `FST_DEBUG_TAB` whose guide opens.
    ///   - contentSize: The preferred content size category.
    /// - Returns: The launched app.
    @MainActor
    private func launchGuide(tab: String, contentSize: UIContentSizeCategory) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIRST_RUN_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": "force",
            "FST_DEBUG_TAB": tab,
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        app.launch()
        return app
    }

    /// The title rules of ``testGuideTitleIsReadFirstAtLargestText()`` on one open guide.
    ///
    /// - Parameters:
    ///   - app: The launched app showing a guide.
    ///   - title: The page title the guide must carry.
    ///   - firstSlide: Title of the guide's first slide.
    ///   - size: The launch's text size, for messages and attachments.
    /// - Returns: The title's ink height in pixels.
    /// - Throws: An unreadable snapshot or an unrecognized title.
    @MainActor
    private func assertGuideTitle(
        _ app: XCUIApplication, title: String, firstSlide: String, size: String
    ) throws -> CGFloat {
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: FestivalApp.budget(20)), "\(title) guide opens (\(size))")
        // Next, or Done for a one-slide guide (Leaderboards without a player).
        let next = app.buttons.matching(
            NSPredicate(format: "identifier IN %@", ["fst.first-run.next", "fst.first-run.done"])
        ).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: FestivalApp.budget(10)), "\(title) guide shows Next or Done")
        let bar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        let heading = bar.staticTexts[title]
        XCTAssertTrue(heading.waitForExistence(timeout: FestivalApp.budget(5)), "\(title) guide is titled \(title)")
        let slide = slide(app, titled: firstSlide)
        XCTAssertTrue(slide.waitForExistence(timeout: FestivalApp.budget(10)), "\(firstSlide) slide")
        Thread.sleep(forTimeInterval: FestivalApp.budget(1))
        SongsUITestSupport.record(app, name: "first-run-title-\(title.lowercased())-\(size)")

        // Name and role: the bar's only text is the page name, read as a heading.
        let nodes = Self.flatten(try bar.snapshot()).map(\.node)
        let texts = nodes.filter { $0.elementType == .staticText }
        XCTAssertEqual(texts.map(\.label), [title], "the guide's bar reads only its title (\(size))")
        if let text = texts.first, let traits = Self.traits(text) {
            XCTAssertNotEqual(traits & UIAccessibilityTraits.header.rawValue, 0, "'\(title)' is a heading (\(size))")
        }
        let readable = nodes.filter { $0.elementType == .staticText || $0.elementType == .button }
            .map { $0.identifier.isEmpty ? $0.label : $0.identifier }
        XCTAssertEqual(readable, [title, "fst.first-run.close"], "bar reads title then Close (\(size))")

        try assertGuideReadingOrder(app, title: title, firstSlide: firstSlide, size: size)

        // Placement: wholly on screen, before Close, above the slide and its controls.
        let window = app.windows.firstMatch.frame
        let frame = heading.frame
        XCTAssertTrue(window.contains(frame), "'\(title)' wholly on screen: \(frame) (\(size))")
        XCTAssertLessThanOrEqual(frame.maxX, close.frame.minX, "'\(title)' ends before Close (\(size))")
        XCTAssertFalse(frame.intersects(close.frame), "'\(title)' does not overlap Close (\(size))")
        XCTAssertLessThanOrEqual(frame.maxY, slide.frame.minY + 0.5,
                                 "'\(title)' \(frame) above the slide \(slide.frame) (\(size))")
        XCTAssertLessThan(frame.maxY, next.frame.minY, "'\(title)' above \(next.label) (\(size))")

        // Text scaling: the drawn title reads back whole; the caller compares its ink height.
        let reading = RecognizedText.recognize(heading, label: title, frame: frame)
        XCTAssertTrue(RecognizedText.showsWhole(title, in: reading.text),
                      "'\(title)' reads back whole at \(size): '\(reading.text ?? "nil")'")
        let height = CGFloat(try SongsUITestSupport.brightGlyphHeight(in: heading))
        XCTAssertGreaterThan(height, 8, "'\(title)' has measurable ink at \(size)")

        // Close: a named, hittable button beside the title. Its frame reads about 35 pt but
        // the system expands its hit region (near-miss taps:
        // `testControlsAcceptNearMissesAndReadAsButtons`); the AX5 audit's hit-region check
        // covers it.
        XCTAssertEqual(close.label, "Close")
        XCTAssertEqual(close.elementType, .button)
        XCTAssertTrue(close.isHittable, "Close is reachable (\(size))")
        return height
    }

    /// The whole presented guide reads its title, then Close, then the first slide.
    ///
    /// The app snapshot follows the accessibility element order VoiceOver navigates. Across
    /// the whole app (not just the guide's bar) the first readable elements must be the title,
    /// Close and the slide, in that order. The guide is the smallest subtree holding its
    /// navigation bar and its first slide; nothing readable may lie outside it except the
    /// system sheet grabber (the sheet's own "Sheet Grabber" button, which UIKit places ahead of
    /// the sheet's content in every grabber sheet; it is sheet chrome, not body), so the page
    /// behind the modal sheet is out of the tree.
    ///
    /// - Parameters:
    ///   - app: The launched app showing a guide.
    ///   - title: The page title the guide must carry.
    ///   - firstSlide: Title of the guide's first slide.
    ///   - size: The launch's text size, for messages.
    /// - Throws: An unreadable snapshot.
    @MainActor
    private func assertGuideReadingOrder(
        _ app: XCUIApplication, title: String, firstSlide: String, size: String
    ) throws {
        let all = Self.flatten(try app.snapshot())
        func name(_ node: XCUIElementSnapshot) -> String {
            node.identifier.isEmpty ? node.label : node.identifier
        }
        func isGrabber(_ node: XCUIElementSnapshot) -> Bool {
            node.elementType == .button && node.label == "Sheet Grabber"
        }
        let titleNode = all.first { entry in
            entry.node.elementType == .staticText && entry.node.label == title
                && all.contains { $0.node.elementType == .navigationBar && entry.path.starts(with: $0.path) }
        }
        let slideNode = all.first { $0.node.label.hasPrefix("\(firstSlide). ") }
        let titlePath = try XCTUnwrap(titleNode?.path, "'\(title)' in the app snapshot (\(size))")
        let slidePath = try XCTUnwrap(slideNode?.path, "'\(firstSlide)' slide in the app snapshot (\(size))")
        let guide = Array(zip(titlePath, slidePath).prefix { $0 == $1 }.map(\.0))
        // A readable element is one VoiceOver stops on: text, a button, or the combined slide.
        // Nodes inside the slide are combined into it, so VoiceOver reads them with the slide.
        let readable = all.filter { entry in
            (entry.node.elementType == .staticText || entry.node.elementType == .button
                || entry.node.label.hasPrefix("\(firstSlide). ")) && !name(entry.node).isEmpty
                && !(entry.path.count > slidePath.count && entry.path.starts(with: slidePath))
        }
        let attachment = XCTAttachment(string: readable.map { entry in
            let inGuide = entry.path.count > guide.count && entry.path.starts(with: guide)
            return "\(inGuide ? "guide" : "outside") \(entry.node.elementType.rawValue) \(name(entry.node))"
        }.joined(separator: "\n"))
        attachment.name = "first-run-\(title.lowercased())-\(size)-reading-order"
        attachment.lifetime = .keepAlways
        add(attachment)

        let order = readable.filter { !isGrabber($0.node) }.map { name($0.node) }
        XCTAssertEqual(Array(order.prefix(3)), [title, "fst.first-run.close", slideNode?.node.label ?? firstSlide],
                       "the presented guide reads its title, then Close, then the slide (\(size)): \(order)")
        let outside = readable.filter { entry in
            !(entry.path.count > guide.count && entry.path.starts(with: guide)) && !isGrabber(entry.node)
        }.map { name($0.node) }
        XCTAssertEqual(outside, [], "the page behind the guide is out of the accessibility tree (\(size))")
    }

    /// Audit the guide's bar at AX5: the title and Close, and anything drawn in the bar.
    ///
    /// - Parameters:
    ///   - app: The launched app showing a guide at AX5.
    ///   - title: The page title the guide carries.
    /// - Throws: A failed audit run.
    @MainActor
    private func auditGuideBar(_ app: XCUIApplication, title: String) throws {
        let bar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription, .elementDetection],
            name: "\(title) guide bar", reset: { issues = [] }
        ) { issue in
            guard let element = issue.element else { return true }
            let frame = element.frame
            guard element.identifier == "fst.first-run.close" || element.label == title
                || frame.intersects(bar.frame) else { return true }
            issues.append("\(issue.compactDescription): #\(element.identifier) '\(element.label)' \(frame)")
            return true
        }
        XCTAssertEqual(issues, [], "Open audit issues in the \(title) guide's bar")
    }

    /// Every node of a snapshot in depth-first (accessibility) order, with its child-index path.
    ///
    /// - Parameter root: The snapshot root.
    /// - Returns: Nodes in order; a node's path is a prefix of its descendants' paths.
    @MainActor
    private static func flatten(_ root: XCUIElementSnapshot) -> [(node: XCUIElementSnapshot, path: [Int])] {
        var nodes: [(node: XCUIElementSnapshot, path: [Int])] = []
        func visit(_ node: XCUIElementSnapshot, _ path: [Int]) {
            nodes.append((node, path))
            for (index, child) in node.children.enumerated() { visit(child, path + [index]) }
        }
        visit(root, [])
        return nodes
    }

    /// The snapshot's accessibility traits, when readable (as `WhatsNewAccessibilityJourneyTests`).
    @MainActor
    private static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
    }

    // MARK: - Song demos (issue #26, accessibility backfill #401)

    /// Issue #26: the Songs list demo shows real catalogue songs (redacted placeholders while
    /// they load), as a decorative picture. At the largest accessibility text size (AX5) the
    /// slide is still one element named by its title and description only: no placeholder,
    /// song title or song row from the demo is reachable, the slide reads above the page dots,
    /// Next and Skip, both actions keep 44 pt targets on screen, and the system audit finds no
    /// clipped text, small hit regions or unnamed elements in the guide. HIG VoiceOver:
    /// "Exclude purely decorative images that convey no useful or actionable information".
    /// Hosted counterpart: `FirstRunDemoSongsAccessibilityTests` (every song demo, both states).
    @MainActor
    func testSongDemoSlideAccessibleAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIRST_RUN_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": "force",
        ])
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let title = "Song List"
        let description = "Browse and search the entire Festival library. Tap a song to see leaderboards and more details."
        let slide = slide(app, titled: title)
        XCTAssertTrue(slide.waitForExistence(timeout: FestivalApp.budget(20)), "Song List slide")
        // The catalogue answers within a moment on the loopback fixture; then the demo's rows
        // are real songs.
        let songRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'fst.songs.row.'")).firstMatch
        _ = songRow.waitForExistence(timeout: FestivalApp.budget(5))
        Thread.sleep(forTimeInterval: FestivalApp.budget(2))
        XCTAssertEqual(slide.label, "\(title). \(description)", "The slide reads its title and description only")
        SongsUITestSupport.record(app, name: "first-run-song-demo-ax5")

        try assertSongDemoSlideAccessible(app, slide: slide)
    }

    // MARK: - Demo data swaps (issue #27, accessibility backfill #402)

    /// Issue #27: with motion on, the Songs list demo swaps in different catalogue songs every
    /// 5 s with a 400 ms fade. At AX5 a swap must not change what VoiceOver reads: the slide
    /// stays one element named by its title and description, no swapped-in song, placeholder
    /// or loading indicator becomes reachable, the reading order and 44 pt targets hold, and
    /// the system audit stays clean. The demo picture itself must change (rotation is live:
    /// `FST_DEBUG_STILL_BACKGROUND=0`, which otherwise freezes it for XCUITest).
    /// HIG Accessibility: "When Reduce Motion is on, reduce automatic and repetitive
    /// animation"; VoiceOver: "Exclude purely decorative images". Hosted counterpart:
    /// `FirstRunDemoRotationAccessibilityTests` (all 12 rotating demos, Reduce Motion).
    @MainActor
    func testSongDemoRotationKeepsSlideAccessibleAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIRST_RUN_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": "force",
            "FST_DEBUG_STILL_BACKGROUND": "0",
        ])
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let title = "Song List"
        let description = "Browse and search the entire Festival library. Tap a song to see leaderboards and more details."
        let slide = slide(app, titled: title)
        XCTAssertTrue(slide.waitForExistence(timeout: FestivalApp.budget(20)), "Song List slide")
        let songRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'fst.songs.row.'")).firstMatch
        _ = songRow.waitForExistence(timeout: FestivalApp.budget(5))
        Thread.sleep(forTimeInterval: FestivalApp.budget(1))
        XCTAssertEqual(slide.label, "\(title). \(description)", "The slide reads its title and description only")
        let before = slide.screenshot().pngRepresentation

        // Past at least one 5 s swap and its 400 ms fade out and in (longer in a VM).
        Thread.sleep(forTimeInterval: FestivalApp.budget(6.5))
        XCTAssertNotEqual(slide.screenshot().pngRepresentation, before, "The demo swapped its songs (rotation live)")
        XCTAssertEqual(slide.label, "\(title). \(description)", "A swap leaves the slide's name unchanged")
        let busy = app.activityIndicators.allElementsBoundByIndex.filter { $0.exists && slide.frame.intersects($0.frame) }
        XCTAssertEqual(busy.map(\.label), [], "No loading indicator from the swapped-in artwork is reachable")
        SongsUITestSupport.record(app, name: "first-run-song-demo-rotation-ax5")
        try assertSongDemoSlideAccessible(app, slide: slide)
    }

    /// The guide's AX5 checks for the Songs list demo slide: no demo song or placeholder is
    /// reachable, the slide reads above the page dots, Next and Skip, both actions keep 44 pt
    /// on-screen targets, and the scoped system audit finds nothing.
    ///
    /// - Parameters:
    ///   - app: The running app, showing the Song List slide.
    ///   - slide: The slide element.
    @MainActor
    private func assertSongDemoSlideAccessible(_ app: XCUIApplication, slide: XCUIElement) throws {
        // Nothing the guide exposes is a demo song or a placeholder.
        let window = app.windows.firstMatch.frame
        var reachable: [XCUIElementSnapshot] = []
        func collect(_ node: XCUIElementSnapshot) {
            reachable.append(node)
            node.children.forEach(collect)
        }
        collect(try app.snapshot())
        let sheetTop = slide.frame.minY
        let leaks = reachable.filter { node in
            node.label.localizedCaseInsensitiveContains("placeholder")
                || (node.identifier.hasPrefix("fst.songs.row.") && node.frame.minY >= sheetTop - 1
                    && window.intersects(node.frame))
        }.map { "\($0.elementType.rawValue) '\($0.label)' #\($0.identifier) \($0.frame)" }
        XCTAssertEqual(leaks, [], "Demo songs or placeholders reachable:\n\(app.debugDescription)")

        // Reading order follows the layout: slide, page dots, Next, Skip.
        let dots = app.descendants(matching: .any).matching(identifier: "fst.first-run.dots").firstMatch
        let next = app.buttons["fst.first-run.next"]
        let skip = app.buttons["fst.first-run.skip"]
        XCTAssertTrue(dots.exists && next.exists && skip.exists)
        XCTAssertEqual(dots.label, "Page")
        XCTAssertEqual(dots.value as? String, "1 of 6")
        XCTAssertLessThanOrEqual(slide.frame.minY, dots.frame.minY, "slide \(slide.frame) above dots \(dots.frame)")
        XCTAssertLessThan(dots.frame.minY, next.frame.minY, "dots above Next")
        XCTAssertLessThan(next.frame.minY, skip.frame.minY, "Next above Skip")

        // Targets: 44 pt and on screen at AX5 (the sheet draws about 0.96× scaled).
        for control in [next, skip] {
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 * 0.96, "\(control.identifier) \(control.frame)")
            XCTAssertTrue(window.contains(control.frame), "\(control.identifier) on screen: \(control.frame)")
            XCTAssertTrue(control.isHittable, control.identifier)
        }

        var issues: [String] = []
        var behindSheet = 0
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion, .sufficientElementDescription, .elementDetection]) { issue in
            let element = issue.element
            if UIDevice.current.userInterfaceIdiom == .pad, element == nil, issue.auditType == .elementDetection {
                // Proved below: the iPad form sheet leaves the dimmed page visible.
                behindSheet += 1
                return true
            }
            issues.append("\(issue.compactDescription): #\(element?.identifier ?? "") '\(element?.label ?? "")' \(element?.frame ?? .zero)")
            return true
        }
        XCTAssertEqual(issues, [], "Open audit issues")
        if behindSheet > 0 {
            try assertUnnamedTextIsBehindSheet(app, slide: slide, issues: behindSheet)
        }
    }

    /// Prove that element-less "Potentially inaccessible text" on iPad is the page behind the
    /// guide's form sheet (`unattributed-text-behind-sheet`, `testing/apple/accessibility.md`):
    /// the sheet is narrower than the window, so the dimmed Songs page shows around it and is
    /// correctly outside the tree while the sheet is modal. Every line Vision reads inside the
    /// sheet must be named by an element, or lie in the slide, whose one element covers its
    /// decorative demo; and some text must show outside the sheet for the audit to have meant.
    ///
    /// - Parameters:
    ///   - app: The guide at rest, as the audit left it.
    ///   - slide: The slide element.
    ///   - issues: How many element-less issues the audit reported.
    /// - Throws: A missing snapshot.
    @MainActor
    private func assertUnnamedTextIsBehindSheet(_ app: XCUIApplication, slide: XCUIElement, issues: Int) throws {
        let window = app.windows.firstMatch.frame
        let nodes = Self.flatten(try app.snapshot()).map(\.node)
        // The slide scrolls at AX5, so its frame can run past the sheet: Close (top) and
        // Skip (bottom) bound it instead.
        let parts = [app.buttons["fst.first-run.close"].frame, app.buttons["fst.first-run.skip"].frame]
        // The sheet: the smallest container holding Close and Skip.
        let sheet = nodes.map(\.frame)
            .filter { frame in parts.allSatisfy { frame.insetBy(dx: -1, dy: -1).contains($0) } }
            .min { $0.width * $0.height < $1.width * $1.height }
        let sheetFrame = try XCTUnwrap(sheet, "No container holds the guide's Close and Skip")
        XCTAssertLessThan(sheetFrame.width, window.width - 40, "\(issues) unnamed texts, but the sheet \(sheetFrame) fills \(window)")
        let names = nodes.flatMap { [$0.label, ($0.value as? String) ?? "", $0.title] }.filter { !$0.isEmpty }
        let lines = RecognizedText.lines(in: app.screenshot())
        let centre = { (frame: CGRect) in CGPoint(x: frame.midX + window.minX, y: frame.midY + window.minY) }
        let unnamed = lines.filter { line in
            let point = centre(line.frame)
            guard sheetFrame.contains(point), !slide.frame.contains(point),
                  line.text.filter({ $0.isLetter || $0.isNumber }).count >= 3 else { return false }
            return !names.contains { RecognizedText.showsWhole(line.text, in: $0) }
        }.map(\.text)
        let behind = lines.filter { !sheetFrame.contains(centre($0.frame)) }.map(\.text)
        XCTContext.runActivity(
            named: "\(issues) unnamed texts; sheet \(sheetFrame); behind it: \(behind.prefix(12))"
        ) { _ in }
        XCTAssertEqual(unnamed, [], "Text inside the sheet \(sheetFrame) that no element names")
        XCTAssertFalse(behind.isEmpty, "\(issues) unnamed texts, but no text shows outside the sheet \(sheetFrame)")
    }

    // MARK: - Real-control demos (issue #380, accessibility backfill #498)

    /// The Songs guide without a player (shop highlighting on), in order: title and
    /// description of each slide. Sort Songs and Navigation show #380's real controls (the
    /// Songs Sort sheet and a system tab bar), the three Item Shop slides real Songs rows.
    static let songsGuideSlides: [(title: String, description: String)] = [
        ("Song List", "Browse and search the entire Festival library. Tap a song to see leaderboards and more details."),
        ("Sort Songs", "Tap the sort button to reorder by default song data. Select a player profile to narrow it down even more."),
        ("Navigation", "Use the bottom tabs to navigate the app. Select a player profile to see even more options."),
        ("Item Shop Highlights", "Songs currently available in the Item Shop are highlighted with a pulsing glow so you can spot them at a glance."),
        ("New in the Item Shop", "New songs in Festival that are in the item shop for the first time pulse gold, while regular shop songs keep the green highlight."),
        ("Leaving Tomorrow", "Songs about to leave the Item Shop pulse red so you know which ones to grab before they're gone."),
    ]

    /// Issue #380 rebuilt the demos from the pages' real controls (the Sort sheet with its
    /// toggles and Apply, a real tab bar with five tabs) and made Skip a borderless accent
    /// button. At AX5, on every page of the Songs guide: the slide is one element named only by
    /// its title and description; no button, toggle, tab, cell or text from its demo is
    /// reachable; VoiceOver reads the slide, the page dots, Next (Done on the last page), then
    /// Skip; Next, Done and Skip are named buttons with on-screen 44 pt targets; and Back from
    /// page two on is a named button. The real-control pages and the last page pass the
    /// system audit (clipped text, hit regions, descriptions, element detection, contrast)
    /// with no issue accepted. HIG VoiceOver: "Exclude purely decorative images that convey no useful or
    /// actionable information"; HIG Accessibility: 44×44 pt default control size. Hosted
    /// counterpart: `FirstRunNativeDemosAccessibilityTests` (all 42 demos, Reduce Motion,
    /// hard edges, Skip contrast).
    @MainActor
    func testSongsGuideRealControlDemosAccessibleAtLargestText() throws {
        try assertSongsGuideAccessibleAtLargestText(duoWindow: nil)
    }

    /// ``testSongsGuideRealControlDemosAccessibleAtLargestText()`` in the simulated folded
    /// iPhone Duo window (the narrow outer display's sheet).
    @MainActor
    func testSongsGuideRealControlDemosAccessibleAtLargestTextDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertSongsGuideAccessibleAtLargestText(duoWindow: "folded")
    }

    /// Walk the Songs guide at AX5 with the checks of
    /// ``testSongsGuideRealControlDemosAccessibleAtLargestText()``.
    ///
    /// - Parameter duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Throws: An unreadable snapshot or a failed audit run.
    @MainActor
    private func assertSongsGuideAccessibleAtLargestText(duoWindow: String?) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var environment = [
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIRST_RUN_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": "force",
        ]
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        }
        let app = FestivalApp.makeApp(environment)
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let form = duoWindow.map { "duo-\($0)" } ?? "device"
        if let duoWindow {
            let marker = app.staticTexts["fst.shell.debug.duo-window"]
            XCTAssertTrue(marker.waitForExistence(timeout: FestivalApp.budget(20)), "Duo window marker")
            XCTAssertTrue(marker.label.hasPrefix("\(duoWindow) "), "simulated \(duoWindow) window: '\(marker.label)'")
        }

        let slides = Self.songsGuideSlides
        for (index, expected) in slides.enumerated() {
            let page = index + 1
            let last = page == slides.count
            let slide = slide(app, titled: expected.title)
            XCTAssertTrue(slide.waitForExistence(timeout: FestivalApp.budget(20)), "'\(expected.title)' slide (\(form))")
            waitForPage(app, "\(page) of \(slides.count)")
            // Past the entrance cascade and the title and description fade.
            Thread.sleep(forTimeInterval: FestivalApp.budget(1.5))
            XCTAssertEqual(slide.label, "\(expected.title). \(expected.description)",
                           "page \(page) reads its title and description only (\(form))")
            try assertGuidePageAccessible(app, slide: slide, page: page, last: last, form: form)
            if [2, 3, slides.count].contains(page) {
                SongsUITestSupport.record(app, name: "first-run-songs-\(page)-ax5-\(form)")
                try auditGuidePage(app, title: expected.title, form: form)
            }
            if !last {
                app.buttons["fst.first-run.next"].tap()
            }
        }
        app.buttons["fst.first-run.done"].tap()
        // Not `assertCarouselClosed`: the large catalogue's AX5 list doesn't reach `fixture-pulse`.
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["fst.first-run.close"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: FestivalApp.budget(10)), .completed, "Done closes the guide (\(form))")
        let songRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'fst.songs.row.'")).firstMatch
        XCTAssertTrue(songRow.waitForExistence(timeout: FestivalApp.budget(15)), "Songs shows after Done (\(form))")
    }

    /// One guide page's AX5 checks: no demo element is reachable, reading order, named
    /// 44 pt actions and Back.
    ///
    /// - Parameters:
    ///   - app: The running app showing the page.
    ///   - slide: The page's slide element.
    ///   - page: One-based page number.
    ///   - last: Whether this is the last page (Done, no Skip).
    ///   - form: Device form, for messages.
    /// - Throws: An unreadable snapshot.
    @MainActor
    private func assertGuidePageAccessible(
        _ app: XCUIApplication, slide: XCUIElement, page: Int, last: Bool, form: String
    ) throws {
        let all = Self.flatten(try app.snapshot())
        let slideFrame = slide.frame
        let window = app.windows.firstMatch.frame
        func name(_ node: XCUIElementSnapshot) -> String {
            node.identifier.isEmpty ? node.label : node.identifier
        }
        let bars = all.filter { $0.node.elementType == .navigationBar }.map(\.path)
        let slidePath = all.first { $0.node.label == slide.label }?.path
        // Anything VoiceOver could stop on inside the slide's on-screen area, other than the
        // slide itself and the guide's own chrome, belongs to the demo. The paged carousel's
        // unnamed cell around the slide is a container, not a stop.
        let readableTypes: Set<XCUIElement.ElementType> = [
            .button, .switch, .toggle, .tab, .tabBar, .cell, .staticText, .image, .link, .slider,
            .segmentedControl, .menuButton, .popUpButton, .searchField, .textField, .picker, .stepper,
        ]
        let visibleSlide = slideFrame.intersection(window)
        let leaks = all.filter { entry in
            let node = entry.node
            guard readableTypes.contains(node.elementType), node.frame.intersects(visibleSlide),
                  !node.identifier.hasPrefix("fst.first-run."), node.label != "Sheet Grabber",
                  entry.path != slidePath,
                  !(node.label.isEmpty && node.identifier.isEmpty && slidePath.map { $0.starts(with: entry.path) } == true),
                  !bars.contains(where: { entry.path.starts(with: $0) }) else { return false }
            return true
        }.map { "\($0.node.elementType.rawValue) '\($0.node.label)' #\($0.node.identifier) \($0.node.frame)" }
        XCTAssertEqual(leaks, [], "page \(page): the demo's controls reach VoiceOver (\(form))")

        // Reading order: slide, dots, Next or Done, then Skip while pages remain.
        let action = last ? "fst.first-run.done" : "fst.first-run.next"
        let order = all.map { name($0.node) }
        let slideIndex = try XCTUnwrap(all.firstIndex { $0.path == slidePath }, "slide in the snapshot (\(form))")
        let dotsIndex = try XCTUnwrap(order.firstIndex(of: "fst.first-run.dots"), "dots (\(form))")
        let actionIndex = try XCTUnwrap(order.firstIndex(of: action), "\(action) (\(form))")
        XCTAssertLessThan(slideIndex, dotsIndex, "page \(page): the slide reads before the dots (\(form))")
        XCTAssertLessThan(dotsIndex, actionIndex, "page \(page): the dots read before \(action) (\(form))")
        let skip = app.buttons["fst.first-run.skip"]
        if last {
            XCTAssertFalse(skip.exists, "the last page offers no Skip (\(form))")
        } else {
            let skipIndex = try XCTUnwrap(order.firstIndex(of: "fst.first-run.skip"), "Skip (\(form))")
            XCTAssertLessThan(actionIndex, skipIndex, "page \(page): Next reads before Skip (\(form))")
        }

        // Named buttons with 44 pt on-screen targets (the sheet draws about 0.96× scaled).
        var controls = [(app.buttons[action], last ? "Done" : "Next")]
        if !last { controls.append((skip, "Skip")) }
        for (control, label) in controls {
            XCTAssertEqual(control.label, label, "page \(page) \(control.identifier) (\(form))")
            XCTAssertEqual(control.elementType, .button, "page \(page): \(label) is a button (\(form))")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 * 0.96, "page \(page) \(label) \(control.frame) (\(form))")
            XCTAssertTrue(window.contains(control.frame), "page \(page) \(label) on screen: \(control.frame) (\(form))")
            XCTAssertTrue(control.isHittable, "page \(page) \(label) hittable (\(form))")
        }
        let back = app.buttons["fst.first-run.back"]
        if page == 1 {
            XCTAssertFalse(back.exists, "no Back on the first page (\(form))")
        } else {
            XCTAssertEqual(back.label, "Back", "page \(page) Back (\(form))")
            XCTAssertTrue(back.isHittable, "page \(page) Back hittable (\(form))")
        }
    }

    /// Audit one guide page at AX5: clipped text, hit regions, descriptions, element detection
    /// and contrast (Skip's borderless accent text, Next, Done), with no issue accepted.
    ///
    /// - Parameters:
    ///   - app: The running app showing the page.
    ///   - title: The page's slide title.
    ///   - form: Device form, for messages.
    /// - Throws: A failed audit run.
    @MainActor
    private func auditGuidePage(_ app: XCUIApplication, title: String, form: String) throws {
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.textClipped, .hitRegion, .sufficientElementDescription, .elementDetection, .contrast],
            name: "\(title) guide page (\(form))", reset: { issues = [] }
        ) { issue in
            let element = issue.element
            issues.append("\(issue.auditType.rawValue) \(issue.compactDescription): #\(element?.identifier ?? "") '\(element?.label ?? "")' \(element?.frame ?? .zero)")
            return true
        }
        XCTAssertEqual(issues, [], "Open audit issues on '\(title)' (\(form))")
    }
}
