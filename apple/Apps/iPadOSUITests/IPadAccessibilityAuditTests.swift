import XCTest

/// iPadOS and iPhone Duo accessibility audits for the universal FestivalMobile app on
/// "FST Native iPad Pro 11" and "iPhone Duo (FST)" (`.agents/testing/apple/accessibility.md`).
///
/// Every page and sheet runs `performAccessibilityAudit(for: .all)` in each mode: the
/// full-screen landscape window (on-demand split), a regular-width portrait window
/// (one stack), a compact ⅓
/// window (Split View "Arrange thirds"), Dynamic Type AX1 and AX5, and the system
/// settings Bold Text, Increase Contrast and Reduce Transparency. The **shell** group
/// audits the redesigned shell itself: the overlay flyout open, and each split page with
/// its trailing pane open (landscape only). `Duo*` modes run the same pages on iPhone Duo
/// in whatever pose Device Hub holds (`ios_sim.py pose --set …` first; the test never
/// rotates or resizes the Duo). Each audit collects every issue (so
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
/// sees the setting on). The structural journeys (`IPadShellAccessibilityTests`) check
/// the flyout's modality and dismissal, and the split's reading order, selection and
/// focus moves.
///
/// Fixture-backed (`tools/mock_service.py` on 127.0.0.1:8765), never production.
final class IPadAccessibilityAuditTests: XCTestCase {
    /// iPhone Duo: whether this run's pose splits (read once per test).
    private var duoSplitPossible: Bool?
    /// The app window of the last page reached (in the JSON: proves the pose or tile).
    private var lastWindow = ""

    // MARK: - Modes and pages

    /// Window and text configuration for one audit pass.
    enum Mode: String {
        case regular, landscape, landscapeAX5, compact, ax1, ax5, ax5Compact
        case boldText, increaseContrast, reduceTransparency
        case duo, duoAX5

        /// Portrait, except the landscape window (list pages split on demand); nil on iPhone
        /// Duo, whose pose and rotation only Device Hub sets.
        var orientation: UIDeviceOrientation? {
            switch self {
            case .landscape, .landscapeAX5: .landscapeLeft
            case .duo, .duoAX5: nil
            default: .portrait
            }
        }

