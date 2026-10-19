import UIKit
import XCTest

// MARK: - Grouped dashboard cards at AX5 (issue #381, backfilled by #499)

/// #381 put the Leaderboards overview's rankings rows (like Song Details' top scores, Score
/// History and the Compete previews) into one `FestivalGlassSection` group card: rows edge
/// to edge with inset hairlines between them and the selected player's row a flat purple
/// band. macOS has no Dynamic Type, so `FestivalUITests/GroupedCardAccessibilityTests`
/// pins every grouped card's names, reading order, hidden hairlines and row tiling in
/// `apple-ci`; this journey is the iPhone and iPad evidence with real large text.
///
/// At AX5 the Lead card's first rows must:
/// - read as one button each, the selected player's named in words ("Your rank, 2nd.
///   Fixture Player 2."), not only with the purple band;
/// - grow with the text (taller than at the default size) and stay hittable targets at
///   least 44 pt tall that share the card's full width, one under the other with only the
///   1 pt hairline between them;
/// - pass a scoped audit (Dynamic Type, clipped text, hit region, description, contrast).
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_GROUPED_A11Y_FIXTURE_URL` for another mock) with `fixture-player-2`
/// selected. `apple-ci` runs it on its iPhone and iPad simulators
/// (`testing/apple/xcuitest.md#ci-journeys`).
///
/// HIG Accessibility: "Strive for the platform's recommended minimum control size" (iOS
/// 44×44 pt) and "Never rely on color alone"; HIG Typography: "Keep text truncation to a
/// minimum as font size increases".
final class GroupedCardAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_GROUPED_A11Y_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    private static let card = "fst.leaderboards.card.Solo_Guitar"
    private static let rows = ["fixture-player-1", "fixture-player-2", "fixture-rank-3"]
        .map { "fst.rankings.row.\($0)" }

    // MARK: - Journey

    /// At AX5 the Leaderboards Lead card's grouped rows are named, grow with the text,
    /// tile the card as full-width 44 pt targets and pass a scoped audit.
    @MainActor
    func testLeaderboardsGroupedCardIsReadableAtAX5() throws {
        continueAfterFailure = false
        let standard = try launchLeaderboards(size: nil)
        let standardRows = try revealRows(in: standard)
        diagnose(standard, rows: standardRows, tag: "default", tap: false)
        let standardHeights = standardRows.map(\.frame.height)
        standard.terminate()

        let app = try launchLeaderboards(size: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        let rows = try revealRows(in: app)
        let window = app.windows.firstMatch.frame
        record(app, name: "grouped-leaderboards-card-ax5")
        diagnose(app, rows: rows, tag: "ax5", tap: true)

        // Names, roles and state: one button per row, the selected one said in words.
        for row in rows {
            XCTAssertEqual(row.elementType, .button, "\(row.identifier) is one button")
            XCTAssertFalse(row.isSelected, "a row link has no selected state: \(row.identifier)")
        }
        XCTAssertTrue(rows[0].label.contains("Fixture Player 1") && !rows[0].label.hasPrefix("Your rank"),
                      "'\(rows[0].label)'")
        XCTAssertEqual(rows[1].label, "Your rank, 2nd. Fixture Player 2.", "the purple band is also spoken")
        XCTAssertTrue(rows[2].label.contains("Fixture Rank 3") && !rows[2].label.hasPrefix("Your rank"),
                      "'\(rows[2].label)'")

        // Target size and tiling: full-width 44 pt targets, one hairline apart.
        let frames = rows.map(\.frame)
        for (row, frame) in zip(rows, frames) {
            XCTAssertTrue(row.isHittable, "\(row.identifier) is reachable at AX5: \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, 44 - 1, "at least 44 pt tall: \(frame)")
            XCTAssertGreaterThan(frame.width, min(window.width, 700) * 0.75, "spans the card: \(frame)")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "starts on screen: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "ends on screen: \(frame)")
        }
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(upper.minX, lower.minX, accuracy: 0.5, "rows share the card's leading edge")
            XCTAssertEqual(upper.width, lower.width, accuracy: 0.5, "rows share the card's width")
            let gap = lower.minY - upper.maxY
            XCTAssertTrue(gap >= -0.5 && gap <= 1.5, "only the hairline separates rows (gap \(gap)): \(upper) / \(lower)")
        }

        // Text scaling: every row grows with the text.
        for (index, frame) in frames.enumerated() {
            XCTAssertGreaterThan(frame.height, standardHeights[index] * 1.2,
                                 "\(rows[index].identifier) grows at AX5: \(frame.height) vs \(standardHeights[index])")
        }

        // Audit the grouped rankings cards only: the chrome has its own journeys.
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription, .contrast]
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            guard let element = issue.element,
                  element.identifier.hasPrefix("fst.rankings.row.") || element.identifier.hasPrefix("fst.leaderboards.card.")
            else { return true }
            issues.append("\(element.identifier) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        do {
            try app.performAccessibilityAudit(for: audit, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            // The CI runner can exceed XCTest's audit deadline (#388): retry once.
            issues.removeAll()
            try app.performAccessibilityAudit(for: audit, handler)
        }
        XCTAssertEqual(issues, [], "grouped card audit issues at AX5")
    }

    // MARK: - Launch and reveal

    /// Open Leaderboards with `fixture-player-2` selected at a text size.
    ///
    /// - Parameter size: A `UIContentSizeCategory` raw value; nil keeps the default.
    /// - Returns: The launched app on Leaderboards.
    @MainActor
    private func launchLeaderboards(size: String?) throws -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-2:Fixture Player 2",
            // With a player selected Leaderboards is pushed from Compete, not a tab.
            "FST_DEBUG_ROUTE": "leaderboards",
        ])
        if let size {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: FestivalApp.budget(20)),
                      "Leaderboards opens")
        return app
    }

    /// Scroll the Lead card's first three rows on screen, clear of the scroll-edge fades
    /// and the bottom chrome, and let the card settle.
    ///
    /// - Parameter app: The app on Leaderboards.
    /// - Returns: The first three rows of the Lead card, top to bottom.
    @MainActor
    private func revealRows(in app: XCUIApplication) throws -> [XCUIElement] {
        let card = app.descendants(matching: .any).matching(identifier: Self.card).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: FestivalApp.budget(20)), "Leaderboards shows the Lead card")
        let rows = Self.rows.map { card.buttons[$0].firstMatch }
        for row in rows {
            XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(20)), "\(row) in the Lead card")
        }
        let window = app.windows.firstMatch.frame
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<12 {
            let top = rows[0].frame, bottom = rows[2].frame
            XCTContext.runActivity(named: "rows \(top) … \(bottom), hittable \(rows.map(\.isHittable))") { _ in }
            if rows.allSatisfy(\.isHittable), top.minY >= window.height * 0.1, bottom.maxY <= window.height * 0.9 { break }
            // Move the three rows' centre towards the middle of the screen, at most 40% of it per drag.
            let offset = max(-window.height * 0.4, min(window.height * 0.4, window.height * 0.5 - (top.minY + bottom.maxY) / 2))
            // A short drag that starts on a row lands as a tap and opens the player: only scroll far.
            if abs(offset) < 60 { break }
            // Slow, then held: the page stops where the finger lifts instead of flinging past.
            start.press(
                forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)),
                withVelocity: .slow, thenHoldForDuration: 0.3
            )
        }
        // Let the card's fade-in finish.
        sleep(UInt32(FestivalApp.budget(1)))
        return rows
    }

    // TEMP diag #675: hittability timeline, elements under the row's centre, tree, tap probe.
    @MainActor
    private func diagnose(_ app: XCUIApplication, rows: [XCUIElement], tag: String, tap: Bool) {
        func note(_ text: String) {
            let attachment = XCTAttachment(string: text)
            attachment.name = "diag-\(tag)-\(text.prefix(24))"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("DIAG675 [\(tag)] \(text.prefix(4000))")
        }
        var timeline: [String] = []
        let started = Date()
        for _ in 0..<10 {
            let t0 = Date()
            let hittable = rows.map(\.isHittable)
            let cost = Date().timeIntervalSince(t0)
            timeline.append(String(format: "t=%.1f hittable=%@ cost=%.2fs frame0=%@", Date().timeIntervalSince(started),
                                   "\(hittable)", cost, "\(rows[0].frame)"))
            if hittable.allSatisfy({ $0 }) { break }
            Thread.sleep(forTimeInterval: 4)
        }
        note("timeline\n" + timeline.joined(separator: "\n"))
        let point = CGPoint(x: rows[0].frame.midX, y: rows[0].frame.midY)
        if let snapshot = try? app.snapshot() {
            var lines: [String] = []
            func walk(_ node: XCUIElementSnapshot, depth: Int) {
                if node.frame.contains(point) {
                    lines.append("\(String(repeating: "  ", count: depth))type=\(node.elementType.rawValue) id='\(node.identifier)' label='\(node.label.prefix(60))' frame=\(node.frame) enabled=\(node.isEnabled)")
                }
                for child in node.children { walk(child, depth: depth + 1) }
            }
            walk(snapshot, depth: 0)
            note("under \(point)\n" + lines.joined(separator: "\n"))
        }
        note("tree\n" + app.debugDescription)
        note("springboard\n" + XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)
        guard !rows[0].isHittable else { return }
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "diag-\(tag)-screen"
        screen.lifetime = .keepAlways
        add(screen)
        guard tap else { return }
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        Thread.sleep(forTimeInterval: 8)
        let bars = app.navigationBars.allElementsBoundByIndex.map(\.identifier)
        note("after tap: leaderboards bar \(app.navigationBars["Leaderboards"].exists), bars \(bars), row exists \(rows[0].exists)")
        record(app, name: "diag-after-tap")
    }

    /// Keep a screenshot with the test result.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
