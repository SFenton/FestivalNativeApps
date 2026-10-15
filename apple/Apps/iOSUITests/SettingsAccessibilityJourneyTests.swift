import UIKit
import XCTest

/// Accessibility of Settings where the Diagnostics section used to be (#496, for #374).
///
/// #374 removed the Debug-only Diagnostics section (Tap Diagnostics, Tap Telemetry) that sat
/// between Accessibility and Item Shop on the iPhone Settings page, and its Quick Link. These
/// journeys run the Debug build (the only build that ever showed it) and check what VoiceOver
/// and large-text users now get across that join: the Quick Links sheet offers Accessibility
/// directly followed by Item Shop, named and at least 44 pt tall; on the page, the Accessibility
/// heading, its four switches, the Item Shop heading and its two switches read in that order,
/// up to the Show Instruments heading, with nothing named Diagnostics or Tap between them;
/// each switch is named by its title, has the switch role, an on/off value, and a 44×44 pt
/// target (HIG Accessibility, Mobility: "iOS, iPadOS 44×44pt"); each title is a heading; the
/// region passes a scoped `performAccessibilityAudit`. At AX5 the heading's glyphs and the
/// rows grow by `RecognizedText.minimumGrowth` and the heading is drawn whole.
///
/// Needs `tools/mock_service.py` (plain or `--large-catalogue`) at `SongsUITestSupport.fixtureURL`
/// (port 8765, or `FST_FIXTURE_URL`); listed in `apple-ci` `JOURNEYS`.
final class SettingsAccessibilityJourneyTests: XCTestCase {
    // MARK: - Region

    /// What one entry of the region is.
    private enum Kind { case heading, toggle }

    /// One entry of the region, in visual (and reading) order.
    private struct Entry {
        let kind: Kind
        /// The switch's identifier, or the heading's text.
        let key: String
        /// What VoiceOver reads first: the heading text or the switch's title.
        let title: String
    }

    /// Accessibility, then Item Shop (Diagnostics sat between them until #374), closed by the
    /// next section's heading.
    /// 44 pt, less one pixel of tolerance off the pixel grid (as `PathsSwitchAccessibilityJourneyTests`).
    private static let minimumTarget: CGFloat = 43.67

    /// The trailing switch and its spacing, left out of a title's contrast crop.
    private static let switchWidth: CGFloat = 72

    private static let region: [Entry] = [
        Entry(kind: .heading, key: "Accessibility", title: "Accessibility"),
        Entry(kind: .toggle, key: "fst.settings.reduce-motion", title: "Reduce Motion"),
        Entry(kind: .toggle, key: "fst.settings.disable-artwork-animation", title: "Disable Animated Artwork"),
        Entry(kind: .toggle, key: "fst.settings.more-contrast", title: "Increase Contrast"),
        Entry(kind: .toggle, key: "fst.settings.less-transparency", title: "Reduce Transparency"),
        Entry(kind: .heading, key: "Item Shop", title: "Item Shop"),
        Entry(kind: .toggle, key: "fst.settings.hide-shop", title: "Hide Item Shop"),
        Entry(kind: .toggle, key: "fst.settings.shop-highlights", title: "Highlight Shop Items"),
        Entry(kind: .heading, key: "Show Instruments", title: "Show Instruments"),
    ]

    /// The sections' descriptions, which the audit also owns.
    private static let descriptions = [
        "Off follows your device; On adds an app override. VoiceOver and text size are managed in device Settings.",
        "Control how Item Shop availability is displayed.",
    ]

    /// Words the removed section used; nothing on the page or in Quick Links may read them.
    private static let removedWords = ["diagnostic", "tap telemetry", "tap-telemetry"]

    private static let itemPrefix = "fst.quick-links.item."

    /// One region element as read from a snapshot.
    private struct Node {
        let key: String
        let elementType: XCUIElement.ElementType
        let label: String
        let value: String?
        let frame: CGRect
        let isHeading: Bool
        let isEnabled: Bool
    }

