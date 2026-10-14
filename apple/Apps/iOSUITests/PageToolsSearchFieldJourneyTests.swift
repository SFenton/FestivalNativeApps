import XCTest

/// Accessibility of the page tools #89 moved out of the search bar (#442, for #89).
///
/// #89 reported Sort and Filter drawn inside the Songs search capsule and a lone Quick
/// Links stretched into a full-width text capsule. Since #92/#300 the tools are separate
/// icon-only buttons: in the floating page tools on iPhone (`FloatingPageToolsBar`) and in
/// the navigation bar on iPhone Duo and iPad (`SongsPageTools`), while Songs' text filter
/// is its own "Filter Songs" field (the system navigation-bar drawer, or
/// `BottomSearchField` at the bottom of the Duo page). These journeys measure the production
/// chrome, which the hosted `NavButtonAccessibilityTests` cannot reproduce:
///
/// - each tool is one named button (Quick Links with its current section), never part of
///   the field: not inside it in the accessibility hierarchy, not overlapping it, and read
///   before or after it, never in the middle;
/// - the tools read in their drawn order, each a 44 × 44 pt target (HIG Buttons: "the
///   hit region is at least 44x44 pt"; a navigation-bar item's 36 pt element gets its
///   44 pt region from the bar, proven by the audit), Quick Links one round icon button
///   rather than a wide capsule;
/// - at the largest accessibility text size the same holds, with Sort and Filter still
///   separate buttons (iPhone's fixed 44 pt floating circles fold only on a too-narrow
///   window since #632, `FloatingPageToolsFit`; the Duo's navigation bar keeps them
///   separate);
/// - the system audit (hit region, description, Dynamic Type, clipping) reports nothing
///   on the tools or the field;
/// - on iPad with a hardware keyboard, keyboard focus rests in the tools' navigation bar,
///   the tools sit in its focus group in drawn order before the field, and ⌥⌘↓ / ⌥⌘↑
///   operate Quick Links.
///
/// Runs against `tools/mock_service.py --large-catalogue` (Songs' Year sort needs several
/// years for Quick Links), read from `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL` or the
/// default port. iPhone and the simulated folded iPhone Duo window (default and AX5) run on
/// the CI iPhone, the iPad forms on the CI iPad, the keyboard form in its own
/// `--a11y full-keyboard-access` run (`apple-ci` journeys).
final class PageToolsSearchFieldJourneyTests: XCTestCase {
    /// One page tool: its identifier and the name VoiceOver reads.
    private struct Tool {
        let id: String
        let label: String
    }

    private static let sort = Tool(id: "fst.songs.sort", label: "Sort")
    private static let filter = Tool(id: "fst.songs.filter", label: "Filter Songs")
    private static let quickLinks = Tool(id: "fst.quick-links.open", label: "Quick Links")

    // MARK: - Songs

    /// Songs (Year sort) at the default text size: Sort, Filter Songs and Quick Links are
    /// separate buttons apart from the Filter Songs field.
    @MainActor
    func testSongsToolsSitApartFromTheFilterField() throws {
        continueAfterFailure = false
        let app = try launchSongs(typeSize: nil, duoWindow: nil)
        defer { app.terminate() }
        try assertToolsApartFromField(
            in: app, tools: [Self.sort, Self.filter, Self.quickLinks], name: "songs-default"
        )
    }

    /// Songs (Year sort) at the largest accessibility text size: Sort, Filter Songs and
    /// Quick Links stay separate buttons (the iPhone's floating circles do not grow, so
    /// they no longer fold, #632); none joins the field.
    @MainActor
    func testSongsToolsSitApartFromTheFilterFieldAtAX5() throws {
        continueAfterFailure = false
        let app = try launchSongs(typeSize: Self.ax5, duoWindow: nil)
        defer { app.terminate() }
        try assertToolsApartFromField(
            in: app, tools: [Self.sort, Self.filter, Self.quickLinks], name: "songs-ax5"
        )
    }

