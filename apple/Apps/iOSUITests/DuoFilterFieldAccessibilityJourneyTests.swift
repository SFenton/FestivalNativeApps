import XCTest

/// Accessibility of the iPhone Duo bottom "Filter Songs" field in the poses #334 changed
/// (#475, for #334).
///
/// #334 made the field (`BottomSearchField`) span the page's full bottom width in every
/// pose except a book-pose fold, where it lies on the right page clear of the fold. The
/// hosted `SongsDuoFilterFieldAccessibilityTests` pin its names, reading order and
/// column on macOS, which has no Dynamic Type and no UIKit touch targets; this journey
/// is the on-device evidence, flat in landscape, in book pose and flat in portrait, at
/// the default and the largest accessibility text size (AX5):
///
/// - one search field named "Filter Songs" that spans its column: across the middle of
///   the window when flat, wholly on the right page when a fold is reported and that
///   page is at least `BottomSearchFieldPlacement.minimumPageWidth` wide (full width
///   otherwise, as on the folded CI window);
/// - its touch target is the whole capsule: taps 21 pt above and below the text line's
///   centre and on the magnifier focus it (the text line itself is ~22 pt, taller at AX5);
/// - typed text adds "Clear Search", a 44 × 44 pt button read right after the field,
///   which empties it;
/// - the system audit (hit region, description, Dynamic Type, clipping) reports nothing
///   on the field or Clear Search;
/// - flat in portrait, where page tools float above the tab bar (issue #633), the field
///   stacks above the 44 pt floating Sort and Filter buttons instead of covering them.
///
/// HIG Accessibility: iOS default control size 44×44 pt; "Provide VoiceOver descriptions
/// for all interface elements". HIG Designing for iPhone Duo: "use reserved-region APIs to
/// keep important elements clear of the center".
///
/// Runs on the iPhone Duo device type (`apple-ci` Songs Filter journeys, `duo-folded` leg;
/// locally `ios_sim.py uitest --device duo`), whose system tab bar is the
/// vertical bar, with the `DebugDuoWindow` simulation of each unfolded pose; the book fold
/// lies down the middle of the real window (`fold=<x>` in the readout). It skips on a plain
/// iPhone: there the simulation keeps the phone's horizontal tab bar over the bottom field
/// (as `GlobalSearchAccessibilityJourneyTests` notes), so its touches would land on tabs.
/// Runs against `tools/mock_service.py` (any catalogue), read from
/// `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL` or the default port.
final class DuoFilterFieldAccessibilityJourneyTests: XCTestCase {
    private static let field = "fst.songs.filter-field"
    private static let clear = "fst.songs.filter-clear"
    /// The simulated inner-display poses, flat landscape first (the launch window).
    private static let poses = ["unfolded-landscape", "book", "unfolded-portrait"]
    /// `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`.
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"
    /// HIG Accessibility: the iOS minimum touch target.
    private static let minimumTarget: CGFloat = 44
    /// `BottomSearchFieldPlacement.margin` and `.minimumPageWidth`, and half
    /// `DebugDuoPose.foldHeight`.
    private static let margin: CGFloat = 16
    private static let minimumPageWidth: CGFloat = 200
    private static let foldHalfWidth: CGFloat = 12
    /// Offsets from the text line's centre at the edges of a 44 pt target, and onto the
    /// magnifier (the text starts 8 pt after the glyph), as `SongsChromeJourneyTests`'
    /// drawer near misses.
    private static let nearMisses: [CGVector] = [
        CGVector(dx: 0, dy: -21), CGVector(dx: 0, dy: 21),
    ]

    /// The large-catalogue fixture service's origin.
    private static var fixtureURL: String {
        ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
    }