    // MARK: - Tests

    /// Default text size: Quick Links lists Accessibility then Item Shop with no Diagnostics
    /// row, and the page region reads in order with named, stateful, 44 pt switches and
    /// heading titles, and passes the scoped audit.
    @MainActor
    func testAccessibilityThenItemShopReadInOrder() throws {
        continueAfterFailure = false
        let app = launchSettings(largeText: false)
        try assertQuickLinksJoin(app, size: "default")
        assertTitleTapToggles(app, id: "fst.settings.reduce-motion", size: "default")
        try auditRegion(app, size: "default")
        _ = try collectRegion(app, size: "default")
        SongsUITestSupport.record(app, name: "settings-a11y-region-default")
    }

    /// Largest accessibility text size: the same order, names, roles, states and targets; the
    /// Accessibility heading is drawn whole with glyphs at least 1.35× their default height,
    /// the switches grow by as much, and the region passes the scoped audit.
    @MainActor
    func testAccessibilityThenItemShopReadableAtAX5() throws {
        continueAfterFailure = false
        let regular = launchSettings(largeText: false)
        try assertQuickLinksJoin(regular, size: "default")
        let smallHeading = headingReading(regular, size: "default")
        let small = try collectRegion(regular, size: "default")
        regular.terminate()

        let app = launchSettings(largeText: true)
        try assertQuickLinksJoin(app, size: "AX5")
        let largeHeading = headingReading(app, size: "AX5")
        assertTitleTapToggles(app, id: "fst.settings.reduce-motion", size: "AX5")
        try auditRegion(app, size: "AX5")
        let large = try collectRegion(app, size: "AX5")
        SongsUITestSupport.record(app, name: "settings-a11y-region-ax5")

        let smallLine = try XCTUnwrap(smallHeading.lineHeight, "No default reading of the Accessibility heading")
        let largeLine = try XCTUnwrap(largeHeading.lineHeight, "No AX5 reading of the Accessibility heading")
        XCTAssertGreaterThanOrEqual(
            largeLine, smallLine * RecognizedText.minimumGrowth,
            "The Accessibility heading did not grow: \(smallLine) → \(largeLine) pt"
        )
        for entry in Self.region where entry.kind == .toggle {
            let before = try XCTUnwrap(small[entry.key]).frame.height
            let after = try XCTUnwrap(large[entry.key]).frame.height
            XCTAssertGreaterThanOrEqual(
                after, before * RecognizedText.minimumGrowth, "\(entry.title) did not grow: \(before) → \(after) pt"
            )
        }
    }

    // MARK: - Launch and Quick Links

