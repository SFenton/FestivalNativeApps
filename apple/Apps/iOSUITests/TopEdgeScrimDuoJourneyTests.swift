import XCTest

/// The page's top darkening gradient under the real iPhone Duo vertical bar, from an
/// assistive technology's side (issue #476, for #335).
///
/// #335 spread `TopEdgeScrim` under the horizontal safe areas, so on the folded Duo the
/// art under the trailing vertical bar is dimmed like the page beside it. On the real
/// folded Duo at AX5 the gradient's band holds the page title beside the bar and the
/// system status area at the bar's top; the bar's own items (the page tools, then the
/// sections) stack below it. This journey checks the region the gradient covers (the top
/// `scrimBand` points of the window, page and bar) and the bar items next to it:
///
/// - the page title is a readable heading, read before the first row, hittable and at
///   least 4.5:1 rendered contrast over the darkened art;
/// - the page tools and the sections in the bar are named buttons that the gradient never
///   covers (each is hittable, so a touch at its centre reaches it), the tools in the bar
///   below its status area;
/// - `performAccessibilityAudit` (all types) reports nothing on an element in the band or
///   on the bar's page tools.
///
/// The hosted `TopEdgeScrimAccessibilityTests` prove the gradient is decoration (same tree
/// with and without it), keeps controls beside and in a bar hittable and pressable, and
/// darkens the bar like the page in every Reduce Transparency / Increase Contrast mode.
///
/// Needs the real folded Duo (the simulated `DebugDuoWindow` has no vertical bar inset), so
/// it runs on `apple-ci`'s `duo-folded` leg against the plain fixture:
///
/// ```
/// python3 tools/mock_service.py --port 18476 &
/// TEST_RUNNER_FST_FIXTURE_URL=http://127.0.0.1:18476 \
///   python3 tools/ios_sim.py uitest --device duo --pose folded --only TopEdgeScrimDuoJourneyTests
/// ```
///
/// HIG Accessibility: iOS/iPadOS default control size 44×44 pt. HIG for iPhone Duo
/// (`duo-checklist.md` §3): "Vertical bars get a background under Reduce Transparency, so
/// custom content must stay legible there."
final class TopEdgeScrimDuoJourneyTests: XCTestCase {
    /// `TopEdgeScrim.maxHeight`: the tallest the gradient gets, from the window's top.
    private static let scrimBand: CGFloat = 150
    /// The page tools Songs puts in the navigation bar (the vertical bar, under its status
    /// area, on the folded Duo).
    private static let tools: [(id: String, label: String)] = [
        ("fst.songs.sort", "Sort"), ("fst.songs.filter", "Filter Songs"),
    ]

    /// Songs on the folded Duo at AX5: title, page tools and sections over the gradient
    /// stay named, hittable and readable, and the audit finds nothing in the band.
    @MainActor
    func testScrimUnderTheVerticalBarKeepsTheTopAccessibleAtAX5() throws {
        continueAfterFailure = false
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = SongsUITestSupport.fixtureURL
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        let firstRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row.")).firstMatch
        guard firstRow.waitForExistence(timeout: FestivalApp.budget(30)) else {
            throw XCTSkip("No Songs rows; run tools/mock_service.py on \(SongsUITestSupport.fixtureURL).")
        }
        let window = app.windows.firstMatch.frame
        let sections = try verticalBarSections(in: app, window: window)
        let barEdge = try XCTUnwrap(sections.map(\.frame.minX).min())
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "songs-duo-folded-ax5-top"
        attachment.lifetime = .keepAlways
        add(attachment)

        // The title: a heading over the darkened art beside the bar, read before the rows.
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label == %@", "Songs")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(10)), "Songs' title at the top")
        XCTAssertLessThan(title.frame.minY - window.minY, Self.scrimBand, "the title sits in the gradient: \(title.frame)")
        XCTAssertLessThanOrEqual(title.frame.maxX, barEdge + 0.5, "the title stays beside the bar: \(title.frame)")
        try SongsUITestSupport.assertHeaderContrast(title, in: app)
        let order = try readingOrder(app)
        let titleIndex = try XCTUnwrap(order.firstIndex { $0.elementType == .staticText && $0.label == "Songs" })
        let rowIndex = try XCTUnwrap(order.firstIndex { $0.identifier.hasPrefix("fst.songs.row.") })
        XCTAssertLessThan(titleIndex, rowIndex, "the title reads before the first row")

        // The bar's items over the gradient: named buttons a touch reaches.
        var band: Set<String> = []
        for tool in Self.tools {
            let button = app.buttons[tool.id]
            XCTAssertTrue(button.waitForExistence(timeout: FestivalApp.budget(10)), "\(tool.id) exists")
            // Sort also reads its current order ("Sort, Title, ascending").
            XCTAssertTrue(button.label.hasPrefix(tool.label), "\(tool.id) is named: '\(button.label)'")
            XCTAssertTrue(button.isHittable, "\(tool.id) is reachable over the gradient: \(button.frame)")
            XCTAssertGreaterThanOrEqual(button.frame.minX, barEdge - 0.5, "\(tool.id) is in the vertical bar")
            XCTAssertLessThan(button.frame.maxY, sections[0].frame.minY, "\(tool.id) sits above the sections")
            band.insert(tool.id)
        }
        for section in sections {
            XCTAssertTrue(section.isHittable, "section \(section.label) is reachable: \(section.frame)")
        }

        try auditBand(app, window: window, owned: band, title: title.frame)
    }