    /// iPhone Duo folded (field at the bottom of the page): the tools are navigation-bar
    /// buttons apart from the bottom Filter Songs field.
    @MainActor
    func testSongsToolsSitApartFromTheFilterFieldDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        continueAfterFailure = false
        let app = try launchSongs(typeSize: nil, duoWindow: "folded")
        defer { app.terminate() }
        try assertToolsApartFromField(
            in: app, tools: [Self.sort, Self.filter, Self.quickLinks], name: "songs-duo-folded"
        )
    }

    /// iPhone Duo folded at the largest accessibility text size: the Duo keeps Sort,
    /// Filter Songs and Quick Links as separate navigation-bar buttons, apart from the bottom Filter Songs field.
    @MainActor
    func testSongsToolsSitApartFromTheFilterFieldAtAX5DuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        continueAfterFailure = false
        let app = try launchSongs(typeSize: Self.ax5, duoWindow: "folded")
        defer { app.terminate() }
        try assertToolsApartFromField(
            in: app, tools: [Self.sort, Self.filter, Self.quickLinks], name: "songs-ax5-duo-folded"
        )
    }

    // MARK: - Leaderboards (Quick Links alone)

    /// Leaderboards, the page #89 showed with a full-width Quick Links capsule: Quick
    /// Links is its only tool, one round named icon button, at the default and the
    /// largest accessibility text size.
    @MainActor
    func testLeaderboardsQuickLinksIsOneIconButton() throws {
        try assertLeaderboardsQuickLinks(duoWindow: nil)
    }

    /// The same on the folded iPhone Duo, where Quick Links is a navigation-bar button
    /// rather than a floating page tool.
    @MainActor
    func testLeaderboardsQuickLinksIsOneIconButtonDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertLeaderboardsQuickLinks(duoWindow: "folded")
    }

    /// Leaderboards at the default and AX5 text sizes: Quick Links is the page's only
    /// tool, one round named icon button.
    ///
    /// - Parameter duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    @MainActor
    private func assertLeaderboardsQuickLinks(duoWindow: String?) throws {
        continueAfterFailure = false
        for typeSize in [nil, Self.ax5] {
            let app = launch(["FST_DEBUG_TAB": "leaderboards"], typeSize: typeSize, duoWindow: duoWindow)
            let open = app.buttons[Self.quickLinks.id]
            guard open.waitForExistence(timeout: FestivalApp.budget(20)) else {
                app.terminate()
                throw XCTSkip("Leaderboards never offered Quick Links; run tools/mock_service.py on \(Self.fixtureURL).")
            }
            try assertToolsApartFromField(
                in: app, tools: [Self.quickLinks], field: false,
                name: "leaderboards-\(typeSize == nil ? "default" : "ax5")\(duoWindow.map { "-duo-\($0)" } ?? "")"
            )
            app.terminate()
        }
    }

    // MARK: - Keyboard (iPad)

    /// iPad with a hardware keyboard (`ios_sim.py uitest --a11y full-keyboard-access`):
    /// UIKit's keyboard focus rests in the navigation bar that holds Sort, Filter Songs
    /// and Quick Links, the tools sit in that bar's focus group in drawn order with the
    /// Filter Songs field after them, and the keyboard operates Quick Links through Go ›
    /// Next / Previous Section (⌥⌘↓ / ⌥⌘↑).
    ///
    /// Needs the setting for a focus stop (the board's keyboard journey finds none without
    /// it, #473). XCUITest's Tab, arrows and Space never move or activate the simulator's
    /// keyboard focus (#461, #473, re-checked for #442), so Full Keyboard Access traversal
    /// itself stays an operator check (`.agents/design/apple/ipados.md`).
    @MainActor
    func testPageToolsAreInTheKeyboardFocusGroupAndOperable() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "The hardware-keyboard journey runs on iPad")
        continueAfterFailure = false
        let app = try launchSongs(typeSize: nil, duoWindow: nil)
        defer { app.terminate() }
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true"))
        let stop = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: focused)
        XCTAssertEqual(XCTWaiter.wait(for: [stop], timeout: FestivalApp.budget(10)), .completed,
                       "No hardware-keyboard focus stop; run with --a11y full-keyboard-access")

        let entries = try accessibilityWalk(app)
        let tools = [Self.sort, Self.filter, Self.quickLinks]
        var indices: [Int] = []
        for tool in tools {
            let index = try XCTUnwrap(entries.indices.first { entries[$0].node.identifier == tool.id }, "\(tool.id) missing")
            XCTAssertEqual(entries[index].node.elementType, .button, "\(tool.id) role")
            XCTAssertTrue(entries[index].node.isEnabled, "\(tool.id) disabled")
            indices.append(index)
        }
        let bars = entries.indices.filter { entries[$0].node.elementType == .navigationBar }
        let bar = try XCTUnwrap(bars.first { bar in indices.allSatisfy { bar < $0 && $0 < entries[bar].end } },
                                "Sort, Filter Songs and Quick Links are not in one navigation bar")
        XCTAssertEqual(indices, indices.sorted(), "the tools' focus order is not their drawn order")
        let focusedNode = try XCTUnwrap(entries.indices.first { entries[$0].node.hasFocus }, "focus left the hierarchy")
        XCTAssertTrue(bar < focusedNode && focusedNode < entries[bar].end,
                      "keyboard focus \(entries[focusedNode].node.identifier) is outside the tools' navigation bar")
        if let field = entries.indices.first(where: { entries[$0].node.elementType == .searchField }),
           bar < field, field < entries[bar].end {
            XCTAssertGreaterThan(field, indices.last ?? field, "the Filter Songs field is focused before the tools")
        }

        // Keyboard operation: Next Section moves Quick Links on; Previous Section returns.
        let open = app.buttons[Self.quickLinks.id]
        // The section is the value, or in a system bar joined to the label (R26).
        let spoken = { "\(open.label)|\((open.value as? String) ?? "")" }
        let first = spoken()
        XCTAssertNotEqual(first, "\(Self.quickLinks.label)|", "Quick Links reads no current section")
        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [.option, .command])
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in spoken() != first }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: FestivalApp.budget(10)), .completed,
                       "⌥⌘↓ left Quick Links on \(first)")
        app.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: [.option, .command])
        let back = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in spoken() == first }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: FestivalApp.budget(10)), .completed,
                       "⌥⌘↑ did not return Quick Links to \(first): \(spoken())")
    }

    // MARK: - Launch

    /// `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`.
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    /// The large-catalogue fixture service's origin.
    private static var fixtureURL: String {
        ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
    }

    /// Launch Songs in the Year sort, whose sections bring Quick Links, with no selected
    /// player.
    ///
    /// - Parameters:
    ///   - typeSize: A `UIContentSizeCategory` raw value, or nil for the default.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Returns: The launched app, with Quick Links offered.
    /// - Throws: A skip when the fixture has a single year (Quick Links stays hidden).
    @MainActor
    private func launchSongs(typeSize: String?, duoWindow: String?) throws -> XCUIApplication {
        // The argument domain sets the sort for this launch only; nothing persists.
        let app = launch(
            [:], arguments: ["-fst.songs.sortMode", "year", "-fst.songs.sortAscending", "YES"],
            typeSize: typeSize, duoWindow: duoWindow
        )
        guard app.buttons[Self.quickLinks.id].waitForExistence(timeout: FestivalApp.budget(20)) else {
            app.terminate()
            throw XCTSkip("Songs' Year sort offered no Quick Links; use mock_service.py --large-catalogue.")
        }
        return app
    }

    /// Launch the app against the fixture with no selected player, waiting for a
    /// simulated Duo window when one is asked for.
    ///
    /// - Parameters:
    ///   - extra: Launch environment on top of the fixture origin and cleared profile.
    ///   - arguments: Extra launch arguments.
    ///   - typeSize: A `UIContentSizeCategory` raw value, or nil for the default.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Returns: The launched app.
    @MainActor
    private func launch(
        _ extra: [String: String], arguments: [String] = [], typeSize: String?, duoWindow: String?
    ) -> XCUIApplication {
        var environment = ["FST_API_BASE_URL": Self.fixtureURL, "FST_UI_TEST_CLEAR_PROFILE": "1"]
        environment.merge(extra) { _, new in new }
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        }
        let app = FestivalApp.makeApp(environment)
        app.launchArguments += arguments
        if let typeSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", typeSize] }
        app.launch()
        if let duoWindow {
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "\(duoWindow) "), object: readout
            )
            XCTAssertEqual(XCTWaiter.wait(for: [reached], timeout: FestivalApp.budget(15)), .completed,
                           "the app never simulated \(duoWindow): \(readout.exists ? readout.label : "no readout")")
        }
        return app
    }

    // MARK: - Assertions

    /// One node of a depth-first walk of the app's accessibility snapshot.
    private struct AXEntry {
        let node: XCUIElementSnapshot
        /// Index one past this node's last descendant.
        var end: Int
    }

    /// The app's accessibility hierarchy in depth-first order, the order VoiceOver
    /// swipes through (`NavButtonHitRegionJourneyTests`, #394).
    @MainActor
    private func accessibilityWalk(_ app: XCUIApplication) throws -> [AXEntry] {
        var entries: [AXEntry] = []
        func walk(_ node: XCUIElementSnapshot) {
            let index = entries.count
            entries.append(AXEntry(node: node, end: index + 1))
            node.children.forEach(walk)
            entries[index].end = entries.count
        }
        walk(try app.snapshot())
        return entries
    }

    /// Require `tools` to be separate, named, 44 pt buttons read in drawn order and, with
    /// `field`, apart from the Filter Songs field; then audit them.
    ///
    /// - Parameters:
    ///   - app: The running app, settled on the page.
    ///   - tools: The page's tools in reading order.
    ///   - field: Whether the page has the Filter Songs field.
    ///   - name: Attachment name for the hierarchy dump and screenshot.
    @MainActor
    private func assertToolsApartFromField(
        in app: XCUIApplication, tools: [Tool], field: Bool = true, name: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for tool in tools {
            let button = app.buttons[tool.id]
            XCTAssertTrue(button.waitForExistence(timeout: FestivalApp.budget(10)), "\(tool.id) missing",
                          file: file, line: line)
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: FestivalApp.budget(5)), .completed,
                           "\(tool.id) not hittable", file: file, line: line)
        }
        let entries = try accessibilityWalk(app)
        func ancestors(of index: Int) -> [Int] {
            entries.indices.filter { $0 < index && index < entries[$0].end }
        }
        func describe(_ index: Int) -> String {
            let node = entries[index].node
            return "\(index) \(node.elementType.rawValue) id='\(node.identifier)' label='\(node.label)'"
                + " value='\((node.value as? String) ?? "")' \(node.frame)"
        }
        let dump = entries.indices.filter { index in
            let node = entries[index].node
            return ([.navigationBar, .tabBar, .toolbar, .button, .searchField, .textField] as [XCUIElement.ElementType])
                .contains(node.elementType) || node.identifier.hasPrefix("fst.page-tools")
        }.map(describe)
        let attachment = XCTAttachment(string: dump.joined(separator: "\n"))
        attachment.name = "page-tools-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "page-tools-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
        let context = dump.joined(separator: "\n")

        // Each tool: exactly one named button with a 44 pt target.
        var indices: [Int] = []
        for tool in tools {
            let matches = entries.indices.filter { entries[$0].node.identifier == tool.id }
            XCTAssertEqual(matches.count, 1, "\(tool.id) elements \(matches)\n\(context)", file: file, line: line)
            let index = try XCTUnwrap(matches.first, file: file, line: line)
            let node = entries[index].node
            XCTAssertEqual(node.elementType, .button, "\(tool.id) role", file: file, line: line)
            let inBar = ancestors(of: index).contains { entries[$0].node.elementType == .navigationBar }
            // A system navigation bar drops a toolbar item's value, so there the tool's
            // state joins its name ("Sort, Year, ascending"; page-tools-and-nav-chrome R26,
            // `BarItemSpokenState`); the floating tools keep the bare name.
            let named = node.label == tool.label || (inBar && node.label.hasPrefix("\(tool.label), "))
            XCTAssertTrue(named, "\(tool.id) name '\(node.label)'", file: file, line: line)
            // A navigation-bar item's element is the system's 36 pt glass shape and the
            // bar extends its hit region to 44 pt, so the `.hitRegion` audit below proves
            // it (same as Choose Profile, `NavButtonHitRegionJourneyTests`); the
            // floating tools' own circles are 44 pt elements.
            let minimum: CGFloat = inBar ? 36 : 44
            XCTAssertGreaterThanOrEqual(node.frame.width, minimum, "\(tool.id) \(node.frame)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(node.frame.height, minimum, "\(tool.id) \(node.frame)", file: file, line: line)
            XCTAssertFalse(ancestors(of: index).contains { entries[$0].node.elementType == .button },
                           "\(tool.id) is inside another button\n\(context)", file: file, line: line)
            indices.append(index)
        }
        if let open = tools.firstIndex(where: { $0.id == Self.quickLinks.id }) {
            let node = entries[indices[open]].node
            // #89: an icon-only button, not a capsule wide enough to hold its title
            // (about 110 pt with its glyph at the default size). A system bar group
            // pads its items more at larger text (55 pt on iPad at AX5), so allow 72.
            XCTAssertLessThanOrEqual(node.frame.width, 72,
                                     "Quick Links is wider than one icon button: \(node.frame)", file: file, line: line)
            // The current section is its value, or in a system bar joined to its name (R26).
            let section = (node.value as? String) ?? ""
            XCTAssertTrue(!section.isEmpty || node.label.hasPrefix("\(Self.quickLinks.label), "),
                          "Quick Links reads no current section: '\(node.label)' / '\(section)'",
                          file: file, line: line)
        }
        // Read in drawn order: left to right in a horizontal bar, top to bottom in the
        // Duo vertical bar.
        XCTAssertEqual(indices, indices.sorted(), "tools read out of order\n\(context)", file: file, line: line)
        let frames = indices.map { entries[$0].node.frame }
        for (first, second) in zip(frames, frames.dropFirst()) {
            XCTAssertFalse(first.insetBy(dx: 0.5, dy: 0.5).intersects(second), "tools overlap: \(first) \(second)",
                           file: file, line: line)
            XCTAssertTrue(first.maxX <= second.minX + 0.5 || first.maxY <= second.minY + 0.5,
                          "\(first) is not before \(second)", file: file, line: line)
        }

        var audited = Set(tools.map(\.id))
        if field {
            let fields = entries.indices.filter { index in
                let node = entries[index].node
                return node.elementType == .searchField || node.identifier == "fst.songs.filter-field"
            }
            XCTAssertEqual(fields.count, 1, "Filter Songs fields \(fields)\n\(context)", file: file, line: line)
            let fieldIndex = try XCTUnwrap(fields.first, file: file, line: line)
            let fieldNode = entries[fieldIndex].node
            XCTAssertTrue(
                [fieldNode.label, fieldNode.placeholderValue ?? ""].contains("Filter Songs"),
                "field name '\(fieldNode.label)' / '\(fieldNode.placeholderValue ?? "")'", file: file, line: line
            )
            for (tool, index) in zip(tools, indices) {
                XCTAssertFalse(fieldIndex < index && index < entries[fieldIndex].end,
                               "\(tool.id) is inside the Filter Songs field\n\(context)", file: file, line: line)
                XCTAssertFalse(entries[index].node.frame.intersects(fieldNode.frame),
                               "\(tool.id) \(entries[index].node.frame) overlaps the field \(fieldNode.frame)",
                               file: file, line: line)
            }
            // The field reads before or after the tools, never between two of them.
            let first = try XCTUnwrap(indices.first, file: file, line: line)
            let last = try XCTUnwrap(indices.last, file: file, line: line)
            XCTAssertFalse(first < fieldIndex && fieldIndex < last, "the field reads between the tools\n\(context)",
                           file: file, line: line)
            if !fieldNode.identifier.isEmpty { audited.insert(fieldNode.identifier) }
        }

        let types: XCUIAccessibilityAuditType = [.hitRegion, .sufficientElementDescription, .dynamicType, .textClipped]
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            // Only the tools and the field; other regions have their own journeys.
            guard let element = issue.element else { return true }
            if audited.contains(element.identifier) { return false }
            if field, element.elementType == .searchField { return false }
            return true
        }
        do {
            try app.performAccessibilityAudit(for: types, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            // A long page can exceed XCTest's audit deadline on a slow host (#388): retry once.
            XCTContext.runActivity(named: "Audit \(name) did not complete in time; retrying once") { _ in }
            try app.performAccessibilityAudit(for: types, handler)
        }
    }
}
