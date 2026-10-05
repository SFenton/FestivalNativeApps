import XCTest

/// iPadOS accessibility audits for the universal FestivalMobile app on
/// "FST Native iPad Pro 11" (`.agents/testing/apple/accessibility.md`, iPad section).
///
/// Every page and sheet runs `performAccessibilityAudit(for: .all)` in each mode: the
/// full-screen three-column split (landscape), a regular-width portrait window
/// (sidebar | list), a compact ⅓
/// window (Split View "Arrange thirds"), Dynamic Type AX1 and AX5, and the system
/// settings Bold Text, Increase Contrast and Reduce Transparency. Each audit collects every issue (so
/// one run lists all of them), attaches the list and a screenshot, writes a JSON summary
/// plus each page's capture and element tree to `FST_AUDIT_OUT`
/// (`TEST_RUNNER_FST_AUDIT_OUT` through xcodebuild) when set, and then fails if any issue
/// is left open. An issue is accepted only by a narrow entry in ``IPadAuditWaivers``:
/// a measurement of that element in the same run (rendered contrast, AX5 growth, text
/// read back whole) or a system control the app does not draw.
///
/// System settings cannot be switched from a test: run those methods with
/// `python3 tools/ios_sim.py uitest --device ipad --a11y bold-text --only
/// IPadAccessibilityAuditTests/testBoldTextBrowse` (the method skips unless the runner
/// sees the setting on). The structural journey (`testThreeColumnReadingOrderAndTraits`)
/// checks reading order, the selected-row trait and headings in the three-column split.
///
/// Fixture-backed (`tools/mock_service.py` on 127.0.0.1:8765), never production.
final class IPadAccessibilityAuditTests: XCTestCase {
    // MARK: - Modes and pages

    /// Window and text configuration for one audit pass.
    enum Mode: String {
        case regular, threeColumn, compact, ax1, ax5, ax5Compact, boldText, increaseContrast, reduceTransparency

        /// Portrait, except the three-column split (from a 1000 pt window: landscape on
        /// the 11-inch iPad).
        var orientation: UIDeviceOrientation { self == .threeColumn ? .landscapeLeft : .portrait }

        /// Audit types for this mode. Contrast is audited where colours can change:
        /// regular, compact, three columns, Increase Contrast and Reduce Transparency.
        /// Text-size modes (AX1, AX5, Bold Text) target growth and clipping; their colours
        /// equal the regular run's.
        ///
        /// In landscape the audit's own contrast sampling reads a portrait-oriented
        /// framebuffer (white rows reported failing), and `XCUIApplication.screenshot()`
        /// is cut off; `XCUIScreen.main.screenshot()` holds the whole landscape screen and
        /// is turned upright (``IPadAuditRenderedContrast/Capture``), so each landscape
        /// contrast verdict is checked against real pixels like the portrait ones.
        var auditTypes: XCUIAccessibilityAuditType {
            switch self {
            case .regular, .threeColumn, .compact, .increaseContrast, .reduceTransparency: .all
            default: XCUIAccessibilityAuditType.all.subtracting(.contrast)
            }
        }

        /// Dynamic Type launch override, if any.
        var contentSize: UIContentSizeCategory? {
            switch self {
            case .ax1: .accessibilityMedium
            case .ax5, .ax5Compact: .accessibilityExtraExtraExtraLarge
            default: nil
            }
        }

        /// True for a compact ⅓ window.
        var isCompact: Bool { self == .compact || self == .ax5Compact }

        /// The system setting this mode needs, checked in the runner (same simulator).
        @MainActor
        var systemSettingMissing: String? {
            switch self {
            case .boldText: UIAccessibility.isBoldTextEnabled ? nil : "bold-text"
            case .increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled ? nil : "increase-contrast"
            case .reduceTransparency: UIAccessibility.isReduceTransparencyEnabled ? nil : "reduce-transparency"
            default: nil
            }
        }
    }

    /// A page or sheet to audit: how to reach it and what proves it loaded.
    struct Page {
        let name: String
        var env: [String: String] = [:]
        /// Needs the fixture player selected.
        var profile = false
        /// Any element identifier (navigation bars use their title) that proves the page loaded.
        let ready: String
        /// Steps after `ready` to open a sheet; returns the identifier proving it opened.
        var open: (@MainActor (XCUIApplication) -> String?)?
        /// The page is a presented sheet (its proof, or `ready`, lies inside it).
        var sheet = false
    }

