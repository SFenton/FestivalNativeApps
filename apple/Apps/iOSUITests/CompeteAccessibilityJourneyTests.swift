import UIKit
import XCTest

// MARK: - Compete at AX5 (issue #35, backfilled by #407)

/// Compete's loaded page at the default text size and at the largest accessibility size
/// (AX5) on iPhone, after the one page spinner #35 introduced (since #354 the shared
/// `FestivalReloadGate`, "Loading Compete") has left.
///
/// The app reads the loopback fixture (`tools/mock_service.py`) as `fixture-riv` with Lead and
/// Bass shown: each board lists Fixture Player 1, Fixture Player 2 and Fixture Rank 3. Each
/// launch waits for the spinner to leave the tree, checks the reading order (the Leaderboards
/// heading, each instrument heading, its rows, its "View Full Leaderboard, <instrument>"
/// button, then the Rivals heading; headings with the header trait), and brings every one of
/// those elements wholly into view between the navigation bar and the bottom chrome (tab-bar
/// accessory and tab bar). At AX5 each one must read back whole from its own capture (no
/// ellipsis, no clipped word), render glyphs more than 1.35× taller than at the default size
/// (recognized line height), and every row and button must be hittable there, the buttons at
/// least 44 × 44 pt. A scoped audit covers Dynamic Type, clipped text, hit regions and
/// descriptions on Compete's own elements. macOS hosting cannot scale text, so this journey is
/// the AX5 evidence; `FestivalUITests/CompeteLoadingAccessibilityTests` covers the spinner's
/// name, role and the VoiceOver tree in `apple-ci`.
///
/// Needs `tools/mock_service.py` (`apple-ci` serves it with `--large-catalogue` on the default
/// port 8765; `FST_COMPETE_FIXTURE_URL` points a local run at another port). `apple-ci` runs it
/// on its iPhone simulator (`testing/apple/xcuitest.md#ci-journeys`). Waits use
/// `FestivalApp.budget(_:)` for the runner.
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases"; HIG
/// Accessibility: "offer text enlargement of at least 200%" and a 44×44 pt default control
/// size.
final class CompeteAccessibilityJourneyTests: XCTestCase {
    private static let fixtureService = ProcessInfo.processInfo.environment["FST_COMPETE_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// Settings keys of every instrument; only Lead and Bass are shown.
    private static let instrumentKeys = [
        "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
        "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
        "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
    ]
    private static let shownKeys: Set<String> = ["fst.settings.showLead", "fst.settings.showBass"]

    /// One element VoiceOver reads on the page.
    private struct Item: CustomStringConvertible {
        enum Kind { case heading, row, action }
        let kind: Kind
        /// Its accessibility label (a row's starts with its rank, e.g. "#1").
        let label: String
        /// The text it draws, read back from its capture.
        let drawn: String
        /// Which match of `label` (a row's rank repeats on each board).
        let occurrence: Int

        var description: String { "\(label) [\(occurrence)]" }
    }

    /// The fixture's board rows: rank, name, songs and score.
    private static let rows = [
        (rank: 1, name: "Fixture Player 1", songs: "39 / 50", score: "89,000,000"),
        (rank: 2, name: "Fixture Player 2", songs: "38 / 50", score: "88,000,000"),
        (rank: 3, name: "Fixture Rank 3", songs: "37 / 50", score: "87,000,000"),
    ]

    /// The Leaderboards section in reading order, then the Rivals heading.
    private static let readingOrder: [Item] = {
        var items = [Item(kind: .heading, label: "Leaderboards", drawn: "Leaderboards", occurrence: 0)]
        for (board, instrument) in ["Lead", "Bass"].enumerated() {
            items.append(Item(kind: .heading, label: instrument, drawn: instrument, occurrence: 0))
            for row in rows {
                items.append(Item(
                    kind: .row, label: "#\(row.rank)",
                    drawn: "#\(row.rank) \(row.name) \(row.songs) \(row.score)", occurrence: board
                ))
            }
            items.append(Item(
                kind: .action, label: "View Full Leaderboard, \(instrument)", drawn: "View Full Leaderboard", occurrence: 0
            ))
        }
        items.append(Item(kind: .heading, label: "Rivals", drawn: "Rivals", occurrence: 0))
        return items
    }()

    // MARK: - Journey

    /// Headings, rows and View Full Leaderboard buttons grow, stay whole, in order and
    /// reachable above the bottom chrome at AX5.
    @MainActor
    func testCompeteIsReadableAtAX5() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let standard = launch(contentSize: UIContentSizeCategory.large.rawValue)
        assertReadingOrder(standard, size: "default")
        var baseline: [CGFloat] = []
        for item in Self.readingOrder {
            let (element, frame) = reveal(item, in: standard)
            let reading = RecognizedText.recognize(element, label: item.drawn, frame: frame)
            XCTAssertTrue(RecognizedText.showsWhole(item.drawn, in: reading.text),
                          "\(item) reads back whole at the default size: '\(reading.text ?? "nil")'")
            let height = try XCTUnwrap(reading.lineHeight, "\(item) recognized at the default size")
            XCTAssertGreaterThan(height, 4, "\(item) has a measurable line height")
            baseline.append(height)
        }
        record(standard, name: "compete-default")
        standard.terminate()

        let app = launch(contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        record(app, name: "compete-ax5")
        assertReadingOrder(app, size: "AX5")
        let window = app.windows.firstMatch.frame
        var growth: [String] = []
        for (index, item) in Self.readingOrder.enumerated() {
            let (element, frame) = reveal(item, in: app)
            let region = contentRegion(app)
            XCTAssertGreaterThanOrEqual(frame.minY, region.minY - 0.5, "\(item) under the navigation bar: \(frame) vs \(region)")
            XCTAssertLessThanOrEqual(frame.maxY, region.maxY + 0.5, "\(item) under the bottom chrome: \(frame) vs \(region)")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(item) cut off at the leading edge: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(item) cut off at the trailing edge: \(frame)")
            let reading = RecognizedText.recognize(element, label: item.drawn, frame: frame)
            XCTAssertTrue(RecognizedText.showsWhole(item.drawn, in: reading.text),
                          "\(item) reads back whole at AX5: '\(reading.text ?? "nil")'")
            let height = try XCTUnwrap(reading.lineHeight, "\(item) recognized at AX5")
            let ratio = height / baseline[index]
            growth.append(String(format: "%@ %.2f", item.description, ratio))
            XCTAssertGreaterThan(ratio, RecognizedText.minimumGrowth,
                                 "\(item) glyphs grow at AX5: \(height) vs \(baseline[index]) pt")
            if item.kind != .heading {
                XCTAssertTrue(element.isHittable, "\(item) is reachable at AX5")
            }
            if item.kind == .action {
                XCTAssertGreaterThanOrEqual(frame.height, 44, "\(item) is at least 44 pt tall: \(frame)")
                XCTAssertGreaterThanOrEqual(frame.width, 44, "\(item) is at least 44 pt wide: \(frame)")
            }
        }
        attach("compete-ax5-growth", growth.joined(separator: "\n"))
        record(app, name: "compete-ax5-end")

        var issues: [String] = []
        let labels = Set(Self.readingOrder.filter { $0.kind != .row }.map(\.label))
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        ) { issue in
            let id = issue.element?.identifier ?? ""
            let label = issue.element?.label ?? ""
            let ours = id.hasPrefix("fst.compete.") || id.hasPrefix("fst.rankings.row.")
                || labels.contains(label) || label.hasPrefix("#")
            guard ours else { return true }
            issues.append("\(id) '\(label)': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Compete audit issues at AX5")
    }

    // MARK: - Reading order

    /// The page's headings, rows and buttons read in ``readingOrder``, each heading with the
    /// header trait, and the loading spinner is gone.
    ///
    /// - Parameters:
    ///   - app: The launched, loaded app.
    ///   - size: Label for failure messages.
    @MainActor
    private func assertReadingOrder(_ app: XCUIApplication, size: String) {
        guard let snapshot = try? app.snapshot() else {
            XCTFail("app snapshot (\(size))")
            return
        }
        let wanted = Set(Self.readingOrder.map(\.label))
        var read: [XCUIElementSnapshot] = []
        Self.walk(snapshot) { node in
            if wanted.contains(Self.key(node.label)), [.staticText, .button].contains(node.elementType) {
                read.append(node)
            }
        }
        let order = read.map { Self.key($0.label) }
        XCTAssertEqual(order, Self.readingOrder.map(\.label), "reading order at \(size): \(read.map { "\($0.elementType.rawValue) \($0.identifier) \($0.label) \($0.frame)" })")
        for node in read where Self.readingOrder.contains(where: { $0.kind == .heading && $0.label == node.label }) {
            if let traits = Self.traits(node) {
                XCTAssertNotEqual(traits & UIAccessibilityTraits.header.rawValue, 0, "'\(node.label)' is a heading at \(size)")
            }
        }
        for node in read where node.label.hasPrefix("View Full Leaderboard") {
            XCTAssertEqual(node.elementType, .button, "'\(node.label)' is a button at \(size)")
        }
    }

    /// The reading-order key for a label: a row's rank (its label starts "#1, …"), else the label.
    private static func key(_ label: String) -> String {
        guard label.hasPrefix("#"), let rank = label.split(whereSeparator: { $0 == "," || $0 == " " }).first
        else { return label }
        return String(rank)
    }

    // MARK: - Launch and scrolling

    /// Launch Compete for `fixture-riv` (Lead and Bass) at `contentSize` and wait until the
    /// page spinner has left and the last board's button is in the tree.
    ///
    /// - Parameter contentSize: `UIContentSizeCategory` raw value.
    /// - Returns: The loaded app.
    @MainActor
    private func launch(contentSize: String) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixtureService,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
            "FST_DEBUG_TAB": "compete",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        for key in Self.instrumentKeys {
            app.launchArguments += ["-\(key)", Self.shownKeys.contains(key) ? "YES" : "NO"]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: FestivalApp.budget(30)), "Compete opened")
        let last = app.buttons["View Full Leaderboard, Bass"]
        XCTAssertTrue(last.waitForExistence(timeout: FestivalApp.budget(30)),
                      "Compete loaded from \(Self.fixtureService)")
        let spinner = app.descendants(matching: .any)["fst.compete.loading"]
        XCTAssertTrue(spinner.waitForNonExistence(timeout: FestivalApp.budget(10)), "the page spinner leaves the tree")
        return app
    }

    /// The element for `item`.
    @MainActor
    private func element(_ item: Item, in app: XCUIApplication) -> XCUIElement {
        switch item.kind {
        case .row:
            return app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", item.label))
                .element(boundBy: item.occurrence)
        case .action:
            return app.buttons[item.label]
        case .heading:
            return app.staticTexts.matching(NSPredicate(format: "label == %@", item.label)).element(boundBy: item.occurrence)
        }
    }

    /// The scrolling page's visible region now: below the navigation bar, above the tab-bar
    /// accessory and the tab bar (both move as the page scrolls, issue #92).
    @MainActor
    private func contentRegion(_ app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let top = app.navigationBars["Compete"].frame.maxY
        var bottom = window.maxY
        let accessory = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        if accessory.exists, !accessory.frame.isEmpty { bottom = min(bottom, accessory.frame.minY) }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, !tabBar.frame.isEmpty { bottom = min(bottom, tabBar.frame.minY) }
        return CGRect(x: window.minX, y: top, width: window.width, height: bottom - top)
    }

    /// Scroll `item` wholly into the content region with slow, held drags (no fling).
    ///
    /// - Parameters:
    ///   - item: An entry of ``readingOrder``.
    ///   - app: The launched app.
    /// - Returns: The element and its frame once revealed (or after the last drag).
    @MainActor
    private func reveal(_ item: Item, in app: XCUIApplication) -> (XCUIElement, CGRect) {
        let element = element(item, in: app)
        XCTAssertTrue(element.exists, "\(item) is on the page")
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        var frame = element.frame
        var region = contentRegion(app)
        for _ in 0..<16 {
            if frame.minY >= region.minY - 0.5, frame.maxY <= region.maxY + 0.5 { break }
            let step = region.height * 0.6
            let delta = frame.maxY > region.maxY
                ? -min(frame.maxY - region.maxY + 16, step)
                : min(region.minY - frame.minY + 16, step)
            let startY = delta < 0 ? region.maxY - 16 : region.minY + 16
            // Drag at the leading margin, beside the cards' rows and buttons.
            let start = origin.withOffset(CGVector(dx: region.minX + 8, dy: startY))
            let end = origin.withOffset(CGVector(dx: region.minX + 8, dy: startY + delta))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: FestivalApp.budget(0.3))
            frame = element.frame
            region = contentRegion(app)
        }
        return (element, frame)
    }

    // MARK: - Snapshot helpers

    /// Visit `root` and its descendants in tree (reading) order. A button is one element to
    /// VoiceOver, so the texts XCUITest lists inside it are not visited.
    @MainActor
    private static func walk(_ root: XCUIElementSnapshot, _ visit: (XCUIElementSnapshot) -> Void) {
        visit(root)
        guard root.elementType != .button else { return }
        for child in root.children { walk(child, visit) }
    }

    /// The snapshot's accessibility traits, when readable.
    @MainActor
    private static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
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
