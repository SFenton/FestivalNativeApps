import UIKit
import XCTest

/// The Settings lane's pages in the UIKit port (`UIKit/Features/Settings`) and the SwiftUI
/// app's: the Settings page's switches and link rows, Licenses, the Privacy Policy sheet, the
/// First Run replay from Settings and the Notifications sheet, each with identifiers, labels,
/// roles and 44 pt targets, and the page at AX5 with a scoped accessibility audit. They run on
/// both apps (the SwiftUI app is the parity reference).
///
/// Run with `python3 tools/ios_sim.py uitest --app uikit --only UKSettingsJourneyTests --batch-size 3`.
/// Needs `tools/mock_service.py --port 8765`.
final class UKSettingsJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ env: [String: String] = [:], largeText: Bool = false, arguments: [String] = []) -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": SongsUITestSupport.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "settings",
        ]
        environment.merge(env) { $1 }
        let app = FestivalApp.makeApp(environment)
        app.launchArguments += arguments
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
        }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    // MARK: - Settings page

    /// Settings uses the shared title scrim without adding a focus stop or covering its first switch.
    @MainActor
    func testSettingsTitleScrimKeepsFirstSwitchReachable() throws {
        let app = launch([
            "FST_DEBUG_FLAT_BACKDROP": "1", "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a phone or the Duo cover")
        let toggle = app.switches["fst.settings.show-instrument-icons"]
        XCTAssertTrue(toggle.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(toggle.isHittable && toggle.isEnabled)
        XCTAssertTrue(toggle.label.hasPrefix("Show Instrument Icons"))
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        XCTAssertEqual(toggle.value as? String, "1")
        try SongsUITestSupport.assertPageScrim(in: app, window: window)

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }

    /// Adding the available Feedback actions keeps an open CHOpt choice and its selected state.
    @MainActor
    func testFeedbackAvailabilityPreservesOpenPathChoice() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["FST_SETTINGS_FEEDBACK_TEST"] == "1",
            "Requires the dedicated Feedback availability fixture"
        )
        let origin = try XCTUnwrap(URL(string: SongsUITestSupport.fixtureURL))
        try XCTSkipUnless(origin.scheme == "http" && origin.host == "127.0.0.1" && origin.port != nil)

        struct Capability: Decodable {
            let features: String
            let lastFeatures: Bool?
        }
        func fixture(_ query: String = "") async throws -> Capability {
            let url = try XCTUnwrap(URL(string: "/__feedback__/mode\(query)", relativeTo: origin))
            let (data, response) = try await URLSession.shared.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try JSONDecoder().decode(Capability.self, from: data)
        }

        let off = try await fixture("?features=off&reset=1")
        XCTAssertEqual(off.features, "off")
        let app = launch([
            "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ], arguments: [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-fst.accessibility.reduceMotion", "YES", "-fst.settings.enableVisualOrder", "NO",
            "-fst.settings.pathDefaultView", "image",
        ])
        defer { app.terminate() }
        let choiceID = "fst.settings.path-default-view"
        let choice = element(app, choiceID)
        let image = app.buttons["\(choiceID).image"]
        XCTAssertTrue(FeedbackJourney.scrollTo(choice, in: app))
        choice.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        XCTAssertTrue(image.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertTrue(image.isSelected)
        let report = FeedbackJourney.row("bug", in: app)
        XCTAssertFalse(report.exists)
        let read = try await fixture()
        XCTAssertEqual(read.lastFeatures, false)

        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: FestivalApp.budget(10)))
        let on = try await fixture("?features=on&reset=1")
        XCTAssertEqual(on.features, "on")
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        XCTAssertTrue(report.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertTrue(FeedbackJourney.row("feature", in: app).exists)
        XCTAssertEqual(choice.value as? String, "Image, Expanded")
        XCTAssertTrue(image.exists && image.isSelected)
        XCTAssertTrue(FeedbackJourney.scrollTo(image, in: app))
        SongsUITestSupport.record(app, name: "settings-chopt-choice-after-feedback-available")
    }

    /// Settings separators align with the switch labels, including the row revealed by a switch.
    @MainActor
    func testSettingsSeparatorsStartAtRowContent() throws {
        let app = launch([
            "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off", "FST_DEBUG_FLAT_BACKDROP": "1",
        ], arguments: [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-fst.accessibility.reduceMotion", "YES",
        ])
        defer { app.terminate() }
        let window = app.windows.firstMatch
        let bounds = window.frame
        try XCTSkipUnless(bounds.width < 500 && bounds.height > bounds.width, "Requires a phone or the Duo cover")

        let icons = app.switches["fst.settings.show-instrument-icons"]
        XCTAssertTrue(icons.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(icons.isHittable && icons.isEnabled)
        try assertInsetSeparator(after: icons, in: window)
        SongsUITestSupport.record(app, name: "settings-separator-at-top")

        let filter = app.switches["fst.settings.filter-invalid-scores"]
        let leeway = app.sliders["fst.settings.leeway"]
        XCTAssertTrue(filter.exists)
        positionWrappedSetting(filter, in: app)
        XCTAssertTrue(filter.isHittable && filter.isEnabled)
        XCTAssertTrue(filter.label.hasPrefix("Filter Invalid Scores"))
        XCTAssertGreaterThanOrEqual(filter.frame.height, 44)
        let original = try XCTUnwrap(filter.value as? String)
        defer { SongsUITestSupport.setSwitch(filter, to: original) }
        SongsUITestSupport.setSwitch(filter, to: "0")
        XCTAssertTrue(leeway.waitForNonExistence(timeout: FestivalApp.budget(5)))
        SongsUITestSupport.setSwitch(filter, to: "1")
        XCTAssertTrue(leeway.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(leeway.label, "Max Score Leeway")
        XCTAssertGreaterThan(leeway.frame.minY, filter.frame.maxY)
        try assertInsetSeparator(after: filter, in: window)
        SongsUITestSupport.record(app, name: "settings-separator-with-leeway")
    }

    /// A one-point band must be visible after the padding but absent in the leading gutter.
    @MainActor
    private func assertInsetSeparator(after row: XCUIElement, in window: XCUIElement) throws {
        let frame = row.frame.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        let image = try XCTUnwrap(window.screenshot().image.cgImage)
        let scale = CGFloat(image.width) / window.frame.width
        let first = Int((frame.maxY + 4) * scale)
        let last = Int((frame.maxY + 9) * scale)
        XCTAssertGreaterThan(first, 1)
        XCTAssertLessThan(last + 1, image.height)
        let pixels = try SongsUITestSupport.bitmapPixels(image)
        func brightness(at y: Int, offsets: ClosedRange<CGFloat>) -> Double {
            let columns = Int((frame.minX + offsets.lowerBound) * scale)...Int((frame.minX + offsets.upperBound) * scale)
            return Double(columns.reduce(0) { $0 + Int(pixels[(y * image.width + $1) * 4]) }) / Double(columns.count)
        }
        let baseline = first - 2
        let content: ClosedRange<CGFloat> = 6...44
        let gutter: ClosedRange<CGFloat> = -10 ... -5
        let line = try XCTUnwrap((first...last).max { brightness(at: $0, offsets: content) < brightness(at: $1, offsets: content) })
        let contentRise = brightness(at: line, offsets: content) - brightness(at: baseline, offsets: content)
        let gutterRise = brightness(at: line, offsets: gutter) - brightness(at: baseline, offsets: gutter)
        XCTAssertGreaterThan(contentRise, 8, "The separator must be painted under \(row.identifier)")
        XCTAssertLessThan(gutterRise, contentRise / 3, "The separator must not cross the leading gutter")
    }

    // These journeys move the persisted slider. Restore the fixture's preference file after
    // a run on a reused simulator, rather than approximating the original value with a gesture.

    /// Leeway's native slider updates the signed value, example cap and wrapped explanation together.
    @MainActor
    func testLeewayShowsBoundsAndReadableExample() throws {
        let app = launch([
            "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off", "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_UI_TEST_CLEAR_PROFILE": "0", "FST_DEBUG_ANONYMOUS": "1",
        ], arguments: [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-fst.accessibility.reduceMotion", "YES", "-fst.accessibility.moreContrast", "NO",
        ])
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a phone or the Duo cover")
        let filter = app.switches["fst.settings.filter-invalid-scores"]
        XCTAssertTrue(filter.waitForExistence(timeout: FestivalApp.budget(15)))
        positionWrappedSetting(filter, in: app)
        let originalState = try XCTUnwrap(filter.value as? String)
        defer { SongsUITestSupport.setSwitch(filter, to: originalState) }
        SongsUITestSupport.setSwitch(filter, to: "1")
        let slider = app.sliders["fst.settings.leeway"]
        XCTAssertTrue(slider.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(slider.label, "Max Score Leeway")
        XCTAssertTrue(slider.isHittable && slider.isEnabled)
        for (position, value, cap) in [(0.0, "-5.0%", "95,000"), (1.0, "+5.0%", "105,000")] {
            setLeewayEndpoint(slider, maximum: position == 1)
            let title = app.staticTexts["Maximum Score Leeway: \(value)"]
            let example = app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "scores up to \(cap) as valid")
            ).firstMatch
            XCTAssertTrue(example.exists && title.exists)
            XCTAssertLessThan(filter.frame.maxY, title.frame.minY)
            XCTAssertLessThanOrEqual(title.frame.maxY, example.frame.minY)
            XCTAssertLessThanOrEqual(example.frame.maxY, slider.frame.minY)
            let shot = example.screenshot()
            let lines = RecognizedText.lines(in: shot)
            XCTAssertTrue(RecognizedText.showsWhole("scores up to \(cap) as valid",
                                                   in: lines.map(\.text).joined(separator: " ")))
            let inkBottom = try assertLeewayExampleLinePitch(in: shot, pointWidth: example.frame.width)
            if position == 1 {
                let trackTop = try leewayTrackTop(slider, increasedContrast: false)
                let gap = trackTop - example.frame.minY - inkBottom
                let geometry = XCTAttachment(string: "trackGap=\(gap); sliderHeight=\(slider.frame.height)")
                geometry.name = "settings-leeway-track-geometry"
                geometry.lifetime = .keepAlways
                add(geometry)
                if #available(iOS 27.3, *) {
                    XCTAssertEqual(gap, 20, accuracy: 2,
                                   "The active track should sit close below the painted example")
                }
            }
            SongsUITestSupport.record(app, name: "settings-leeway-\(position == 0 ? "minimum" : "maximum")")
        }
    }

    /// Settings changes the selected player's effective score and the signed full-chart request.
    @MainActor
    func testLeewayChangesSelectedScoreAndLeaderboardQuery() async throws {
        let app = launch([
            "FST_DEBUG_TAB": "songs", "FST_DEBUG_PROFILE": "fixture-leeway:Fixture Leeway",
            "FST_UI_TEST_CLEAR_PROFILE": "0", "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off",
        ], arguments: [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-fst.accessibility.reduceMotion", "YES", "-fst.settings.hideShop", "YES",
            "-fst.settings.showInstrumentIcons", "NO",
            "-fst.settings.metadataScore", "YES", "-fst.settings.metadataPercentage", "YES",
            "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
        ])
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a phone or the Duo cover")
        let filter = app.switches["fst.settings.filter-invalid-scores"]
        let slider = app.sliders["fst.settings.leeway"]
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        let score = SongsUITestSupport.metadataElement("score", in: app)
        let accuracy = SongsUITestSupport.metadataElement("accuracy", in: app)
        let indicator = app.buttons["fst.songs.invalid-score.fixture-pulse"]
        let full = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        let first = element(app, "fst.song-leaderboard.row.fixture-player-1")

        func verifySongs(fallback: Bool, phase: String) {
            let expected = fallback ? "Score 94,000" : "Score 104,000"
            let expectedAccuracy = fallback ? "Full combo, accuracy 97 percent" : "Accuracy 99 percent"
            XCTAssertTrue(score.wait(for: \.label, toEqual: expected, timeout: FestivalApp.budget(15)))
            XCTAssertEqual(accuracy.label, expectedAccuracy)
            XCTAssertTrue(song.isHittable && song.label.contains(expected) && song.label.contains(expectedAccuracy))
            if fallback {
                XCTAssertTrue(indicator.waitForExistence(timeout: FestivalApp.budget(5)))
                XCTAssertEqual(indicator.label, "Invalid score indicator")
                XCTAssertTrue(indicator.isHittable)
                XCTAssertGreaterThanOrEqual(min(indicator.frame.width, indicator.frame.height), 43.5)
            } else {
                XCTAssertFalse(indicator.exists)
            }
            SongsUITestSupport.record(app, name: "settings-leeway-songs-\(phase)")
        }

        func tapBack() {
            let back = app.buttons["BackButton"]
            (back.exists && back.isHittable ? back : app.navigationBars.buttons.firstMatch).tap()
        }

        func verifyBoard(leeway: Double, phase: String) async throws {
            song.tap()
            XCTAssertTrue(full.waitForExistence(timeout: FestivalApp.budget(15)))
            SongsUITestSupport.reveal(full, in: app, scrollingUp: false)
            full.tap()
            XCTAssertTrue(first.waitForExistence(timeout: FestivalApp.budget(15)))
            let query = try await SongsUITestSupport.latestFixtureScoreQuery(fullOnly: true)
            XCTAssertEqual(query.top, 25)
            XCTAssertEqual(query.offset, 0)
            XCTAssertEqual(query.leeway, leeway)
            SongsUITestSupport.record(app, name: "settings-leeway-full-chart-\(phase)")
            tapBack()
            XCTAssertTrue(full.waitForExistence(timeout: FestivalApp.budget(10)))
            tapBack()
            XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(10)))
        }

        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(15)))
        navigateViaDrawer("settings", to: filter, in: app)
        positionWrappedSetting(filter, in: app)
        SongsUITestSupport.setSwitch(filter, to: "1")
        XCTAssertTrue(slider.waitForExistence(timeout: FestivalApp.budget(5)))
        setLeewayEndpoint(slider, maximum: true)
        navigateViaDrawer("songs", to: song, in: app)
        verifySongs(fallback: false, phase: "maximum")
        try await verifyBoard(leeway: 5, phase: "maximum")

        navigateViaDrawer("settings", to: filter, in: app)
        positionWrappedSetting(filter, in: app)
        setLeewayEndpoint(slider, maximum: false)
        navigateViaDrawer("songs", to: song, in: app)
        verifySongs(fallback: true, phase: "minimum")
        try await verifyBoard(leeway: -5, phase: "minimum")

        navigateViaDrawer("settings", to: filter, in: app)
        positionWrappedSetting(filter, in: app)
        SongsUITestSupport.setSwitch(filter, to: "0")
        navigateViaDrawer("songs", to: song, in: app)
        verifySongs(fallback: false, phase: "switched-off")
    }

    /// Move the native slider to the exact endpoint, including the Duo cover's final step.
    @MainActor
    private func setLeewayEndpoint(_ slider: XCUIElement, maximum: Bool) {
        let value = maximum ? "+5.0%" : "-5.0%"
        slider.adjust(toNormalizedSliderPosition: maximum ? 1 : 0)
        if slider.value as? String != value {
            let nearEnd = slider.coordinate(withNormalizedOffset: CGVector(dx: maximum ? 0.94 : 0.06, dy: 0.5))
            nearEnd.press(forDuration: 0.05, thenDragTo: slider.coordinate(
                withNormalizedOffset: CGVector(dx: maximum ? 0.995 : 0.005, dy: 0.5)
            ), withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTAssertEqual(slider.value as? String, value)
    }

    /// Higher contrast changes the slider's track paint without changing its accessible value.
    @MainActor
    func testLeewayTrackUsesIncreasedContrastTint() throws {
        let app = launch([
            "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off", "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_UI_TEST_CLEAR_PROFILE": "0", "FST_DEBUG_ANONYMOUS": "1",
        ], arguments: [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-fst.accessibility.reduceMotion", "YES", "-fst.accessibility.moreContrast", "YES",
            "-fst.settings.filterInvalidScores", "YES",
        ])
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a phone or the Duo cover")
        let slider = app.sliders["fst.settings.leeway"]
        XCTAssertTrue(slider.waitForExistence(timeout: FestivalApp.budget(15)))
        positionWrappedSetting(slider, in: app)
        XCTAssertTrue(slider.isHittable && slider.isEnabled)
        XCTAssertEqual(slider.label, "Max Score Leeway")
        setLeewayEndpoint(slider, maximum: true)
        _ = try leewayTrackTop(slider, increasedContrast: true)
        SongsUITestSupport.record(app, name: "settings-leeway-increased-contrast")
    }

    /// Find the first painted track line, keeping the thumb and track ends out of the sample.
    @MainActor
    private func leewayTrackTop(_ slider: XCUIElement, increasedContrast: Bool) throws -> CGFloat {
        let image = try XCTUnwrap(slider.screenshot().image.cgImage)
        let bytes = try SongsUITestSupport.bitmapPixels(image)
        let columns = image.width / 4 ..< image.width * 3 / 4
        let expected = increasedContrast ? [255, 255, 255] : [45, 130, 230]
        for y in 0..<image.height {
            var run = 0
            for x in columns {
                let offset = 4 * (y * image.width + x)
                let matches = expected.enumerated().allSatisfy { channel, value in
                    abs(Int(bytes[offset + channel]) - value) <= 8
                }
                run = matches ? run + 1 : 0
                if Double(run) > Double(columns.count) * 0.9 {
                    return slider.frame.minY + CGFloat(y) * slider.frame.width / CGFloat(image.width)
                }
            }
        }
        return try XCTUnwrap(nil, "No continuous \(increasedContrast ? "high-contrast white" : "brand-blue") track")
    }

    /// Switch between the mounted Settings and Songs destinations through their common drawer.
    @MainActor
    private func navigateViaDrawer(_ destination: String, to target: XCUIElement, in app: XCUIApplication) {
        ShellUITestSupport.tapToolbarItem(
            "fst.shell.drawer.open", overflowLabels: ["Menu", "Open Navigation"], in: app
        )
        let link = app.buttons["fst.shell.drawer.\(destination)"]
        XCTAssertTrue(link.waitForExistence(timeout: FestivalApp.budget(5)))
        link.tap()
        XCTAssertTrue(target.waitForExistence(timeout: FestivalApp.budget(15)))
    }

    /// Measure each line's rise and return the bottom of the painted example in capture points.
    @MainActor
    private func assertLeewayExampleLinePitch(in screenshot: XCUIScreenshot, pointWidth: CGFloat) throws -> CGFloat {
        let image = try XCTUnwrap(screenshot.image.cgImage)
        let bytes = try SongsUITestSupport.bitmapPixels(image)
        var lineStarts: [Int] = []
        var inkBottom = 0
        var previousRowHasInk = false
        for y in 0..<image.height {
            let first = y * image.width * 4
            let ink = stride(from: first, to: first + image.width * 4, by: 4).count {
                bytes[$0] >= 140 && bytes[$0 + 1] >= 140 && bytes[$0 + 2] >= 140
            }
            let rowHasInk = ink > image.width / 36
            if rowHasInk, !previousRowHasInk { lineStarts.append(y) }
            if rowHasInk { inkBottom = y }
            previousRowHasInk = rowHasInk
        }
        XCTAssertEqual(lineStarts.count, 2, "The complete example wraps over two lines at Large on the covers")
        let first = try XCTUnwrap(lineStarts.first)
        let last = try XCTUnwrap(lineStarts.last)
        let pointsPerPixel = pointWidth / CGFloat(image.width)
        XCTAssertGreaterThanOrEqual(CGFloat(last - first) * pointsPerPixel, 16.5)
        return CGFloat(inkBottom) * pointsPerPixel
    }

    /// The CHOpt disclosure and reorder heading fit the reference spacing; the enlarged
    /// row still acts as one named button and reports the selection in place.
    @MainActor
    func testPathChoiceSpacingAndAccessibility() throws {
        let app = launch([
            "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off", "FST_DEBUG_FLAT_BACKDROP": "1",
        ], arguments: [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-fst.settings.enableVisualOrder", "NO", "-fst.accessibility.reduceMotion", "YES",
        ])
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a phone or the Duo cover")
        let identifier = "fst.settings.path-default-view"
        let choice = element(app, identifier)
        let order = app.staticTexts["CHOpt Text Path Column Order"]
        XCTAssertTrue(choice.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(choice.isHittable && choice.isEnabled)
        XCTAssertTrue([.button, .disclosureTriangle].contains(choice.elementType))
        XCTAssertEqual(choice.label, "CHOpt Path Default View")
        XCTAssertGreaterThanOrEqual(choice.frame.width, 44)
        XCTAssertEqual(choice.frame.height, window.width >= 450 ? 90.33 : 70.33, accuracy: 1)

        XCTAssertTrue(order.exists)
        let first = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fst.settings.path-column-order.")
        ).firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertEqual(first.frame.minY - order.frame.minY, 74.33, accuracy: 1)

        let value = try XCTUnwrap(choice.value as? String)
        let original = try XCTUnwrap(value.components(separatedBy: ", ").first)
        XCTAssertTrue(["Image", "Text"].contains(original))
        XCTAssertEqual(value, "\(original), Collapsed")
        let selected = app.buttons["\(identifier).\(original.lowercased())"]
        XCTAssertFalse(selected.exists)
        choice.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).tap()
        XCTAssertEqual(choice.value as? String, "\(original), Expanded")
        XCTAssertTrue(selected.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertTrue(selected.isSelected)
        XCTAssertEqual(selected.label, original)
        XCTAssertGreaterThanOrEqual(selected.frame.height, 43.5)
        XCTAssertGreaterThan(selected.frame.minY, choice.frame.maxY)

        let alternative = original == "Image" ? "Text" : "Image"
        let unselected = app.buttons["\(identifier).\(alternative.lowercased())"]
        func leadingInset(_ button: XCUIElement) throws -> CGFloat {
            let shot = button.screenshot()
            let line = try XCTUnwrap(RecognizedText.lines(in: shot).first {
                RecognizedText.showsWhole(button.label, in: $0.text)
            })
            return line.frame.minX / shot.image.size.width * button.frame.width
        }
        XCTAssertTrue(unselected.exists && unselected.isHittable && unselected.isEnabled)
        XCTAssertFalse(unselected.isSelected)
        let originalInset = try leadingInset(selected)
        let alternativeInset = try leadingInset(unselected)
        XCTAssertEqual(originalInset, 12, accuracy: 3)
        XCTAssertEqual(alternativeInset, 12, accuracy: 3)
        unselected.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        defer { if unselected.exists && unselected.isSelected { selected.tap() } }
        XCTAssertEqual(choice.value as? String, "\(alternative), Expanded")
        XCTAssertTrue(unselected.isSelected)
        XCTAssertFalse(selected.isSelected)
        XCTAssertEqual(try leadingInset(selected), originalInset, accuracy: 2)
        XCTAssertEqual(try leadingInset(unselected), alternativeInset, accuracy: 2)
        selected.tap()
        choice.tap()
        XCTAssertEqual(choice.value as? String, value)
        XCTAssertTrue(selected.waitForNonExistence(timeout: FestivalApp.budget(5)))
        XCTAssertFalse(unselected.exists)
    }

    /// Settings changes the default for new Paths sheets; a sheet's own View choice is temporary.
    @MainActor
    func testPathDefaultAppliesToNewSheetsAndSurvivesColdLaunch() throws {
        let flags = [
            "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off", "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ]
        let arguments = [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-fst.settings.enableVisualOrder", "NO", "-fst.accessibility.reduceMotion", "YES",
        ]
        let choiceID = "fst.settings.path-default-view"
        let displayID = "fst.paths.display"
        func select(_ mode: String, in app: XCUIApplication) {
            let choice = element(app, choiceID)
            XCTAssertTrue(choice.isHittable && choice.isEnabled)
            XCTAssertEqual(choice.label, "CHOpt Path Default View")
            choice.tap()
            let option = app.buttons["\(choiceID).\(mode.lowercased())"]
            XCTAssertTrue(option.isHittable && option.isEnabled)
            option.tap()
            XCTAssertTrue(option.isSelected)
            choice.tap()
            XCTAssertEqual(choice.value as? String, "\(mode), Collapsed")
            XCTAssertFalse(option.exists)
        }
        func assertChart(_ mode: String, in app: XCUIApplication, checkpoint: String) {
            let display = element(app, displayID)
            let chart = mode == "Text"
                ? element(app, "fst.paths.text.Solo_Guitar.expert")
                : app.images["fst.paths.image"]
            XCTAssertTrue(chart.waitForExistence(timeout: FestivalApp.budget(15)), "No \(mode) chart at \(checkpoint)")
            XCTAssertTrue(display.isHittable && display.isEnabled)
            XCTAssertGreaterThanOrEqual(display.frame.width, 43.5)
            XCTAssertGreaterThanOrEqual(display.frame.height, 43.5)
            let nameAndValue = "\(display.label) \((display.value as? String) ?? "")"
            XCTAssertTrue(nameAndValue.contains("View") && nameAndValue.contains(mode), nameAndValue)
            SongsUITestSupport.record(app, name: "settings-path-default-\(checkpoint)-\(mode.lowercased())")
        }
        func assertTextValueDrawsOnOneLine(_ choice: XCUIElement) {
            let shot = choice.screenshot()
            let size = shot.image.size
            let trailing = CGRect(x: size.width * 0.8, y: 0, width: size.width * 0.2, height: size.height)
            let lines = RecognizedText.lines(in: shot, region: trailing).map(\.text)
            XCTAssertTrue(lines.contains { $0.split(separator: " ").first == "Text" },
                          "The current value must draw as one whole word: \(lines)")
        }

        let app = launch(flags, arguments: arguments)
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a phone or the Duo cover")
        let choice = element(app, choiceID)
        XCTAssertTrue(choice.waitForExistence(timeout: FestivalApp.budget(15)))
        let value = try XCTUnwrap(choice.value as? String)
        let original = try XCTUnwrap(["Image", "Text"].first { value == "\($0), Collapsed" })
        // The wrap occurs when a row laid out with Text returns to it after showing Image.
        if original != "Text" {
            select("Text", in: app)
            app.terminate()
            app.launch()
            XCTAssertTrue(choice.waitForExistence(timeout: FestivalApp.budget(15)))
        }
        XCTAssertEqual(choice.value as? String, "Text, Collapsed")
        select("Image", in: app)
        select("Text", in: app)
        SongsUITestSupport.record(app, name: "settings-path-default-saved-text")
        assertTextValueDrawsOnOneLine(choice)

        ShellUITestSupport.tapToolbarItem(
            "fst.shell.drawer.open", overflowLabels: ["Menu", "Open Navigation"], in: app
        )
        let songs = app.buttons["fst.shell.drawer.songs"]
        XCTAssertTrue(songs.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertTrue(songs.isHittable && songs.isEnabled)
        songs.tap()
        PathsUITestSupport.openPaths(in: app)
        assertChart("Text", in: app, checkpoint: "first-open")
        PathsUITestSupport.choose("Image", in: element(app, displayID), app: app)
        assertChart("Image", in: app, checkpoint: "temporary")
        let close = app.buttons["fst.paths.close"]
        XCTAssertTrue(close.isHittable && close.isEnabled)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: FestivalApp.budget(5)))
        PathsUITestSupport.openPathsFromSongDetail(in: app)
        assertChart("Text", in: app, checkpoint: "reopened")
        app.terminate()

        let cold = launch(flags, arguments: arguments)
        defer { cold.terminate() }
        let storedChoice = element(cold, choiceID)
        XCTAssertTrue(storedChoice.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertEqual(storedChoice.value as? String, "Text, Collapsed")
        if original != "Text" { select(original, in: cold) }
    }

    /// Reorder from the grip, relaunch with the changed order, and scroll from the label.
    @MainActor
    func testPathColumnGripReorderSurvivesColdLaunch() throws {
        let flags = ["FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off", "FST_DEBUG_FLAT_BACKDROP": "1"]
        func start() -> XCUIApplication {
            launch(flags, arguments: [
                "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
                "-fst.settings.enableVisualOrder", "NO", "-fst.accessibility.reduceMotion", "YES",
            ])
        }
        func rows(in app: XCUIApplication) -> [XCUIElement] {
            ["note", "beat", "time", "od", "score"].map { element(app, "fst.settings.path-column-order.\($0)") }
        }
        func position(_ position: Int, in app: XCUIApplication) throws -> XCUIElement {
            try XCTUnwrap(rows(in: app).first { $0.value as? String == "\(position) of 5" })
        }
        func grip(_ row: XCUIElement) -> XCUICoordinate {
            row.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 24, dy: row.frame.height * 0.5))
        }
        func dragUp(_ lower: XCUIElement, over upper: XCUIElement) {
            grip(lower).press(forDuration: 0.2, thenDragTo: grip(upper),
                              withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let app = start()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        try XCTSkipUnless(window.frame.width < 500 && window.frame.height > window.frame.width,
                          "Requires a phone or the Duo cover")
        XCTAssertTrue(rows(in: app)[0].waitForExistence(timeout: FestivalApp.budget(15)))
        let upper = try position(1, in: app)
        let lower = try position(2, in: app)
        let ids = (upper.identifier, lower.identifier)
        let labels = (upper.label, lower.label)
        positionWrappedSetting(upper, in: app)
        for row in [upper, lower] {
            XCTAssertTrue(row.isHittable && row.isEnabled)
            XCTAssertEqual(row.elementType, .staticText)
            XCTAssertGreaterThanOrEqual(row.frame.height, 43.5)
        }
        XCTAssertLessThan(upper.frame.minY, lower.frame.minY)
        SongsUITestSupport.record(app, name: "settings-chopt-columns-before")
        dragUp(lower, over: upper)
        XCTAssertEqual(lower.value as? String, "1 of 5")
        XCTAssertEqual(upper.value as? String, "2 of 5")
        XCTAssertLessThan(lower.frame.minY, upper.frame.minY)
        SongsUITestSupport.record(app, name: "settings-chopt-columns-moved")
        app.terminate()

        let cold = start()
        defer { cold.terminate() }
        let moved = element(cold, ids.1)
        XCTAssertTrue(moved.waitForExistence(timeout: FestivalApp.budget(15)))
        let displaced = element(cold, ids.0)
        positionWrappedSetting(moved, in: cold)
        let persisted = (moved.value as? String, displaced.value as? String)
        XCTAssertEqual(moved.label, labels.1)
        XCTAssertEqual(displaced.label, labels.0)
        XCTAssertLessThan(moved.frame.minY, displaced.frame.minY)
        SongsUITestSupport.record(cold, name: "settings-chopt-columns-cold")
        let beforeScroll = moved.frame.midY
        let text = moved.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        text.press(forDuration: 0.05, thenDragTo: text.withOffset(CGVector(dx: 0, dy: -75)),
                   withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertLessThan(moved.frame.midY, beforeScroll - 24, "Dragging the label must scroll Settings")
        XCTAssertEqual(moved.value as? String, "1 of 5", "Dragging the label must not reorder the row")
        dragUp(displaced, over: moved)
        XCTAssertEqual(displaced.value as? String, "1 of 5")
        XCTAssertEqual(moved.value as? String, "2 of 5")
        XCTAssertEqual(persisted.0, "1 of 5")
        XCTAssertEqual(persisted.1, "2 of 5")
    }

    /// Settings changes the painted and accessible primary field of an already-loaded Songs list.
    @MainActor
    func testIndependentVisualOrderUpdatesSongsAndSurvivesColdLaunch() throws {
        let app = launch([
            "FST_DEBUG_TAB": "songs", "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_UI_TEST_CLEAR_PROFILE": "0", "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_DEBUG_FIRST_RUN": "off", "FST_DEBUG_WHATS_NEW": "off",
        ], arguments: [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue,
            "-fst.accessibility.reduceMotion", "YES", "-fst.settings.hideShop", "YES",
            "-fst.settings.showInstrumentIcons", "NO", "-fst.settings.filterInvalidScores", "NO",
            "-fst.settings.metadataScore", "YES", "-fst.settings.metadataPercentage", "YES",
            "-fst.settings.metadataPercentile", "NO", "-fst.settings.metadataStars", "NO",
            "-fst.settings.metadataSeason", "NO", "-fst.settings.metadataIntensity", "NO",
            "-fst.settings.metadataDifficulty", "NO", "-fst.settings.metadataLastPlayed", "NO",
            "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
        ])
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a phone or the Duo cover")

        let song = app.buttons["fst.songs.row.fixture-pulse"]
        let score = SongsUITestSupport.metadataElement("score", in: app)
        let accuracy = SongsUITestSupport.metadataElement("accuracy", in: app)
        let toggle = app.switches["fst.settings.enable-visual-order"]
        let scoreRow = element(app, "fst.settings.song-row-order.score")
        let percentageRow = element(app, "fst.settings.song-row-order.percentage")

        func assertSongOrder(scoreFirst: Bool, checkpoint: String) {
            XCTAssertTrue(score.waitForExistence(timeout: FestivalApp.budget(15)))
            XCTAssertTrue(accuracy.exists && song.isHittable)
            XCTAssertTrue(score.label.hasPrefix("Score "))
            XCTAssertTrue(accuracy.label.localizedCaseInsensitiveContains("accuracy"))
            let ordered = scoreFirst ? [score, accuracy] : [accuracy, score]
            let labels = ordered.map(\.label)
            let pattern = labels.map(NSRegularExpression.escapedPattern(for:)).joined(separator: ".*")
            let order = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label MATCHES %@", "(?s).*\(pattern).*"), object: song
            )
            XCTAssertEqual(XCTWaiter.wait(for: [order], timeout: FestivalApp.budget(4)), .completed,
                           "\(checkpoint) must read \(labels) in order; actual: \(song.label)")
            XCTAssertLessThan(ordered[0].frame.midY, ordered[1].frame.midY, "The primary pill moves above the secondary one")
            XCTAssertGreaterThanOrEqual(song.frame.height, 44)
            SongsUITestSupport.record(app, name: "settings-visual-order-songs-\(checkpoint)")
        }
        func moveToFirst(_ lower: XCUIElement, above upper: XCUIElement) {
            positionWrappedSetting(upper, in: app)
            for row in [lower, upper] {
                XCTAssertTrue(row.isHittable)
                XCTAssertEqual(row.elementType, .staticText)
                XCTAssertGreaterThanOrEqual(row.frame.height, 43.5)
            }
            func grip(_ row: XCUIElement) -> XCUICoordinate {
                row.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 24, dy: row.frame.height * 0.5))
            }
            grip(lower).press(forDuration: 0.2, thenDragTo: grip(upper),
                              withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertEqual(lower.value as? String, "1 of 2")
            XCTAssertEqual(upper.value as? String, "2 of 2")
            XCTAssertLessThan(lower.frame.minY, upper.frame.minY)
        }

        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(15)))
        navigateViaDrawer("settings", to: toggle, in: app)
        XCTAssertEqual(toggle.elementType, .switch)
        XCTAssertTrue(toggle.label.hasPrefix("Enable Independent Song Row Visual Order"))
        let originalState = try XCTUnwrap(toggle.value as? String)
        SongsUITestSupport.setSwitch(toggle, to: "1")
        XCTAssertTrue(scoreRow.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(scoreRow.label, "Score")
        XCTAssertEqual(percentageRow.label, "Percentage")
        let originallyScoreFirst = scoreRow.value as? String == "1 of 2"
        if !originallyScoreFirst { moveToFirst(scoreRow, above: percentageRow) }
        navigateViaDrawer("songs", to: song, in: app)
        assertSongOrder(scoreFirst: true, checkpoint: "before")

        navigateViaDrawer("settings", to: toggle, in: app)
        positionWrappedSetting(scoreRow, in: app)
        SongsUITestSupport.record(app, name: "settings-visual-order-before")
        moveToFirst(percentageRow, above: scoreRow)
        SongsUITestSupport.record(app, name: "settings-visual-order-changed")
        navigateViaDrawer("songs", to: song, in: app)
        assertSongOrder(scoreFirst: false, checkpoint: "changed")
        app.terminate()
        app.launch()
        assertSongOrder(scoreFirst: false, checkpoint: "cold")

        navigateViaDrawer("settings", to: toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1")
        SongsUITestSupport.reveal(toggle, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(toggle, to: "0")
        XCTAssertTrue(scoreRow.waitForNonExistence(timeout: FestivalApp.budget(5)))
        navigateViaDrawer("songs", to: song, in: app)
        assertSongOrder(scoreFirst: true, checkpoint: "switched-off")

        navigateViaDrawer("settings", to: toggle, in: app)
        SongsUITestSupport.setSwitch(toggle, to: "1")
        XCTAssertTrue(percentageRow.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(percentageRow.value as? String, "1 of 2", "Switching off must keep the saved custom order")
        if originallyScoreFirst { moveToFirst(scoreRow, above: percentageRow) }
        SongsUITestSupport.reveal(toggle, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(toggle, to: originalState)
    }

    /// Settings uses the app's blue tint without changing the native switch's spoken state.
    @MainActor
    func testEnabledInstrumentSwitchUsesAppTint() throws {
        let app = launch(["FST_UI_TEST_RESET_SONG_CARDS": "1", "FST_UI_TEST_RESET_VISUALS": "1"])
        defer { app.terminate() }
        let toggle = app.switches["fst.settings.show-instrument-icons"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(toggle.label.hasPrefix("Show Instrument Icons"))
        XCTAssertGreaterThan(try bluePixels(in: toggle), 50, "the native switch draws its enabled track in blue")
    }

    /// The wrapped Settings description draws at the reference's line pitch, and
    /// remains fully readable in the same switch element at AX5.
    @MainActor
    func testWrappedSettingDescriptionKeepsNativeLeadingAndScales() throws {
        let description = "Display instrument icons on each song row showing which parts have leaderboard scores or FCs."
        func read(largeText: Bool) throws -> CGFloat {
            let app = launch(["FST_UI_TEST_RESET_VISUALS": "1"], largeText: largeText)
            defer { app.terminate() }
            let toggle = app.switches["fst.settings.show-instrument-icons"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 15))
            if largeText {
                positionWrappedSetting(toggle, in: app)
                SongsUITestSupport.record(app, name: "settings-wrapped-description-ax5")
            }
            XCTAssertTrue(toggle.isHittable)
            XCTAssertEqual(toggle.value as? String, "1")
            XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
            let reading = RecognizedText.recognize(toggle, label: description, frame: toggle.frame)
            let displayHeight = try XCTUnwrap(RecognizedText.recognizeLine("Display", in: toggle).lineHeight)
            if largeText, !RecognizedText.showsWhole(description, in: reading.text) {
                // The folded cover may be shorter than the description. Require overlapping
                // chunks from the same row so missing or clipped words still fail the test.
                let first = "Display instrument icons on each song row showing which parts"
                let last = "showing which parts have leaderboard scores or FCs."
                XCTAssertTrue(RecognizedText.showsWhole(first, in: reading.text), reading.text ?? "No start")
                let window = app.windows.firstMatch
                dragSettings(in: window, by: -window.frame.height / 3)
                let tail = RecognizedText.recognize(toggle, label: last, frame: toggle.frame)
                XCTAssertTrue(RecognizedText.showsWhole(last, in: tail.text), tail.text ?? "No end")
                SongsUITestSupport.record(app, name: "settings-wrapped-description-ax5-end")
            } else {
                XCTAssertTrue(RecognizedText.showsWhole(description, in: reading.text), reading.text ?? "No rendered text")
            }
            if !largeText {
                let lines = RecognizedText.lines(in: toggle.screenshot())
                let first = try XCTUnwrap(lines.firstIndex { $0.text.localizedCaseInsensitiveContains("Display") })
                let last = try XCTUnwrap(lines.lastIndex { RecognizedText.showsWhole("FCs", in: $0.text) })
                XCTAssertGreaterThan(last, first)
                let pitch = (lines[last].frame.midY - lines[first].frame.midY) / CGFloat(last - first)
                XCTAssertGreaterThanOrEqual(pitch, 19, "Reference subheadline lines are 20 pt apart at Large")
                XCTAssertLessThanOrEqual(pitch, 21.5, "Do not add paragraph spacing between wrapped lines")
            }
            return displayHeight
        }

        let regular = try read(largeText: false)
        let large = try read(largeText: true)
        XCTAssertGreaterThanOrEqual(large / regular, RecognizedText.minimumGrowth)
    }

    /// Centers a tall row for a whole-copy screenshot without flinging it through the header.
    @MainActor
    private func positionWrappedSetting(_ row: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let bounds = window.frame
        for _ in 0..<4 {
            let frame = row.frame
            let center = bounds.minY + bounds.height * 0.52
            let offset = max(-bounds.height * 0.35, min(bounds.height * 0.35, center - frame.midY))
            if abs(offset) < 24 { break }
            dragSettings(in: window, by: offset)
        }
    }

    @MainActor
    private func dragSettings(in window: XCUIElement, by offset: CGFloat) {
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    @MainActor
    private func bluePixels(in element: XCUIElement) throws -> Int {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let pixels = try SongsUITestSupport.bitmapPixels(image)
        return stride(from: 0, to: pixels.count, by: 4).filter { offset in
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            return blue > 140 && blue > green + 35 && green > red + 30
        }.count
    }

    /// A disabled setting communicates that state visually and ignores the same label tap that works when enabled.
    @MainActor
    func testShopHighlightLabelDimsAndDoesNotToggleWhileDisabled() throws {
        let app = launch(["FST_UI_TEST_RESET_SONG_CARDS": "1", "FST_UI_TEST_RESET_VISUALS": "1"])
        defer { app.terminate() }
        let hide = app.switches["fst.settings.hide-shop"]
        let highlights = app.switches["fst.settings.shop-highlights"]
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hide, to: "0")
        XCTAssertTrue(highlights.isEnabled)
        XCTAssertTrue(highlights.label.hasPrefix("Highlight Shop Items"))
        XCTAssertGreaterThanOrEqual(highlights.frame.height, 43.5)
        let original = try XCTUnwrap(highlights.value as? String)
        let flipped = original == "1" ? "0" : "1"
        let label = highlights.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let enabled = try labelBrightness(of: highlights)
        label.tap()
        XCTAssertEqual(highlights.value as? String, flipped)
        label.tap()
        XCTAssertEqual(highlights.value as? String, original)

        SongsUITestSupport.setSwitch(hide, to: "1")
        XCTAssertFalse(highlights.isEnabled)
        let disabled = try labelBrightness(of: highlights)
        XCTAssertLessThan(disabled, enabled * 0.8, "disabled Settings text is distinct from enabled text")
        label.tap()
        XCTAssertEqual(highlights.value as? String, original)
        SongsUITestSupport.setSwitch(hide, to: "0")
        XCTAssertTrue(highlights.isEnabled)
        XCTAssertGreaterThan(try labelBrightness(of: highlights), disabled * 1.25)
    }

    @MainActor
    private func labelBrightness(of toggle: XCUIElement) throws -> Double {
        let image = try XCTUnwrap(toggle.screenshot().image.cgImage)
        let label = try XCTUnwrap(image.cropping(to: CGRect(
            x: 0, y: 0, width: image.width * 2 / 3, height: image.height
        )))
        return try SongsUITestSupport.measuredTextContrast(in: SongsUITestSupport.bitmapPixels(label)).text
    }

    /// Settings fields fit beside the real folded Duo rail, rather than scrolling beneath it.
    @MainActor
    func testFoldedSettingsSwitchAndReorderRowsStayClearOfTheRail() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name
        try XCTSkipUnless(device.contains("Duo"), "Requires the iPhone Duo simulator")
        let app = launch(["FST_UI_TEST_RESET_SONG_CARDS": "1"])
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless([window.width.rounded(), window.height.rounded()] == [466, 678],
                          "Requires the folded Duo portrait window")
        let settingsButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Settings"))
        XCTAssertTrue(settingsButtons.firstMatch.waitForExistence(timeout: 15))
        let railButton = try XCTUnwrap(settingsButtons.allElementsBoundByIndex.first {
            $0.frame.midX > window.maxX - 80 && $0.frame.width > 0
        })
        let toggle = app.switches["fst.settings.show-instrument-icons"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertLessThanOrEqual(toggle.frame.maxX, railButton.frame.minX)
        let note = element(app, "fst.settings.path-column-order.note")
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertEqual(note.label, "Note")
        XCTAssertEqual(note.value as? String, "1 of 5")
        XCTAssertLessThanOrEqual(note.frame.maxX, railButton.frame.minX)

        let invalid = app.switches["fst.settings.filter-invalid-scores"]
        SongsUITestSupport.reveal(invalid, in: app, scrollingUp: true)
        positionWrappedSetting(invalid, in: app)
        XCTAssertTrue(invalid.isHittable)
        XCTAssertTrue(invalid.label.hasPrefix("Filter Invalid Scores"))
        XCTAssertEqual(invalid.value as? String, "0")
        XCTAssertLessThanOrEqual(invalid.frame.maxX, railButton.frame.minX)
        let lines = RecognizedText.lines(in: invalid.screenshot()).map(\.text)
        XCTAssertTrue(lines.contains { RecognizedText.showsWhole("values based on the maximum score", in: $0) },
                      "The default-size description should wrap without an extra line on the cover: \(lines)")
    }

    /// The page's switches are named, stateful switch elements at least 44 pt tall; its link rows
    /// are buttons with a hint; the section headings are headings; Highlight Shop Items follows
    /// Hide Item Shop.
    @MainActor
    func testSettingsRowsAreNamedStatefulAndLargeEnough() throws {
        let app = launch()
        let toggles = [
            "fst.settings.show-instrument-icons", "fst.settings.enable-visual-order", "fst.settings.filter-invalid-scores",
            "fst.settings.experimental-ranks", "fst.settings.reduce-motion", "fst.settings.disable-artwork-animation",
            "fst.settings.more-contrast", "fst.settings.less-transparency", "fst.settings.hide-shop", "fst.settings.shop-highlights",
        ]
        XCTAssertTrue(app.switches[toggles[0]].waitForExistence(timeout: 20))
        for id in toggles {
            let toggle = app.switches[id]
            SongsUITestSupport.reveal(toggle, in: app, scrollingUp: true)
            XCTAssertFalse(toggle.label.isEmpty, "\(id) has no label")
            XCTAssertTrue(["0", "1"].contains(toggle.value as? String ?? ""), "\(id) has no on/off value")
            XCTAssertGreaterThanOrEqual(toggle.frame.height, 43.5, "\(id) target height")
        }
        let hide = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hide, in: app, scrollingUp: true)
        let highlights = app.switches["fst.settings.shop-highlights"]
        SongsUITestSupport.setSwitch(hide, to: "1")
        XCTAssertFalse(highlights.isEnabled, "Highlight Shop Items follows Hide Item Shop")
        SongsUITestSupport.setSwitch(hide, to: "0")
        XCTAssertTrue(highlights.isEnabled)
        for id in ["fst.settings.licenses", "fst.settings.privacy-policy"] {
            let row = app.buttons[id]
            SongsUITestSupport.reveal(row, in: app, scrollingUp: false)
            XCTAssertFalse(row.label.isEmpty, "\(id) has no label")
            XCTAssertGreaterThanOrEqual(row.frame.height, 43.5, "\(id) target height")
        }
        SongsUITestSupport.record(app, name: "settings-rows")
    }

    /// Reset App Settings restores a changed switch and the path default view, and asks first.
    @MainActor
    func testResetRestoresDefaultsAfterConfirmation() throws {
        let app = launch()
        let motion = app.switches["fst.settings.reduce-motion"]
        XCTAssertTrue(motion.waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(motion, in: app, scrollingUp: true)
        let original = motion.value as? String ?? "0"
        SongsUITestSupport.setSwitch(motion, to: "1")
        let reset = app.buttons["fst.settings.reset"]
        SongsUITestSupport.reveal(reset, in: app, scrollingUp: false)
        reset.tap()
        let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "Reset App Settings"))
        let dialog = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 1"), object: confirmations)
        XCTAssertEqual(XCTWaiter.wait(for: [dialog], timeout: 10), .completed, "Reset asks before it acts")
        let confirm = try XCTUnwrap(
            confirmations.allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "fst.settings.reset" }
        )
        confirm.tap()
        SongsUITestSupport.reveal(motion, in: app, scrollingUp: true)
        XCTAssertEqual(motion.value as? String, "0", "Reset restores Reduce Motion (was \(original))")
    }

    // MARK: - Privacy Policy and Licenses

    /// Settings retains the single window-level account group while Licenses has its own Close.
    @MainActor
    func testSplitLicensesKeepsAccountControlsInSettings() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { if isPad { XCUIDevice.shared.orientation = .portrait } }
        let app = launch([
            "FST_DEBUG_ROUTE": "licenses",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_UI_TEST_RESET_VISUALS": "1",
        ])
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width >= 720 && window.width > window.height,
                          "Requires a landscape iPad or unfolded landscape Duo")
        let close = app.buttons["fst.split.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "Licenses opens beside Settings")
        let pane = element(app, "fst.split.trailing")
        XCTAssertTrue(pane.exists)
        let note = app.staticTexts["fst.licenses.empty"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        let reading = RecognizedText.recognize(note, label: note.label, frame: note.frame)
        XCTAssertTrue(RecognizedText.showsWhole(note.label, in: reading.text), "The entire note must fit in the detail pane")
        let showIcons = app.switches["fst.settings.show-instrument-icons"]
        XCTAssertTrue(showIcons.waitForExistence(timeout: 10))
        XCTAssertTrue(showIcons.isHittable)
        XCTAssertEqual(pane.frame.minX - showIcons.frame.maxX, 33, accuracy: 3,
                       "The Settings row ends at its card margin, not an inherited rail inset")
        XCTAssertEqual(close.label, "Close")
        XCTAssertGreaterThan(try bluePixels(in: close), 20, "split Close uses the app accent")
        let profile = app.buttons.matching(identifier: "fst.shell.profile")
        let notifications = app.buttons.matching(identifier: "fst.shell.notifications")
        XCTAssertEqual(profile.count, 1)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(profile.firstMatch.label, "Profile: Fixture Player 1")
        XCTAssertLessThan(profile.firstMatch.frame.midX, pane.frame.minX)
        close.tap()
        XCTAssertTrue(element(app, "fst.settings.placeholder").waitForExistence(timeout: 10))
        XCTAssertFalse(close.exists)
        XCTAssertFalse(note.exists)
        XCTAssertEqual(profile.count, 1)
    }

    #if FST_UIKIT_PORT
    /// The trailing Settings placeholder reads its heading and complete instruction, not its icon.
    @MainActor
    func testWideSettingsPlaceholderScalesAndReadsInOrder() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { if isPad { XCUIDevice.shared.orientation = .portrait } }
        let instruction = "Select a setting to see more options here"
        var defaultInkHeight: CGFloat = 0
        for largeText in [false, true] {
            let app = launch(["FST_UI_TEST_RESET_VISUALS": "1"], largeText: largeText)
            defer { app.terminate() }
            let window = app.windows.firstMatch.frame
            try XCTSkipUnless(window.width >= 720 && window.width > window.height,
                              "Requires a landscape iPad or inner landscape Duo")
            let placeholder = element(app, "fst.settings.placeholder")
            XCTAssertTrue(placeholder.waitForExistence(timeout: 15))
            let labels = placeholder.staticTexts.allElementsBoundByIndex
            XCTAssertEqual(labels.map(\.label), ["Settings", instruction])
            XCTAssertTrue(placeholder.images.allElementsBoundByIndex.isEmpty)
            XCTAssertTrue(placeholder.buttons.allElementsBoundByIndex.isEmpty)
            XCTAssertFalse(app.buttons["fst.split.close"].exists)
            let heading = placeholder.staticTexts["Settings"]
            let subtitle = placeholder.staticTexts[instruction]
            XCTAssertTrue(heading.isHittable)
            XCTAssertTrue(subtitle.isHittable)
            XCTAssertLessThan(heading.frame.maxY, subtitle.frame.minY)
            let reading = RecognizedText.recognize(subtitle, label: instruction, frame: subtitle.frame)
            XCTAssertTrue(RecognizedText.showsWhole(instruction, in: reading.text))
            let inkHeight = try XCTUnwrap(RecognizedText.recognizeLine("Select", in: subtitle).lineHeight)
            if largeText {
                XCTAssertGreaterThan(inkHeight, defaultInkHeight * RecognizedText.minimumGrowth)
            } else {
                defaultInkHeight = inkHeight
            }
            let image = try XCTUnwrap(subtitle.screenshot().image.cgImage)
            let contrast = try SongsUITestSupport.measuredTextContrast(in: SongsUITestSupport.bitmapPixels(image))
            XCTAssertGreaterThan(contrast.brightPixels, 100, "The subtitle crop must contain text")
            XCTAssertGreaterThanOrEqual(contrast.ratio, 4.5, "The rendered subtitle must stay legible")
            SongsUITestSupport.record(app, name: "settings-split-placeholder-\(largeText ? "ax5" : "large")")
        }
    }
    #endif

    /// Privacy Policy opens as a sheet with its effective date and first section, a title, and a
    /// Close that dismisses it.
    @MainActor
    func testPrivacyPolicyOpensAsASheetAndCloses() throws {
        let app = launch()
        let row = app.buttons["fst.settings.privacy-policy"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(row, in: app, scrollingUp: false)
        row.tap()
        let date = element(app, "fst.privacy-policy.effective-date")
        XCTAssertTrue(date.waitForExistence(timeout: 10), "Effective date")
        XCTAssertTrue(element(app, "fst.privacy-policy.section.overview").exists, "First section heading")
        let close = app.buttons["fst.privacy-policy.close"]
        XCTAssertTrue(close.exists)
        // The shared sheet's system Close (Design lane) is a 36 pt glass button.
        XCTAssertGreaterThanOrEqual(close.frame.height, 35.5)
        SongsUITestSupport.record(app, name: "privacy-policy-sheet")
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }

    #if FST_UIKIT_PORT
    /// The end-of-page jump exposes named links with readable descriptions and full row targets.
    @MainActor
    func testStandaloneLinksKeepCompactRowsAndFullSizeTargets() throws {
        let title = "Privacy Policy"
        let description = "How Festival Score Tracker handles your information."

        func read(largeText: Bool) throws -> CGFloat {
            let app = launch(largeText: largeText)
            defer { app.terminate() }
            let entry = app.buttons["fst.quick-links.open"]
            XCTAssertTrue(entry.waitForExistence(timeout: 15))
            entry.tap()
            let destination = FestivalApp.quickLinkRow("privacy-policy", label: title, in: app)
            for _ in 0..<5 where !destination.isHittable { app.swipeUp() }
            XCTAssertTrue(destination.isHittable)
            destination.tap()

            let row = app.buttons["fst.settings.privacy-policy"]
            let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: row)
            XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: 10), .completed)
            XCTAssertFalse(destination.exists)
            XCTAssertEqual(row.label, title)
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
            if !largeText {
                let licenses = app.buttons["fst.settings.licenses"]
                XCTAssertEqual(licenses.label, "View Licenses")
                XCTAssertGreaterThanOrEqual(licenses.frame.height, 44)
                XCTAssertLessThanOrEqual(licenses.frame.height, 45)
                XCTAssertLessThan(licenses.frame.maxY, row.frame.minY)
                XCTAssertLessThanOrEqual(row.frame.height, 62, "No extra padding around the two-line description")
                let reset = app.buttons["fst.settings.reset"]
                XCTAssertEqual(reset.label, "Reset App Settings")
                XCTAssertLessThan(row.frame.maxY, reset.frame.minY)
                XCTAssertEqual(reset.frame.height, 46.33, accuracy: 0.75, "Match the reference's prominent button")
            }
            let reading = RecognizedText.recognize(row, label: "\(title) \(description)", frame: row.frame)
            XCTAssertTrue(RecognizedText.showsWhole("\(title) \(description)", in: reading.text),
                          reading.text ?? "Missing painted text")
            SongsUITestSupport.record(app, name: largeText ? "settings-link-rows-ax5" : "settings-link-rows")
            return try XCTUnwrap(reading.lineHeight)
        }

        let regular = try read(largeText: false)
        let large = try read(largeText: true)
        XCTAssertGreaterThanOrEqual(large / regular, RecognizedText.minimumGrowth)
    }
    #endif

    // MARK: - First Run replay

    /// Show on a First Run Guides row opens that page's guide with page dots, Next, Skip and
    /// Close; Next moves to a second page with Back; Done on the last page closes it.
    @MainActor
    func testFirstRunReplayFromSettings() throws {
        let app = launch()
        let show = app.buttons["fst.settings.first-run.shop"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(show, in: app, scrollingUp: false)
        XCTAssertEqual(show.label, "Show Item Shop guide")
        #if FST_UIKIT_PORT
        let frame = show.frame
        XCTAssertGreaterThanOrEqual(frame.height, 44)
        XCTAssertEqual(frame.width, 75, accuracy: 1)
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let pixels = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: app.windows.firstMatch.frame.width))
        let bands: [(CGFloat, ClosedRange<Double>)] = [(2, 0...0.05), (8, 0.95...1)]
        for (offset, expected) in bands {
            let band = CGRect(x: frame.midX - 4, y: frame.minY + offset, width: 8, height: 2)
            let blue = try XCTUnwrap(pixels.fraction(in: band, matching: ButtonFillPixels.accentBlue))
            XCTAssertTrue(expected.contains(blue), "Guide fill at vertical offset \(offset): \(blue)")
        }
        show.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.07)).tap()
        #else
        show.tap()
        #endif
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        let dots = element(app, "fst.first-run.dots")
        XCTAssertTrue(dots.exists)
        XCTAssertTrue((dots.value as? String ?? "").hasPrefix("1 of "), "Dots read the first page")
        XCTAssertTrue(app.buttons["fst.first-run.skip"].exists)
        XCTAssertFalse(app.buttons["fst.first-run.back"].exists)
        next.tap()
        XCTAssertTrue(app.buttons["fst.first-run.back"].waitForExistence(timeout: 10))
        SongsUITestSupport.record(app, name: "first-run-replay-second-page")
        app.buttons["fst.first-run.skip"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }

    #if FST_UIKIT_PORT
    /// The compact Show fill grows with its label at AX5 without clipping its text.
    @MainActor
    func testFirstRunShowButtonGrowsAtLargestText() throws {
        let fixture = ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
        let app = launch(["FST_API_BASE_URL": fixture], largeText: true)
        defer { app.terminate() }
        let links = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(links.waitForExistence(timeout: 15))
        links.tap()
        let guides = FestivalApp.quickLinkRow("first-run", label: "First Run Guides", in: app)
        for _ in 0..<5 where !guides.isHittable { app.swipeUp() }
        XCTAssertTrue(guides.isHittable)
        guides.tap()
        let show = app.buttons["fst.settings.first-run.songs"]
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: show)
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: 10), .completed)
        XCTAssertEqual(show.label, "Show Songs guide")
        XCTAssertGreaterThan(show.frame.height, 60)
        let drawn = RecognizedText.recognize(show, label: "Show", frame: show.frame)
        XCTAssertTrue(RecognizedText.showsWhole("Show", in: drawn.text))
    }
    #endif

    // MARK: - AX5

    /// The empty Licenses note draws in full at standard size and scrolls to the end at AX5.
    @MainActor
    func testLicensesNoteScalesWithoutClipping() throws {
        let standard = try readLicensesNote(largeText: false)
        let largest = try readLicensesNote(largeText: true)
        XCTAssertGreaterThanOrEqual(largest / standard, RecognizedText.minimumGrowth)
    }

    @MainActor
    private func readLicensesNote(largeText: Bool) throws -> CGFloat {
        let app = launch(["FST_DEBUG_ROUTE": "licenses", "FST_DEBUG_STILL_BACKGROUND": "1"], largeText: largeText)
        defer { app.terminate() }
        let note = app.staticTexts["fst.licenses.empty"]
        let end = "This list updates the day one is added."
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(note.label.hasSuffix(end))
        let firstLine = RecognizedText.recognizeLine("This build", in: note)
        if largeText {
            let scroll = app.scrollViews.containing(.staticText, identifier: note.identifier).firstMatch
            XCTAssertTrue(scroll.exists)
            scroll.swipeUp(velocity: .fast)
        }
        let expected = largeText ? "added." : note.label
        let visible = RecognizedText.recognize(note, label: expected, frame: note.frame)
        XCTAssertTrue(RecognizedText.showsWhole(expected, in: visible.text), "Rendered note: \(visible.text ?? "none")")
        return try XCTUnwrap(firstLine.lineHeight)
    }

    /// At AX5 the page keeps its switches named and large, wraps instead of clipping, and the
    /// Accessibility card passes a scoped accessibility audit.
    @MainActor
    func testSettingsAtAX5PassesAScopedAudit() throws {
        let app = launch(largeText: true)
        let icons = app.switches["fst.settings.show-instrument-icons"]
        XCTAssertTrue(icons.waitForExistence(timeout: 25))
        XCTAssertGreaterThanOrEqual(icons.frame.height, 43.5)
        XCTAssertFalse(icons.label.isEmpty)
        var issues: [String] = []
        try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .hitRegion]) { issue in
            guard issue.element?.identifier == "fst.settings.show-instrument-icons" else { return true }
            issues.append("\(issue.element?.identifier ?? ""): \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [])
        SongsUITestSupport.record(app, name: "settings-ax5")
    }

    // MARK: - Notifications

    /// The bell opens Notifications with a profile selected: the sheet has its title and Close,
    /// and shows either rows or the empty state; Close dismisses it.
    @MainActor
    func testNotificationsSheetOpensAndCloses() throws {
        let app = launch(["FST_DEBUG_PROFILE": "fixture-player-1:FixturePlayer", "FST_UI_TEST_CLEAR_PROFILE": "0"])
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 25))
        bell.tap()
        let close = app.buttons["fst.notifications.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Notifications"].exists || app.staticTexts["Notifications"].exists)
        let content = element(app, "fst.notifications.empty")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fst.notifications.row.'"))
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"), object: rows
        )
        _ = XCTWaiter.wait(for: [loaded], timeout: 8)
        XCTAssertTrue(content.exists || rows.count > 0, "Rows or the empty state")
        SongsUITestSupport.record(app, name: "notifications-sheet")
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }
}