    /// Songs list | Song Detail, its sheets, Item Shop and Search.
    static let browse: [Page] = [
        Page(name: "songs", ready: "fst.songs.list"),
        Page(name: "song-detail", ready: "fst.songs.list", open: { app in
            // Regular width auto-selects the detail; compact pushes it from the row.
            if !app.otherElements["fst.song-detail.intensity"].exists,
               !anyElement(app, "fst.song-detail.intensity").waitForExistence(timeout: 8) {
                let row = app.buttons["fst.songs.row.fixture-pulse"]
                guard row.waitForExistence(timeout: 10) else { return nil }
                row.tap()
            }
            return "fst.song-detail.intensity"
        }),
        Page(name: "sort-sheet", ready: "fst.songs.list", open: { app in
            tapFirst(app, ["fst.songs.sort", "fst.songs.tools.sort"]) ? "fst.songs.sort.mode" : nil
        }, sheet: true),
        Page(name: "filter-sheet", ready: "fst.songs.list", open: { app in
            tapFirst(app, ["fst.songs.filter", "fst.songs.tools.filter"]) ? "fst.songs.filter.form" : nil
        }, sheet: true),
        Page(name: "paths-sheet", ready: "fst.songs.list", open: { app in
            if !anyElement(app, "fst.song-detail.paths").waitForExistence(timeout: 8) {
                let row = app.buttons["fst.songs.row.fixture-pulse"]
                guard row.waitForExistence(timeout: 10) else { return nil }
                row.tap()
            }
            guard tapFirst(app, ["fst.song-detail.paths"], timeout: 15) else { return nil }
            // The fixture song charts Karaoke, so Paths opens with the system "Some
            // Instruments Unavailable" alert (UIKit-owned, not audited: accessibility.md).
            // Audit the sheet itself after OK, as a person sees it.
            let alert = app.alerts.firstMatch
            if alert.waitForExistence(timeout: 5) {
                alert.buttons["OK"].tap()
                _ = alert.waitForNonExistence(timeout: 5)
            }
            return "fst.paths.display"
        }, sheet: true),
        Page(name: "item-shop", env: ["FST_DEBUG_ROUTE": "shop"], ready: "Item Shop"),
        Page(name: "search", ready: "fst.songs.list", open: { app in
            if anyElement(app, "fst.nav.sidebar.search").waitForExistence(timeout: 5) {
                anyElement(app, "fst.nav.sidebar.search").tap()
            } else if app.tabBars.buttons["Search"].waitForExistence(timeout: 5) {
                app.tabBars.buttons["Search"].tap()
            } else {
                return nil
            }
            return "Search"
        }),
    ]

    /// Leaderboards, Full Rankings | player, Settings, Licenses and the anonymous sheets.
    static let rankings: [Page] = [
        Page(name: "leaderboards", env: ["FST_DEBUG_TAB": "leaderboards"], ready: "Leaderboards"),
        Page(name: "full-rankings", env: ["FST_DEBUG_ROUTE": "fullRankings:Solo_Guitar"], ready: "Lead Rankings"),
        Page(name: "player", env: ["FST_DEBUG_ROUTE": "player:fixture-player-2"], ready: "Fixture Player 2"),
        Page(name: "settings", env: ["FST_DEBUG_TAB": "settings"], ready: "Settings"),
        Page(name: "licenses", env: ["FST_DEBUG_ROUTE": "licenses"], ready: "Licenses"),
        Page(name: "profile-sheet", env: ["FST_DEBUG_SHEET": "profile"], ready: "fst.profile.scope", sheet: true),
        Page(name: "whats-new", env: ["FST_DEBUG_WHATS_NEW": "force"], ready: "fst.whats-new.dismiss", sheet: true),
    ]

    /// Pages that need a selected player.
    static let profile: [Page] = [
        Page(name: "statistics", env: ["FST_DEBUG_TAB": "statistics"], profile: true, ready: "Fixture Player 1"),
        Page(name: "suggestions", env: ["FST_DEBUG_TAB": "suggestions"], profile: true, ready: "Suggestions"),
        Page(name: "rivals", env: ["FST_DEBUG_ROUTE": "rivals"], profile: true, ready: "Rivals"),
        Page(name: "rival-detail",
             env: ["FST_DEBUG_ROUTE": "rivalDetail:f1c749eb07c32578cfa3e59ec38c03a8:song:Solo_Guitar"],
             profile: true, ready: "fst.rival-detail.view-profile"),
        Page(name: "compete-or-bands", env: ["FST_DEBUG_ROUTE": "bands"], profile: true, ready: "Bands"),
        Page(name: "notifications", profile: true, ready: "fst.songs.list", open: { app in
            tapFirst(app, ["fst.shell.notifications"]) ? "Notifications" : nil
        }, sheet: true),
    ]