        /// Runs on iPhone Duo (and only there).
        var isDuo: Bool { self == .duo || self == .duoAX5 }

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
            case .regular, .landscape, .compact, .increaseContrast, .reduceTransparency, .duo: .all
            default: XCUIAccessibilityAuditType.all.subtracting(.contrast)
            }
        }

        /// Dynamic Type launch override, if any.
        var contentSize: UIContentSizeCategory? {
            switch self {
            case .ax1: .accessibilityMedium
            case .ax5, .ax5Compact, .landscapeAX5, .duoAX5: .accessibilityExtraExtraExtraLarge
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
        /// Replaces `env` in a compact ⅓ window, where some sections are not phone tabs.
        var compactEnv: [String: String]?
        /// Needs the fixture player selected.
        var profile = false
        /// Any element identifier (navigation bars use their title) that proves the page loaded.
        let ready: String
        /// Steps after `ready` to open a sheet; returns the identifier proving it opened.
        var open: (@MainActor (XCUIApplication) -> String?)?
        /// The page is a presented sheet (its proof, or `ready`, lies inside it).
        var sheet = false
        /// The page is a split with its trailing pane open: audited only in a landscape
        /// window (portrait and compact push the same page, audited in its own group).
        var splitOnly = false
    }

    /// Songs list | Song Detail, its sheets, Item Shop and Search.
    static let browse: [Page] = [
        Page(name: "songs", ready: "fst.songs.list"),
        Page(name: "song-detail", ready: "fst.songs.list", open: { app in
            // Regular width auto-selects the detail (the top row, Fixture Orbit); compact
            // pushes the same song from its row. The top row: at AX5 in a ⅓ window the
            // second row's centre sits under the floating page tools.
            if !app.otherElements["fst.song-detail.intensity"].exists,
               !anyElement(app, "fst.song-detail.intensity").waitForExistence(timeout: 8) {
                let row = app.buttons["fst.songs.row.fixture-orbit"]
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
                let row = app.buttons["fst.songs.row.fixture-orbit"]
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
        // iPhone Duo: the Search tab opens at launch (`FST_DEBUG_TAB=search`); its rail
        // button is not hittable on the inner display in landscape (Lane A11Y3).
        runningOnDuo ? Page(name: "search", env: ["FST_DEBUG_TAB": "search"], ready: "Search") :
        Page(name: "search", ready: "fst.songs.list", open: { app in
            // Regular width: the flyout's Search row (no persistent sidebar, 2026-10-04).
            if anyElement(app, "fst.shell.drawer.open").waitForExistence(timeout: 5),
               !app.tabBars.buttons["Search"].exists {
                anyElement(app, "fst.shell.drawer.open").tap()
                guard anyElement(app, "fst.shell.drawer.search").waitForExistence(timeout: 5) else { return nil }
                anyElement(app, "fst.shell.drawer.search").tap()
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
        // Close, not Dismiss: beside the iPhone Duo vertical bar the sheet has no Dismiss bar
        // (`/duo` M1), which left What's New unreached there (Lane A11Y3).
        Page(name: "whats-new", env: ["FST_DEBUG_WHATS_NEW": "force"], ready: "fst.whats-new.close", sheet: true),
    ]

    /// Pages that need a selected player.
    static let profile: [Page] = [
        // The overview section, not the title: the iPhone Duo bar does not expose it.
        // iPhone Duo and a ⅓ window have no Statistics tab: the route pushes the same page
        // (Lane A11Y4; in a ⅓ window the tab launch fell back to Compete, which earlier
        // audits recorded as "statistics").
        Page(name: "statistics",
             env: runningOnDuo ? ["FST_DEBUG_ROUTE": "statistics"] : ["FST_DEBUG_TAB": "statistics"],
             compactEnv: ["FST_DEBUG_ROUTE": "statistics"],
             profile: true, ready: "fst.player.overview"),
        Page(name: "suggestions", env: ["FST_DEBUG_TAB": "suggestions"], profile: true, ready: "Suggestions"),
        Page(name: "rivals", env: ["FST_DEBUG_ROUTE": "rivals"], profile: true, ready: "Rivals"),
        Page(name: "rival-detail",
             env: ["FST_DEBUG_ROUTE": "rivalDetail:f1c749eb07c32578cfa3e59ec38c03a8:song:Solo_Guitar"],
             // The rival's name titles the page in every width; View Profile moves out of
             // the content in a compact window.
             profile: true, ready: "uwphe"),
        Page(name: "compete-or-bands", env: ["FST_DEBUG_ROUTE": "bands"], profile: true, ready: "Bands"),
        Page(name: "notifications", profile: true, ready: "fst.songs.list", open: { app in
            tapFirst(app, ["fst.shell.notifications"]) ? "Notifications" : nil
        }, sheet: true),
    ]

    /// The redesigned shell (Lane SPLIT, 2026-10-05): the overlay flyout open (modal,
    /// its footer reachable at AX5), and every split page with its trailing pane open.
    static let shell: [Page] = [
        Page(name: "flyout", profile: true, ready: "fst.songs.list", open: { app in
            // The proof is a row inside the panel, so the panel is the "sheet" region.
            openDrawer(app) ? "fst.shell.drawer.songs" : nil
        }, sheet: true),
        // Song Detail opened from its Songs row, as a person does: a page pushed by
        // `FST_DEBUG_SONG` did not scroll under XCUITest drags or scroll-to-tap.
        Page(name: "song-board-split", ready: "fst.songs.list", open: { app in
            openSong(app, "fixture-pulse") ? openSplit(app, ids: ["fst.song-detail.leaderboard.Solo_Guitar"]) : nil
        }, splitOnly: true),
        // More than five Lead scores, so View All Scores shows (issue #324).
        Page(name: "song-history-split", env: ["FST_DEBUG_PROFILE": "fixture-history-multi:Multi History"],
             profile: true, ready: "fst.songs.list", open: { app in
            openSong(app, "fixture-pulse") ? openSplit(app, ids: ["fst.song-detail.history.view-all"]) : nil
        }, splitOnly: true),
        Page(name: "rivals-split", env: ["FST_DEBUG_ROUTE": "rivals"], profile: true, ready: "Rivals",
             open: { app in openSplit(app, prefix: "fst.rivals.row.") }, splitOnly: true),
        Page(name: "leaderboards-split", env: ["FST_DEBUG_TAB": "leaderboards"], ready: "Leaderboards",
             open: { app in openSplit(app, prefix: "fst.rankings.row.") }, splitOnly: true),
        Page(name: "full-rankings-split", env: ["FST_DEBUG_ROUTE": "fullRankings:Solo_Guitar"],
             ready: "Lead Rankings", open: { app in openSplit(app, prefix: "fst.rankings.row.") }, splitOnly: true),
        Page(name: "settings-split", env: ["FST_DEBUG_TAB": "settings"], ready: "Settings",
             open: { app in openSplit(app, ids: ["fst.settings.licenses"]) }, splitOnly: true),
    ]

    // MARK: - Lifecycle

    /// The runner is on iPhone Duo (simulator device name).
    static var runningOnDuo: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.contains("Duo") ?? false
    }

    override func setUpWithError() throws {
        let isPad = MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
        try XCTSkipUnless(isPad || Self.runningOnDuo, "iPad and iPhone Duo journeys")
        continueAfterFailure = true
    }

    override func tearDown() {
        guard !Self.runningOnDuo else { return }
        MainActor.assumeIsolated {
            let app = FestivalApp.makeApp()
            if app.state == .runningForeground { WindowResize.fill(app) }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Audits: landscape (on-demand split)

    @MainActor func testLandscapeBrowse() throws { try audit(Self.browse, mode: .landscape, group: "browse") }
    @MainActor func testLandscapeRankings() throws { try audit(Self.rankings, mode: .landscape, group: "rankings") }
    @MainActor func testLandscapeProfile() throws { try audit(Self.profile, mode: .landscape, group: "profile") }
    @MainActor func testLandscapeShell() throws { try audit(Self.shell, mode: .landscape, group: "shell") }
    @MainActor func testLandscapeAX5Shell() throws { try audit(Self.shell, mode: .landscapeAX5, group: "shell") }

    // MARK: - Audits: the shell in portrait modes (flyout; splits push there)

    @MainActor func testRegularShell() throws { try audit(Self.shell, mode: .regular, group: "shell") }
    @MainActor func testCompactShell() throws { try audit(Self.shell, mode: .compact, group: "shell") }
    @MainActor func testAX1Shell() throws { try audit(Self.shell, mode: .ax1, group: "shell") }
    @MainActor func testAX5Shell() throws { try audit(Self.shell, mode: .ax5, group: "shell") }
    @MainActor func testBoldTextShell() throws { try audit(Self.shell, mode: .boldText, group: "shell") }
    @MainActor func testIncreaseContrastShell() throws { try audit(Self.shell, mode: .increaseContrast, group: "shell") }
    @MainActor func testReduceTransparencyShell() throws {
        try audit(Self.shell, mode: .reduceTransparency, group: "shell")
    }

    // MARK: - Audits: iPhone Duo (pose set in Device Hub beforehand)

    @MainActor func testDuoBrowse() throws { try audit(Self.browse, mode: .duo, group: "browse") }
    @MainActor func testDuoRankings() throws { try audit(Self.rankings, mode: .duo, group: "rankings") }
    @MainActor func testDuoProfile() throws { try audit(Self.profile, mode: .duo, group: "profile") }
    @MainActor func testDuoShell() throws { try audit(Self.shell, mode: .duo, group: "shell") }
    @MainActor func testDuoAX5Shell() throws { try audit(Self.shell, mode: .duoAX5, group: "shell") }

    // MARK: - Audits: regular width (portrait: one stack)

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
        /// Absent from the accessibility snapshot (hidden by a modal panel), when checked.
        var outsideTree: Bool?
        /// The waiver that accepted this issue (``IPadAuditWaivers``), if any.
        var waiver: String?
    }

    /// Visit each page in `mode`, audit it and fail once at the end if anything was found.
    @MainActor
    private func audit(_ pages: [Page], mode: Mode, group: String) throws {
        if let missing = mode.systemSettingMissing {
            throw XCTSkip("run with `ios_sim.py uitest --device ipad --a11y \(missing)`")
        }
        if mode.isDuo != Self.runningOnDuo {
            throw XCTSkip(mode.isDuo ? "iPhone Duo mode" : "iPad mode")
        }
        if let orientation = mode.orientation { XCUIDevice.shared.orientation = orientation }
        // iPhone Duo: read the pose's window once (split possible, capture orientation).
        if mode.isDuo { _ = splitPossible(mode) }
        var findings: [Finding] = []
        var unreached: [String] = []
        var skipped: [String] = []
        for page in pages where Self.pageSelected(page.name) {
            if page.splitOnly, !splitPossible(mode) {
                skipped.append(page.name)
                continue
            }
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
                        }),
                        outsideTree: finding.outsideTree ?? false
                    ),
                    page: page.name, mode: mode.rawValue
                )?.id
            }
            findings += pageFindings
        }
        report(findings, unreached: unreached, skipped: skipped, mode: mode, group: group)
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
        lastWindow = NSCoder.string(for: app.windows.firstMatch.frame)
        var proof = page.ready
        if let open = page.open {
            guard let opened = open(app),
                  opened == "fst.split.opened" || Self.anyElement(app, opened).waitForExistence(timeout: 15) else {
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
    private func report(_ findings: [Finding], unreached: [String], skipped: [String], mode: Mode, group: String) {
        struct Summary: Codable {
            let mode: String
            let group: String
            let unreached: [String]
            /// Split pages left out because this window cannot split (portrait, compact).
            let skipped: [String]
            /// The app window of the last page reached (iPhone Duo pose, ⅓ tile).
            let window: String
            /// The `FST_AUDIT_PAGES` filter, when the run audited only some pages.
            let pages: [String]?
            let findings: [Finding]
        }
        let summary = Summary(
            mode: mode.rawValue, group: group, unreached: unreached, skipped: skipped,
            window: lastWindow, pages: Self.pageFilter.map { $0.sorted() }, findings: findings
        )
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

    /// `FST_AUDIT_PAGES` (comma-separated page names, `TEST_RUNNER_FST_AUDIT_PAGES` through
    /// xcodebuild): audit only those pages of the group, for re-checking one fix. Unset
    /// audits every page; a filtered run's JSON lists the filter in `pages`.
    static var pageFilter: Set<String>? {
        guard let raw = ProcessInfo.processInfo.environment["FST_AUDIT_PAGES"], !raw.isEmpty else { return nil }
        return Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// Whether `FST_AUDIT_PAGES` leaves this page in the run.
    ///
    /// - Parameter name: The page's audit name.
    /// - Returns: True when unfiltered or listed.
    static func pageSelected(_ name: String) -> Bool { pageFilter?.contains(name) ?? true }

    /// A configured, not-yet-launched app for a page and mode.
    @MainActor
    func makeApp(_ page: Page, mode: Mode, contentSize: UIContentSizeCategory? = nil) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if page.profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        env.merge(mode.isCompact ? page.compactEnv ?? page.env : page.env) { _, new in new }
        let app = FestivalApp.makeApp(env)
        // Pin Sort to Title per launch (never the saved preference).
        app.launchArguments += ["-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES"]
        if let size = contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size.rawValue]
        }
        return app
    }

    /// Launch and make the window fill the screen (iPadOS remembers resized windows).
    /// iPhone Duo has one full-screen window per display: nothing to resize.
    @MainActor
    func launchFilled(_ app: XCUIApplication) {
        app.launch()
        if !Self.runningOnDuo { WindowResize.fill(app) }
    }

    /// Whether the mode's window splits on demand: the iPad landscape modes; on iPhone Duo
    /// the inner display in landscape (a probe launch reads the window, since Device Hub
    /// holds the pose).
    @MainActor
    private func splitPossible(_ mode: Mode) -> Bool {
        switch mode {
        case .landscape, .landscapeAX5: return true
        case .duo, .duoAX5:
            if let known = duoSplitPossible { return known }
            let app = makeApp(Page(name: "probe", ready: "fst.songs.list"), mode: mode)
            app.launch()
            _ = Self.anyElement(app, "fst.songs.list").waitForExistence(timeout: 25)
            let frame = app.windows.firstMatch.frame
            app.terminate()
            // Inner landscape is 951 × 669 pt; inner portrait and the outer display push.
            let known = frame.width > frame.height && frame.width >= 800
            duoSplitPossible = known
            IPadAuditRenderedContrast.interfaceIsLandscape = frame.width > frame.height
            IPadAuditRenderedContrast.windowSize = frame.size
            return known
        default: return false
        }
    }

    /// Open the flyout or drawer: its toolbar button, or on the folded iPhone Duo rail the
    /// system overflow menu that holds it (`/duo` W1: the hamburger overflows there).
    ///
    /// - Returns: True once the drawer shows.
    @MainActor
    static func openDrawer(_ app: XCUIApplication) -> Bool {
        if tapFirst(app, ["fst.shell.drawer.open"], timeout: 5) {
            return anyElement(app, "fst.shell.drawer.songs").waitForExistence(timeout: 5)
        }
        let more = app.buttons.matching(NSPredicate(format: "label IN %@", ["More", "Show More"])).firstMatch
        guard more.waitForExistence(timeout: 5) else { return false }
        more.tap()
        let item = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Open Navigation' OR label == 'Menu'")).firstMatch
        guard item.waitForExistence(timeout: 5) else { return false }
        item.tap()
        return anyElement(app, "fst.shell.drawer.songs").waitForExistence(timeout: 5)
    }

    /// Open a song's detail page from its Songs row.
    ///
    /// - Returns: True once Song Detail shows.
    @MainActor
    static func openSong(_ app: XCUIApplication, _ songId: String) -> Bool {
        let row = app.buttons["fst.songs.row.\(songId)"]
        guard row.waitForExistence(timeout: 15) else { return false }
        // At AX5 the row can sit below the fold: bring it on screen with slow drags.
        let window = app.windows.firstMatch.frame
        for _ in 0..<8 where !(row.isHittable && window.insetBy(dx: 0, dy: 60).contains(
            CGPoint(x: row.frame.midX, y: row.frame.midY))) {
            // The middle: Songs' trailing edge holds the section index scrubber.
            slowDrag(app, x: window.midX, fromY: window.minY + window.height * 0.75,
                     toY: window.minY + window.height * 0.35)
        }
        row.tap()
        return anyElement(app, "fst.song-detail.intensity").waitForExistence(timeout: 20)
    }

    /// The trailing pane's frame while a split is open, else nil: `fst.split.trailing`,
    /// or on iOS 27.1 (iPhone Duo), where that container identifier is not exposed, the
    /// navigation bar that starts right of the window's middle.
    @MainActor
    static func trailingPane(_ app: XCUIApplication) -> CGRect? {
        let pane = anyElement(app, "fst.split.trailing")
        if pane.exists { return pane.frame }
        let window = app.windows.firstMatch.frame
        let bars = app.navigationBars.allElementsBoundByIndex.map(\.frame)
            .filter { $0.height > 0 && $0.minX > window.midX - 40 && $0.maxY < window.midY }
        guard let bar = bars.first else { return nil }
        return CGRect(x: bar.minX, y: window.minY, width: window.maxX - bar.minX, height: window.height)
    }

    /// Wait for the trailing pane (``trailingPane(_:)``) to show and finish sliding in:
    /// its frame read mid-spring (791 pt instead of 605) failed the midpoint check.
    @MainActor
    static func waitForTrailingPane(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        var last: CGRect?
        repeat {
            let frame = trailingPane(app)
            if let frame, let last, abs(frame.minX - last.minX) < 0.5 { return true }
            last = frame
            Thread.sleep(forTimeInterval: 0.4)
        } while Date.now < deadline
        return last != nil
    }

    /// A slow vertical drag between two screen points (no flick momentum).
    @MainActor
    static func slowDrag(_ app: XCUIApplication, x: CGFloat, fromY: CGFloat, toY: CGFloat) {
        let origin = screenOrigin(app)
        origin.withOffset(CGVector(dx: x, dy: fromY)).press(
            forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: toY)),
            withVelocity: .slow, thenHoldForDuration: 0.2
        )
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Width of the iPhone Duo system vertical bar at the window's trailing edge (inner
    /// display, measured ≈ 80 pt), kept clear of scroll drags.
    static let duoVerticalBarClearance: CGFloat = 96

    /// A drag's x, moved left of the iPhone Duo vertical bar: a drag starting on the bar
    /// pressed its tab buttons (Leaderboards' split row was never opened, Lane A11Y4).
    ///
    /// - Parameters:
    ///   - x: The wanted x in screen points.
    ///   - app: The running app.
    /// - Returns: `x`, or on iPhone Duo at most the window's trailing edge minus the bar.
    @MainActor
    static func dragX(_ x: CGFloat, in app: XCUIApplication) -> CGFloat {
        guard runningOnDuo else { return x }
        return min(x, app.windows.firstMatch.frame.maxX - duoVerticalBarClearance)
    }

    /// The coordinate of screen point (0, 0) for gestures given in screen points.
    ///
    /// On iPhone Duo the app's own coordinates do not land on the inner display (taps and
    /// drags from `app.coordinate` went nowhere, Lane A11Y3), while gestures on an element
    /// do: there the origin is taken from the app window, offset back by the window's
    /// frame. iPad keeps the app's coordinate space.
    ///
    /// - Parameter app: The running app.
    /// - Returns: A coordinate at screen point (0, 0).
    @MainActor
    static func screenOrigin(_ app: XCUIApplication) -> XCUICoordinate {
        guard runningOnDuo else { return app.coordinate(withNormalizedOffset: .zero) }
        let window = app.windows.firstMatch
        let frame = window.frame
        return window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -frame.minX, dy: -frame.minY))
    }

    /// Open a split page's trailing pane from a row (an identifier, or the first row
    /// whose identifier has `prefix`), scrolling the page with slow drags until the row
    /// is on screen. Programmatic taps on offscreen rows stall the main thread
    /// (`xcuitest.md` pitfalls).
    ///
    /// - Returns: `fst.split.opened` (a marker ``reachWithProof`` accepts) once the
    ///   trailing pane shows, else nil.
    @MainActor
    static func openSplit(_ app: XCUIApplication, ids: [String] = [], prefix: String? = nil) -> String? {
        func row() -> XCUIElement {
            if let prefix {
                return app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
            }
            for id in ids where anyElement(app, id).exists { return anyElement(app, id) }
            return anyElement(app, ids.first ?? "")
        }
        _ = row().waitForExistence(timeout: 15)
        let window = app.windows.firstMatch.frame
        for attempt in 0..<12 {
            let element = row()
            if element.exists, element.isHittable, window.insetBy(dx: 0, dy: 80).contains(
                CGPoint(x: element.frame.midX, y: element.frame.midY)
            ) {
                element.tap()
                return waitForTrailingPane(app) ? "fst.split.opened" : nil
            }
            // Screen points from the window frame: normalized app coordinates stay in the
            // portrait frame in a landscape window, so the drag ran sideways.
            // Song Detail ignores these drags in landscape (its score-history chart spans
            // the page and takes them as bar selection); XCUITest's own scroll-to-tap
            // reaches the row there (as `IPadShellJourneyTests` does).
            if attempt >= 4, element.exists {
                element.tap()
                return waitForTrailingPane(app) ? "fst.split.opened" : nil
            }
            // The trailing margin: a drag that starts on a chart selects a bar.
            slowDrag(app, x: dragX(window.maxX - 10, in: app), fromY: window.minY + window.height * 0.75,
                     toY: window.minY + window.height * 0.35)
        }
        return nil
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
}