    /// The field in each unfolded pose at the default text size, then at AX5, where its
    /// target is taller than at the default size in the same pose (only a little in flat
    /// portrait, where the default is already the tab bar Search button's 62 pt).
    @MainActor
    func testFilterFieldKeepsItsColumnAtAX5DuoUnfolded() throws {
        try XCTSkipUnless(
            (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Needs the iPhone Duo device type: on an iPhone the simulated window keeps the phone tab bar over the field"
        )
        continueAfterFailure = false
        var standard: [String: CGFloat] = [:]
        let app = try launch(typeSize: nil)
        for pose in Self.poses {
            standard[pose] = try assertField(in: app, pose: pose, name: "default")
        }
        app.terminate()

        let large = try launch(typeSize: Self.ax5)
        defer { large.terminate() }
        for pose in Self.poses {
            let height = try assertField(in: large, pose: pose, name: "ax5")
            let base = try XCTUnwrap(standard[pose])
            XCTAssertGreaterThan(height, base, "\(pose): the AX5 field (\(height) pt) does not grow past \(base) pt")
        }
    }

    // MARK: - Launch

    /// Launch Songs in the simulated flat inner landscape against the fixture, with no
    /// selected player, and wait for the Filter Songs field.
    ///
    /// - Parameter typeSize: A `UIContentSizeCategory` raw value, or nil for the default.
    /// - Returns: The launched app.
    /// - Throws: A skip when the fixture never loads Songs.
    @MainActor
    private func launch(typeSize: String?) throws -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixtureURL, "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_DUO_WINDOW_REMOTE": "1", "FST_DEBUG_DUO_WINDOW": Self.poses[0],
        ])
        if let typeSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", typeSize] }
        app.launch()
        guard field(in: app).waitForExistence(timeout: FestivalApp.budget(20)) else {
            app.terminate()
            throw XCTSkip("Songs showed no Filter Songs field; run tools/mock_service.py on \(Self.fixtureURL).")
        }
        return app
    }

    /// The Filter Songs field.
    @MainActor
    private func field(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: Self.field).firstMatch
    }

    // MARK: - Assertions

    /// Inner portrait has a horizontal tab bar, so Songs' tools float above it (issue
    /// #633): the field stacks above the floating Sort and Filter buttons instead of
    /// covering them, and each stays a 44 × 44 pt target.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - field: The Filter Songs field (its text line, inside the capsule).
    ///   - label: Pose and text-size label for messages.
    @MainActor
    private func assertClearsFloatingTools(_ app: XCUIApplication, _ field: XCUIElement, label: String) {
        let tools = ["fst.songs.sort", "fst.songs.filter"].map {
            app.descendants(matching: .any).matching(identifier: $0).firstMatch
        }
        for tool in tools {
            XCTAssertTrue(tool.waitForExistence(timeout: FestivalApp.budget(10)), "\(label): no floating \(tool)")
        }
        let stacked = NSPredicate { _, _ in tools.allSatisfy { field.frame.maxY <= $0.frame.minY } }
        let settled = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: stacked, object: nil)],
                                     timeout: FestivalApp.budget(5))
        XCTAssertEqual(settled, .completed,
                       "\(label): field \(field.frame) covers the floating tools \(tools.map(\.frame))")
        for tool in tools {
            XCTAssertGreaterThanOrEqual(tool.frame.width, Self.minimumTarget, "\(label): \(tool.identifier) \(tool.frame)")
            XCTAssertGreaterThanOrEqual(tool.frame.height, Self.minimumTarget, "\(label): \(tool.identifier) \(tool.frame)")
        }
    }

    /// Switch to `pose`, then require the field's name, role, column and target; type to
    /// bring Clear Search and require its name, order and target; audit both; clear.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - pose: A `DebugDuoWindow` raw value.
    ///   - name: Text-size label for attachments.
    /// - Returns: The field's height, in points.
    @MainActor
    @discardableResult
    private func assertField(in app: XCUIApplication, pose: String, name: String) throws -> CGFloat {
        let label = "\(pose)-\(name)"
        DuoWindowSwitch.post(pose)
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "\(pose) "), object: readout)
        XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: FestivalApp.budget(15)), .completed,
                       "never simulated \(pose): \(readout.exists ? readout.label : "no readout")")
        let fold = readout.label.components(separatedBy: " fold=").dropFirst().first.flatMap { Double($0) }
        XCTAssertEqual(fold != nil, pose == "book", "\(label): fold reported only in book pose: \(readout.label)")
        let window = app.windows.firstMatch.frame
        let element = field(in: app)
        XCTAssertTrue(element.waitForExistence(timeout: FestivalApp.budget(10)), "\(label): field missing")

        // The field settles in its column: across the middle when flat; in book pose on
        // the page past the fold, unless that page is narrower than
        // `BottomSearchFieldPlacement.minimumPageWidth` (the folded CI window simulates
        // the fold at its free span's middle, leaving ~190 pt), when it keeps the full
        // width. The row ends a margin past the field, so the page is its trailing edge
        // less the fold's and a margin.
        func onRightPage(_ frame: CGRect) -> Bool {
            guard let fold else { return false }
            return frame.maxX - (CGFloat(fold) + Self.foldHalfWidth) - Self.margin >= Self.minimumPageWidth
        }
        let placed = NSPredicate { _, _ in
            let frame = element.frame
            if let fold, onRightPage(frame) { return frame.minX > CGFloat(fold) + 12 }
            return frame.minX < window.midX - 40 && frame.maxX > window.midX + 40
        }
        let settled = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: placed, object: nil)],
                                     timeout: FestivalApp.budget(10))
        attach(app, name: label)
        XCTAssertEqual(settled, .completed, "\(label): field \(element.frame) is not in its column (window \(window), fold \(String(describing: fold)))")

        let fields = app.descendants(matching: .any).matching(identifier: Self.field)
        XCTAssertEqual(fields.count, 1, "\(label): Filter Songs fields")
        XCTAssertTrue([.searchField, .textField].contains(element.elementType), "\(label): role \(element.elementType.rawValue)")
        XCTAssertTrue([element.label, element.placeholderValue ?? ""].contains("Filter Songs"),
                      "\(label): field name '\(element.label)' / '\(element.placeholderValue ?? "")'")
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.height, 20, "\(label): field text line \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "\(label): field \(frame) leaves the window")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "\(label): field \(frame) leaves the window")
        XCTAssertLessThanOrEqual(frame.maxY, window.maxY, "\(label): field \(frame) leaves the window")
        if let fold, onRightPage(frame) { XCTAssertGreaterThan(frame.minX, CGFloat(fold) + 12, "\(label): field \(frame) crosses the fold") }

        if pose == "unfolded-portrait" { assertClearsFloatingTools(app, element, label: label) }

        try assertCapsuleTarget(app, element, label: label)

        // Typed text: Clear Search, a 44 pt target read right after the field.
        element.tap()
        element.typeText("zq")
        let clear = app.buttons[Self.clear]
        XCTAssertTrue(clear.waitForExistence(timeout: FestivalApp.budget(5)), "\(label): no Clear Search after typing")
        XCTAssertEqual(clear.label, "Clear Search", "\(label): Clear Search name")
        XCTAssertGreaterThanOrEqual(clear.frame.width, Self.minimumTarget, "\(label): Clear Search target \(clear.frame)")
        XCTAssertGreaterThanOrEqual(clear.frame.height, Self.minimumTarget, "\(label): Clear Search target \(clear.frame)")
        // Trailing: after the text line, or inside the trailing end when iOS reports the
        // whole capsule as the field's frame.
        XCTAssertGreaterThan(clear.frame.midX, element.frame.midX, "\(label): Clear Search \(clear.frame) is not trailing the field \(element.frame)")
        XCTAssertLessThanOrEqual(clear.frame.maxX, window.maxX, "\(label): Clear Search \(clear.frame) leaves the window")
        if let fold { XCTAssertGreaterThan(clear.frame.minX, CGFloat(fold), "\(label): Clear Search \(clear.frame) crosses the fold") }
        let order = try FestivalApp.snapshotNodes(in: app) { [Self.field, Self.clear].contains($0.identifier) }
            .map(\.identifier)
        XCTAssertEqual(order, [Self.field, Self.clear], "\(label): reading order \(order)")
        attach(app, name: "\(label)-typed")
        try audit(app, name: label)

        clear.tap()
        let emptied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !clear.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [emptied], timeout: FestivalApp.budget(5)), .completed, "\(label): Clear Search did not clear")
        XCTAssertNotEqual(element.value as? String, "zq", "\(label): the field kept its text")
        element.typeText("\n")
        return frame.height
    }

    /// HIG Buttons: "the hit region is at least 44x44 pt". The text line is shorter than
    /// the capsule, so taps 21 pt above and below its centre and on the magnifier must
    /// focus the field; Return ends each.
    @MainActor
    private func assertCapsuleTarget(_ app: XCUIApplication, _ field: XCUIElement, label: String) throws {
        let frame = field.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        // Read focus from a fresh snapshot on every poll: the element's own key-value
        // reading (and a format predicate bound to it) can return a cached snapshot's
        // focus, which reported the field focused after Return in book pose while every
        // UI snapshot showed it unfocused. Return has ended editing once the field lost
        // focus or the keyboard is gone.
        let hasFocus = {
            ((try? field.snapshot()) as? NSObject)?.value(forKey: "hasKeyboardFocus") as? Bool ?? false
        }
        let focused = { XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in hasFocus() }, object: nil) }
        let unfocused = {
            XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !hasFocus() || app.keyboards.count == 0 }, object: nil)
        }
        // iOS reports either the text line (magnifier to its left) or the whole capsule
        // (magnifier just inside its leading edge) as the field's frame.
        let magnifierX = frame.height >= Self.minimumTarget ? frame.minX + 20 : frame.minX - 18
        XCTAssertGreaterThan(magnifierX, 0, "\(label): magnifier probe off screen for \(frame)")
        let points = Self.nearMisses.map { CGPoint(x: frame.midX + $0.dx, y: frame.midY + $0.dy) }
            + [CGPoint(x: magnifierX, y: frame.midY)]
        for point in points {
            origin.withOffset(CGVector(dx: point.x, dy: point.y)).tap()
            XCTAssertEqual(
                XCTWaiter.wait(for: [focused()], timeout: FestivalApp.budget(3)),
                .completed,
                "\(label): Filter Songs \(frame) ignored a tap at \(point)"
            )
            // Return ends editing; a Return typed while the keyboard is still animating
            // in can be dropped, so it is sent once more before failing.
            field.typeText("\n")
            if XCTWaiter.wait(for: [unfocused()], timeout: FestivalApp.budget(3)) != .completed, hasFocus() {
                field.typeText("\n")
            }
            XCTAssertEqual(
                XCTWaiter.wait(for: [unfocused()], timeout: FestivalApp.budget(3)),
                .completed, "\(label): Filter Songs kept focus after Return"
            )
            let rested = NSPredicate { _, _ in abs(field.frame.minY - frame.minY) <= 1 }
            XCTAssertEqual(
                XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: rested, object: nil)],
                               timeout: FestivalApp.budget(3)),
                .completed, "\(label): Filter Songs did not settle back to \(frame) after Return"
            )
        }
    }

    /// Audit the field and Clear Search only (other regions have their own journeys).
    @MainActor
    private func audit(_ app: XCUIApplication, name: String) throws {
        let types: XCUIAccessibilityAuditType = [.hitRegion, .sufficientElementDescription, .dynamicType, .textClipped]
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(app, types, name: name, reset: { issues = [] }) { issue in
            guard let element = issue.element,
                  [Self.field, Self.clear].contains(element.identifier) || element.elementType == .searchField
            else { return true }
            issues.append("\(issue.auditType) \(element.identifier): \(issue.compactDescription)")
            return false
        }
        XCTAssertEqual(issues, [], "\(name): audit")
    }

    /// Keep a screenshot of the current pose.
    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "duo-filter-field-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