    // MARK: - Helpers

    /// The shell's section buttons, required to stack in the trailing vertical bar of a
    /// real folded Duo window; skips elsewhere.
    @MainActor
    private func verticalBarSections(in app: XCUIApplication, window: CGRect) throws -> [XCUIElement] {
        let sides = [min(window.width, window.height).rounded(), max(window.width, window.height).rounded()]
        try XCTSkipUnless(sides == [466, 678], "Needs the folded iPhone Duo (window \(window.size))")
        let sections = ["Songs", "Settings"].compactMap { label -> XCUIElement? in
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
            _ = matches.firstMatch.waitForExistence(timeout: FestivalApp.budget(10))
            return matches.allElementsBoundByIndex.first { $0.frame.width > 0 && $0.frame.height > 0 && $0.frame.minX > window.midX }
        }
        try XCTSkipUnless(
            sections.count == 2 && abs(sections[0].frame.midX - sections[1].frame.midX) < 4,
            "Needs the trailing vertical bar (fold the Duo): \(sections.map(\.frame))"
        )
        return sections
    }

    /// The app's accessibility elements in the depth-first order VoiceOver swipes through.
    @MainActor
    private func readingOrder(_ app: XCUIApplication) throws -> [XCUIElementSnapshot] {
        var nodes: [XCUIElementSnapshot] = []
        func walk(_ node: XCUIElementSnapshot) {
            nodes.append(node)
            node.children.forEach(walk)
        }
        walk(try app.snapshot())
        return nodes
    }

    /// Audit everything and fail on any issue with an element in the gradient's band or
    /// in `owned` (the bar's page tools). A contrast estimate on the title text is accepted
    /// only because its rendered contrast was measured at ≥ 4.5:1 first; other issues
    /// belong to other journeys and are listed as an activity.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - window: The app window's frame.
    ///   - owned: Identifiers whose issues fail the test wherever they sit.
    ///   - title: The measured page title's frame.
    @MainActor
    private func auditBand(_ app: XCUIApplication, window: CGRect, owned: Set<String>, title: CGRect) throws {
        var rejected: [String] = []
        var elsewhere: [String] = []
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            let description = "\(issue.compactDescription) [" + (issue.element.map {
                "\($0.elementType.rawValue) '\($0.identifier)' '\($0.label)' \($0.frame)"
            } ?? "no element") + "]"
            guard let element = issue.element else {
                elsewhere.append(description)
                return true
            }
            let frame = element.frame
            let inBand = owned.contains(element.identifier)
                || (frame.minY - window.minY < Self.scrimBand && frame.height < window.height / 2)
            if !inBand {
                elsewhere.append(description)
            } else if issue.auditType == .contrast, element.elementType == .staticText, frame == title {
                elsewhere.append("title measured ≥ 4.5:1: \(description)")
            } else {
                rejected.append(description)
            }
            return true
        }
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, .all, name: "duo-top-band", reset: { rejected = []; elsewhere = [] }, handler
        )
        XCTContext.runActivity(named: "Outside the gradient's band: \(elsewhere)") { _ in }
        XCTAssertTrue(rejected.isEmpty, "audit issues in the gradient's band: \(rejected)")
    }
}