    // MARK: - Lifecycle

    override func setUpWithError() throws {
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad, "iPad-only journeys")
        continueAfterFailure = true
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            let app = FestivalApp.makeApp()
            if app.state == .runningForeground { WindowResize.fill(app) }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Audits: three columns (landscape)

    @MainActor func testThreeColumnBrowse() throws { try audit(Self.browse, mode: .threeColumn, group: "browse") }
    @MainActor func testThreeColumnRankings() throws {
        try audit(Self.rankings, mode: .threeColumn, group: "rankings")
    }
    @MainActor func testThreeColumnProfile() throws { try audit(Self.profile, mode: .threeColumn, group: "profile") }

    // MARK: - Audits: regular width (portrait: sidebar | list)

    @MainActor func testRegularBrowse() throws { try audit(Self.browse, mode: .regular, group: "browse") }
    @MainActor func testRegularRankings() throws { try audit(Self.rankings, mode: .regular, group: "rankings") }
    @MainActor func testRegularProfile() throws { try audit(Self.profile, mode: .regular, group: "profile") }

    // MARK: - Audits: compact ⅓ window

    @MainActor func testCompactBrowse() throws { try audit(Self.browse, mode: .compact, group: "browse") }
    @MainActor func testCompactRankings() throws { try audit(Self.rankings, mode: .compact, group: "rankings") }
    @MainActor func testCompactProfile() throws { try audit(Self.profile, mode: .compact, group: "profile") }

    // MARK: - Audits: Dynamic Type

    @MainActor func testAX1Browse() throws { try audit(Self.browse, mode: .ax1, group: "browse") }
    @MainActor func testAX1Rankings() throws { try audit(Self.rankings, mode: .ax1, group: "rankings") }
    @MainActor func testAX1Profile() throws { try audit(Self.profile, mode: .ax1, group: "profile") }
    @MainActor func testAX5Browse() throws { try audit(Self.browse, mode: .ax5, group: "browse") }
    @MainActor func testAX5Rankings() throws { try audit(Self.rankings, mode: .ax5, group: "rankings") }
    @MainActor func testAX5Profile() throws { try audit(Self.profile, mode: .ax5, group: "profile") }
    @MainActor func testAX5CompactBrowse() throws { try audit(Self.browse, mode: .ax5Compact, group: "browse") }
    @MainActor func testAX5CompactRankings() throws { try audit(Self.rankings, mode: .ax5Compact, group: "rankings") }
    @MainActor func testAX5CompactProfile() throws { try audit(Self.profile, mode: .ax5Compact, group: "profile") }

    // MARK: - Audits: system settings (run with `ios_sim.py uitest --a11y …`)

    @MainActor func testBoldTextBrowse() throws { try audit(Self.browse, mode: .boldText, group: "browse") }
    @MainActor func testBoldTextRankings() throws { try audit(Self.rankings, mode: .boldText, group: "rankings") }
    @MainActor func testBoldTextProfile() throws { try audit(Self.profile, mode: .boldText, group: "profile") }
    @MainActor func testIncreaseContrastBrowse() throws {
        try audit(Self.browse, mode: .increaseContrast, group: "browse")
    }
    @MainActor func testIncreaseContrastRankings() throws {
        try audit(Self.rankings, mode: .increaseContrast, group: "rankings")
    }
    @MainActor func testIncreaseContrastProfile() throws {
        try audit(Self.profile, mode: .increaseContrast, group: "profile")
    }
    @MainActor func testReduceTransparencyBrowse() throws {
        try audit(Self.browse, mode: .reduceTransparency, group: "browse")
    }
    @MainActor func testReduceTransparencyRankings() throws {
        try audit(Self.rankings, mode: .reduceTransparency, group: "rankings")
    }
    @MainActor func testReduceTransparencyProfile() throws {
        try audit(Self.profile, mode: .reduceTransparency, group: "profile")
    }

    // MARK: - Structure: reading order, selection and headings

