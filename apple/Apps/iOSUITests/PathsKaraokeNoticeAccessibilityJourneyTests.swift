import UIKit
import XCTest

// MARK: - Paths Karaoke notice after the chart (issue #649)

/// The "Some Instruments Unavailable" notice waits for the path on screen (issue #649,
/// `load-transition` R1): Paths opens on its labelled spinner alone, and the system alert
/// appears only once every visible form has replaced its spinner with its image, table or
/// error.
///
/// The fixture's `/__fixture__/hold-paths` control holds the opening's path reads, so the
/// pre-resolution state stays on screen while the journey checks it:
///
/// - **Held:** exactly one busy indicator per held form, named for it ("Loading image path"
///   / "Loading text path") and matching the View menu, nothing of a chart (no image, table,
///   activation, zoom or error) and no notice, through a dwell longer than the old
///   `onAppear` alert took; Close and the selectors stay hittable and an audit passes on
///   the held state.
/// - **Released:** the notice appears; at that moment the chart is loaded behind it and no
///   spinner is left. The notice reads its message and offers OK and "Don't show again",
///   and OK returns to the loaded chart.
/// - **iPhone Duo book pose** (Side by Side is the only mode, `hinge-columns` R10): only the
///   table's read is held, so the image loads while the table still spins. The notice must
///   not appear over that spinner; it follows the table.
///
/// Forms: the device's own (the iPhone sheet; the iPad full-window cover, #368), at Large
/// and AX5; the simulated folded iPhone Duo sheet on an iPhone; the simulated book pose on
/// a landscape iPad (the iPhone window is narrower than the inner display). The audit runs
/// every type but contrast, Dynamic Type and clipping: `PathsSwitchAccessibilityJourneyTests`
/// audits the same spinner and selectors for those with measured waivers, and the notice
/// is UIKit's (`testing/apple/accessibility.md`).
///
/// Runs against `tools/mock_service.py --large-catalogue` (`apple-ci` default port 8765;
/// `FST_PATHS_FIXTURE_URL` points a local run at another port); each test skips when the
/// listener has no hold control.
///
/// HIG Alerts: "Prefer conveying information in context"; HIG Progress indicators: "Help
/// people understand what's happening by describing the action".
final class PathsKaraokeNoticeAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_PATHS_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// The selectors, in reading order.
    private static let selectors = ["fst.paths.instrument", "fst.paths.difficulty", "fst.paths.display"]

    /// The notice's title.
    private static let notice = "Some Instruments Unavailable"

    /// Longest hold a journey asks for (×4 in a VM; the fixture's limit is 240 s).
    private static let holdSeconds = Int(FestivalApp.budget(60))

    /// Width of the simulated inner display (`DebugDuoWindow.book`).
    private static let innerDisplayWidth: CGFloat = 951

    /// Audit types for the held state: contrast, Dynamic Type and clipping of this spinner
    /// and these selectors are measured by `PathsSwitchAccessibilityJourneyTests`.
    private static let auditTypes = XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType, .textClipped])

    override func tearDown() {
        _ = PathsUITestSupport.pathHold(origin: Self.origin, "seconds=0")
        super.tearDown()
    }

    // MARK: - Journeys

    /// The device's own form at the default size: the iPhone sheet, the iPad cover.
    @MainActor
    func testNoticeWaitsForTheHeldPath() throws {
        let app = try launch(name: "default")
        try openOnSongDetail(app, duoWindow: nil)
        try assertNoticeWaitsForHeldChart(in: app, name: "default")
    }

    /// The device's own form at AX5.
    @MainActor
    func testNoticeWaitsForTheHeldPathAtAX5() throws {
        let app = try launch(name: "ax5", contentSize: .accessibilityExtraExtraExtraLarge)
        try openOnSongDetail(app, duoWindow: nil)
        try assertNoticeWaitsForHeldChart(in: app, name: "ax5")
    }

    /// iPhone Duo folded: the compact sheet (simulated on an iPhone).
    @MainActor
    func testNoticeWaitsForTheHeldPathDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        let app = try launch(name: "duo-folded", duoWindow: "folded")
        try openOnSongDetail(app, duoWindow: "folded")
        try assertNoticeWaitsForHeldChart(in: app, name: "duo-folded")
    }

    /// iPhone Duo book pose: Side by Side, the image loaded and the table held. The notice
    /// waits for the table (simulated on a landscape iPad, whose window fits the inner
    /// display).
    @MainActor
    func testNoticeWaitsForEveryPaneDuoBook() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad,
                      "The book pose needs the inner display's width: a landscape iPad")
        let app = try launch(name: "duo-book", duoWindow: "book", orientation: .landscapeLeft)
        guard app.windows.firstMatch.frame.width >= Self.innerDisplayWidth else {
            app.terminate()
            throw XCTSkip("Book pose needs a \(Int(Self.innerDisplayWidth)) pt window: \(app.windows.firstMatch.frame)")
        }
        try openOnSongDetail(app, duoWindow: "book")
        try assertNoticeWaitsForTheHeldTable(in: app)
    }

    // MARK: - Single form

    /// Hold every path read, open Paths, check the held state, release and check the notice.
    ///
    /// - Parameters:
    ///   - app: The running app on `fixture-pulse`'s Song Detail.
    ///   - name: Run name for messages and attachments.
    /// - Throws: A failed requirement or audit.
    @MainActor
    private func assertNoticeWaitsForHeldChart(in app: XCUIApplication, name: String) throws {
        defer { app.terminate() }
        try hold(nil)
        app.buttons["fst.song-detail.paths"].tap()
        let display = PathsUITestSupport.element("fst.paths.display", in: app)
        XCTAssertTrue(display.waitForExistence(timeout: FestivalApp.budget(10)), "No Paths sheet (\(name))")
        let form = (display.value as? String) == "Text" ? "text" : "image"
        let spinner = PathsUITestSupport.spinner(in: app, form: form)
        XCTAssertTrue(spinner.waitForExistence(timeout: FestivalApp.budget(10)),
                      "No 'Loading \(form) path' spinner (\(name)); View shows \(display.value ?? "nil")")
        try waitUntilHeldReadArrives()
        assertOnlySpinners([form], in: app, name)
        assertNoNoticeWhileHeld(in: app, name)
        assertControlsReachable(in: app, name)
        record(app, name: "paths-notice-\(name)-held")
        try audit(app, name)
        XCTAssertTrue(spinner.exists, "The spinner left during the audit (\(name))")

        try release()
        try assertNoticeFollowsTheChart(in: app, name)
        XCTAssertTrue(PathsUITestSupport.loadedChart(in: app).exists, "OK left no chart (\(name))")
    }

    // MARK: - Side by Side

    /// Hold the table's read only, open Paths in book pose (Side by Side): the image loads
    /// beside the table's spinner and no notice shows; released, the notice follows the table.
    ///
    /// - Parameter app: The running app on `fixture-pulse`'s Song Detail in book pose.
    /// - Throws: A failed requirement or audit.
    @MainActor
    private func assertNoticeWaitsForTheHeldTable(in app: XCUIApplication) throws {
        let name = "duo-book"
        defer { app.terminate() }
        try hold("data")
        app.buttons["fst.song-detail.paths"].tap()
        let image = app.images["fst.paths.image"]
        XCTAssertTrue(image.waitForExistence(timeout: FestivalApp.budget(15)), "Side by Side shows no image (\(name))")
        let textSpinner = PathsUITestSupport.spinner(in: app, form: "text")
        XCTAssertTrue(textSpinner.waitForExistence(timeout: FestivalApp.budget(5)),
                      "No 'Loading text path' spinner beside the image (\(name))")
        try waitUntilHeldReadArrives()
        XCTAssertFalse(PathsUITestSupport.element("fst.paths.display", in: app).exists,
                       "Book pose keeps Side by Side, with no View menu (\(name))")
        XCTAssertLessThan(image.frame.midX, textSpinner.frame.midX, "The image pane is first (\(name))")
        assertOnlySpinners(["text"], in: app, name, imageLoaded: true)
        assertNoNoticeWhileHeld(in: app, name)
        record(app, name: "paths-notice-\(name)-table-held")
        try audit(app, name)
        XCTAssertTrue(textSpinner.exists, "The table's spinner left during the audit (\(name))")

        try release()
        try assertNoticeFollowsTheChart(in: app, name)
        XCTAssertTrue(image.exists, "Side by Side lost its image (\(name))")
        XCTAssertTrue(PathsUITestSupport.element("fst.paths.text.Solo_Guitar.expert", in: app).exists,
                      "Side by Side shows no table after the notice (\(name))")
    }

    // MARK: - Assertions

    /// The held sheet exposes only the named spinners of `forms` (busy indicators), nothing
    /// of a chart and, unless `imageLoaded`, no image.
    ///
    /// - Parameters:
    ///   - forms: `image` and/or `text`, the forms still loading.
    ///   - app: The running app.
    ///   - name: Run name, for messages.
    ///   - imageLoaded: The image pane has loaded (Side by Side with the table held).
    @MainActor
    private func assertOnlySpinners(_ forms: [String], in app: XCUIApplication, _ name: String,
                                    imageLoaded: Bool = false) {
        let all = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Loading ", " path"
        ))
        XCTAssertEqual(all.count, forms.count, "Spinners: \(all.allElementsBoundByIndex.map(\.label)) (\(name))")
        let window = app.windows.firstMatch.frame
        for form in forms {
            let spinner = PathsUITestSupport.spinner(in: app, form: form)
            XCTAssertEqual(spinner.elementType, .activityIndicator, "'Loading \(form) path' is a busy indicator (\(name))")
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(spinner.frame),
                          "'Loading \(form) path' on screen: \(spinner.frame) in \(window) (\(name))")
        }
        let chart = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier IN %@",
            "fst.paths.text.", "fst.paths.activation.",
            imageLoaded ? ["fst.paths.error"] : ["fst.paths.image", "fst.paths.error", "fst.paths.zoom-in"]
        ))
        XCTAssertEqual(chart.count, 0, "Chart content before the held read resolved (\(name)): "
                       + chart.allElementsBoundByIndex.map(\.identifier).joined(separator: ", "))
    }

    /// No notice over the held state, through a dwell longer than the old `onAppear` alert
    /// took to present.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - name: Run name, for messages.
    @MainActor
    private func assertNoNoticeWhileHeld(in app: XCUIApplication, _ name: String) {
        XCTAssertFalse(app.alerts[Self.notice].waitForExistence(timeout: FestivalApp.budget(3)),
                       "The notice showed over the loading spinner (\(name))")
        XCTAssertGreaterThan(holdWaiting(), 0, "The held read was answered early (\(name))")
    }

    /// Close and the shown selectors are named, enabled and hittable while the path loads.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - name: Run name, for messages.
    @MainActor
    private func assertControlsReachable(in app: XCUIApplication, _ name: String) {
        for identifier in Self.selectors {
            let selector = PathsUITestSupport.element(identifier, in: app)
            XCTAssertTrue(selector.isHittable, "\(identifier) is reachable while loading (\(name))")
            XCTAssertFalse(selector.label.isEmpty, "\(identifier) is named (\(name))")
        }
        let close = app.buttons["fst.paths.close"]
        XCTAssertTrue(close.isHittable, "Close is reachable while loading (\(name))")
        XCTAssertTrue(close.isEnabled, "Close is enabled while loading (\(name))")
    }

    /// After the release: the notice appears with the chart loaded behind it and no spinner;
    /// it reads its message, offers both answers, and OK closes it.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - name: Run name, for messages.
    /// - Throws: A failed requirement.
    @MainActor
    private func assertNoticeFollowsTheChart(in app: XCUIApplication, _ name: String) throws {
        let warning = app.alerts[Self.notice]
        XCTAssertTrue(warning.waitForExistence(timeout: FestivalApp.budget(15)),
                      "No notice after the path loaded (\(name))")
        PathsUITestSupport.assertKaraokeNoticeFollowsLoadedChart(in: app, name)
        XCTAssertTrue(warning.staticTexts["Karaoke is not available for path visualization yet."].exists,
                      "The notice reads its message (\(name))")
        let ok = warning.buttons["OK"]
        XCTAssertTrue(ok.isHittable, "OK is reachable (\(name))")
        XCTAssertTrue(warning.buttons.matching(identifier: "fst.paths.warning.dismiss").firstMatch.exists
                      || warning.buttons["Don't show again"].exists, "Don't show again is offered (\(name))")
        record(app, name: "paths-notice-\(name)-after-load")
        ok.tap()
        XCTAssertTrue(warning.waitForNonExistence(timeout: FestivalApp.budget(5)), "OK left the notice (\(name))")
    }

    /// Audit the held state (``auditTypes``).
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - name: Run name, for messages and the attachment.
    /// - Throws: An audit that could not run.
    @MainActor
    private func audit(_ app: XCUIApplication, _ name: String) throws {
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, Self.auditTypes, name: "paths notice \(name)", reset: { issues.removeAll() }
        ) { issue in
            let node = try? issue.element?.snapshot()
            issues.append("\(node?.identifier ?? "nil") '\(node?.label ?? "")' "
                          + "\(String(describing: node?.frame)): \(issue.compactDescription)")
            return true
        }
        let attachment = XCTAttachment(string: issues.isEmpty ? "(none)" : issues.joined(separator: "\n"))
        attachment.name = "paths-notice-\(name)-audit"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(issues, [], "Audit issues while the path loads (\(name))")
    }

    // MARK: - Launch

    /// Launch with the notice reset, optionally in a simulated iPhone Duo window.
    ///
    /// - Parameters:
    ///   - name: Run name.
    ///   - contentSize: Dynamic Type size.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    ///   - orientation: Device orientation before launch.
    /// - Returns: The launched app.
    /// - Throws: A skip without the hold control.
    @MainActor
    private func launch(
        name: String, contentSize: UIContentSizeCategory = .large, duoWindow: String? = nil,
        orientation: UIDeviceOrientation = .portrait
    ) throws -> XCUIApplication {
        continueAfterFailure = false
        try XCTSkipUnless(PathsUITestSupport.pathHold(origin: Self.origin, "seconds=0") != nil,
                          "Start `tools/mock_service.py --large-catalogue` from this revision at \(Self.origin)")
        XCUIDevice.shared.orientation = orientation
        var environment = [
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_UI_TEST_RESET_PATH_WARNING": "1",
        ]
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
            // The folded vertical bar keeps Songs' search off the page: open the song by route.
            environment["FST_DEBUG_SONG"] = "fixture-pulse"
        }
        let app = FestivalApp.makeApp(environment)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        app.launch()
        return app
    }

    /// Reach `fixture-pulse`'s Song Detail with Paths closed.
    ///
    /// - Parameters:
    ///   - app: The launched app.
    ///   - duoWindow: The simulated Duo window, or nil (open from Songs).
    /// - Throws: A skip when the fixture never loads.
    @MainActor
    private func openOnSongDetail(_ app: XCUIApplication, duoWindow: String?) throws {
        if let duoWindow {
            guard app.buttons["fst.song-detail.paths"].waitForExistence(timeout: FestivalApp.budget(20)) else {
                app.terminate()
                throw XCTSkip("Song Detail never loaded; run tools/mock_service.py --large-catalogue on \(Self.origin).")
            }
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "\(duoWindow) "), object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
                           "The app never simulated \(duoWindow): \(readout.exists ? readout.label : "no readout")")
        } else {
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
            guard rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(20)) else {
                app.terminate()
                throw XCTSkip("Songs never loaded; run tools/mock_service.py --large-catalogue on \(Self.origin).")
            }
            PathsUITestSupport.openSongDetail(in: app)
        }
        let open = app.buttons["fst.song-detail.paths"]
        for _ in 0..<20 where !open.isHittable {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(open.isHittable, "Paths is reachable on Song Detail")
    }

    // MARK: - Fixture hold control

    /// Hold the opening's path reads.
    ///
    /// - Parameter form: `image` or `data` to hold one form's reads, nil for both.
    /// - Throws: A missing hold control.
    private func hold(_ form: String?) throws {
        let query = "seconds=\(Self.holdSeconds)" + (form.map { "&form=\($0)" } ?? "")
        let status = try XCTUnwrap(PathsUITestSupport.pathHold(origin: Self.origin, query), "Hold control")
        XCTAssertTrue(status.held, "Paths reads held")
    }

    /// Answer the held reads.
    ///
    /// - Throws: A missing hold control.
    private func release() throws {
        let status = try XCTUnwrap(PathsUITestSupport.pathHold(origin: Self.origin, "seconds=0"), "Hold control")
        XCTAssertFalse(status.held, "Paths reads released")
    }

    /// Reads parked at the fixture now (0 without the control).
    private func holdWaiting() -> Int {
        PathsUITestSupport.pathHold(origin: Self.origin, nil)?.waiting ?? 0
    }

    /// Wait until the opening's read reaches the held listener.
    ///
    /// - Throws: Never; a read that never arrives fails the test.
    private func waitUntilHeldReadArrives() throws {
        let deadline = Date().addingTimeInterval(FestivalApp.budget(10))
        while Date() < deadline {
            if holdWaiting() > 0 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("The opening's Paths read never reached the fixture")
    }

    /// Attach a screenshot.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
