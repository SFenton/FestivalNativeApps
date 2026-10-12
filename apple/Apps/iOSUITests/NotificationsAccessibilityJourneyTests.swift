import UIKit
import XCTest

/// Accessibility of the Notifications sheet's rows under its pinned "New" title (#469,
/// for #322).
///
/// #322 hid the List's own row separators and drew each row's line inside the row's
/// masked background, so the line fades under the pinned title with the row
/// (`PinnedHeaderRowSeparator` in `PinnedHeaderEdgeFade.swift`). That line and the
/// separator-guide markers must stay decoration: each journey opens the sheet on the
/// fixture account `fixture-notify-many` (24 unread rows, `tools/mock_service.py`), checks
/// the title is a heading read before the rows, the rows read in feed order with their
/// full labels and 44 pt targets (HIG Accessibility, "iOS, iPadOS 44×44 pt"), then drags
/// one row into the fade band and across the title's edge and checks the row keeps its
/// label, frame, descendants and hit target with nothing else exposed inside it, and
/// audits the masked state. The AX5 journey also checks the title and rows grow with
/// Dynamic Type. The hosted `NotificationsPinnedHeaderAccessibilityTests` pin the same
/// contract (plus the "Older" title and the hard-edge modes) on macOS in `apple-ci`.
///
/// Needs `tools/mock_service.py` on port 8765 (plain or `--large-catalogue`), or at
/// `FST_NOTIFICATIONS_FIXTURE_URL` (`TEST_RUNNER_FST_NOTIFICATIONS_FIXTURE_URL` through
/// `xcodebuild`) when another lane's mock holds that port.
final class NotificationsAccessibilityJourneyTests: XCTestCase {
    // MARK: - Fixture

    private static let account = "fixture-notify-many"
    private static let rowCount = 24
    private static let rowPrefix = "fst.notifications.row."

    /// One element the sheet's list exposes, in snapshot (reading) order.
    private struct Node {
        let identifier: String
        let label: String
        let frame: CGRect
        let isHeading: Bool
        let isEnabled: Bool
    }