    /// In the three-column split the accessibility order is sidebar → list → detail; the
    /// sidebar's current destination, the list's selected song and the chosen row after a
    /// tap carry the selected trait; the detail exposes headings for the rotor; and
    /// choosing another row keeps the split (the detail follows, the list stays).
    @MainActor
    func testThreeColumnReadingOrderAndTraits() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = makeApp(Page(name: "songs", ready: "fst.songs.list"), mode: .threeColumn)
        launchFilled(app)
        XCTAssertTrue(Self.anyElement(app, "fst.song-detail.intensity").waitForExistence(timeout: 25))

        // Order: depth-first over the app's accessibility snapshot, as VoiceOver walks
        // SwiftUI's ordered element tree.
        let order = try flatten(app.snapshot())
        func index(_ match: (XCUIElementSnapshot) -> Bool) -> Int? { order.firstIndex(where: match) }
        let sidebar = index { $0.identifier == "fst.nav.songs" }
        let list = index { $0.identifier.hasPrefix("fst.songs.row.") }
        let detail = index { $0.identifier == "fst.song-detail.intensity" }
        XCTAssertNotNil(sidebar, "sidebar row in the tree")
        XCTAssertNotNil(list, "list row in the tree")
        XCTAssertNotNil(detail, "detail in the tree")
        if let sidebar, let list, let detail {
            XCTAssertLessThan(sidebar, list, "sidebar reads before the list")
            XCTAssertLessThan(list, detail, "list reads before the detail")
        }

        // Selection: the sidebar destination and the auto-selected song.
        XCTAssertTrue(Self.anyElement(app, "fst.nav.songs").waitForSelection(timeout: 5),
                      "the sidebar's current destination is selected")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.songs.row.'"))
        let selectedRows = rows.matching(NSPredicate(format: "isSelected == true"))
        XCTAssertEqual(selectedRows.count, 1, "exactly one list row carries the selected trait")