    /// Launch Settings against the fixture with no selected profile.
    ///
    /// - Parameter largeText: Launch at the largest accessibility text size (AX5).
    /// - Returns: The launched app, Settings loaded.
    @MainActor
    private func launchSettings(largeText: Bool) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_API_BASE_URL": SongsUITestSupport.fixtureURL,
            "FST_DEBUG_TAB": "settings",
        ])
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
        }
        app.launch()
        XCTAssertTrue(
            app.buttons["fst.quick-links.open"].waitForExistence(timeout: FestivalApp.budget(20)), "Settings did not load"
        )
        return app
    }

    /// Open Quick Links, check Accessibility is directly followed by Item Shop with no
    /// Diagnostics row, both named and at least 44 pt tall, then jump to Accessibility.
    ///
    /// - Parameters:
    ///   - app: Settings, loaded.
    ///   - size: Label for failure messages.
    @MainActor
    private func assertQuickLinksJoin(
        _ app: XCUIApplication, size: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let open = app.buttons["fst.quick-links.open"]
        XCTAssertEqual(open.label, "Quick Links", file: file, line: line)
        XCTAssertGreaterThanOrEqual(open.frame.width, 44, "Quick Links width at \(size)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(open.frame.height, 44, "Quick Links height at \(size)", file: file, line: line)
        open.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.itemPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)), "Quick Links did not open",
                      file: file, line: line)
        let all = rows.allElementsBoundByIndex.map { (id: String($0.identifier.dropFirst(Self.itemPrefix.count)),
                                                      label: $0.label, frame: $0.frame) }
        XCTAssertFalse(
            all.contains { row in Self.removedWords.contains { row.id.lowercased().contains($0) || row.label.lowercased().contains($0) } },
            "Quick Links offers the removed Diagnostics section at \(size): \(all.map(\.id))", file: file, line: line
        )
        let screen = app.windows.firstMatch.frame
        let visible = all.filter { screen.contains($0.frame) }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(
            Array(visible.prefix(3).map(\.id)), ["app-settings", "accessibility", "item-shop"],
            "Accessibility is not directly followed by Item Shop at \(size): \(visible.map(\.id))", file: file, line: line
        )
        for row in visible.prefix(3) {
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(row.id) row height at \(size)", file: file, line: line)
        }
        XCTAssertEqual(visible.dropFirst().first?.label, "Accessibility", file: file, line: line)
        XCTAssertEqual(visible.dropFirst(2).first?.label, "Item Shop", file: file, line: line)

        app.buttons[Self.itemPrefix + "accessibility"].tap()
        let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Accessibility"), object: open)
        XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: FestivalApp.budget(10)), .completed,
                       "Quick Links did not land on Accessibility at \(size)", file: file, line: line)
        // Let the jump settle before measuring.
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1)))
    }

    /// Vision's reading of the on-screen Accessibility heading.
    @MainActor
    private func headingReading(_ app: XCUIApplication, size: String) -> RecognizedText.Reading {
        let heading = app.staticTexts.matching(NSPredicate(format: "label == %@", "Accessibility"))
            .allElementsBoundByIndex.first { $0.isHittable }
        guard let heading else {
            XCTFail("The Accessibility heading is not on screen at \(size)")
            return RecognizedText.Reading(text: nil, lineHeight: nil)
        }
        let reading = RecognizedText.recognize(heading, label: "Accessibility", frame: heading.frame)
        XCTAssertTrue(
            RecognizedText.showsWhole("Accessibility", in: reading.text),
            "The Accessibility heading is not drawn whole at \(size): '\(reading.text ?? "nothing")'"
        )
        return reading
    }

    // MARK: - Touch target

    /// The whole row is the switch's touch target, like the web `ToggleRow`: a tap on the
    /// row's title, away from the switch, flips it, and a tap on the switch itself flips it
    /// back exactly once (the row's tap never doubles the switch's own).
    ///
    /// - Parameters:
    ///   - app: Settings with the row on screen.
    ///   - id: The switch's identifier.
    ///   - size: Label for failure messages.
    @MainActor
    private func assertTitleTapToggles(
        _ app: XCUIApplication, id: String, size: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        // Quick Links has just landed Accessibility at the top, with this switch under it.
        let toggle = app.switches[id]
        XCTAssertTrue(toggle.isHittable, "\(id) is not on screen after the landing at \(size)", file: file, line: line)
        let original = toggle.value as? String ?? ""
        // The switch's own tap lands on the track the thumb leaves bare, never on the thumb
        // (#626, #659), so its point is read after the title tap has moved the thumb.
        let steps: [(place: String, target: () -> XCUICoordinate, expected: String)] = [
            ("title", { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)) }, original == "1" ? "0" : "1"),
            ("switch", { SongsUITestSupport.switchBareTrack(of: toggle) }, original),
        ]
        for step in steps {
            step.target().tap()
            let flipped = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", step.expected), object: toggle
            )
            let result = XCTWaiter.wait(for: [flipped], timeout: FestivalApp.budget(3))
            if result != .completed {
                SongsUITestSupport.record(app, name: "settings-missed-\(step.place)-tap-\(size)")
            }
            XCTAssertEqual(
                result, .completed,
                "A tap on \(id)'s \(step.place) did not flip it once at \(size) (frame \(toggle.frame))",
                file: file, line: line
            )
            // Exactly once: a late second flip (the row's tap doubling the switch's) fails too.
            Thread.sleep(forTimeInterval: 0.5)
            XCTAssertEqual(
                toggle.value as? String, step.expected,
                "A tap on \(id)'s \(step.place) flipped it more than once at \(size)", file: file, line: line
            )
        }
    }

    // MARK: - Reading order

    /// Walk the region from the Accessibility heading down to Show Instruments with short
    /// drags, merging each snapshot's region elements in reading order, and check order,
    /// names, roles, states and targets, with nothing from the removed section in between.
    ///
    /// - Parameters:
    ///   - app: Settings, Accessibility landed at the top.
    ///   - size: Label for failure messages.
    /// - Returns: The first reading of each region element, by key.
    @MainActor
    private func collectRegion(_ app: XCUIApplication, size: String) throws -> [String: Node] {
        var order: [String] = []
        var seen: [String: Node] = [:]
        let window = app.windows.firstMatch
        for _ in 0..<16 {
            let (nodes, removed) = try regionNodes(app)
            XCTAssertEqual(removed, [], "The removed Diagnostics section reads at \(size)")
            let indices = nodes.compactMap { node in Self.region.firstIndex { $0.key == node.key } }
            XCTAssertEqual(indices, indices.sorted(), "Out of order at \(size): \(nodes.map(\.key))")
            for node in nodes where seen[node.key] == nil {
                seen[node.key] = node
                order.append(node.key)
            }
            if seen["Show Instruments"] != nil { break }
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(
                forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            )
        }
        XCTContext.runActivity(named: "Region at \(size): \(order.map { seen[$0].map { "\($0.key) '\($0.label)' \($0.frame)" } ?? $0 })") { _ in }
        XCTAssertEqual(order, Self.region.map(\.key), "Region reading order at \(size)")

        for entry in Self.region {
            let node = try XCTUnwrap(seen[entry.key], "\(entry.key) never read at \(size)")
            switch entry.kind {
            case .heading:
                XCTAssertTrue(node.isHeading, "'\(entry.title)' is not a heading at \(size)")
            case .toggle:
                XCTAssertEqual(node.elementType, .switch, "\(entry.key) is not a switch at \(size)")
                XCTAssertTrue(node.label.hasPrefix(entry.title), "\(entry.key) reads '\(node.label)' at \(size)")
                XCTAssertTrue(["0", "1"].contains(node.value ?? ""), "\(entry.key) has no on/off value at \(size): \(String(describing: node.value))")
                XCTAssertGreaterThanOrEqual(node.frame.height, Self.minimumTarget, "\(entry.key) target height at \(size)")
                XCTAssertGreaterThanOrEqual(node.frame.width, Self.minimumTarget, "\(entry.key) target width at \(size)")
            }
        }
        // Highlight Shop Items is disabled exactly while the Item Shop is hidden.
        let hidden = seen["fst.settings.hide-shop"]?.value == "1"
        XCTAssertEqual(seen["fst.settings.shop-highlights"]?.isEnabled, !hidden,
                       "Highlight Shop Items enabled state does not follow Hide Item Shop at \(size)")
        return seen
    }

    /// The region's headings and switches in snapshot (reading) order, without descending into
    /// buttons or switches (VoiceOver reads each as one element), plus any element that reads
    /// the removed section's words.
    @MainActor
    private func regionNodes(_ app: XCUIApplication) throws -> (nodes: [Node], removed: [String]) {
        let headings = Set(Self.region.filter { $0.kind == .heading }.map(\.key))
        let toggles = Set(Self.region.filter { $0.kind == .toggle }.map(\.key))
        var nodes: [Node] = []
        var removed: [String] = []
        func walk(_ node: XCUIElementSnapshot) {
            let text = (node.identifier + " " + node.label).lowercased()
            if Self.removedWords.contains(where: text.contains) {
                removed.append("\(node.elementType.rawValue) \(node.identifier) '\(node.label)'")
            }
            if node.elementType == .switch, toggles.contains(node.identifier) {
                nodes.append(Node(key: node.identifier, elementType: node.elementType, label: node.label,
                                  value: node.value as? String, frame: node.frame, isHeading: false,
                                  isEnabled: node.isEnabled))
                return
            }
            if node.elementType == .staticText, headings.contains(node.label) {
                let isHeading = Self.traits(node).map { $0 & UIAccessibilityTraits.header.rawValue != 0 } ?? true
                if isHeading {
                    nodes.append(Node(key: node.label, elementType: node.elementType, label: node.label,
                                      value: nil, frame: node.frame, isHeading: true, isEnabled: node.isEnabled))
                }
            }
            if [.button, .switch, .tabBar].contains(node.elementType) { return }
            node.children.forEach(walk)
        }
        walk(try app.snapshot())
        return (nodes, removed)
    }

    /// The snapshot's accessibility traits, when readable (as `NotificationsAccessibilityJourneyTests`).
    @MainActor
    private static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
    }

    // MARK: - Audit

    /// Audit the screen with Accessibility landed at the top and fail on any issue in the
    /// region's own elements (its headings, descriptions and switches).
    ///
    /// The audit can flag region text over the glass card's artwork backdrop, or text it
    /// reads under the tab bar and Quick Links accessory. A contrast flag on a region title,
    /// heading or description is accepted only once that text, scrolled clear of the bottom
    /// chrome, measures at least 4.5:1 rendered (testing/apple/accessibility.md
    /// `contrast-rendered`; precedent `PathsSwitchAccessibilityJourneyTests`); a weaker
    /// reading, or any other issue, fails the test.
    ///
    /// - Parameters:
    ///   - app: Settings, Accessibility landed at the top.
    ///   - size: Label for failure messages.
    @MainActor
    private func auditRegion(_ app: XCUIApplication, size: String) throws {
        let ids = Set(Self.region.filter { $0.kind == .toggle }.map(\.key))
        let labels = Set(Self.region.map(\.title) + Self.descriptions)
        var issues: [String] = []
        var flagged: [(element: XCUIElement, leadingTextWidth: CGFloat?, name: String)] = []
        try app.performAccessibilityAudit(for: .all) { issue in
            let id = issue.element?.identifier ?? ""
            let label = issue.element?.label ?? ""
            let toggle = Self.region.first { $0.kind == .toggle && ($0.key == id || label.hasPrefix($0.title)) }
            guard toggle != nil || ids.contains(id) || labels.contains(label) else { return true }
            guard issue.auditType == .contrast else {
                issues.append("\(id) '\(label)': \(issue.compactDescription)")
                return true
            }
            if let toggle {
                let element = app.switches[toggle.key]
                flagged.append((element, max(element.frame.width - Self.switchWidth, 44), toggle.key))
            } else {
                let element = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
                flagged.append((element, nil, "'\(label)'"))
            }
            return true
        }
        XCTAssertEqual(issues, [], "Settings region audit issues at \(size)")
        guard !flagged.isEmpty else { return }
        for entry in flagged {
            SongsUITestSupport.reveal(entry.element, in: app, scrollingUp: true)
            try SongsUITestSupport.assertHeaderContrast(entry.element, in: app, leadingTextWidth: entry.leadingTextWidth)
        }
        XCTContext.runActivity(named: "Contrast measured ≥ 4.5:1 at \(size): \(flagged.map(\.name))") { _ in }
        // Hand the region back to the reading-order walk with its heading on screen.
        let heading = app.staticTexts.matching(NSPredicate(format: "label == %@", "Accessibility")).firstMatch
        SongsUITestSupport.reveal(heading, in: app, scrollingUp: false)
    }
}
