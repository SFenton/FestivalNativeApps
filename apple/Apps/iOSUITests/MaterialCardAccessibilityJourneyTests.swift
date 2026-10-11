import UIKit
import XCTest

// MARK: - Material card controls at AX5 (issue #291, backfilled by #454)

/// The floating controls #291 moved off per-card Liquid Glass onto the shared material
/// capsule (`festivalCardCapsule`, pattern `surface-materials`), on iPhone at the default
/// text size and at the largest accessibility size (AX5): Band Rankings' floating bar,
/// its pager (`RankingsGlassPager`) and band-size pill (`RankingsSwitcherPillLabel`).
///
/// Each launch reads the loopback fixture's Duos board (two bands, so one page). The rows
/// are enabled, named buttons; the pager's four arrows are buttons named First, Previous,
/// Next and Last Page, disabled on the only page, and its badge reads "Page, 1 of 1"; the
/// band-size pill is one button ("Band size, Duos"), not one per icon and title. Every
/// control is at least 44 × 44 pt, wholly on screen, and reads after the rows: pager in
/// visual order, then the pill. At AX5 the badge's text and the pill (its `@ScaledMetric`
/// height) grow while the arrows keep 44 pt targets, so First Page and Last Page stay on
/// screen (#454: the arrows' scaled 124 pt targets pushed them off it), and a scoped audit
/// covers Dynamic Type, clipped text, hit regions and descriptions on the board's own
/// elements. The same holds on the opaque
/// card the app's Reduce Transparency setting draws instead of the material.
///
/// macOS hosting cannot scale text, so this journey is the AX5 evidence;
/// `FestivalUITests/MaterialCardControlsAccessibilityTests` covers the same controls'
/// names, roles, order, targets and actions in `apple-ci` under every transparency and
/// contrast setting, and `BoardFooterFadeJourneyTests` the in-content pager at AX5.
///
/// Needs `tools/mock_service.py` (`apple-ci` serves it with `--large-catalogue` on the
/// default port 8765; `FST_MATERIAL_CARD_FIXTURE_URL`, as
/// `TEST_RUNNER_FST_MATERIAL_CARD_FIXTURE_URL`, points a local run at another port).
/// `apple-ci` runs it on its iPhone simulator (`testing/apple/xcuitest.md#ci-journeys`).
/// Skips when the board never loads.
///
/// HIG Accessibility: iOS default control size "44×44pt"; "Label elements correctly for
/// Voice Control and VoiceOver". HIG Materials: "Use standard materials within the
/// content layer".
final class MaterialCardAccessibilityJourneyTests: XCTestCase {
    private static let fixtureService = ProcessInfo.processInfo.environment["FST_MATERIAL_CARD_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    /// Identifier prefix of the board's rows.
    private static let rowPrefix = "fst.band-rankings.row."
    /// The fixture's Duos rows.
    private static let rows = ["fst.band-rankings.row.fixture-team-1", "fst.band-rankings.row.fixture-team-2"]
    /// The pager's arrows with the word each name carries.
    private static let pagerArrows = [
        (id: "fst.band-rankings.page-first", name: "First Page"),
        (id: "fst.band-rankings.page-previous", name: "Previous Page"),
        (id: "fst.band-rankings.page-next", name: "Next Page"),
        (id: "fst.band-rankings.page-last", name: "Last Page"),
    ]
    /// The pager's adjustable page badge.
    private static let pageInfo = "fst.band-rankings.page-info"
    /// The band-size switcher pill.
    private static let bandSize = "fst.band-rankings.band-type-menu"
    /// HIG Accessibility: iOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44

    // MARK: - Journeys

    /// The material capsule at the default size, then at AX5: the controls keep their
    /// names, roles, states, order and targets, and grow with the text.
    @MainActor
    func testBandRankingsFloatingBarIsAccessibleAtDefaultSizeAndAX5() throws {
        continueAfterFailure = false
        let (standard, standardWindow) = try launchBoard(contentSize: nil, lessTransparency: false)
        let standardFrames = try assertFloatingBar(in: standard, window: standardWindow, size: "default")
        standard.terminate()

        let (large, largeWindow) = try launchBoard(
            contentSize: .accessibilityExtraExtraExtraLarge, lessTransparency: false
        )
        let largeFrames = try assertFloatingBar(in: large, window: largeWindow, size: "AX5")
        // The badge's text and the pill grow with the text; the arrows keep their 44 pt
        // targets so the whole pager stays on screen (asserted above).
        let pill = (try XCTUnwrap(standardFrames[Self.bandSize]), try XCTUnwrap(largeFrames[Self.bandSize]))
        XCTAssertGreaterThan(pill.1.height, pill.0.height * 1.3, "the pill did not grow at AX5: \(pill)")
        let badge = (try XCTUnwrap(standardFrames[Self.pageInfo]), try XCTUnwrap(largeFrames[Self.pageInfo]))
        XCTAssertGreaterThan(badge.1.height, badge.0.height + 4, "the page badge did not grow at AX5: \(badge)")
        try auditBoard(large, size: "AX5")
    }

    /// The opaque card (Settings › Reduce Transparency) at AX5 exposes the same controls.
    @MainActor
    func testBandRankingsFloatingBarIsAccessibleWithReduceTransparencyAtAX5() throws {
        continueAfterFailure = false
        let (app, window) = try launchBoard(contentSize: .accessibilityExtraExtraExtraLarge, lessTransparency: true)
        _ = try assertFloatingBar(in: app, window: window, size: "AX5, Reduce Transparency")
        try auditBoard(app, size: "AX5, Reduce Transparency")
    }

    // MARK: - Launch

    /// Launch on the Duos Band Rankings board.
    ///
    /// - Parameters:
    ///   - contentSize: Preferred text size, or nil for the default.
    ///   - lessTransparency: Settings › Reduce Transparency (the opaque card).
    /// - Returns: The app with its pager loaded, and the window's frame.
    /// - Throws: A skip when the board never loads.
    @MainActor
    private func launchBoard(
        contentSize: UIContentSizeCategory?, lessTransparency: Bool
    ) throws -> (XCUIApplication, CGRect) {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixtureService,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_ROUTE": "bandRankings:Band_Duets",
        ])
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        }
        app.launchArguments += ["-fst.accessibility.lessTransparency", lessTransparency ? "YES" : "NO"]
        app.launch()
        let info = app.descendants(matching: .any)[Self.pageInfo]
        guard info.waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("Band Rankings never loaded; run tools/mock_service.py on \(Self.fixtureService).")
        }
        return (app, app.windows.firstMatch.frame)
    }

    // MARK: - Assertions

    /// The rows are named, enabled buttons; the pager and the band-size pill are named
    /// controls with their states, 44 pt targets wholly on screen, reading after the rows
    /// in visual order.
    ///
    /// - Parameters:
    ///   - app: The app on Band Rankings.
    ///   - window: The window's frame.
    ///   - size: Label for failure messages.
    /// - Returns: Each control's frame, by identifier.
    @MainActor
    @discardableResult
    private func assertFloatingBar(
        in app: XCUIApplication, window: CGRect, size: String
    ) throws -> [String: CGRect] {
        let first = app.buttons[Self.rows[0]]
        XCTAssertTrue(first.waitForExistence(timeout: FestivalApp.budget(10)), "No band rows (\(size))")
        for id in Self.rows {
            let row = app.buttons[id]
            XCTAssertTrue(row.exists, "\(id) is not a button (\(size))")
            XCTAssertTrue(row.isEnabled, "\(id) is not enabled (\(size))")
            XCTAssertFalse(row.label.isEmpty, "\(id) has no name (\(size))")
        }
        XCTAssertTrue(first.isHittable, "\(Self.rows[0]) is not reachable (\(size)): \(first.frame)")

        var frames: [String: CGRect] = [:]
        for arrow in Self.pagerArrows {
            let button = app.buttons[arrow.id]
            XCTAssertTrue(button.exists, "\(arrow.id) is not a button (\(size))")
            XCTAssertEqual(button.label, arrow.name, "\(arrow.id) name (\(size))")
            XCTAssertFalse(button.isEnabled, "\(arrow.id) is enabled on the only page (\(size))")
            frames[arrow.id] = button.frame
        }
        let info = app.descendants(matching: .any)[Self.pageInfo]
        XCTAssertEqual(info.label, "Page", "page badge name (\(size))")
        XCTAssertEqual(info.value as? String, "1 of 1", "page badge value (\(size))")
        frames[Self.pageInfo] = info.frame

        // One control for the whole pill, a button VoiceOver names "Band size, Duos".
        let pills = app.descendants(matching: .any).matching(identifier: Self.bandSize)
        XCTAssertEqual(pills.count, 1, "the band-size pill is one element (\(size))")
        let pill = app.buttons[Self.bandSize]
        XCTAssertTrue(pill.exists, "the band-size pill is not a button (\(size))")
        XCTAssertEqual(pill.label, "Band size", "band-size pill name (\(size))")
        XCTAssertEqual(pill.value as? String, "Duos", "band-size pill value (\(size))")
        XCTAssertTrue(pill.isEnabled, "the band-size pill is not enabled (\(size))")
        XCTAssertTrue(pill.isHittable, "the band-size pill is not reachable (\(size)): \(pill.frame)")
        frames[Self.bandSize] = pill.frame

        for (id, frame) in frames {
            XCTAssertGreaterThanOrEqual(frame.width, Self.minimumTarget - 0.5, "\(id) target \(frame) (\(size))")
            XCTAssertGreaterThanOrEqual(frame.height, Self.minimumTarget - 0.5, "\(id) target \(frame) (\(size))")
            XCTAssertTrue(window.contains(frame), "\(id) off screen: \(frame) (\(size))")
        }
        // The pager reads in visual order: First, Previous, the badge, Next, Last.
        let pagerOrder = [Self.pagerArrows[0].id, Self.pagerArrows[1].id, Self.pageInfo,
                          Self.pagerArrows[2].id, Self.pagerArrows[3].id]
        for (left, right) in zip(pagerOrder, pagerOrder.dropFirst()) {
            let a = try XCTUnwrap(frames[left]), b = try XCTUnwrap(frames[right])
            XCTAssertGreaterThan(b.minX, a.minX, "\(right) is drawn before \(left) (\(size))")
        }
        try assertReadingOrder(in: app, expected: pagerOrder + [Self.bandSize], size: size)
        return frames
    }

    /// Rows, then the pager, then the band-size pill, in the accessibility tree.
    ///
    /// - Parameters:
    ///   - app: The app on Band Rankings.
    ///   - expected: The floating bar's identifiers in reading order.
    ///   - size: Label for failure messages.
    @MainActor
    private func assertReadingOrder(in app: XCUIApplication, expected: [String], size: String) throws {
        var identifiers: [String] = []
        func walk(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty { identifiers.append(element.identifier) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        let lastRow = try XCTUnwrap(identifiers.lastIndex { $0.hasPrefix(Self.rowPrefix) }, "No row in the tree")
        let bar = identifiers.filter { expected.contains($0) }
        XCTAssertEqual(bar, expected, "floating bar reading order (\(size))")
        let firstBar = try XCTUnwrap(identifiers.firstIndex { expected.contains($0) }, "No floating bar")
        XCTAssertLessThan(lastRow, firstBar, "The floating bar reads before a row (\(size))")
    }

    /// The system audit for the board's own rows, pager and pill (the shell has its own).
    ///
    /// - Parameters:
    ///   - app: The app on Band Rankings.
    ///   - size: Label for failure messages.
    @MainActor
    private func auditBoard(_ app: XCUIApplication, size: String) throws {
        var issues: [String] = []
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        ) { issue in
            let id = issue.element?.identifier ?? ""
            guard id.hasPrefix("fst.band-rankings.") else { return true }
            issues.append("\(id) '\(issue.element?.label ?? "")': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Band Rankings audit issues (\(size))")
    }
}