        // Headings: the detail's section titles are rotor headings.
        let headings = order.filter { Self.isHeader($0) }.map(\.label)
        add(attachment(named: "headings", text: headings.joined(separator: "\n")))
        if let dir = ProcessInfo.processInfo.environment["FST_AUDIT_OUT"] {
            let summary: [String: Any] = [
                "order": ["sidebar": sidebar ?? -1, "list": list ?? -1, "detail": detail ?? -1],
                "traitsReadable": Self.traitsReadable(order), "headings": headings,
            ]
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("structure.json"))
        }
        if Self.traitsReadable(order) {
            XCTAssertTrue(headings.contains { !$0.isEmpty }, "the split exposes rotor headings: \(headings)")
        }

        // Choosing another row: it becomes the selected one, the detail follows.
        let second = app.buttons["fst.songs.row.fixture-pulse"]
        if !second.isSelected {
            second.tap()
            XCTAssertTrue(second.waitForSelection(timeout: 5), "the chosen row is selected")
            XCTAssertEqual(selectedRows.count, 1, "selection moved, not added")
            XCTAssertTrue(app.navigationBars["Fixture Pulse"].waitForExistence(timeout: 10), "the detail follows")
        }
        XCTAssertTrue(Self.anyElement(app, "fst.nav.list-detail").exists, "still split after choosing")
        XCTAssertTrue(Self.anyElement(app, "fst.nav.songs").isSelected, "sidebar selection unchanged")
    }

    // MARK: - Audit runner

    /// One recorded audit issue.
    struct Finding: Codable {
        let page: String
        let type: String
        let summary: String
        let detail: String
        let identifier: String
        let label: String
        let frame: String
        /// `XCUIElement.ElementType` raw value (`-1` with no element).
        var elementType: Int = -1
        /// Rendered contrast of the element's frame in this run's capture (contrast issues only).
        var rendered: IPadAuditRenderedContrast.Measurement?
        /// Page-level evidence for an issue without an element (``IPadAuditPageEvidence``).
        var pageEvidence: IPadAuditPageEvidence.Evidence?
        /// Growth and read-back evidence for Dynamic Type heuristics (``IPadAuditTextEvidence``).
        var text: IPadAuditTextEvidence.Evidence?
        /// The waiver that accepted this issue (``IPadAuditWaivers``), if any.
        var waiver: String?
    }

    /// Visit each page in `mode`, audit it and fail once at the end if anything was found.
    @MainActor
    private func audit(_ pages: [Page], mode: Mode, group: String) throws {
        if let missing = mode.systemSettingMissing {
            throw XCTSkip("run with `ios_sim.py uitest --device ipad --a11y \(missing)`")
        }
        XCUIDevice.shared.orientation = mode.orientation
        var findings: [Finding] = []
        var unreached: [String] = []
        for page in pages {
            guard let (app, proof) = try reachWithProof(page, mode: mode, contentSize: mode.contentSize) else {
                unreached.append(page.name)
                continue
            }
            add(screenshot(app, "\(mode.rawValue)-\(page.name)"))
            var pageFindings: [Finding] = []
            var issues: [XCUIAccessibilityAuditIssue] = []
            try app.performAccessibilityAudit(for: mode.auditTypes) { issue in
                // One snapshot reads every attribute in one query. On iPadOS 26.5 many
                // SwiftUI text nodes come back with no element at all (the issue's own
                // element reference is nil): those get page-level evidence below.
                let element: (any XCUIElementAttributes)? = (try? issue.element?.snapshot()) ?? issue.element
                let finding = Finding(
                    page: page.name,
                    type: String(describing: issue.auditType),
                    summary: issue.compactDescription,
                    detail: issue.detailedDescription,
                    identifier: element?.identifier ?? "",
                    label: element?.label ?? "",
                    frame: element.map { NSCoder.string(for: $0.frame) } ?? "",
                    elementType: element.map { Int($0.elementType.rawValue) } ?? -1
                )
                pageFindings.append(finding)
                issues.append(issue)
                return true // collected; open findings fail below, waived ones are reported
            }
            // Evidence after the audit: nothing before it touches the app, so the audit
            // sees exactly what a fresh query sees. Terminates `app`.
            let containers = try collectEvidence(
                &pageFindings, types: issues.map(\.auditType), page: page, mode: mode, app: app, proof: proof
            )
            for index in pageFindings.indices {
                let finding = pageFindings[index]
                pageFindings[index].waiver = IPadAuditWaivers.match(
                    IPadAuditWaivers.Issue(
                        auditType: issues[index].auditType, summary: finding.summary,
                        identifier: finding.identifier, label: finding.label,
                        elementType: finding.elementType < 0
                            ? nil : XCUIElement.ElementType(rawValue: UInt(finding.elementType)),
                        rendered: finding.rendered, text: finding.text, page: finding.pageEvidence,
                        containers: finding.frame.isEmpty ? [] : Set(containers.compactMap { id, frame in
                            let rect = NSCoder.cgRect(for: finding.frame)
                            return frame.contains(CGPoint(x: rect.midX, y: rect.midY)) ? id : nil
                        })
                    ),
                    page: page.name, mode: mode.rawValue
                )?.id
            }
            findings += pageFindings
        }
        report(findings, unreached: unreached, mode: mode, group: group)
        XCTAssertTrue(unreached.isEmpty, "pages not reached: \(unreached)")
        let open = findings.filter { $0.waiver == nil }
        XCTAssertTrue(open.isEmpty, "\(open.count) audit issue(s) (\(findings.count - open.count) waived):\n"
            + open.map {
                "[\($0.page)] \($0.type): \($0.summary) id=\($0.identifier) label=\($0.label) frame=\($0.frame)"
                    + ($0.rendered.map { " rendered=\($0.ratio)" } ?? "")
            }.joined(separator: "\n"))
    }

    /// Launch `page` in `mode` at `contentSize`, open its sheet and let it settle.
    ///
    /// - Returns: The running app, or nil (with a screenshot) when the page was not reached.
    /// - Throws: `XCTSkip` when compact tiling is unavailable.
    @MainActor
    func reach(_ page: Page, mode: Mode, contentSize: UIContentSizeCategory?) throws -> XCUIApplication? {
        try reachWithProof(page, mode: mode, contentSize: contentSize)?.app
    }

    /// ``reach(_:mode:contentSize:)`` plus the identifier that proved the page (the
    /// sheet's proof for sheet pages).
    @MainActor
    func reachWithProof(
        _ page: Page, mode: Mode, contentSize: UIContentSizeCategory?
    ) throws -> (app: XCUIApplication, proof: String)? {
        let app = makeApp(page, mode: mode, contentSize: contentSize)
        launchFilled(app)
        if mode.isCompact, !makeCompact(app) {
            throw XCTSkip("window-controls tiling unavailable (full-screen multitasking mode)")
        }
        guard Self.anyElement(app, page.ready).waitForExistence(timeout: 25) else {
            add(screenshot(app, "\(mode.rawValue)-\(page.name)-unreached"))
            app.terminate()
            return nil
        }
        var proof = page.ready
        if let open = page.open {
            guard let opened = open(app), Self.anyElement(app, opened).waitForExistence(timeout: 15) else {
                add(screenshot(app, "\(mode.rawValue)-\(page.name)-unreached"))
                app.terminate()
                return nil
            }
            proof = opened
        }
        settle(app)
        return (app, proof)
    }

    /// Write a capture and the element tree next to the JSON (`FST_AUDIT_OUT`).
    @MainActor
    func write(_ capture: IPadAuditRenderedContrast.Capture?, tree app: XCUIApplication, name: String) {
        guard let dir = ProcessInfo.processInfo.environment["FST_AUDIT_OUT"] else { return }
        let base = URL(fileURLWithPath: dir).appendingPathComponent(name)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let capture {
            try? UIImage(cgImage: capture.image).pngData()?.write(to: base.appendingPathExtension("png"))
        }
        // The element tree locates issues the audit reports without an element.
        try? app.debugDescription.write(to: base.appendingPathExtension("tree.txt"), atomically: true, encoding: .utf8)
    }

    /// Attach and (optionally) write the findings as JSON.
    @MainActor
    private func report(_ findings: [Finding], unreached: [String], mode: Mode, group: String) {
        struct Summary: Codable {
            let mode: String
            let group: String
            let unreached: [String]
            let findings: [Finding]
        }
        let summary = Summary(mode: mode.rawValue, group: group, unreached: unreached, findings: findings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(summary) else { return }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "audit-\(mode.rawValue)-\(group).json"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["FST_AUDIT_OUT"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(mode.rawValue)-\(group).json")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }

    // MARK: - Helpers

    /// A configured, not-yet-launched app for a page and mode.
    @MainActor
    private func makeApp(_ page: Page, mode: Mode, contentSize: UIContentSizeCategory? = nil) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if page.profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        env.merge(page.env) { _, new in new }
        let app = FestivalApp.makeApp(env)
        // Pin Sort to Title per launch (never the saved preference).
        app.launchArguments += ["-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES"]
        if let size = contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size.rawValue]
        }
        return app
    }

    /// Launch and make the window fill the screen (iPadOS remembers resized windows).
    @MainActor
    private func launchFilled(_ app: XCUIApplication) {
        app.launch()
        WindowResize.fill(app)
    }

    /// Tile the window to a compact third and wait for the phone tab bar.
    @MainActor
    private func makeCompact(_ app: XCUIApplication) -> Bool {
        guard WindowResize.tile(app, .thirds) else { return false }
        return app.tabBars.firstMatch.waitForExistence(timeout: 10)
    }

    /// Let loading finish: no activity indicator for a moment (bounded), then wait out
    /// the staggered load-in fades (`FestivalFadeIn`, up to ~1.5 s) and sheet
    /// presentation so the audit reads the settled page, not text mid-fade.
    @MainActor
    private func settle(_ app: XCUIApplication) {
        let deadline = Date.now.addingTimeInterval(12)
        var quiet = 0
        while Date.now < deadline, quiet < 2 {
            quiet = app.activityIndicators.firstMatch.exists ? 0 : quiet + 1
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2.5)
    }

    /// Any element by identifier (navigation bars are identified by their title).
    @MainActor
    static func anyElement(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Tap the first of several identifiers that exists.
    @MainActor
    static func tapFirst(_ app: XCUIApplication, _ ids: [String], timeout: TimeInterval = 10) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        repeat {
            for id in ids {
                let element = anyElement(app, id)
                if element.exists, element.isHittable {
                    element.tap()
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date.now < deadline
        return false
    }

    /// Depth-first flattening of a snapshot (accessibility tree order).
    private func flatten(_ snapshot: XCUIElementSnapshot) throws -> [XCUIElementSnapshot] {
        var out: [XCUIElementSnapshot] = [snapshot]
        for child in snapshot.children { out += try flatten(child) }
        return out
    }

    /// The snapshot's accessibility traits, when the runtime exposes them (`traits` on the
    /// concrete snapshot class); nil otherwise.
    static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
    }

    /// True when some snapshot exposes its traits.
    static func traitsReadable(_ snapshots: [XCUIElementSnapshot]) -> Bool {
        snapshots.contains { traits($0) != nil }
    }

    /// True for a heading.
    static func isHeader(_ snapshot: XCUIElementSnapshot) -> Bool {
        guard let traits = traits(snapshot) else { return false }
        return traits & UIAccessibilityTraits.header.rawValue != 0
    }

    /// A kept screenshot attachment.
    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }

    /// A kept text attachment.
    private func attachment(named name: String, text: String) -> XCTAttachment {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
