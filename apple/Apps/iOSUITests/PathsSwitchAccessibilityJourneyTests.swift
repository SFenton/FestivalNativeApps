import UIKit
import XCTest

// MARK: - Paths switch accessibility (issue #70, backfilled by #430)

/// The Paths sheet's chart switch on iPhone, held mid-switch: the old image or table fades
/// out, one named spinner holds its place, then the new chart fades in (issue #70,
/// `load-transition` R6; web `PathsModal`).
///
/// The fixture's `/__fixture__/hold-paths` control holds every Paths read until the journey
/// releases it (at most 60 s), so the switching state stays on screen while the journey
/// checks it. Held, the sheet must expose exactly one busy indicator named for the form
/// loading ("Loading text path" / "Loading image path"), nothing of the old chart (no stale
/// table, activation cards, image or error), the spinner before the Instrument, Difficulty
/// and View selectors in reading order, those selectors hittable with 44 pt targets showing
/// the new choice, and the system Close hittable. `performAccessibilityAudit` runs on the held state (and
/// the spinner is still held after it), at the default size with every audit type and at
/// AX5 with every type but contrast (`testing/apple/accessibility.md`). The audit flags the
/// changed selectors' capsules for contrast on iOS 26.5 and 27 although their text renders
/// white on the dark card (about 17:1); the journey accepts that only after measuring the
/// capsule's rendered contrast at 4.5:1 or more. Released, the new
/// chart reads before the selectors again. The same journey runs with Settings' Reduce
/// Motion on (swaps without fades; `SongPathsSheet.switchTiming`) and at AX5.
///
/// XCUITest waits for the app to go idle, so it cannot time a 300 ms fade; the hosted
/// `FestivalUITests/SongPathsSwitchAccessibilityTests` prove the timing, announcements and
/// macOS reading order. This journey is the iOS evidence: UIKit's accessibility tree, real
/// hit regions and Dynamic Type.
///
/// Needs `tools/mock_service.py` from this revision (`apple-ci` serves `--large-catalogue` on
/// the default port 8765; `FST_PATHS_FIXTURE_URL` points a local run at another port). Each
/// test skips when the listener has no hold control.
///
/// HIG Progress indicators: "Help people understand what's happening by describing the
/// action"; HIG Accessibility: 44×44 pt controls, "Prefer system-defined text styles" and
/// "Minimize motion when Reduce Motion is on".
final class PathsSwitchAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_PATHS_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// The selectors, in reading order.
    private static let selectors = ["fst.paths.instrument", "fst.paths.difficulty", "fst.paths.display"]

    /// Longest hold a journey asks for: 60 s, scaled ×4 in a VM, where one form's hold
    /// outlasted 60 s before its audit ended (#386; the fixture's limit is 240 s).
    private static let holdSeconds = Int(FestivalApp.budget(60))

    /// One form of the sheet.
    private enum Form: String {
        case text
        case image

        /// The View menu's option.
        var option: String { self == .text ? "Text" : "Image" }
        /// The spinner's accessible name.
        var spinner: String { "Loading \(rawValue) path" }
    }

    /// Launch settings for one run.
    private struct Run {
        let name: String
        var reduceMotion = false
        var contentSize = UIContentSizeCategory.large.rawValue
        var auditTypes: XCUIAccessibilityAuditType = .all
    }

    override func tearDown() {
        _ = try? fixture("seconds=0")
        super.tearDown()
    }

    // MARK: - Journeys

    /// Default size, fades on: a Difficulty switch and a View switch, each held.
    @MainActor
    func testHeldSwitchReadsOneSpinnerBeforeTheSelectors() throws {
        try runJourney(Run(name: "default"))
    }

    /// Settings' Reduce Motion on: the same held states and the same reading order.
    @MainActor
    func testHeldSwitchUnderReduceMotion() throws {
        try runJourney(Run(name: "reduce-motion", reduceMotion: true))
    }

    /// AX5: the spinner and every selector stay reachable with 44 pt targets, and the
    /// audit (all but contrast) passes on the held state.
    @MainActor
    func testHeldSwitchAtAX5() throws {
        try runJourney(Run(
            name: "ax5",
            contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            auditTypes: XCUIAccessibilityAuditType.all.subtracting(.contrast)
        ))
    }

    // MARK: - Journey

    /// Open Paths in Text, hold a Difficulty switch (Expert → Hard), release it, then hold
    /// a View switch (Text → Image) and release it, checking each held and settled state.
    ///
    /// - Parameter run: Launch settings.
    /// - Throws: A skip without the hold control, or a failed requirement.
    @MainActor
    private func runJourney(_ run: Run) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try requireHoldControl()
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        app.launchArguments += [
            "-fst.accessibility.reduceMotion", run.reduceMotion ? "YES" : "NO",
            "-UIPreferredContentSizeCategoryName", run.contentSize,
        ]
        app.launch()
        defer { app.terminate() }
        openPaths(in: app)

        let display = element("fst.paths.display", in: app)
        choose(Form.text.option, in: display, app: app)
        let expert = element("fst.paths.text.Solo_Guitar.expert", in: app)
        XCTAssertTrue(expert.waitForExistence(timeout: FestivalApp.budget(15)), "No Expert table")
        assertOrder(["fst.paths.text.Solo_Guitar.expert", "fst.paths.activation.1"] + Self.selectors,
                    in: app, "Expert table loaded (\(run.name))")

        // Difficulty switch, held: the table goes, one text spinner stands in for it.
        try hold()
        choose("Hard", in: element("fst.paths.difficulty", in: app), app: app)
        try assertHeld(.text, in: app, run: run, values: ["Lead", "Hard", "Text"])
        try release()
        let hard = element("fst.paths.text.Solo_Guitar.hard", in: app)
        XCTAssertTrue(hard.waitForExistence(timeout: FestivalApp.budget(15)), "No Hard table after release")
        assertSpinnerGone(.text, in: app)
        assertOrder(["fst.paths.text.Solo_Guitar.hard", "fst.paths.activation.1"] + Self.selectors,
                    in: app, "Hard table loaded (\(run.name))")

        // View switch, held: the table goes, one image spinner stands in for it.
        try hold()
        choose(Form.image.option, in: display, app: app)
        try assertHeld(.image, in: app, run: run, values: ["Lead", "Hard", "Image"])
        try release()
        let image = app.images.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "fst.paths.image", "Hard"
        )).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: FestivalApp.budget(15)), "No Hard image after release")
        assertSpinnerGone(.image, in: app)
        assertOrder(["fst.paths.image"] + Self.selectors, in: app, "Hard image loaded (\(run.name))")
        record(app, name: "paths-switch-\(run.name)-loaded")
    }

    // MARK: - Held state

    /// Require the held switching state: one named spinner, no stale chart, the spinner
    /// before the selectors, reachable 44 pt controls, a clean audit, and the read still
    /// held afterwards (so the audit saw the spinner, not the new chart).
    ///
    /// - Parameters:
    ///   - form: The form loading.
    ///   - app: The running app.
    ///   - run: Launch settings (audit types, attachment names).
    ///   - values: The selectors' expected values, in order.
    /// - Throws: A failed requirement or audit.
    @MainActor
    private func assertHeld(_ form: Form, in app: XCUIApplication, run: Run, values: [String]) throws {
        let spinners = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", form.spinner))
        XCTAssertTrue(spinners.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)),
                      "No '\(form.spinner)' spinner (\(run.name))")
        try waitUntilHeldReadArrives()
        XCTAssertEqual(spinners.count, 1, "One '\(form.spinner)' element (\(run.name))")
        XCTAssertEqual(spinners.firstMatch.elementType, .activityIndicator,
                       "'\(form.spinner)' is a busy indicator (\(run.name))")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(spinners.firstMatch.frame),
                      "Spinner on screen: \(spinners.firstMatch.frame) in \(window)")
        let other: Form = form == .text ? .image : .text
        XCTAssertFalse(app.descendants(matching: .any)[other.spinner].exists, "A second form's spinner shows")
        let stale = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@ OR identifier IN %@",
            "fst.paths.text.", "fst.paths.activation.", ["fst.paths.image", "fst.paths.error", "fst.paths.zoom-in"]
        ))
        XCTAssertEqual(stale.count, 0, "Old chart still exposed while switching (\(run.name)): "
                       + stale.allElementsBoundByIndex.map(\.identifier).joined(separator: ", "))
        // The system menu dims the row's labels until its dismissal finishes; under Reduce
        // Motion the spinner is in before that, so let it settle before the audit samples.
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1)))
        assertOrder([form.spinner] + Self.selectors, in: app, "\(form.rawValue) switch held (\(run.name))")
        assertControlsReachable(in: app, values: values, run: run)
        record(app, name: "paths-switch-\(run.name)-\(form.rawValue)-held")

        var issues: [String] = []
        var measured: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, run.auditTypes, name: "paths switch \(run.name) \(form.rawValue)",
            reset: { issues.removeAll(); measured.removeAll() }
        ) { issue in
            let node = issue.element
            let line = "\(node?.identifier ?? "nil") '\(node?.label ?? "")' \(String(describing: node?.frame)): "
                + issue.compactDescription
            // The audit flags a just-changed selector's capsule though its text renders white on
            // the dark card (~17:1). Accept that only once its rendered contrast measures at
            // least 4.5:1 (precedent `SongsJourneyTests.auditSectionTitlePage`).
            if issue.auditType == .contrast, let node, !node.frame.isEmpty,
               let selector = zip(Self.selectors, values).first(where: { $0.1 == node.label }).map({
                   self.element($0.0, in: app)
               }), selector.frame.contains(CGPoint(x: node.frame.midX, y: node.frame.midY)) {
                // The value text itself is not hittable; measure the capsule that shows it.
                try SongsUITestSupport.assertHeaderContrast(selector, in: app)
                measured.append(line)
                return true
            }
            issues.append(line)
            return true
        }
        attach("paths-switch-\(run.name)-\(form.rawValue)-audit",
               (issues + measured.map { "measured ≥ 4.5:1, accepted: \($0)" }).joined(separator: "\n"))
        XCTAssertEqual(issues, [], "Audit issues on the held \(form.rawValue) switch (\(run.name))")
        XCTAssertTrue(spinners.firstMatch.exists, "The spinner left during the audit (\(run.name))")
        XCTAssertGreaterThan(try holdStatus().waiting, 0, "The read was answered during the audit (\(run.name))")
    }

    /// The selectors: hittable, wholly on screen, at least 44 pt (one pixel of tolerance off
    /// the pixel grid) and showing the current choice. Close: named, enabled and hittable.
    /// It is the system `.close` toolbar button, whose glass circle reports a 36 pt frame
    /// while UIKit owns its hit region; the audit's `.hitRegion` check covers it.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - values: The selectors' expected values, in order.
    ///   - run: Launch settings, for messages.
    @MainActor
    private func assertControlsReachable(in app: XCUIApplication, values: [String], run: Run) {
        let window = app.windows.firstMatch.frame
        for (identifier, expected) in zip(Self.selectors, values) {
            let selector = element(identifier, in: app)
            XCTAssertTrue(selector.isHittable, "\(identifier) is reachable (\(run.name))")
            XCTAssertTrue(selector.isEnabled, "\(identifier) is enabled (\(run.name))")
            XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(selector.frame),
                          "\(identifier) wholly on screen: \(selector.frame) in \(window) (\(run.name))")
            XCTAssertGreaterThanOrEqual(selector.frame.height, 43.67, "\(identifier) target \(selector.frame)")
            XCTAssertGreaterThanOrEqual(selector.frame.width, 43.67, "\(identifier) target \(selector.frame)")
            XCTAssertFalse(selector.label.isEmpty, "\(identifier) is named")
            let shown = "\(selector.label) \((selector.value as? String) ?? "")"
            XCTAssertTrue(shown.contains(expected), "\(identifier) shows \(expected): '\(shown)' (\(run.name))")
        }
        let close = app.buttons["fst.paths.close"]
        XCTAssertTrue(close.isHittable, "Close is reachable while switching (\(run.name))")
        XCTAssertTrue(close.isEnabled, "Close is enabled while switching (\(run.name))")
        XCTAssertFalse(close.label.isEmpty, "Close is named")
    }

    /// The spinner has left once the new chart is in.
    @MainActor
    private func assertSpinnerGone(_ form: Form, in app: XCUIApplication) {
        let spinner = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", form.spinner))
        XCTAssertTrue(spinner.firstMatch.waitForNonExistence(timeout: FestivalApp.budget(5)),
                      "'\(form.spinner)' stayed beside the loaded chart")
    }

    // MARK: - Reading order

    /// The sheet's landmarks, in the hierarchy's depth-first order (XCUITest cannot read
    /// VoiceOver's cursor; precedent `NavButtonHitRegionJourneyTests`), must be `expected`.
    /// A landmark is a Paths identifier or a spinner's name; repeats of one landmark (a
    /// container and its element share an identifier) count once.
    ///
    /// - Parameters:
    ///   - expected: Landmarks in reading order.
    ///   - app: The running app.
    ///   - context: Failure message.
    @MainActor
    private func assertOrder(_ expected: [String], in app: XCUIApplication, _ context: String) {
        guard let root = try? app.snapshot() else {
            XCTFail("No snapshot: \(context)")
            return
        }
        let wanted = Set(expected + Self.selectors + [
            Form.text.spinner, Form.image.spinner, "fst.paths.image", "fst.paths.error",
            "fst.paths.activation.1", "fst.paths.text.Solo_Guitar.expert", "fst.paths.text.Solo_Guitar.hard",
        ])
        var order: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            let key = wanted.contains(node.identifier) ? node.identifier
                : wanted.contains(node.label) ? node.label : nil
            if let key, !order.contains(key) { order.append(key) }
            node.children.forEach(walk)
        }
        walk(root)
        XCTAssertEqual(order, expected, "Reading order: \(context)")
    }

    // MARK: - Fixture hold control

    /// Skip unless the listener serves `/__fixture__/hold-paths`, and start unheld.
    private func requireHoldControl() throws {
        let status = try? fixture("seconds=0")
        try XCTSkipUnless(status != nil, "Start `tools/mock_service.py` from this revision at \(Self.origin)")
    }

    /// Hold every Paths read until ``release()``.
    private func hold() throws {
        let status = try XCTUnwrap(try fixture("seconds=\(Self.holdSeconds)"), "Hold control")
        XCTAssertTrue(status.held, "Paths reads held")
    }

    /// Answer the held reads.
    private func release() throws {
        let status = try XCTUnwrap(try fixture("seconds=0"), "Hold control")
        XCTAssertFalse(status.held, "Paths reads released")
    }

    /// The hold's status.
    private func holdStatus() throws -> (held: Bool, waiting: Int) {
        try XCTUnwrap(try fixture(nil), "Hold control")
    }

    /// Wait until the app's read reaches the held listener, so the state is the switch.
    private func waitUntilHeldReadArrives() throws {
        let deadline = Date().addingTimeInterval(FestivalApp.budget(10))
        while Date() < deadline {
            let status = try holdStatus()
            XCTAssertTrue(status.held, "The hold expired")
            if status.waiting > 0 { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("The switch's Paths read never reached the fixture")
    }

    /// Call the hold control.
    ///
    /// - Parameter query: `seconds=<n>`, or nil for the status.
    /// - Returns: The status, or nil when the listener has no hold control.
    private func fixture(_ query: String?) throws -> (held: Bool, waiting: Int)? {
        PathsUITestSupport.pathHold(origin: Self.origin, query)
    }

    // MARK: - App helpers

    /// Open `fixture-pulse`'s Paths sheet (``PathsUITestSupport/openPaths(in:)``).
    @MainActor
    private func openPaths(in app: XCUIApplication) {
        PathsUITestSupport.openPaths(in: app)
    }

    /// The first element with an identifier, of any type.
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        PathsUITestSupport.element(identifier, in: app)
    }

    /// Open a menu picker and pick an option.
    @MainActor
    private func choose(_ option: String, in menu: XCUIElement, app: XCUIApplication) {
        PathsUITestSupport.choose(option, in: menu, app: app)
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
