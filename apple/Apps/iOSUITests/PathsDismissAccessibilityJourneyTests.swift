import UIKit
import XCTest

// MARK: - Paths dismissal accessibility (issue #96, backfilled by #445)

/// The Paths viewer without its gestures: what a VoiceOver, Switch Control or Voice Control
/// user has where others swipe the sheet down or pinch the image (issue #96).
///
/// #96 let the system swipe-down close the Paths sheet (it had
/// `.interactiveDismissDisabled()`) and made the image viewport scroll sideways only once
/// the zoomed image is wider than it. `SongDetailJourneyTests/testSongPathsSwipeDownDismisses`
/// proves the gestures; this journey proves their alternatives (HIG Accessibility: "Offer
/// another physical interaction for core functionality—for example, provide a button as
/// well as swipe-to-dismiss"; Modality: "Always provide an obvious, platform-conventional
/// dismissal"):
///
/// - **Close** is a named, enabled button wholly on screen and hittable in Image (at fit
///   and zoomed) and in Text, and tapping it closes the viewer back to Song Detail with
///   Paths still reachable.
/// - **Zoom Out / Zoom In** stand in for the pinch: named, Zoom Out disabled at 100 %,
///   Zoom In at 300 %, with the zoom read as "Zoom <n> percent". Zooming in scales the
///   image (on a phone past the viewport's width, the two-axis state #96 introduced) and
///   keeps it named and every control reachable.
/// - **The path image** is an image named "Lead Expert CHOpt path" inside the
///   `fst.paths.image-viewport` scroll view.
/// - **Reading order:** the bar's zoom group and Close, then the image or table, then
///   Instrument, Difficulty and View.
/// - `performAccessibilityAudit` on the fitted image, the zoomed image and the table:
///   every type at the default size, every type but contrast at AX5
///   (`testing/apple/accessibility.md`). A contrast flag on a selector capsule or an
///   activation-table text passes only once its rendered contrast measures 4.5:1 or more;
///   a selector clipped or not growing in the simulated inner display passes only there
///   at Large (the iPhone's real window is narrower); at AX5 a selector flagged clipped
///   there passes only once Vision reads its value whole in the same run.
/// - **Text scaling:** the Difficulty value ("Expert", named in every form) draws whole
///   (Vision) and, at AX5, its rendered glyphs (`SongsUITestSupport.brightGlyphHeight`) are
///   over 1.35× as tall as in a paired Large launch of the same form, with Close, the zoom
///   group and the stacked selectors still on screen and hittable.
///
/// Forms, each at Large and AX5: the iPhone sheet; the iPhone Duo folded sheet and the
/// inner display's full-window cover (`DebugDuoWindow` simulation, as CI has no Duo device
/// type); the iPad's full-window cover (#368), where no system swipe exists. Runs against
/// `tools/mock_service.py --large-catalogue` (`apple-ci` default port 8765;
/// `FST_PATHS_FIXTURE_URL` points a local run at another port).
final class PathsDismissAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_PATHS_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// The selectors, in reading order.
    private static let selectors = ["fst.paths.instrument", "fst.paths.difficulty", "fst.paths.display"]

    /// Launch settings for one run.
    private struct Run {
        let name: String
        var contentSize = UIContentSizeCategory.large.rawValue
        var auditTypes: XCUIAccessibilityAuditType = .all
        /// `DebugDuoWindow` to simulate, or nil for the device itself.
        var duoWindow: String?

        /// Whether this run is at AX5, so it pairs with a Large launch to prove text growth.
        var isAX5: Bool {
            contentSize == UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        }

        /// An AX5 run: every audit type but contrast (`testing/apple/accessibility.md`).
        ///
        /// - Parameters:
        ///   - name: Attachment and message name.
        ///   - duoWindow: `DebugDuoWindow` to simulate, or nil.
        /// - Returns: The run.
        static func ax5(name: String, duoWindow: String? = nil) -> Run {
            Run(
                name: name,
                contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
                auditTypes: XCUIAccessibilityAuditType.all.subtracting(.contrast),
                duoWindow: duoWindow
            )
        }

        /// The same form at the default (Large) size, the AX5 run's growth baseline.
        var large: Run { Run(name: "\(name)-large-baseline", duoWindow: duoWindow) }
    }

    /// The Difficulty selector's value on the fixture's first chart: the Paths text measured
    /// for Dynamic Type growth. Every form names it (Instrument and View go icon-only on a
    /// phone and folded Duo), and it is white body text on the dark capsule.
    private static let measuredValue = "Expert"

    // MARK: - Journeys

    /// The device's own form at the default text size: an iPhone sheet, an iPad cover.
    @MainActor
    func testPathsCloseAndZoomWithoutGestures() throws {
        try runJourney(Run(name: "default"))
    }

    /// AX5: the Difficulty value grows over 1.35× its Large glyph height (a paired Large
    /// launch) and draws whole; Close, the zoom group and the selectors stay reachable and the
    /// audit (all but contrast) passes.
    @MainActor
    func testPathsCloseAndZoomWithoutGesturesAtAX5() throws {
        try runJourney(.ax5(name: "ax5"))
    }

    /// iPhone Duo folded: the compact sheet, titled "Paths · Lead" (#360).
    @MainActor
    func testPathsCloseAndZoomWithoutGesturesDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try runJourney(Run(name: "duo-folded", duoWindow: "folded"))
    }

    /// iPhone Duo inner display: the full-window cover (#368), which has no system swipe.
    @MainActor
    func testPathsCloseAndZoomWithoutGesturesDuoUnfolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try runJourney(Run(name: "duo-unfolded", duoWindow: "unfolded-portrait"))
    }

    /// iPhone Duo folded at AX5: the compact sheet's stacked selectors (icon-only
    /// Instrument and View, #360) with the same growth, whole-text and reachability checks.
    @MainActor
    func testPathsCloseAndZoomWithoutGesturesDuoFoldedAtAX5() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try runJourney(.ax5(name: "duo-folded-ax5", duoWindow: "folded"))
    }

    /// iPhone Duo inner display at AX5: the full-window cover's stacked, named selectors
    /// with the same growth, whole-text and reachability checks.
    @MainActor
    func testPathsCloseAndZoomWithoutGesturesDuoUnfoldedAtAX5() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try runJourney(.ax5(name: "duo-unfolded-ax5", duoWindow: "unfolded-portrait"))
    }

    // MARK: - Journey

    /// Open Paths on Image, check it at fit and zoomed with the buttons, close it with
    /// Close; reopen it on Text and close it with Close again. An AX5 run first launches the
    /// same form at Large to measure the Difficulty value's baseline glyph height.
    ///
    /// - Parameter run: Launch settings.
    /// - Throws: A skip without the fixture, or a failed requirement or audit.
    @MainActor
    private func runJourney(_ run: Run) throws {
        continueAfterFailure = false
        let baseline = run.isAX5 ? try measureBaseline(run.large) : nil
        let app = try launchOnPaths(run)
        defer { app.terminate() }
        let open = app.buttons["fst.song-detail.paths"]
        let display = element("fst.paths.display", in: app)

        // Image at fit: Zoom Out off, Zoom In on, the image named and inside its viewport.
        PathsUITestSupport.choose("Image", in: display, app: app)
        let image = app.images["fst.paths.image"]
        XCTAssertTrue(image.waitForExistence(timeout: FestivalApp.budget(15)), "No path image (\(run.name))")
        let viewport = element("fst.paths.image-viewport", in: app)
        assertImage(image, in: viewport, app: app, zoom: 100, run: run)
        let fitWidth = image.frame.width
        XCTAssertLessThanOrEqual(fitWidth, viewport.frame.width + 1,
                                 "Fitted image wider than its viewport (\(run.name))")
        assertCloseReachable(in: app, run: run, "image at fit")
        assertSelectorsReachable(in: app, run: run)
        try assertMeasuredValue(in: app, run: run, baseline: baseline)
        assertOrder(["fst.paths.zoom-out", "fst.paths.zoom-in", "fst.paths.close", "fst.paths.image"]
                    + Self.selectors, in: app, "image at fit (\(run.name))")
        record(app, name: "paths-dismiss-\(run.name)-image-fit")
        try audit(app, run: run, "image-fit")

        // Zoomed with the buttons; on a phone past the viewport's width (two-axis
        // scrolling, #96). Fit never enlarges the image, so the fixture's narrow path
        // still fits the iPad cover's width at 300 %.
        let zoomIn = app.buttons["fst.paths.zoom-in"]
        zoomIn.tap()
        zoomIn.tap()
        assertImage(image, in: viewport, app: app, zoom: 225, run: run)
        XCTAssertEqual(image.frame.width, fitWidth * 2.25, accuracy: 2,
                       "Zoom In did not scale the image (\(run.name))")
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertGreaterThan(image.frame.width, viewport.frame.width + 1,
                                 "Zoom In did not widen the image past its viewport (\(run.name))")
        }
        assertCloseReachable(in: app, run: run, "image zoomed")
        assertSelectorsReachable(in: app, run: run)
        record(app, name: "paths-dismiss-\(run.name)-image-zoomed")
        try audit(app, run: run, "image-zoomed")
        zoomIn.tap()
        assertImage(image, in: viewport, app: app, zoom: 300, run: run)

        // Close, not a swipe, returns to Song Detail.
        closeWithCloseButton(in: app, run: run, "from the zoomed image")

        // Text: Close is the same reachable button over the activation table.
        PathsUITestSupport.openPathsFromSongDetail(in: app)
        PathsUITestSupport.choose("Text", in: display, app: app)
        let table = element("fst.paths.text.Solo_Guitar.expert", in: app)
        XCTAssertTrue(table.waitForExistence(timeout: FestivalApp.budget(15)), "No Expert table (\(run.name))")
        XCTAssertFalse(app.buttons["fst.paths.zoom-in"].exists, "Zoom controls without the image (\(run.name))")
        assertCloseReachable(in: app, run: run, "text")
        assertSelectorsReachable(in: app, run: run)
        assertOrder(["fst.paths.close", "fst.paths.text.Solo_Guitar.expert", "fst.paths.activation.1"]
                    + Self.selectors, in: app, "text (\(run.name))")
        record(app, name: "paths-dismiss-\(run.name)-text")
        try audit(app, run: run, "text")
        closeWithCloseButton(in: app, run: run, "from the table")
        XCTAssertTrue(open.isHittable, "Paths is reachable again after Close (\(run.name))")
    }

    // MARK: - Launch

    /// Launch the run's form at its text size and open Paths: from Songs on the device's
    /// own form, by route from Song Detail in a simulated Duo window.
    ///
    /// - Parameter run: Launch settings.
    /// - Returns: The app with the Paths viewer open.
    /// - Throws: A skip when the fixture never loads.
    @MainActor
    private func launchOnPaths(_ run: Run) throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        var environment = [
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ]
        if let duoWindow = run.duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
            // The folded vertical bar keeps Songs' search off the page, so the Duo windows
            // open the song by route (as `DuoSongTitleJourneyTests`).
            environment["FST_DEBUG_SONG"] = "fixture-pulse"
        }
        let app = FestivalApp.makeApp(environment)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", run.contentSize]
        app.launch()
        if let duoWindow = run.duoWindow {
            guard app.buttons["fst.song-detail.paths"].waitForExistence(timeout: FestivalApp.budget(20)) else {
                app.terminate()
                throw XCTSkip("Song Detail never loaded; run tools/mock_service.py --large-catalogue on \(Self.origin).")
            }
            waitForDuoWindow(duoWindow, in: app)
            PathsUITestSupport.openPathsFromSongDetail(in: app)
        } else {
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
            guard rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(20)) else {
                app.terminate()
                throw XCTSkip("Songs never loaded; run tools/mock_service.py --large-catalogue on \(Self.origin).")
            }
            PathsUITestSupport.openPaths(in: app)
        }
        return app
    }

    /// The Difficulty value's rendered glyph height at Large in the AX5 run's form, on the
    /// fitted image (the state the AX5 run measures).
    ///
    /// - Parameter run: The Large twin of the AX5 run (``Run/large``).
    /// - Returns: The glyph height in screenshot pixels.
    /// - Throws: A skip without the fixture, or a missing measurement.
    @MainActor
    private func measureBaseline(_ run: Run) throws -> Int {
        let app = try launchOnPaths(run)
        defer { app.terminate() }
        PathsUITestSupport.choose("Image", in: element("fst.paths.display", in: app), app: app)
        XCTAssertTrue(app.images["fst.paths.image"].waitForExistence(timeout: FestivalApp.budget(15)),
                      "No path image (\(run.name))")
        XCTAssertTrue(app.staticTexts["Zoom 100 percent"].waitForExistence(timeout: FestivalApp.budget(5)),
                      "The image never settled at fit (\(run.name))")
        return try measuredGlyphs(in: app, run: run)
    }

    // MARK: - Assertions

    /// The image and its zoom group at one zoom level.
    ///
    /// - Parameters:
    ///   - image: `fst.paths.image`.
    ///   - viewport: `fst.paths.image-viewport`.
    ///   - app: The running app.
    ///   - zoom: Expected zoom, in percent (100–300).
    ///   - run: Launch settings, for messages.
    @MainActor
    private func assertImage(
        _ image: XCUIElement, in viewport: XCUIElement, app: XCUIApplication, zoom: Int, run: Run
    ) {
        XCTAssertEqual(image.elementType, .image, "The path is an image (\(run.name))")
        XCTAssertEqual(image.label, "Lead Expert CHOpt path", "The path image is named (\(run.name))")
        XCTAssertEqual(viewport.elementType, .scrollView, "The path scrolls in a scroll view (\(run.name))")
        let percent = app.staticTexts["Zoom \(zoom) percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: FestivalApp.budget(5)),
                      "Zoom reads 'Zoom \(zoom) percent' (\(run.name))")
        let zoomOut = app.buttons["fst.paths.zoom-out"]
        let zoomIn = app.buttons["fst.paths.zoom-in"]
        XCTAssertEqual(zoomOut.label, "Zoom Out", "Zoom Out is named (\(run.name))")
        XCTAssertEqual(zoomIn.label, "Zoom In", "Zoom In is named (\(run.name))")
        XCTAssertEqual(zoomOut.isEnabled, zoom > 100, "Zoom Out enabled only above 100 % (\(run.name), \(zoom) %)")
        XCTAssertEqual(zoomIn.isEnabled, zoom < 300, "Zoom In enabled only below 300 % (\(run.name), \(zoom) %)")
        for button in [zoomOut, zoomIn] where button.isEnabled {
            XCTAssertTrue(button.isHittable, "\(button.label) is reachable (\(run.name), \(zoom) %)")
        }
    }

    /// Text scaling on the Difficulty value (``measuredValue``): it draws whole (Vision reads
    /// it with no ellipsis or cut letters) and, in an AX5 run, its glyphs render over 1.35×
    /// as tall as at Large in the same form (`testing/apple/accessibility.md` Large text).
    ///
    /// The simulated inner display at Large lays its 669-pt named row out inside the
    /// iPhone's narrower window, so there only the growth baseline is taken, not the
    /// whole-text check (the audit's matching acceptance, below).
    ///
    /// - Parameters:
    ///   - app: The viewer on the fitted image.
    ///   - run: Launch settings.
    ///   - baseline: The Large launch's glyph height, for an AX5 run.
    /// - Throws: A missing screenshot or glyph pixels.
    @MainActor
    private func assertMeasuredValue(in app: XCUIApplication, run: Run, baseline: Int?) throws {
        let difficulty = element("fst.paths.difficulty", in: app)
        XCTAssertEqual(difficulty.value as? String, Self.measuredValue, "Difficulty value (\(run.name))")
        let glyphs = try measuredGlyphs(in: app, run: run)
        let frame = difficulty.frame
        let window = app.windows.firstMatch.frame
        let simulatedWide = simulatesInnerDisplay(run, in: window)
        let reading = RecognizedText.recognize(difficulty, label: Self.measuredValue, frame: frame)
        attach("paths-dismiss-\(run.name)-difficulty-text",
               "glyphs \(glyphs) px, baseline \(baseline.map(String.init) ?? "-") px; "
               + "read '\(reading.text ?? "")', line \(reading.lineHeight.map { "\($0)" } ?? "-") pt; frame \(frame)")
        if run.isAX5 || !simulatedWide {
            XCTAssertTrue(RecognizedText.showsWhole(Self.measuredValue, in: reading.text),
                          "'\(Self.measuredValue)' draws whole: read '\(reading.text ?? "")' (\(run.name))")
        }
        if let baseline {
            XCTAssertGreaterThan(CGFloat(glyphs), CGFloat(baseline) * RecognizedText.minimumGrowth,
                                 "'\(Self.measuredValue)' grows at AX5: \(glyphs) px vs \(baseline) px at Large (\(run.name))")
        }
    }

    /// The Difficulty value's rendered glyph height (`SongsUITestSupport.brightGlyphHeight`:
    /// its white text and chevron on the dark capsule), required to sit inside the capsule
    /// so it measures the text, not the capsule's edge.
    ///
    /// - Parameters:
    ///   - app: The viewer, settled.
    ///   - run: Launch settings, for messages.
    /// - Returns: Glyph height in screenshot pixels.
    /// - Throws: A missing screenshot or glyph pixels.
    @MainActor
    private func measuredGlyphs(in app: XCUIApplication, run: Run) throws -> Int {
        let difficulty = element("fst.paths.difficulty", in: app)
        XCTAssertTrue(difficulty.waitForExistence(timeout: FestivalApp.budget(5)), "No Difficulty (\(run.name))")
        let glyphs = try SongsUITestSupport.brightGlyphHeight(in: difficulty)
        let height = try XCTUnwrap(difficulty.screenshot().image.cgImage).height
        XCTAssertLessThan(glyphs, height * 9 / 10,
                          "Difficulty's bright pixels fill the capsule (\(glyphs) of \(height) px; \(run.name))")
        return glyphs
    }

    /// Close: named, enabled, wholly on screen and hittable. It is the system `.close`
    /// toolbar button, whose glass circle reports a 36 pt frame while UIKit owns its hit
    /// region; the audit's `.hitRegion` check covers its size.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - run: Launch settings, for messages.
    ///   - context: The viewer's state, for messages.
    @MainActor
    private func assertCloseReachable(in app: XCUIApplication, run: Run, _ context: String) {
        let close = app.buttons["fst.paths.close"]
        XCTAssertTrue(close.waitForExistence(timeout: FestivalApp.budget(5)), "No Close: \(context) (\(run.name))")
        XCTAssertEqual(close.label, "Close", "Close is named: \(context) (\(run.name))")
        XCTAssertTrue(close.isEnabled, "Close is enabled: \(context) (\(run.name))")
        XCTAssertTrue(close.isHittable, "Close is reachable: \(context) (\(run.name))")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(close.frame),
                      "Close wholly on screen: \(close.frame) in \(window), \(context) (\(run.name))")
    }

    /// Instrument, Difficulty and View: named, hittable, wholly on screen, 44 pt.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - run: Launch settings, for messages.
    @MainActor
    private func assertSelectorsReachable(in app: XCUIApplication, run: Run) {
        let window = app.windows.firstMatch.frame
        for identifier in Self.selectors {
            let selector = element(identifier, in: app)
            XCTAssertTrue(selector.isHittable, "\(identifier) is reachable (\(run.name))")
            XCTAssertFalse(selector.label.isEmpty, "\(identifier) is named (\(run.name))")
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(selector.frame),
                          "\(identifier) wholly on screen: \(selector.frame) in \(window) (\(run.name))")
            XCTAssertGreaterThanOrEqual(selector.frame.height, 43.67, "\(identifier) target \(selector.frame)")
            XCTAssertGreaterThanOrEqual(selector.frame.width, 43.67, "\(identifier) target \(selector.frame)")
        }
    }

    /// Tap Close and require the viewer gone and Song Detail's Paths button back.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - run: Launch settings, for messages.
    ///   - context: Where Close was tapped, for messages.
    @MainActor
    private func closeWithCloseButton(in app: XCUIApplication, run: Run, _ context: String) {
        app.buttons["fst.paths.close"].tap()
        XCTAssertTrue(element("fst.paths.display", in: app).waitForNonExistence(timeout: FestivalApp.budget(10)),
                      "Close left the viewer open \(context) (\(run.name))")
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: FestivalApp.budget(10)), "No Song Detail after Close (\(run.name))")
    }

    /// The viewer's landmarks, in the hierarchy's depth-first order (XCUITest cannot read
    /// VoiceOver's cursor; precedent `PathsSwitchAccessibilityJourneyTests.assertOrder`),
    /// must be `expected`. Repeats of one landmark count once.
    ///
    /// - Parameters:
    ///   - expected: Landmark identifiers in reading order.
    ///   - app: The running app.
    ///   - context: Failure message.
    @MainActor
    private func assertOrder(_ expected: [String], in app: XCUIApplication, _ context: String) {
        guard let root = try? app.snapshot() else {
            XCTFail("No snapshot: \(context)")
            return
        }
        let wanted = Set(expected + Self.selectors + [
            "fst.paths.zoom-out", "fst.paths.zoom-in", "fst.paths.close", "fst.paths.image",
            "fst.paths.text.Solo_Guitar.expert", "fst.paths.activation.1",
        ])
        var order: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            if wanted.contains(node.identifier), !order.contains(node.identifier) { order.append(node.identifier) }
            node.children.forEach(walk)
        }
        walk(root)
        XCTAssertEqual(order, expected, "Reading order: \(context)")
    }

    /// Audit the viewer with the run's types; every issue fails.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - run: Launch settings.
    ///   - state: Attachment suffix.
    /// - Throws: The audit's own error.
    @MainActor
    private func audit(_ app: XCUIApplication, run: Run, _ state: String) throws {
        var issues: [String] = []
        var accepted: [String] = []
        let window = app.windows.firstMatch.frame
        let table = element("fst.paths.text.Solo_Guitar.expert", in: app)
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, run.auditTypes, name: "paths dismiss \(run.name) \(state)", reset: { issues.removeAll(); accepted.removeAll() }
        ) { issue in
            let node = issue.element
            let line = "\(node?.identifier ?? "nil") '\(node?.label ?? "")' \(String(describing: node?.frame)): "
                + issue.compactDescription
            let selector = node.flatMap { node -> XCUIElement? in
                guard !node.frame.isEmpty else { return nil }
                let centre = CGPoint(x: node.frame.midX, y: node.frame.midY)
                return Self.selectors.map { self.element($0, in: app) }
                    .first { $0.exists && $0.frame.contains(centre) }
            }
            // The audit flags the selector capsules' text though it renders light on the dark
            // card. Accept that only once the capsule's rendered contrast measures at least
            // 4.5:1 (precedent `PathsSwitchAccessibilityJourneyTests`).
            if issue.auditType == .contrast, let selector {
                try SongsUITestSupport.assertHeaderContrast(selector, in: app)
                accepted.append("measured ≥ 4.5:1: \(line)")
                return true
            }
            // The iPad cover's audit flags some white activation-card labels ("NOTE", "BEAT",
            // a value) on the dark card. Accept a flagged text in the table only once its own
            // rendered contrast measures at least 4.5:1 (as `SuggestionsAccessibilityJourneyTests`).
            if issue.auditType == .contrast, let node, node.elementType == .staticText, !node.frame.isEmpty,
               table.exists, table.frame.contains(CGPoint(x: node.frame.midX, y: node.frame.midY)) {
                try SongsUITestSupport.assertHeaderContrast(node, in: app)
                accepted.append("measured ≥ 4.5:1: \(line)")
                return true
            }
            // `DebugDuoWindow` lays the inner display's 669-pt named selector row out inside
            // the iPhone's real, narrower window ("shell evidence, not a capture"), so a
            // selector value clipped there, or truncated so the audit sees it not grow, is
            // the simulation's. The iPad cover audits the same named row at a real width.
            if issue.auditType == .textClipped || issue.auditType == .dynamicType, let selector,
               self.simulatesInnerDisplay(run, in: window), !run.isAX5 {
                accepted.append("simulated \(run.duoWindow ?? "") in a \(Int(window.width))-pt window: \(line) "
                    + "(\(selector.identifier))")
                return true
            }
            // At AX5 the stacked selectors take the window's width, yet in the simulated inner
            // display the audit still flags the View value ("Image") as clipped, though it
            // renders the same pixels the iPhone AX5 form audits clean. Accept only "Text
            // clipped", and only once Vision reads that selector's value whole and the
            // selector lies wholly in the window, in this run.
            if issue.auditType == .textClipped, let selector, run.isAX5, self.simulatesInnerDisplay(run, in: window) {
                let value = selector.value as? String ?? ""
                let reading = RecognizedText.recognize(selector, label: value, frame: selector.frame)
                if RecognizedText.showsWhole(value, in: reading.text),
                   window.insetBy(dx: -1, dy: -1).contains(selector.frame) {
                    accepted.append("Vision reads '\(value)' whole ('\(reading.text ?? "")'): \(line) "
                        + "(\(selector.identifier))")
                    return true
                }
                issues.append("\(line); Vision read '\(reading.text ?? "")' for '\(value)'")
                return true
            }
            issues.append(line)
            return true
        }
        attach("paths-dismiss-\(run.name)-\(state)-audit", (issues + accepted.map { "accepted, \($0)" })
            .joined(separator: "\n"))
        XCTAssertEqual(issues, [], "Audit issues, \(state) (\(run.name))")
    }

    // MARK: - App helpers

    /// Whether the run simulates the iPhone Duo inner display (`DebugDuoWindow`, 669 pt
    /// wide in portrait) inside a narrower real window.
    ///
    /// - Parameters:
    ///   - run: Launch settings.
    ///   - window: The app's real window frame.
    /// - Returns: True for an unfolded simulation in a window under 669 pt.
    private func simulatesInnerDisplay(_ run: Run, in window: CGRect) -> Bool {
        guard let duo = run.duoWindow else { return false }
        return duo != "folded" && window.width < 669
    }

    /// The first element with an identifier, of any type.
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        PathsUITestSupport.element(identifier, in: app)
    }

    /// Wait until the app reports the simulated Duo window (`DuoShellJourneyTests`).
    ///
    /// - Parameters:
    ///   - pose: Expected `DebugDuoWindow` raw value.
    ///   - app: The running app.
    @MainActor
    private func waitForDuoWindow(_ pose: String, in app: XCUIApplication) {
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let reached = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "\(pose) "), object: readout
        )
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
                       "The app never simulated \(pose): \(readout.exists ? readout.label : "no readout")")
    }

    /// Attach a screenshot.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Attach text.
    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text.isEmpty ? "(none)" : text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