    /// Launch Songs with the long-feed account selected.
    ///
    /// - Parameter largeText: Launch at the largest accessibility text size (AX5).
    /// - Returns: The launched app.
    @MainActor
    private func launch(largeText: Bool) -> XCUIApplication {
        let base = ProcessInfo.processInfo.environment["FST_NOTIFICATIONS_FIXTURE_URL"]
            ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "\(Self.account):Notify Many",
        ])
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
        }
        app.launch()
        return app
    }

    /// Open the sheet from the bell and wait for its first row.
    ///
    /// - Parameter app: The launched app.
    @MainActor
    private func openSheet(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: FestivalApp.budget(20)), "No bell", file: file, line: line)
        let counted = NSPredicate(format: "label == %@", "Notifications, \(Self.rowCount) unread")
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation(for: counted, evaluatedWith: bell)], timeout: FestivalApp.budget(20)),
            .completed, "The bell never announced \(Self.rowCount) unread: '\(bell.label)'", file: file, line: line
        )
        bell.tap()
        XCTAssertTrue(
            app.buttons[Self.rowPrefix + "\(Self.account)-0"].waitForExistence(timeout: FestivalApp.budget(15)),
            "The sheet did not show its first row", file: file, line: line
        )
        waitForRowsToSettle(app)
    }

    // MARK: - Tests

    /// Default text size: heading and rows read in order with their names and targets,
    /// and a row in the fade or cut by the title keeps its accessibility. When the audit
    /// reports the "New" title's Dynamic Type as partially unsupported, the title must
    /// measure at least 1.35x taller in an AX5 launch (the `dynamic-type-grows` evidence).
    @MainActor
    func testRowsUnderThePinnedTitleKeepTheirAccessibility() throws {
        continueAfterFailure = false
        let app = launch(largeText: false)
        openSheet(app)
        let small = try assertReadingOrder(app, size: "default")
        guard try assertRowUnderTheTitle(app, size: "default") else { return }
        app.terminate()

        let large = launch(largeText: true)
        openSheet(large)
        let grown = try assertReadingOrder(large, size: "AX5")
        XCTAssertGreaterThanOrEqual(
            grown.heading.height, small.heading.height * 1.35,
            "Audit flagged 'New' and it did not scale: \(small.heading.height) → \(grown.heading.height) pt"
        )
    }

    /// Largest accessibility text size: the title and rows grow with Dynamic Type, still
    /// read in order unclipped, and a row under the title keeps its accessibility.
    @MainActor
    func testRowsUnderThePinnedTitleKeepTheirAccessibilityAtAX5() throws {
        continueAfterFailure = false
        let regular = launch(largeText: false)
        openSheet(regular)
        let small = try assertReadingOrder(regular, size: "default")
        regular.terminate()

        let app = launch(largeText: true)
        openSheet(app)
        let large = try assertReadingOrder(app, size: "AX5")
        XCTAssertGreaterThanOrEqual(
            large.heading.height, small.heading.height * 1.35,
            "'New' did not scale: \(small.heading.height) → \(large.heading.height) pt"
        )
        XCTAssertGreaterThanOrEqual(
            large.row.height, small.row.height * 1.35,
            "Rows did not scale: \(small.row.height) → \(large.row.height) pt"
        )
        // The growth above is the evidence for a partially-unsupported finding on 'New'.
        _ = try assertRowUnderTheTitle(app, size: "AX5")
    }

    // MARK: - Reading order

    /// The list exposes the one "New" heading, then the rows in feed order, each a named,
    /// enabled button at least 44 pt each way whose label is its own notification's.
    ///
    /// - Parameters:
    ///   - app: The app with the sheet open at its top.
    ///   - size: Label for failure messages.
    /// - Returns: The heading's and first row's frames.
    @MainActor
    private func assertReadingOrder(_ app: XCUIApplication, size: String) throws -> (heading: CGRect, row: CGRect) {
        let nodes = try sheetNodes(app)
        let window = app.windows.firstMatch.frame
        XCTContext.runActivity(named: "Sheet order at \(size): \(nodes.map { "\($0.identifier) '\($0.label)' \($0.frame)" })") { _ in }
        let headings = nodes.filter(\.isHeading)
        XCTAssertEqual(headings.map(\.label), ["New"], "One 'New' heading at \(size)")
        let heading = try XCTUnwrap(headings.first)
        XCTAssertEqual(nodes.first?.label, "New", "The title reads before the rows at \(size)")
        let rows = nodes.filter { $0.identifier.hasPrefix(Self.rowPrefix) }
        XCTAssertEqual(nodes.count, rows.count + 1, "Only the title and rows at \(size): \(nodes.map(\.label))")
        let indices = rows.compactMap { Int($0.identifier.split(separator: "-").last ?? "") }
        XCTAssertEqual(indices, Array(indices.sorted()), "Rows read in feed order at \(size)")
        XCTAssertEqual(indices.first, 0, "The first row reads first at \(size)")
        // At AX5 one row can be taller than the space below the title.
        let onScreen = rows.filter { $0.frame.minY < window.maxY && $0.frame.maxY > window.minY }
        XCTAssertGreaterThanOrEqual(onScreen.count, 1, "No row on screen at \(size)")
        for row in onScreen {
            let index = try XCTUnwrap(Int(row.identifier.split(separator: "-").last ?? ""))
            XCTAssertTrue(row.isEnabled, "\(row.identifier) disabled at \(size)")
            XCTAssertTrue(
                row.label.contains("#\(500 + index) to #\(index + 1)"),
                "\(row.identifier) reads another row's notification at \(size): '\(row.label)'"
            )
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(row.identifier) height at \(size)")
            XCTAssertGreaterThanOrEqual(row.frame.width, 44, "\(row.identifier) width at \(size)")
            XCTAssertGreaterThanOrEqual(row.frame.minY, heading.frame.maxY - 0.5, "\(row.identifier) above the title at \(size)")
        }
        return (heading.frame, try XCTUnwrap(onScreen.first).frame)
    }

    /// The sheet list's headings and row buttons in snapshot order (not descending into
    /// buttons, as VoiceOver reads a button as one element).
    @MainActor
    private func sheetNodes(_ app: XCUIApplication) throws -> [Node] {
        var nodes: [Node] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .button, node.identifier.hasPrefix(Self.rowPrefix) {
                nodes.append(Node(identifier: node.identifier, label: node.label, frame: node.frame,
                                  isHeading: false, isEnabled: node.isEnabled))
                return
            }
            if node.elementType == .staticText, ["New", "Older"].contains(node.label) {
                let traits = Self.traits(node)
                nodes.append(Node(identifier: node.identifier, label: node.label, frame: node.frame,
                                  isHeading: traits.map { $0 & UIAccessibilityTraits.header.rawValue != 0 } ?? true,
                                  isEnabled: node.isEnabled))
            }
            if node.elementType == .button { return }
            node.children.forEach(walk)
        }
        walk(try app.snapshot())
        return nodes
    }

    /// The snapshot's accessibility traits, when readable (as `CompeteAccessibilityJourneyTests`).
    @MainActor
    private static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
    }

    // MARK: - Row under the title

    /// Drag a row clear of the fade into the fade band, then across the pinned title's
    /// edge so the mask cuts it, and check it keeps its accessibility; audit the cut state.
    ///
    /// - Parameters:
    ///   - app: The app with the sheet open at its top.
    ///   - size: Label for failure messages.
    /// - Returns: Whether the audit reported the "New" title's Dynamic Type as partially
    ///   unsupported, which the caller must disprove with measured growth.
    @MainActor
    @discardableResult
    private func assertRowUnderTheTitle(_ app: XCUIApplication, size: String) throws -> Bool {
        let title = app.staticTexts["New"].firstMatch
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
        // XCUITest reads the title as its whole header cell, whose bottom is the pinned
        // band's edge (PinnedHeaderEdgeFade.edge). At rest the cell sits below the gap iOS
        // leaves above the first header; the title is drawn lifted over that gap (#301, a
        // visual effect the cell's frame does not follow), so the edge is read live, once
        // the header has pinned.
        let resting = title.frame
        var edge: CGFloat { title.frame.maxY }
        let window = app.windows.firstMatch.frame
        // A row clear of the fade with its top on screen; at AX5 the first row fills the
        // sheet, so scroll until the next one is.
        func clearRow() -> XCUIElement? {
            rows.allElementsBoundByIndex.first { row in
                row.frame.minY >= edge + 2 * PinnedRowProbe.fade && row.frame.minY <= window.maxY - 120
            }
        }
        var candidate = clearRow()
        for _ in 0..<6 where candidate == nil {
            let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            waitForRowsToSettle(app)
            candidate = clearRow()
        }
        let identifier = try XCTUnwrap(candidate?.identifier, "No row clear of the fade at \(size)")
        let row = app.buttons[identifier]
        let clear = try PinnedRowProbe(row: row, in: app)
        XCTAssertTrue(clear.strays.isEmpty, "Clear row exposes \(clear.strays) at \(size)")

        var pinned: CGRect?
        for (state, offset) in [("in the band", PinnedRowProbe.fade / 4), ("cut", -PinnedRowProbe.fade / 4)] {
            var target: CGFloat { edge + offset }
            // A drag first spends the pan's slop, so a short one never moves the list:
            // back off first, and lengthen each drag by the slop the last one lost
            // (as `SongsChromeJourneyTests.testRowUnderTheSectionBarFadeKeepsItsAccessibility`).
            var slop: CGFloat = 0
            func drag(_ length: CGFloat) {
                let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
                start.press(
                    forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: length)),
                    withVelocity: .slow, thenHoldForDuration: 0.3
                )
                waitForRowsToSettle(app)
            }
            for _ in 0..<6 where abs(row.frame.minY - target) > 6 {
                if abs(row.frame.minY - target) < 40 { drag(80) }
                let before = row.frame.minY
                let delta = target - before
                let length = delta + (delta > 0 ? slop : -slop)
                drag(length)
                slop = max(0, abs(length) - abs(row.frame.minY - before))
            }
            let titleFrame = title.frame
            let masked = try PinnedRowProbe(row: row, in: app)
            XCTContext.runActivity(named: "\(size) \(state): title \(titleFrame) (resting \(resting)), row \(masked.frame)") { _ in }
            XCTAssertEqual(titleFrame.height, resting.height, accuracy: 0.5, "\(size) \(state): the title changed size")
            XCTAssertLessThanOrEqual(titleFrame.minY, resting.minY, "\(size) \(state): the title scrolled down")
            if let pinned {
                XCTAssertEqual(titleFrame.minY, pinned.minY, accuracy: 1, "\(size) \(state): the title did not stay pinned")
            }
            pinned = titleFrame
            XCTAssertLessThan(masked.frame.minY, titleFrame.maxY + PinnedRowProbe.fade / 2, "\(size) \(state): row not under the fade")
            XCTAssertGreaterThan(masked.frame.maxY, titleFrame.maxY + 8, "\(size) \(state): row hidden under the title")
            XCTAssertEqual(masked.label, clear.label, "\(size) \(state): mask changed the row's label")
            XCTAssertEqual(masked.frame.height, clear.frame.height, accuracy: 0.5, "\(size) \(state): mask cut the row's frame")
            XCTAssertEqual(masked.frame.width, clear.frame.width, accuracy: 0.5, "\(size) \(state): mask cut the row's frame")
            XCTAssertEqual(masked.descendants, clear.descendants, "\(size) \(state): mask changed the row's descendants")
            XCTAssertTrue(masked.strays.isEmpty, "\(size) \(state): masked row exposes \(masked.strays)")
            XCTAssertEqual(masked.containers, clear.containers, "\(size) \(state): mask added containers to the row")
            XCTAssertTrue(row.isHittable, "\(size) \(state): masked row not hittable")
            let headings = try sheetNodes(app).filter(\.isHeading)
            XCTAssertEqual(headings.map(\.label), ["New"], "\(size) \(state): one pinned 'New' heading")
            XCTAssertLessThan(titleFrame.minY, masked.frame.minY, "\(size) \(state): row starts above the title")
        }
        return try audit(app, size: size)
    }

    // MARK: - Audit

    /// Run the scoped audit (Dynamic Type, clipped text, hit regions, descriptions) and fail
    /// on any issue in the sheet's title or rows. Contrast is left out: rows in the fade are
    /// dimmed by design (scroll-edge R2), and the clear rows' contrast is the Notifications
    /// render tests' concern.
    ///
    /// The one exception is "Dynamic Type font sizes are partially unsupported" on the
    /// "New" title (`.subheadline`, a scaling text style): iOS reported it intermittently
    /// (#469 retry, 2026-10-12; it passed clean before), so it is returned for the caller
    /// to disprove with ≥ 1.35x AX5 growth, the `dynamic-type-grows` evidence
    /// (`SongsFilterAccessibilityJourneyTests.testDynamicTypeAuditWithShopHidden`).
    ///
    /// - Parameters:
    ///   - app: The app with a row cut by the pinned title.
    ///   - size: Label for failure messages.
    /// - Returns: Whether the title was reported as partially unsupported.
    @MainActor
    private func audit(_ app: XCUIApplication, size: String) throws -> Bool {
        var issues: [String] = []
        var titlePartial = false
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription],
            name: "notifications-\(size)", reset: { issues = []; titlePartial = false }
        ) { issue in
            let id = issue.element?.identifier ?? ""
            let label = issue.element?.label ?? ""
            guard id.hasPrefix(Self.rowPrefix) || label == "New" || label.contains(" · ") else { return true }
            if issue.auditType == .dynamicType, label == "New",
               issue.compactDescription.contains("partially unsupported") {
                titlePartial = true
                XCTContext.runActivity(named: "To prove by AX5 growth: '\(label)' \(issue.compactDescription)") { _ in }
                return true
            }
            issues.append("\(id) '\(label)': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Notifications audit issues at \(size)")
        return titlePartial
    }

    // MARK: - Settling

    /// Wait until the first rows stop moving (stagger fade-in, scroll deceleration).
    @MainActor
    private func waitForRowsToSettle(_ app: XCUIApplication) {
        var last: [CGRect] = []
        for _ in 0..<Int(FestivalApp.budget(20)) {
            let frames = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
                .allElementsBoundByIndex.prefix(4).map(\.frame)
            if !frames.isEmpty, frames == last { return }
            last = frames
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        XCTFail("Notifications list kept moving")
    }
}
