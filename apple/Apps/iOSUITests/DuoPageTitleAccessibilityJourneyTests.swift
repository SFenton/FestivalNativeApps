import UIKit
import XCTest

// MARK: - Duo page titles at AX5 (issue #341, backfilled by #477)

/// Accessibility evidence for the region #341 changed: every root page keeps its system
/// navigation title beside the iPhone Duo's folded vertical bar (pattern
/// page-tools-and-nav-chrome R14), including Statistics' no-profile state, whose
/// `festivalNavigationTitle("Statistics")` #341 added. `DuoPageTitleJourneyTests` checks the
/// title's presence and width per pose at the default size; this journey checks what VoiceOver
/// and Dynamic Type users get, on a real navigation stack with real Dynamic Type.
///
/// For Songs, Leaderboards, Settings and no-profile Statistics, at AX5 the title must:
/// - be the navigation bar's static text named for the page (the system title VoiceOver
///   announces as the page heading), on screen at the top of the page;
/// - be read before the page's content (the first row, card or setting; Statistics' empty
///   state and its Choose Profile button);
/// - grow (> 1.35× its default-size line height; > 1.05× on the iPhone Duo device type, whose
///   system bar caps it, `system-bar-title-size`) and render whole, never "S…";
/// - pass a scoped audit (Dynamic Type, clipped text, description, contrast).
///
/// Statistics' Choose Profile, the no-profile state's only action, stays named, reachable, at
/// least 44 pt tall and drawn with its whole label at AX5, also under More Contrast (the
/// increased-contrast branch of `festivalProminentButton()`, which painted a blank white capsule
/// until #477).
///
/// The system large title of an iPhone (402 pt) truncates "Leaderboards" at AX5; the simulated
/// folded window keeps that bar, so there it is checked by name, place, order and growth, and
/// drawn whole only on the iPhone Duo device type (iPhone finding, testing/apple/accessibility.md).
///
/// `...DuoFolded` methods simulate the folded window in the real one (`FST_DEBUG_DUO_WINDOW`,
/// `DebugDuoWindow`: size classes and vertical-bar layout), so `apple-ci` runs them on its
/// iPhone; on an iPhone Duo simulator run folded (`ios_sim.py uitest --device duo --pose
/// folded`) they meet the real vertical bar. The plain method checks the device's own pose
/// (the Duo's unfolded inner portrait, horizontal bar, when run `--pose unfolded`).
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_DUO_TITLE_A11Y_FIXTURE_URL` for another mock).
///
/// HIG VoiceOver: "Give each page or screen a unique, succinct title describing its content
/// and purpose"; HIG Typography: "Keep text truncation to a minimum as font size increases";
/// HIG Accessibility: "Strive for the platform's recommended minimum control size" (44×44 pt).
final class DuoPageTitleAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_DUO_TITLE_A11Y_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// A root page, the title it shows and the content read after it.
    private struct Root {
        /// `FST_DEBUG_TAB` value.
        let tab: String
        /// The system navigation title.
        let title: String
        /// Identifier prefix of the page content that must be read after the title.
        let content: String
        /// Extra launch environment.
        var environment: [String: String] = [:]
        /// Whether the iPhone's horizontal large title draws it whole at AX5 (the Duo's vertical
        /// bar must always).
        var wholeOnIPhoneLargeTitle = true
    }

    /// The anonymous roots `DuoPageTitleJourneyTests` covers per pose.
    private static let anonymousRoots = [
        Root(tab: "songs", title: "Songs", content: "fst.songs.row."),
        Root(tab: "leaderboards", title: "Leaderboards", content: "fst.leaderboards.card.",
             wholeOnIPhoneLargeTitle: false),
        Root(tab: "settings", title: "Settings", content: "fst.settings."),
    ]

    /// Statistics' no-profile state, held open with the Debug `FST_DEBUG_KEEP_PROFILE_ROUTES=1`.
    private static let noProfileStatistics = Root(
        tab: "statistics", title: "Statistics", content: "fst.statistics.choose-profile",
        environment: ["FST_DEBUG_KEEP_PROFILE_ROUTES": "1"]
    )

    // MARK: - Journeys

    /// Songs, Leaderboards and Settings beside the folded vertical bar at AX5.
    @MainActor
    func testRootTitlesAreAccessibleAtAX5DuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        for root in Self.anonymousRoots {
            try assertTitleAtAX5(root, duoWindow: "folded")
        }
    }

    /// No-profile Statistics (the title #341 added) beside the folded vertical bar at AX5.
    @MainActor
    func testNoProfileStatisticsTitleIsAccessibleAtAX5DuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertTitleAtAX5(Self.noProfileStatistics, duoWindow: "folded")
    }

    /// No-profile Statistics in the device's own pose at AX5 (horizontal bar on an iPhone or the
    /// unfolded Duo's inner portrait).
    @MainActor
    func testNoProfileStatisticsTitleIsAccessibleAtAX5() throws {
        try assertTitleAtAX5(Self.noProfileStatistics, duoWindow: nil)
    }

    /// No-profile Statistics beside the folded vertical bar at AX5 with the app's More Contrast,
    /// whose white prominent fill needs its dark label.
    @MainActor
    func testNoProfileStatisticsIsAccessibleAtAX5WithMoreContrastDuoFolded() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertTitleAtAX5(Self.noProfileStatistics, duoWindow: "folded", moreContrast: true)
    }

    // MARK: - Assertions

    /// Compare the title at the default size with AX5, then check its name, place, reading
    /// order, scaling and audit (and Statistics' Choose Profile).
    ///
    /// - Parameters:
    ///   - root: The page.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    ///   - moreContrast: Turn on the app's More Contrast (`fst.accessibility.moreContrast`).
    @MainActor
    private func assertTitleAtAX5(_ root: Root, duoWindow: String?, moreContrast: Bool = false) throws {
        continueAfterFailure = false
        let state = "\(root.title) (\(duoWindow ?? "device pose")\(moreContrast ? ", More Contrast" : ""))"
        let standard = try launch(root, size: nil, duoWindow: duoWindow, moreContrast: moreContrast)
        let standardTitle = try title(root, in: standard)
        let standardReading = RecognizedText.recognize(standardTitle, label: root.title, frame: standardTitle.frame)
        let standardHeight = try XCTUnwrap(standardReading.lineHeight,
                                           "\(state): default-size title measured: \(standardReading)")
        standard.terminate()

        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        let app = try launch(root, size: ax5, duoWindow: duoWindow, moreContrast: moreContrast)
        defer { app.terminate() }
        let title = try title(root, in: app)
        let window = app.windows.firstMatch.frame
        let frame = title.frame
        record(app, name: "duo-title-ax5-\(root.tab)-\(duoWindow ?? "device")\(moreContrast ? "-more-contrast" : "")")

        // Name and role: the navigation bar's title text, on screen at the top of the page.
        XCTAssertEqual(title.elementType, .staticText, state)
        XCTAssertEqual(title.label, root.title, state)
        XCTAssertTrue(title.isHittable, "\(state): the title is hidden")
        XCTAssertTrue(window.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(state): title \(frame) leaves \(window)")
        XCTAssertLessThan(frame.minY, window.minY + window.height / 3, "\(state): title \(frame) is not at the top")

        // Reading order: the title is read before the page's content.
        let content = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", root.content)).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: FestivalApp.budget(15)), "\(state): \(root.content) content")
        let order = try FestivalApp.snapshotNodes(in: app) { _ in true }
        let titleIndex = try XCTUnwrap(
            order.firstIndex { $0.elementType == .staticText && $0.label == root.title },
            "\(state): title in the tree"
        )
        let contentIndex = try XCTUnwrap(order.firstIndex { $0.identifier.hasPrefix(root.content) },
                                         "\(state): \(root.content) in the tree")
        XCTAssertLessThan(titleIndex, contentIndex, "\(state): title read before the page content")

        // Text scaling: the title grows and renders whole.
        let reading = RecognizedText.recognize(title, label: root.title, frame: frame)
        XCTContext.runActivity(named: "\(state): recognized '\(reading.text ?? "")' \(reading.lineHeight ?? 0) pt") { _ in }
        if Self.isDuo || root.wholeOnIPhoneLargeTitle {
            XCTAssertTrue(RecognizedText.showsWhole(root.title, in: reading.text),
                          "\(state): title whole: \(reading.text ?? "nil")")
        }
        let height = try XCTUnwrap(reading.lineHeight, "\(state): title measured")
        XCTAssertGreaterThan(height, standardHeight * Self.minimumTitleGrowth,
                             "\(state): title grows at AX5: \(height) pt vs \(standardHeight) pt")

        // Statistics' only action stays named, reachable and a full-size target.
        var scoped: Set<String> = [root.title]
        if root.tab == "statistics" {
            let choose = app.buttons["fst.statistics.choose-profile"]
            XCTAssertEqual(choose.label, "Choose Profile", state)
            if !choose.isHittable { app.swipeUp() }
            XCTAssertTrue(choose.isHittable, "\(state): Choose Profile reachable")
            XCTAssertGreaterThanOrEqual(choose.frame.height, 44 - 1, "\(state): Choose Profile height \(choose.frame)")
            // Drawn, not just named: its label is legible on its fill.
            let drawn = RecognizedText.recognize(choose, label: "Choose Profile", frame: choose.frame)
            XCTAssertTrue(RecognizedText.showsWhole("Choose Profile", in: drawn.text),
                          "\(state): Choose Profile label drawn: \(drawn.text ?? "nothing")")
            scoped.insert(choose.label)
        }

        // Audit the title (and Choose Profile) only: page content has its own journeys.
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .sufficientElementDescription, .contrast]
        try SongsUITestSupport.performAuditRetryingTimeout(app, audit, name: "duo-title-\(root.tab)",
                                                           reset: { issues.removeAll() }) { issue in
            guard let element = issue.element, scoped.contains(element.label) else { return true }
            issues.append("\(element.elementType.rawValue) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "\(state): title audit issues at AX5")
    }

    /// Whether this run is on the iPhone Duo device type (not the `DebugDuoWindow` simulation).
    private static var isDuo: Bool {
        (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo")
    }

    /// Minimum growth of the title's recognized line height from the default size to AX5:
    /// the project's 1.35×, except on the iPhone Duo device type, whose system bar caps its
    /// title (`system-bar-title-size`, testing/apple/accessibility.md; 1.10× folded on iOS 27.1).
    private static var minimumTitleGrowth: CGFloat { isDuo ? 1.05 : RecognizedText.minimumGrowth }

    // MARK: - Launch and queries

    /// Open a root at a text size, anonymous, in the simulated Duo window when given.
    ///
    /// - Parameters:
    ///   - root: The page.
    ///   - size: A `UIContentSizeCategory` raw value; nil keeps the default.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil.
    ///   - moreContrast: Turn on the app's More Contrast.
    /// - Returns: The launched app with the page's title on screen.
    /// - Throws: A skip when the fixture never serves the page.
    @MainActor
    private func launch(_ root: Root, size: String?, duoWindow: String?, moreContrast: Bool) throws -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": Self.origin,
            "FST_DEBUG_ANONYMOUS": "1",
            "FST_DEBUG_TAB": root.tab,
        ]
        environment.merge(root.environment) { _, page in page }
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        }
        let app = FestivalApp.makeApp(environment)
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launchArguments += ["-fst.accessibility.moreContrast", moreContrast ? "YES" : "NO"]
        app.launch()
        if let duoWindow {
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                       "\(duoWindow) ", "chrome=verticalBar"),
                object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(15)), .completed,
                           "The app never simulated \(duoWindow): \(readout.exists ? readout.label : "no readout")")
        }
        let content = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", root.content)).firstMatch
        guard content.waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("\(root.title) never loaded; run tools/mock_service.py --large-catalogue on \(Self.origin).")
        }
        // Let the bar's layout settle before reading pixels.
        sleep(UInt32(FestivalApp.budget(1)))
        return app
    }

    /// The page's title text in its navigation bar.
    ///
    /// - Parameters:
    ///   - root: The page.
    ///   - app: The app on that page.
    /// - Returns: The title element.
    @MainActor
    private func title(_ root: Root, in app: XCUIApplication) throws -> XCUIElement {
        let title = app.navigationBars.staticTexts.matching(NSPredicate(format: "label == %@", root.title)).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(10)),
                      "\(root.title) title missing: \(app.navigationBars.allElementsBoundByIndex.map(\.identifier))")
        return title
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
