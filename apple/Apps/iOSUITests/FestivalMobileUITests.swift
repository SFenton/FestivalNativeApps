import XCTest
import UIKit

/// Fixture-backed native flows, never production or privileged endpoints.
final class FestivalMobileUITests: XCTestCase {
    // MARK: - Navigation and orientation

    /// Traverse Songs, Detail and page two, then verify landscape layout survives.
    ///
    /// - Throws: An XCTest failure for missing accessible actions or screen state.
    @MainActor
    func testSongsDetailScoresInPortraitAndLandscape() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()

        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Fixture song row did not load")
        record(app, name: "songs-portrait")
        row.tap()

        XCTAssertTrue(app.staticTexts["Intensity"].waitForExistence(timeout: 10))
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10), "Lead leaderboard action is missing")
        record(app, name: "song-detail-portrait")
        lead.tap()

        let next = app.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Pagination is not reachable")
        XCTAssertTrue(app.staticTexts["1 / 2"].exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        record(app, name: "song-leaderboard-page2-portrait")

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
        record(app, name: "song-leaderboard-page2-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// Run the system audit against a visible fixture-backed native screen.
    ///
    /// - Throws: An accessibility audit issue for actionable labels/contrast/order.
    @MainActor
    func testSongsAccessibilityAudit() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        try app.performAccessibilityAudit(for: .all) { issue in
            let element = issue.element
            let independentlyMeasurableText = UIDevice.current.userInterfaceIdiom == .pad
                && issue.auditType == .contrast
                && element?.elementType == .staticText
                && element?.identifier.isEmpty == true
                && element?.label.isEmpty == false
            let measuredRatio = independentlyMeasurableText
                ? self.textPixelContrast(app: app, element: element)
                : nil
            XCTContext.runActivity(named: "Audit element") { activity in
                let detail = """
                Audit: \(issue.compactDescription)
                Explanation: \(issue.detailedDescription)
                Element: \(element.map { String(describing: $0.elementType) } ?? "none")
                Label: \(element?.label ?? "none")
                Identifier: \(element?.identifier ?? "none")
                Frame: \(element.map { String(describing: $0.frame) } ?? "none")
                Measured contrast: \(measuredRatio.map { String(format: "%.2f", $0) } ?? "not measured")
                """
                let attachment = XCTAttachment(string: detail)
                attachment.name = "Audit element details"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
            return measuredRatio.map { $0 >= 4.5 } ?? false
        }
    }

    /// Exercise real native no-results and service-error presentation.
    ///
    /// - Throws: A missing fixture-only state or retry action.
    @MainActor
    func testEmptyAndErrorCatalogueStates() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "empty"
        app.launch()
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 15))
        record(app, name: "songs-empty")
        app.terminate()

        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        app.launch()
        XCTAssertTrue(app.staticTexts["Songs unavailable"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Retry"].exists)
        record(app, name: "songs-service-error")
    }

    /// Search and tab state must remain accessible across native section changes.
    ///
    /// - Throws: A missing search, Settings or Leaderboards destination.
    @MainActor
    func testSearchAndRootTabDestinations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let search = app.textFields["fst.songs.search"]
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("zzzz")
        let noMatches = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "No Results for")
        ).firstMatch
        XCTAssertTrue(
            noMatches.waitForExistence(timeout: 10),
            "Search result labels: \(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        XCTAssertTrue(noMatches.label.contains("zzzz"))
        record(app, name: "songs-search-empty")
        search.typeText("\n")

        let settingsTab = rootControl("Settings", app: app)
        settingsTab.tap()
        XCTAssertTrue(
            settingsTab.isSelected,
            "Tab value: \(String(describing: settingsTab.value)); labels: \(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        XCTAssertTrue(
            app.staticTexts["App Settings"].waitForExistence(timeout: 10),
            "Settings labels: \(app.staticTexts.allElementsBoundByIndex.prefix(24).map(\.label))"
        )
        record(app, name: "settings-portrait")
        rootControl("Leaderboards", app: app).tap()
        XCTAssertTrue(app.staticTexts["Leaderboards overview migration in progress"].exists)
        record(app, name: "leaderboards-portrait")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10))
    }

    /// Additive motion preference survives a true app relaunch, then is restored.
    ///
    /// - Throws: An unavailable switch or lost preference across process lifetime.
    @MainActor
    func testAccessibilitySettingPersistsAcrossRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        rootControl("Settings", app: app).tap()
        let motion = app.switches["fst.settings.reduce-motion"]
        XCTAssertTrue(motion.waitForExistence(timeout: 10))
        let original = try XCTUnwrap(motion.value as? String)
        XCTAssertTrue(["0", "1"].contains(original))
        motion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = original == "0" ? "1" : "0"
        let changedValue = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", changed), object: motion
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [changedValue], timeout: 5),
            .completed,
            "Motion switch frame: \(motion.frame), value: \(String(describing: motion.value))"
        )
        record(app, name: "settings-motion-override")

        app.terminate()
        app.launch()
        rootControl("Settings", app: app).tap()
        let restored = app.switches["fst.settings.reduce-motion"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.value as? String, changed)
        restored.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(restored.value as? String, original)
    }

    /// A hidden chart disappears from navigation, but remains in song Intensity.
    ///
    /// - Throws: A broken Settings-to-screen dependency or missing slider value.
    @MainActor
    func testInstrumentVisibilityAndScoreFilterPropagation() async throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        rootControl("Settings", app: app).tap()

        let filter = app.switches["Filter Invalid Scores"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        let originalFilter = try XCTUnwrap(filter.value as? String)
        setSwitch(filter, to: "1")
        let leeway = app.sliders["fst.settings.leeway"]
        XCTAssertTrue(leeway.waitForExistence(timeout: 10))
        XCTAssertTrue(
            (leeway.value as? String)?.contains("%") == true,
            "The slider must announce a numeric score tolerance"
        )

        let bass = app.switches["fst.settings.instrument.Solo_Bass"]
        reveal(bass, in: app, scrollingUp: true)
        let originalBass = try XCTUnwrap(bass.value as? String)
        setSwitch(bass, to: "0")

        rootControl("Songs", app: app).tap()
        let menu = app.buttons["fst.songs.instrument-filter"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        XCTAssertFalse(app.buttons["Bass"].exists)
        XCTAssertTrue(app.buttons["Lead"].exists, "Instrument menu did not open")
        let menuItem = app.collectionViews.buttons["All instruments"].firstMatch
        if menuItem.exists {
            menuItem.tap()
        } else {
            app.buttons["All instruments"].firstMatch.tap()
        }

        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["Bass"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fst.song-detail.leaderboard.Solo_Bass"].exists)
        let leadChart = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(leadChart.exists)
        leadChart.tap()
        let next = app.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let enabled = try await latestFixtureScoreQuery()
        XCTAssertEqual(enabled.offset, 0)
        XCTAssertNotNil(enabled.leeway, "Enabled score filtering omitted its wire tolerance")

        rootControl("Settings", app: app).tap()
        reveal(bass, in: app, scrollingUp: true)
        setSwitch(bass, to: originalBass)
        reveal(filter, in: app, scrollingUp: false)
        setSwitch(filter, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        let disabled = try await latestFixtureScoreQuery()
        XCTAssertEqual(disabled.offset, 25)
        XCTAssertNil(disabled.leeway, "Disabled filtering still sent leeway")
        rootControl("Settings", app: app).tap()
        reveal(filter, in: app, scrollingUp: false)
        setSwitch(filter, to: originalFilter)
    }

    /// Split navigation must retain a chart filter and clear it when hidden in Settings.
    ///
    /// - Throws: Lost tab-owned state, a hidden chart still selected or an absent notice.
    @MainActor
    func testSectionSwitchKeepsAndSanitizesInstrument() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let menu = app.buttons["fst.songs.instrument-filter"]
        menu.tap()
        let leadItem = app.collectionViews.buttons["Lead"].firstMatch
        if leadItem.exists {
            leadItem.tap()
        } else {
            app.buttons["Lead"].firstMatch.tap()
        }
        XCTAssertTrue(menu.label.contains("Lead"))
        rootControl("Settings", app: app).tap()
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(menu.label.contains("Lead"), "The selected chart was lost on tab switch")
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].exists)

        rootControl("Settings", app: app).tap()
        let lead = app.switches["fst.settings.instrument.Solo_Guitar"]
        reveal(lead, in: app, scrollingUp: true)
        let original = try XCTUnwrap(lead.value as? String)
        setSwitch(lead, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(menu.label.contains("All instruments"))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Lead was hidden")
            ).firstMatch.waitForExistence(timeout: 10)
        )

        rootControl("Settings", app: app).tap()
        reveal(lead, in: app, scrollingUp: true)
        setSwitch(lead, to: original)
    }

    /// A confirmed app-settings reset must not erase the current Songs query.
    ///
    /// - Throws: Missing reset confirmation, lost route state or wrong defaults.
    @MainActor
    func testAppOnlyResetPreservesSongsSearch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let search = app.textFields["fst.songs.search"]
        search.tap()
        search.typeText("zzzz\n")
        let noMatches = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "No Results for")
        ).firstMatch
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10))
        rootControl("Settings", app: app).tap()

        let filter = app.switches["Filter Invalid Scores"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        setSwitch(filter, to: "1")
        let motion = app.switches["fst.settings.reduce-motion"]
        reveal(motion, in: app, scrollingUp: true)
        setSwitch(motion, to: "1")

        let publication = app.buttons["Check Publication"]
        reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "Publication 7")
        let reset = app.buttons["fst.settings.reset"]
        reveal(reset, in: app, scrollingUp: true)
        reset.tap()
        let confirmation = app.buttons.matching(
            NSPredicate(format: "label == %@", "Reset App Settings")
        ).allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(confirmation, "Reset confirmation was not presented")
        confirmation?.tap()

        reveal(filter, in: app, scrollingUp: false)
        XCTAssertEqual(filter.value as? String, "0")
        XCTAssertFalse(app.sliders["fst.settings.leeway"].exists)
        reveal(motion, in: app, scrollingUp: true)
        XCTAssertEqual(motion.value as? String, "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10))
    }

    /// Explain why an unpinned generation change returns an old Detail route to Songs.
    ///
    /// - Throws: Missing unverified-data label, stale Detail route or absent notice.
    @MainActor
    func testHeaderlessRolloverExplainsRouteReset() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let port = UIDevice.current.userInterfaceIdiom == .pad ? 8768 : 8767
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:\(port)"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.staticTexts["Showing live songs without publication verification"].exists
        )
        XCTAssertFalse(app.staticTexts["Publication changed - updating songs"].exists)
        song.tap()
        XCTAssertTrue(app.staticTexts["Intensity"].waitForExistence(timeout: 10))

        rootControl("Settings", app: app).tap()
        let publication = app.buttons["Check Publication"]
        reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "Publication 8")

        rootControl("Songs", app: app).tap()
        let notice = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Published scores changed.")
        ).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Intensity"].exists)
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        record(app, name: "songs-unpinned-rollover-notice")
    }

    /// Probe Duo outer-window aspect and reachable controls; camera cutouts need pose tests.
    ///
    /// - Throws: A nonrotating simulator window or unreachable fixture control.
    @MainActor
    func testDuoOuterFourRotations() throws {
        continueAfterFailure = false
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))

        let orientations: [(UIDeviceOrientation, String, Bool)] = [
            (.portrait, "portrait", false),
            (.landscapeLeft, "landscape-left", true),
            (.portraitUpsideDown, "portrait-upside-down", false),
            (.landscapeRight, "landscape-right", true),
        ]
        for (orientation, name, isLandscape) in orientations {
            XCUIDevice.shared.orientation = orientation
            let aspect = NSPredicate(block: { _, _ in
                let frame = app.windows.firstMatch.frame
                return isLandscape
                    ? frame.width > frame.height : frame.height > frame.width
            })
            let geometry = XCTNSPredicateExpectation(
                predicate: aspect, object: app
            )
            let settled = XCTWaiter.wait(for: [geometry], timeout: 5)
            record(app, name: "duo-outer-\(name)")
            let frame = app.windows.firstMatch.frame
            XCTAssertEqual(
                settled, .completed,
                "\(name) never reached the expected aspect; window: \(frame)"
            )
            if isLandscape {
                XCTAssertGreaterThan(frame.width, frame.height, name)
            } else {
                XCTAssertGreaterThan(frame.height, frame.width, name)
            }
            XCTAssertTrue(row.isHittable, "Song row obscured in \(name)")
            XCTAssertTrue(
                app.buttons["fst.songs.instrument-filter"].isHittable,
                "Filter action obscured in \(name)"
            )
        }
    }

    // MARK: - Evidence

    /// Select native sidebar buttons on iPad, system tab buttons on iPhone.
    ///
    /// - Parameters:
    ///   - name: Root section's visible label.
    ///   - app: Launched Festival fixture app.
    /// - Returns: Accessible native destination control for the current idiom.
    @MainActor
    private func rootControl(_ name: String, app: XCUIApplication) -> XCUIElement {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return app.buttons["fst.nav.\(name.lowercased())"]
        }
        return app.tabBars.buttons[name]
    }

    private struct FixtureScoreQuery: Decodable {
        let last: Request?

        struct Request: Decodable {
            let top: Int
            let offset: Int
            let leeway: Double?
        }
    }

    /// Inspect only loopback fixture query numbers, never a service account.
    ///
    /// - Returns: The most recent validated synthetic score request.
    /// - Throws: A missing fixture listener or invalid diagnostic response.
    @MainActor
    private func latestFixtureScoreQuery() async throws -> FixtureScoreQuery.Request {
        let url = URL(string: "http://127.0.0.1:8765/__fixture__/last-score-query")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONDecoder().decode(FixtureScoreQuery.self, from: data).last)
    }

    /// Scroll the lazily created native Settings Form to a visible control.
    ///
    /// - Parameters:
    ///   - element: Settings action to reveal before tapping or asserting.
    ///   - app: Fixture app with the Settings Form visible.
    ///   - scrollingUp: True for lower sections, false for the first section.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if scrollingUp {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(
            element.isHittable,
            "Settings control not reachable: \(element.identifier); visible controls: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(16).map(\.label))"
        )
    }

    /// Toggle the trailing native switch only when its current value differs.
    ///
    /// - Parameters:
    ///   - element: Settings switch, not the surrounding static-text label.
    ///   - value: Expected accessibility value, `0` or `1`.
    @MainActor
    private func setSwitch(_ element: XCUIElement, to value: String) {
        if element.value as? String != value {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(element.value as? String, value)
    }

    /// Verify actual sRGB pixels before handling Xcode 27's iPad contrast
    /// false positives for small SwiftUI static-text nodes.
    ///
    /// - Parameters:
    ///   - app: Fixture app with visible foreground and background.
    ///   - element: Manufacturer-reported static-text node.
    /// - Returns: WCAG foreground/background contrast, or nil when sampling is unsafe.
    @MainActor
    private func textPixelContrast(
        app: XCUIApplication, element: XCUIElement?
    ) -> Double? {
        guard let element,
              let image = app.screenshot().image.cgImage,
              element.frame.width > 0, element.frame.height > 0,
              element.frame.width < 260, element.frame.height < 50 else {
            return nil
        }
        let scale = CGFloat(image.width) / app.windows.firstMatch.frame.width
        let rect = CGRect(
            x: element.frame.minX * scale, y: element.frame.minY * scale,
            width: element.frame.width * scale, height: element.frame.height * scale
        ).integral
        guard let cropped = image.cropping(to: rect) else { return nil }
        var bytes = [UInt8](repeating: 0, count: cropped.width * cropped.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: cropped.width, height: cropped.height,
                bitsPerComponent: 8, bytesPerRow: cropped.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cropped, in: CGRect(
                x: 0, y: 0, width: cropped.width, height: cropped.height
            ))
            return true
        }
        guard drawn else { return nil }
        var counts: [UInt32: Int] = [:]
        for index in stride(from: 0, to: bytes.count, by: 4) where bytes[index + 3] > 240 {
            let color = UInt32(bytes[index]) << 16
                | UInt32(bytes[index + 1]) << 8
                | UInt32(bytes[index + 2])
            counts[color, default: 0] += 1
        }
        guard let background = counts.max(by: { $0.value < $1.value })?.key,
              let foreground = counts.filter({ luminance($0.key) > 0.4 })
                  .max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        let light = luminance(foreground)
        let dark = luminance(background)
        return (max(light, dark) + 0.05) / (min(light, dark) + 0.05)
    }

    /// Convert three sRGB channels to WCAG 2.x relative luminance.
    ///
    /// - Parameter color: RGB value encoded as 0xRRGGBB.
    /// - Returns: Linear-light relative luminance between zero and one.
    private func luminance(_ color: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let value = Double((color >> shift) & 0xFF) / 255
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    /// Attach only the app's current display to the Xcode result bundle.
    ///
    /// - Parameters:
    ///   - app: Launched Festival fixture app.
    ///   - name: Named page/state/orientation for the evidence matrix.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        XCTContext.runActivity(named: name) { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }
}
