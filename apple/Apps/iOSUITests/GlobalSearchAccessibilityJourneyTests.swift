import UIKit
import XCTest

// MARK: - Search title at AX5 (issue #100, backfilled by #450)

/// The Search page keeps its "Search" navigation title while its field is active (#100:
/// choosing the Search tab activates `.searchable`, which hid the navigation bar and its
/// title; `GlobalSearchTab` keeps it with `searchPresentationToolbarBehavior`). This is
/// the accessibility evidence for that region on a real navigation stack with real
/// Dynamic Type, in every iOS form the page has:
///
/// - iPhone: the trailing Search tab, field focused and keyboard up;
/// - iPhone Duo (folded, the vertical tab bar): simulated in the real window
///   (`FST_DEBUG_DUO_WINDOW`), so `apple-ci` can run it on its iPhone;
/// - iPad: the sidebar's Search page (field left unfocused, HIG Search fields).
///
/// At AX5, with the field active and again with results shown, the title must:
/// - be the navigation bar's static text named "Search", on screen at the top of the page,
///   and read before the scope bar and results (VoiceOver announces the page title first);
/// - grow (> 1.35× its default-size line height) and render whole, never "Sea…";
/// - pass a scoped audit (Dynamic Type, clipped text, description, contrast) together with
///   the field and Close, which stay named and reachable (Close ≥ 44 pt).
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_SEARCH_A11Y_FIXTURE_URL` for another mock). `apple-ci` runs it on its
/// iPhone and iPad simulators (`testing/apple/xcuitest.md#ci-journeys`). macOS has no Search
/// tab; `FestivalUITests/GlobalSearchSheetAccessibilityTests` covers its Search sheet.
///
/// HIG VoiceOver: "Give each page or screen a unique, succinct title describing its content
/// and purpose"; HIG Typography: "Keep text truncation to a minimum as font size increases";
/// HIG Accessibility: "Strive for the platform's recommended minimum control size" (44×44 pt).
final class GlobalSearchAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_SEARCH_A11Y_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// The system field's prompt for the All scope (`GlobalSearch.prompt(for:)`).
    private static let prompt = "Search songs, players, or bands"

    // MARK: - Journeys

    /// iPhone Search tab or iPad sidebar Search page at AX5.
    @MainActor
    func testSearchTitleStaysReadableAtAX5() throws {
        try assertSearchTitleAtAX5(duoWindow: nil)
    }

    /// The Search tab beside the iPhone Duo's folded vertical tab bar at AX5.
    @MainActor
    func testSearchTitleStaysReadableAtAX5DuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertSearchTitleAtAX5(duoWindow: "folded")
    }

    // MARK: - Assertions

    /// Compare the default size with AX5, then check name, order, scaling, targets and the
    /// audit with the field active, and again once results show.
    ///
    /// - Parameter duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    @MainActor
    private func assertSearchTitleAtAX5(duoWindow: String?) throws {
        continueAfterFailure = false
        let standard = try launchSearch(size: nil, duoWindow: duoWindow)
        let standardTitle = try searchTitle(in: standard)
        let standardReading = RecognizedText.recognize(standardTitle, label: "Search", frame: standardTitle.frame)
        let standardHeight = try XCTUnwrap(standardReading.lineHeight, "default-size title measured: \(standardReading)")
        standard.terminate()

        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        let app = try launchSearch(size: ax5, duoWindow: duoWindow)
        try assertTitle(in: app, growsFrom: standardHeight, state: "field active")

        // With results on screen the title stays the page's first, whole, grown text.
        let field = app.searchFields[Self.prompt]
        if !Self.isPhone { field.tap() }
        field.typeText("Fixture")
        let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.global-search.result."))
            .firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: FestivalApp.budget(15)), "Search results arrive")
        try assertTitle(in: app, growsFrom: standardHeight, state: "results shown", result: result)
    }

    /// The title's name, place, reading order, size and audit, and the field and Close beside it.
    ///
    /// - Parameters:
    ///   - app: The app on the Search page at AX5.
    ///   - standardHeight: The title's line height at the default size.
    ///   - state: Name of the page state, for messages.
    ///   - result: A result row on screen, which must read after the title.
    @MainActor
    private func assertTitle(in app: XCUIApplication, growsFrom standardHeight: CGFloat, state: String,
                             result: XCUIElement? = nil) throws {
        let title = try searchTitle(in: app)
        let window = app.windows.firstMatch.frame
        let frame = title.frame
        record(app, name: "search-title-ax5-\(state)")

        // Name and role: the navigation bar's title text, on screen at the top of the page.
        XCTAssertEqual(title.elementType, .staticText, state)
        XCTAssertEqual(title.label, "Search", state)
        XCTAssertTrue(title.isHittable, "\(state): the Search title is hidden")
        XCTAssertTrue(window.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(state): title \(frame) leaves \(window)")
        XCTAssertLessThan(frame.minY, window.minY + window.height / 3, "\(state): title \(frame) is not at the top")

        // Reading order: the title is read before the scope bar and the results.
        let scope = app.segmentedControls["fst.global-search.scope"]
        XCTAssertTrue(scope.waitForExistence(timeout: FestivalApp.budget(5)), "\(state): scope bar")
        XCTAssertLessThanOrEqual(frame.maxY, scope.frame.minY + 1, "\(state): title above the scope bar")
        let order = try readingOrder(of: app)
        let titleIndex = try XCTUnwrap(order.firstIndex { $0.type == .staticText && $0.label == "Search" },
                                       "\(state): title in the tree \(order)")
        let scopeIndex = try XCTUnwrap(order.firstIndex { $0.identifier == "fst.global-search.scope" },
                                       "\(state): scope bar in the tree")
        XCTAssertLessThan(titleIndex, scopeIndex, "\(state): title read before the scope bar")
        if let result {
            let resultIndex = try XCTUnwrap(order.firstIndex { $0.identifier == result.identifier },
                                            "\(state): result in the tree")
            XCTAssertLessThan(titleIndex, resultIndex, "\(state): title read before the results")
        }

        // Text scaling: the title grows and renders whole.
        let reading = RecognizedText.recognize(title, label: "Search", frame: frame)
        XCTContext.runActivity(named: "\(state): recognized '\(reading.text ?? "")' \(reading.lineHeight ?? 0) pt") { _ in }
        XCTAssertTrue(RecognizedText.showsWhole("Search", in: reading.text), "\(state): title whole: \(reading.text ?? "nil")")
        let height = try XCTUnwrap(reading.lineHeight, "\(state): title measured")
        XCTAssertGreaterThan(height, standardHeight * RecognizedText.minimumGrowth,
                             "\(state): title grows at AX5: \(height) pt vs \(standardHeight) pt")

        // The field (and the phone tab's Close) stay named and reachable beside the title.
        let field = app.searchFields[Self.prompt]
        XCTAssertTrue(field.exists && field.isHittable, "\(state): search field reachable")
        var scoped: Set<String> = [title.label, field.label]
        if Self.isPhone {
            let close = app.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch
            XCTAssertTrue(close.exists && close.isHittable, "\(state): Close reachable")
            XCTAssertGreaterThanOrEqual(close.frame.width, 44 - 1, "\(state): Close width \(close.frame)")
            XCTAssertGreaterThanOrEqual(close.frame.height, 44 - 1, "\(state): Close height \(close.frame)")
            scoped.insert(close.label)
        }

        // Audit the title, field and Close only: rows and scope bar have their own journeys.
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .sufficientElementDescription, .contrast]
        try SongsUITestSupport.performAuditRetryingTimeout(app, audit, name: "search-title-\(state)",
                                                           reset: { issues.removeAll() }) { issue in
            guard let element = issue.element, scoped.contains(element.label) else { return true }
            // Known issues `system-search-placeholder-clipped` and `-contrast`
            // (testing/apple/accessibility.md): UIKit draws the single-line placeholder; seen on iPad at AX5.
            if element.elementType == .searchField, [.textClipped, .contrast].contains(issue.auditType) {
                XCTContext.runActivity(named: "\(state): accepted system search placeholder: \(issue.compactDescription)") { _ in }
                return true
            }
            issues.append("\(element.elementType.rawValue) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "\(state): Search title audit issues at AX5")
    }

    // MARK: - Launch and queries

    /// Whether this run is on an iPhone (the Search tab) rather than an iPad (sidebar page).
    private static var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    /// Open the Search page at a text size and wait for its field (focused on a phone).
    ///
    /// - Parameters:
    ///   - size: A `UIContentSizeCategory` raw value; nil keeps the default.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil.
    /// - Returns: The launched app on Search.
    /// - Throws: A skip when the fixture never serves Search or the Duo window is not simulated.
    @MainActor
    private func launchSearch(size: String?, duoWindow: String?) throws -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "search",
        ]
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        }
        let app = FestivalApp.makeApp(environment)
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        guard app.descendants(matching: .any).matching(identifier: "fst.nav.search").firstMatch
            .waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("Search never opened; run tools/mock_service.py --large-catalogue on \(Self.origin).")
        }
        if let duoWindow {
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "\(duoWindow) "), object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
                           "The app never simulated \(duoWindow): \(readout.exists ? readout.label : "no readout")")
        }
        let field = app.searchFields[Self.prompt]
        XCTAssertTrue(field.waitForExistence(timeout: FestivalApp.budget(10)), "Search field")
        if Self.isPhone {
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: FestivalApp.budget(5)),
                          "the Search tab focuses its field")
        }
        // Let the field's activation and the bar's layout settle before reading pixels.
        sleep(UInt32(FestivalApp.budget(1)))
        return app
    }

    /// The "Search" title text in the page's navigation bar.
    ///
    /// - Parameter app: The app on Search.
    /// - Returns: The title element.
    @MainActor
    private func searchTitle(in app: XCUIApplication) throws -> XCUIElement {
        let bar = app.navigationBars["Search"]
        XCTAssertTrue(bar.waitForExistence(timeout: FestivalApp.budget(5)),
                      "Search navigation bar missing: \(app.navigationBars.allElementsBoundByIndex.map(\.identifier))")
        let title = bar.staticTexts.matching(NSPredicate(format: "label == %@", "Search")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(5)), "Search title missing")
        return title
    }

    /// Elements in accessibility-tree order (depth first), as VoiceOver walks them.
    ///
    /// - Parameter app: The running app.
    /// - Returns: Type, label and identifier of each element.
    @MainActor
    private func readingOrder(of app: XCUIApplication) throws
        -> [(type: XCUIElement.ElementType, label: String, identifier: String)] {
        var order: [(type: XCUIElement.ElementType, label: String, identifier: String)] = []
        func walk(_ node: XCUIElementSnapshot) {
            order.append((node.elementType, node.label, node.identifier))
            node.children.forEach(walk)
        }
        walk(try app.snapshot())
        return order
    }

    /// Keep a capture of the page with the test result.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
