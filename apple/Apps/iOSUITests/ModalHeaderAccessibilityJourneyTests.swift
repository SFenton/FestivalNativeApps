import UIKit
import XCTest

// MARK: - Sheet header accessibility (issue #94, backfilled by #447)

/// Notifications and Paths on iPhone with content scrolled under the sheet header.
///
/// Issue #94 (PR #182) let sheet content scroll under a glass-free inline header and fade to
/// clear before it (`FestivalModal` → `ModalTopEdgeFadeModifier`, `scroll-edge` R2/R3 and
/// `modal-shell`). This journey is the iOS evidence for that change: at the default size and
/// at AX5, at rest and scrolled, the sheet's title is read before its content, the system
/// Close stays named, enabled and hittable over the faded content, visible rows and
/// selectors keep 44 pt targets, and `performAccessibilityAudit` passes on the scrolled
/// state (every type at the default size, every type but contrast at AX5;
/// `testing/apple/accessibility.md`). The audit may flag text in the 40 pt ramp under the
/// header for contrast: that text is fading out by design (R2), so the journey accepts a
/// contrast issue only for an element that starts inside the ramp and fails on any other.
///
/// The hosted `FestivalUITests/ModalTopEdgeFadeAccessibilityTests` prove the mask adds no
/// readable element, rows under the header keep their names, roles and order, and every
/// Reduce Transparency / Increase Contrast setting makes the ramp a hard edge.
///
/// Needs `tools/mock_service.py --large-catalogue` (the `apple-ci` default, port 8765;
/// `FST_MODAL_FIXTURE_URL` points a local run elsewhere).
///
/// HIG VoiceOver: "Give each page or screen a unique, succinct title … assistive
/// technology announces it first"; HIG Accessibility: 44×44 pt controls; HIG Materials:
/// "Let content scroll and peek through while preserving control and navigation legibility".
final class ModalHeaderAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_MODAL_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// Height of the sheet-header ramp (`ScrollEdgeFade.topDistance`).
    private static let ramp: CGFloat = 40

    /// The Paths selectors, in reading order.
    private static let pathsSelectors = ["fst.paths.instrument", "fst.paths.difficulty", "fst.paths.display"]

    /// Launch settings for one run.
    private struct Run {
        let name: String
        var contentSize = UIContentSizeCategory.large.rawValue
        var auditTypes: XCUIAccessibilityAuditType = .all
    }

    private static let defaultRun = Run(name: "default")
    private static let ax5Run = Run(
        name: "ax5",
        contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        auditTypes: XCUIAccessibilityAuditType.all.subtracting(.contrast)
    )

    // MARK: - Journeys

    /// Notifications at the default size: title first, Close reachable, rows named 44 pt
    /// buttons, a clean audit.
    @MainActor
    func testNotificationsHeaderAtDefaultSize() throws {
        try notificationsJourney(Self.defaultRun)
    }

    /// Notifications at AX5, where the two rows outgrow the sheet: scrolled under the
    /// header, the title still reads first and Close stays reachable.
    @MainActor
    func testNotificationsHeaderAtAX5() throws {
        try notificationsJourney(Self.ax5Run)
    }

    /// Paths (Text) at the default size, scrolled under the header.
    @MainActor
    func testPathsHeaderAtDefaultSize() throws {
        try pathsJourney(Self.defaultRun)
    }

    /// Paths (Text) at AX5, scrolled under the header.
    @MainActor
    func testPathsHeaderAtAX5() throws {
        try pathsJourney(Self.ax5Run)
    }

    // MARK: - Notifications

    /// Open the Notifications sheet on `fixture-player-1` (two rows) and check it at rest
    /// and, when the rows outgrow the sheet, scrolled under the header.
    ///
    /// - Parameter run: Launch settings.
    /// - Throws: A failed requirement or audit.
    @MainActor
    private func notificationsJourney(_ run: Run) throws {
        let app = launch(run, profile: true)
        defer { app.terminate() }
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: FestivalApp.budget(20)), "No bell")
        bell.tap()
        let bar = app.navigationBars["Notifications"]
        XCTAssertTrue(bar.waitForExistence(timeout: FestivalApp.budget(15)), "No Notifications sheet")
        let rows = ["fst.notifications.row.fixture-notif-1", "fst.notifications.row.fixture-notif-2"]
        XCTAssertTrue(app.buttons[rows[0]].waitForExistence(timeout: FestivalApp.budget(15)), "No rows")
        settle()
        let sheet = Sheet(bar: bar, close: app.buttons["fst.notifications.close"], title: "Notifications",
                          content: rows, targets: rows)
        try check(sheet, in: app, run: run, state: "rest")
        record(app, name: "notifications-\(run.name)-rest")

        let first = app.buttons[rows[0]]
        guard scrollUnderHeader(first, bar: bar, in: app) else {
            XCTAssertNotEqual(run.name, Self.ax5Run.name, "The AX5 rows never scrolled under the header")
            return
        }
        try check(sheet, in: app, run: run, state: "scrolled")
        record(app, name: "notifications-\(run.name)-scrolled")
    }

    // MARK: - Paths

    /// Open Paths for `fixture-pulse` in Text and check it at rest and with the Expert
    /// table scrolled under the header.
    ///
    /// - Parameter run: Launch settings.
    /// - Throws: A failed requirement or audit.
    @MainActor
    private func pathsJourney(_ run: Run) throws {
        let app = launch(run, profile: false)
        defer { app.terminate() }
        openPaths(in: app)
        choose("Text", in: element("fst.paths.display", in: app), app: app)
        let table = element("fst.paths.text.Solo_Guitar.expert", in: app)
        XCTAssertTrue(table.waitForExistence(timeout: FestivalApp.budget(15)), "No Expert table")
        settle()
        let bar = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Paths")).firstMatch
        XCTAssertTrue(bar.exists, "No Paths header")
        let sheet = Sheet(bar: bar, close: app.buttons["fst.paths.close"], title: bar.identifier,
                          content: ["fst.paths.text.Solo_Guitar.expert"] + Self.pathsSelectors,
                          targets: Self.pathsSelectors)
        try check(sheet, in: app, run: run, state: "rest")
        record(app, name: "paths-\(run.name)-rest")

        XCTAssertTrue(scrollUnderHeader(table, bar: bar, in: app), "The Expert table never scrolled under the header")
        try check(sheet, in: app, run: run, state: "scrolled")
        record(app, name: "paths-\(run.name)-scrolled")
    }

    // MARK: - Checks

    /// One sheet's header and content.
    private struct Sheet {
        let bar: XCUIElement
        let close: XCUIElement
        /// The inline title.
        let title: String
        /// Content landmarks (identifiers) the title must read before.
        let content: [String]
        /// Controls that must keep 44 pt targets wherever they sit wholly below the ramp.
        let targets: [String]
    }

    /// The title reads before the content, Close is reachable over it, controls clear of
    /// the header keep 44 pt targets, and the audit passes.
    ///
    /// - Parameters:
    ///   - sheet: The sheet.
    ///   - app: The running app.
    ///   - run: Launch settings.
    ///   - state: `rest` or `scrolled`, for messages.
    /// - Throws: A failed requirement or audit.
    @MainActor
    private func check(_ sheet: Sheet, in app: XCUIApplication, run: Run, state: String) throws {
        let context = "\(sheet.title) \(run.name) \(state)"
        XCTAssertTrue(sheet.bar.exists, "Header gone: \(context)")
        XCTAssertEqual(sheet.bar.staticTexts.matching(NSPredicate(format: "label == %@", sheet.title)).count, 1,
                       "One title '\(sheet.title)' in the header: \(context)")
        assertTitleFirst(sheet, in: app, context)

        let close = sheet.close
        XCTAssertTrue(close.exists, "No Close: \(context)")
        XCTAssertFalse(close.label.isEmpty, "Close is named: \(context)")
        XCTAssertTrue(close.isEnabled, "Close is enabled: \(context)")
        XCTAssertTrue(close.isHittable, "Close is reachable over the content: \(context)")
        // The system `.close` item reports its 36 pt glass circle while UIKit owns a 44 pt hit
        // region; the audit's `.hitRegion` check covers it (precedent: Paths switch journey).
        XCTAssertTrue(sheet.bar.frame.insetBy(dx: -1, dy: -1).contains(close.frame),
                      "Close sits in the header: \(close.frame) in \(sheet.bar.frame) (\(context))")

        let edge = sheet.bar.frame.maxY
        let window = app.windows.firstMatch.frame
        var clear = 0
        var under = 0
        for identifier in sheet.targets {
            let target = element(identifier, in: app)
            guard target.exists else { continue }
            let frame = target.frame
            if frame.minY < edge {
                // Scrolled under the header: faded out, but still a named element VoiceOver
                // can reach (it scrolls the row back into view).
                under += 1
                XCTAssertFalse(target.label.isEmpty, "\(identifier) under the header stays named: \(context)")
                XCTAssertGreaterThanOrEqual(frame.height, 43.67, "\(identifier) under the header \(frame) (\(context))")
                continue
            }
            // A control that starts below the ramp, on screen (an AX5 row can run past the
            // bottom, so only a wholly visible one must be hittable).
            guard frame.minY >= edge + Self.ramp, frame.minY < window.maxY - 44 else { continue }
            clear += 1
            XCTAssertFalse(target.label.isEmpty, "\(identifier) is named: \(context)")
            if frame.maxY <= window.maxY {
                XCTAssertTrue(target.isHittable, "\(identifier) is reachable: \(context)")
            }
            XCTAssertGreaterThanOrEqual(frame.height, 43.67, "\(identifier) target \(frame) (\(context))")
            XCTAssertGreaterThanOrEqual(frame.width, 43.67, "\(identifier) target \(frame) (\(context))")
        }
        if state == "rest" {
            XCTAssertGreaterThan(clear, 0, "No control clear of the header to check: \(context)")
        } else {
            XCTAssertGreaterThan(clear + under, 0, "No control left to check: \(context)")
        }
        try audit(sheet, in: app, run: run, state: state)
    }

    /// The header (title and Close) comes before every content landmark in the hierarchy's
    /// depth-first order, which VoiceOver follows (precedent `NavButtonHitRegionJourneyTests`).
    @MainActor
    private func assertTitleFirst(_ sheet: Sheet, in app: XCUIApplication, _ context: String) {
        guard let root = try? app.snapshot() else {
            XCTFail("No snapshot: \(context)")
            return
        }
        var order: [String] = []
        func walk(_ node: XCUIElementSnapshot, inBar: Bool) {
            let bar = inBar || node.elementType == .navigationBar && node.identifier == sheet.bar.identifier
            if bar, node.elementType == .staticText, node.label == sheet.title, !order.contains("title") {
                order.append("title")
            } else if sheet.content.contains(node.identifier), !order.contains(node.identifier) {
                order.append(node.identifier)
            }
            node.children.forEach { walk($0, inBar: bar) }
        }
        walk(root, inBar: false)
        XCTAssertEqual(order.first, "title", "The title is read first: \(order) (\(context))")
    }

    /// Run the audit. A contrast issue is accepted only for an element whose top lies in
    /// the ramp below the header, where content fades out by design (`scroll-edge` R2).
    @MainActor
    private func audit(_ sheet: Sheet, in app: XCUIApplication, run: Run, state: String) throws {
        let edge = sheet.bar.frame.maxY
        var issues: [String] = []
        var faded: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, run.auditTypes, name: "\(sheet.title) header \(run.name) \(state)",
            reset: { issues.removeAll(); faded.removeAll() }
        ) { issue in
            let node = issue.element
            let line = "\(node?.identifier ?? "nil") '\(node?.label ?? "")' \(String(describing: node?.frame)): "
                + issue.compactDescription
            if issue.auditType == .contrast, let frame = node?.frame, !frame.isEmpty,
               frame.minY < edge + Self.ramp {
                faded.append(line)
                return true
            }
            issues.append(line)
            return true
        }
        attach("\(sheet.title)-\(run.name)-\(state)-audit",
               (issues + faded.map { "in the header ramp, accepted: \($0)" }).joined(separator: "\n"))
        XCTAssertEqual(issues, [], "Audit issues: \(sheet.title) \(run.name) \(state)")
    }

    // MARK: - Scrolling

    /// Drag the content up slowly until `anchor` starts above the header's bottom edge.
    ///
    /// - Parameters:
    ///   - anchor: The first content element.
    ///   - bar: The sheet header.
    ///   - app: The running app.
    /// - Returns: Whether `anchor` reached under the header.
    @MainActor
    private func scrollUnderHeader(_ anchor: XCUIElement, bar: XCUIElement, in app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch
        for _ in 0..<4 where anchor.frame.minY >= bar.frame.maxY {
            // Never drag down at the top: that dismisses the sheet.
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            settle()
        }
        return anchor.frame.minY < bar.frame.maxY
    }

    // MARK: - App helpers

    /// Launch on the fixture service.
    ///
    /// - Parameters:
    ///   - run: Launch settings.
    ///   - profile: Select `fixture-player-1` (Notifications needs a player).
    /// - Returns: The running app.
    @MainActor
    private func launch(_ run: Run, profile: Bool) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var environment = [
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if profile { environment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        let app = FestivalApp.makeApp(environment)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", run.contentSize]
        app.launch()
        return app
    }

    /// Let scrolling and the fade settle.
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1)))
    }

    /// Filter Songs to `fixture-pulse`, open it, then its Paths sheet, dismissing the
    /// Karaoke notice (as `PathsSwitchAccessibilityJourneyTests`).
    @MainActor
    private func openPaths(in app: XCUIApplication) {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(20)), "No Songs rows")
        let field = SongsUITestSupport.songsSearchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: FestivalApp.budget(5)), "No Filter Songs field")
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        // The live filter can drop a keystroke while it re-renders, so retype once.
        for _ in 0..<2 where !song.exists {
            field.tap()
            if let typed = field.value as? String, !typed.isEmpty, typed != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count))
            }
            field.typeText("Pulse")
            _ = song.waitForExistence(timeout: FestivalApp.budget(5))
        }
        XCTAssertTrue(song.exists, "No fixture-pulse row")
        for _ in 0..<20 where !song.isHittable {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        song.tap()
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: FestivalApp.budget(20)), "No Paths button")
        open.tap()
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: FestivalApp.budget(3)) { warning.buttons["OK"].tap() }
        XCTAssertTrue(element("fst.paths.display", in: app).waitForExistence(timeout: FestivalApp.budget(10)),
                      "No Paths sheet")
    }

    /// The first element with an identifier, of any type.
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Open a menu picker and pick an option.
    @MainActor
    private func choose(_ option: String, in menu: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(menu.waitForExistence(timeout: FestivalApp.budget(10)))
        menu.tap()
        let item = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", option, menu.identifier)
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: FestivalApp.budget(5)), "Menu option \(option) missing")
        item.tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: FestivalApp.budget(5)), "Menu \(option) did not close")
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
