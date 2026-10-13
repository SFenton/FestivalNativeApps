import UIKit
import XCTest

// MARK: - Notifications pinned titles at AX5 (issue #301, backfilled by #459)

/// The Notifications sheet's pinned "New" title and the rows that fade out under it
/// (#301) on a real iPhone/iPad navigation stack with real Dynamic Type. macOS has no
/// Dynamic Type, so `FestivalUITests/NotificationsPinnedTitleCutAccessibilityTests` covers
/// the Mac reading order (each title, then its rows; the push between titles) in
/// `apple-ci`, and this journey is the iOS, iPadOS and iPhone Duo evidence.
///
/// At AX5, with the 24-row `fixture-notify-many` feed (all unread, so one "New"
/// section):
/// - at rest the "New" heading (header trait) is read before its rows, in row order;
/// - the heading and the rows grow, and each row is one named button at least 44 pt tall
///   spanning the sheet;
/// - scrolled until one row has passed under the title and the next is partly under it,
///   the pinned heading stays read, keeps its place and the rows stay in feed order.
///   XCUITest also lists `accessibilityHidden` views (`testing/apple/accessibility.md`),
///   so the hosted Mac test proves a row wholly under the title is no VoiceOver stop
///   (scroll-edge R7);
/// - a scoped audit (Dynamic Type, clipped text, hit region, description) passes.
///
/// Runs against `tools/mock_service.py` (port 8765; set
/// `TEST_RUNNER_FST_NOTIFICATIONS_FIXTURE_URL` for another mock). `apple-ci` runs it
/// on its iPhone and iPad simulators (`testing/apple/xcuitest.md#ci-journeys`).
///
/// HIG VoiceOver: "Specify how elements are grouped, ordered or linked"; HIG
/// Accessibility: iOS, iPadOS default control size 44×44 pt.
final class NotificationsPinnedTitleJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_NOTIFICATIONS_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    private static let account = "fixture-notify-many"
    private static let rowPrefix = "fst.notifications.row.fixture-notify-many-"
    private static let rowCount = 24

    // MARK: - Journeys

    /// iPhone and iPad (and the real iPhone Duo when run there).
    @MainActor
    func testPinnedTitleAndRowsAtLargestText() throws {
        try assertPinnedTitle(duoWindow: nil)
    }

    /// iPhone Duo folded (outer display), simulated on the CI iPhone (`DebugDuoWindow`).
    @MainActor
    func testPinnedTitleAndRowsAtLargestTextDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertPinnedTitle(duoWindow: "folded")
    }

    // MARK: - Assertions

    /// Open the sheet at the default size and at AX5, then check names, roles, order,
    /// targets, scaling and the pinned title while scrolling.
    ///
    /// - Parameter duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    @MainActor
    private func assertPinnedTitle(duoWindow: String?) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let standard = try openSheet(size: nil, duoWindow: duoWindow)
        let standardRest = try rest(in: standard, size: "default")
        standard.terminate()

        continueAfterFailure = true
        let app = try openSheet(
            size: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue, duoWindow: duoWindow
        )
        let large = try rest(in: app, size: "AX5")
        record(app, name: "notifications-ax5-rest")

        // Text scaling: the title and the rows grow.
        XCTAssertGreaterThan(large.heading.height, standardRest.heading.height * 1.3,
                             "the New title grows at AX5: \(large.heading) vs \(standardRest.heading)")
        XCTAssertGreaterThan(large.row.height, standardRest.row.height * 1.2,
                             "rows grow at AX5: \(large.row) vs \(standardRest.row)")

        audit(app)
        try assertPinnedWhileScrolling(app)
    }

    /// The sheet at rest: the heading, then its rows in order, each a named, full-width
    /// button at least 44 pt tall.
    ///
    /// - Parameters:
    ///   - app: The app with the sheet open.
    ///   - size: Label for failure messages.
    /// - Returns: The heading's and the first row's frames.
    @MainActor
    private func rest(in app: XCUIApplication, size: String) throws -> (heading: CGRect, row: CGRect) {
        let sheet = app.collectionViews.firstMatch
        let window = app.windows.firstMatch.frame
        let nodes = try FestivalApp.snapshotNodes(in: sheet) { node in
            Self.isRow(node) || (node.elementType == .staticText && node.label == "New")
        }
        attach("reading order (\(size))", nodes.map(Self.describe).joined(separator: "\n"))
        let heading = try XCTUnwrap(nodes.first { !Self.isRow($0) },
                                    "the New title is read (\(size))")
        XCTAssertTrue(Self.isHeader(heading), "'New' is a heading (\(size))")
        XCTAssertFalse(nodes.first.map(Self.isRow) ?? true,
                       "the New title is read before its rows (\(size))")

        let rows = nodes.filter { Self.isRow($0) && $0.frame.minY < window.maxY }
        XCTAssertFalse(rows.isEmpty, "rows are read (\(size))")
        let indexes = rows.compactMap(Self.index)
        XCTAssertEqual(indexes, Array(0..<indexes.count), "rows are read top to bottom from the first (\(size))")
        XCTAssertLessThanOrEqual(heading.frame.maxY, rows[0].frame.minY + 1, "the title sits above its first row (\(size))")
        for row in rows where row.frame.maxY <= window.maxY {
            XCTAssertEqual(row.elementType, .button, "\(Self.describe(row)) is a button (\(size))")
            XCTAssertFalse(row.label.trimmingCharacters(in: .whitespaces).isEmpty, "\(row.identifier) is named (\(size))")
            XCTAssertGreaterThanOrEqual(row.frame.height, 44 - 1, "\(Self.describe(row)) is at least 44 pt tall (\(size))")
            XCTAssertGreaterThan(row.frame.width, sheet.frame.width * 0.75, "\(Self.describe(row)) spans the sheet (\(size))")
        }
        XCTAssertTrue(app.buttons[rows[0].identifier].isHittable, "the first row is reachable (\(size))")
        return (heading.frame, rows[0].frame)
    }

    /// Scroll in small held drags (no momentum) until a row has passed wholly under the
    /// pinned title and the next is partly under it, checking every step: the title is
    /// still read as a heading, stays pinned once it stops moving, and the rows are read in
    /// feed order. XCUITest also lists `accessibilityHidden` views, so whether the wholly
    /// cut row leaves VoiceOver is asserted by the macOS-hosted
    /// `NotificationsPinnedTitleCutAccessibilityTests` (`testing/apple/accessibility.md`).
    ///
    /// - Parameter app: The app with the sheet open at rest.
    @MainActor
    private func assertPinnedWhileScrolling(_ app: XCUIApplication) throws {
        let sheet = app.collectionViews.firstMatch
        let list = sheet.frame
        let step = min(80, list.height * 0.1)
        let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: list.height * 0.75))
        var headingTops: [CGFloat] = []
        var cutSeen = false
        for index in 0..<40 where !cutSeen || headingTops.count < 4 {
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -step)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            let nodes = try FestivalApp.snapshotNodes(in: sheet) { node in
                Self.isRow(node) || (node.elementType == .staticText && node.label == "New")
            }
            let state = "step \(index): " + nodes.map(Self.describe).joined(separator: "; ")
            guard let heading = nodes.first(where: { !Self.isRow($0) }) else {
                XCTFail("the pinned New title is read: \(state)")
                continue
            }
            XCTAssertTrue(Self.isHeader(heading), "the pinned 'New' is a heading: \(state)")
            let edge = heading.frame.maxY
            let rows = nodes.filter(Self.isRow).sorted { $0.frame.minY < $1.frame.minY }
            let indexes = rows.compactMap(Self.index)
            XCTAssertEqual(indexes, indexes.sorted(), "rows are read in feed order: \(state)")
            // The title has pinned once the first row has scrolled under it.
            if let first = rows.first, first.frame.minY < heading.frame.minY { headingTops.append(heading.frame.minY) }
            // A row past the title, and the next one partly under it.
            if let partly = rows.first(where: { $0.frame.maxY > edge + 0.5 }), let at = Self.index(partly), at > 0,
               partly.frame.minY < edge - 1 {
                if !cutSeen {
                    attach("cut (step \(index))", state)
                    record(app, name: "notifications-ax5-cut")
                }
                cutSeen = true
            }
        }
        XCTAssertTrue(cutSeen, "scrolling never moved a row past the title with the next partly under it")
        if let pinned = headingTops.first {
            for top in headingTops {
                XCTAssertEqual(top, pinned, accuracy: 1, "the New title stays pinned: \(headingTops)")
            }
        } else {
            XCTFail("the New title never pinned")
        }
    }

    /// Audit the sheet's rows at rest (the shell has its own journeys).
    @MainActor
    private func audit(_ app: XCUIApplication) {
        var issues: [String] = []
        let types: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            guard let element = issue.element, element.identifier.hasPrefix("fst.notifications.") else { return true }
            issues.append("\(element.identifier) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        do {
            try app.performAccessibilityAudit(for: types, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            // The CI runner can exceed XCTest's audit deadline (#388): retry once.
            issues.removeAll()
            try? app.performAccessibilityAudit(for: types, handler)
        } catch {
            XCTFail("audit failed: \(error)")
        }
        XCTAssertEqual(issues, [], "Notifications audit issues at AX5")
    }

    // MARK: - Launch

    /// Launch with the long feed's player selected and open the Notifications sheet.
    ///
    /// - Parameters:
    ///   - size: A `UIContentSizeCategory` raw value; nil keeps the default.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Returns: The app with the sheet's rows loaded.
    /// - Throws: A skip when the fixture never loads.
    @MainActor
    private func openSheet(size: String?, duoWindow: String?) throws -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "\(Self.account):Fixture Notifications",
        ]
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        }
        let app = FestivalApp.makeApp(environment)
        if let size {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        if let duoWindow { waitForDuoWindow(duoWindow, in: app) }
        let bell = app.buttons["fst.shell.notifications"]
        guard bell.waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("The bell never showed; run tools/mock_service.py on \(Self.origin).")
        }
        let unread = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "\(Self.rowCount) unread"), object: bell
        )
        XCTAssertEqual(XCTWaiter().wait(for: [unread], timeout: FestivalApp.budget(20)), .completed,
                       "the bell counts the long feed: '\(bell.label)'")
        bell.tap()
        let first = app.buttons["\(Self.rowPrefix)0"]
        XCTAssertTrue(first.waitForExistence(timeout: FestivalApp.budget(20)), "the sheet lists the feed")
        // Let the rows' staggered fade-in finish.
        sleep(UInt32(FestivalApp.budget(2)))
        return app
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

    // MARK: - Snapshot helpers

    /// A row's VoiceOver stop: its button (its cell and content carry the identifier too).
    private static func isRow(_ node: XCUIElementSnapshot) -> Bool {
        node.elementType == .button && node.identifier.hasPrefix(rowPrefix)
    }

    /// A row's position in the feed, from its identifier.
    private static func index(_ node: XCUIElementSnapshot) -> Int? {
        guard node.identifier.hasPrefix(rowPrefix) else { return nil }
        return Int(node.identifier.dropFirst(rowPrefix.count))
    }

    /// The node's accessibility traits, where the snapshot exposes them.
    private static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
    }

    /// True for a heading, or when the snapshot hides traits.
    private static func isHeader(_ snapshot: XCUIElementSnapshot) -> Bool {
        guard let traits = traits(snapshot) else { return true }
        return traits & UIAccessibilityTraits.header.rawValue != 0
    }

    private static func describe(_ node: XCUIElementSnapshot) -> String {
        let frame = node.frame
        return "\(node.elementType.rawValue) \(node.identifier.isEmpty ? node.label : node.identifier) [\(Int(frame.minY))–\(Int(frame.maxY))]"
    }

    // MARK: - Evidence

    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
