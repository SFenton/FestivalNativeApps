import UIKit
import XCTest

// MARK: - Scroll-edge fades, accessibility (issue #462, backfilling #308)

/// The regions #308 moved onto the canonical scroll-edge fades, as VoiceOver, Dynamic Type and
/// the hit-tester see them on iPhone, iPad and the iPhone Duo's windows.
///
/// - **Sheet header** (`scroll-edge` R1, R5): the Notifications sheet is a real `FestivalModal`
///   (`ModalTopEdgeFade` under its inline title) whose "New"/"Older" titles pin through
///   `PinnedHeaderEdgeFade`. The title, Close, each heading (header trait) and each row read in
///   that order; Close is a named, enabled 44×44 pt target; rows scroll under the pinned title
///   while it stays wholly below the sheet header.
/// - **Boards** (R9): Song Leaderboard, Full Rankings, Band Rankings, the band song leaderboard
///   and Player Bands fade above their pager through `BottomChromeFade`. Rows read in rank order
///   and all before the pager; the pager reads First, Previous, Page, Next, Last with page 1's
///   enabled state; each control is a 44 pt target that stays hittable once rows scroll under
///   it; and at the end of the page the last row rests wholly above the pager.
/// - **R7 hard edge**: each region is relaunched at the largest accessibility text size (AX5)
///   with the in-app Less Transparency and Increase Contrast on, which turn every ramp into a
///   hard edge. A scoped `performAccessibilityAudit` then accepts *no* contrast issue in the
///   region; at the standard size (ramps on) it accepts one only for text inside a 40 pt fade
///   band, where the dimming is the design (`.agents/patterns/scroll-edge.md` R2).
/// - **iPhone Duo**: the Debug `FST_DEBUG_DUO_WINDOW_REMOTE` switch simulates the folded and
///   unfolded windows (size classes, hinge, vertical bar) on any iPhone simulator, so the
///   fades' consumers are checked in each Duo form `apple-ci` can run. This is layout and
///   accessibility evidence, not an inner-display capture (that needs the Duo simulator).
///
/// macOS hosting cannot scale text or present the iOS sheet header; the hosted
/// `FestivalUITests/ScrollEdgeFadeAccessibilityTests` cover the same regions on macOS.
///
/// Needs the padded fixture service (boards span two or more pages), started from this
/// revision; each test skips without it, and `apple-ci` fails a skipped journey:
///
///     python3 tools/mock_service.py --large-rankings --port 8766
///
/// `FST_SCROLL_EDGE_FIXTURE_URL` points a local run at another origin. Waits use
/// `FestivalApp.budget(_:)` for the runner (`testing/apple/xcuitest.md#ci-journeys`).
///
/// HIG Accessibility: "a default control size of 44x44 pt"; "offer text enlargement of at least
/// 200%"; "Reduce Transparency" and "Increase Contrast" replace translucent effects with
/// opaque ones. HIG Scroll views: "help people understand where content ends".
final class ScrollEdgeFadeAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_SCROLL_EDGE_FIXTURE_URL"]
        ?? "http://127.0.0.1:8766"

    /// Height of every scroll-edge ramp (`ScrollEdgeFade.distance` / `topDistance`).
    private static let fadeBand: CGFloat = 40

    /// Minimum control size (HIG Accessibility), with half a point of layout rounding.
    private static let minimumTarget: CGFloat = 44 - 0.5

    // MARK: - Forms

    /// Text size and transparency for one launch.
    private enum Presentation: String {
        /// Default text size, ramps on.
        case standard
        /// AX5 text with Less Transparency and Increase Contrast: every ramp is a hard edge (R7).
        case largestHardEdge

        /// Launch arguments for this presentation.
        var arguments: [String] {
            switch self {
            case .standard:
                ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
            case .largestHardEdge:
                ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
                 "-fst.accessibility.lessTransparency", "YES",
                 "-fst.accessibility.moreContrast", "YES"]
            }
        }

        /// Whether the ramps are hard edges, so no contrast issue is accepted.
        var hardEdge: Bool { self == .largestHardEdge }
    }

    /// Every R9 board: a list that fades above its floating pager.
    private enum Board: String, CaseIterable {
        case songLeaderboard, fullRankings, bandRankings, songBand, playerBands

        /// Debug launch hooks that open page 1 of the board with no player selected.
        var environment: [String: String] {
            switch self {
            case .songLeaderboard: ["FST_DEBUG_SONG": "fixture-pulse", "FST_DEBUG_SONG_INSTRUMENT": "Solo_Guitar"]
            case .fullRankings: ["FST_DEBUG_ROUTE": "fullRankings:Solo_Guitar"]
            case .bandRankings: ["FST_DEBUG_ROUTE": "bandRankings:Band_Duets"]
            case .songBand: ["FST_DEBUG_SONG": "fixture-pulse", "FST_DEBUG_SONG_BAND": "Band_Duets"]
            case .playerBands: ["FST_DEBUG_ROUTE": "playerBands:fixture-player-1"]
            }
        }

        /// Identifier prefix of a ranked row.
        var rowPrefix: String {
            switch self {
            case .songLeaderboard: "fst.song-leaderboard.row."
            case .fullRankings: "fst.rankings.row."
            case .bandRankings: "fst.band-rankings.row."
            case .songBand: "fst.song-band-leaderboard.row."
            case .playerBands: "fst.player-bands.row."
            }
        }

        /// Identifier prefix of the pager's controls.
        var pagerPrefix: String {
            switch self {
            case .songLeaderboard: "fst.song-leaderboard"
            case .fullRankings: "fst.full-rankings"
            case .bandRankings: "fst.band-rankings"
            case .songBand: "fst.song-band-leaderboard"
            case .playerBands: "fst.player-bands"
            }
        }

        /// Whether row identifiers end in their rank (Player Bands' end in a band ID).
        var identifiersCarryRank: Bool { self != .playerBands }
    }

    /// Pager controls in reading order, with their spoken names (case-insensitive: the
    /// in-content pager says "First page", the floating glass pager "First Page").
    private static let pagerControls: [(id: String, name: String)] = [
        ("page-first", "first page"), ("page-previous", "previous page"), ("page-info", "page"),
        ("page-next", "next page"), ("page-last", "last page"),
    ]

    // MARK: - Sheet header and pinned titles

    /// Notifications at the default size: header, headings and rows read in order with their
    /// traits, Close is a 44 pt target, and only text in a fade band may fail contrast.
    @MainActor
    func testNotificationsSheetHeaderAndPinnedTitlesAreAccessible() throws {
        try requireFixture()
        let app = launchNotifications(.standard)
        assertNotificationsSheet(in: app, presentation: .standard, form: "iOS standard")
    }

    /// Notifications at AX5 with the hard edge: the same order and targets, the pinned title
    /// stays whole below the header as rows scroll under it, and no contrast issue remains.
    @MainActor
    func testNotificationsSheetAtLargestTextWithHardEdge() throws {
        try requireFixture()
        let app = launchNotifications(.largestHardEdge)
        assertNotificationsSheet(in: app, presentation: .largestHardEdge, form: "iOS AX5 hard edge")
    }

    // MARK: - Boards (R9)

    /// Song Leaderboard (solo) at AX5 with the hard edge.
    @MainActor
    func testSongLeaderboardFadeKeepsRowsAndPagerAccessible() throws {
        try assertBoardJourney(.songLeaderboard)
    }

    /// Full Rankings at AX5 with the hard edge.
    @MainActor
    func testFullRankingsFadeKeepsRowsAndPagerAccessible() throws {
        try assertBoardJourney(.fullRankings)
    }

    /// Band Rankings (floating glass pager) at AX5 with the hard edge.
    @MainActor
    func testBandRankingsFadeKeepsRowsAndPagerAccessible() throws {
        try assertBoardJourney(.bandRankings)
    }

    /// The band song leaderboard at AX5 with the hard edge.
    @MainActor
    func testSongBandLeaderboardFadeKeepsRowsAndPagerAccessible() throws {
        try assertBoardJourney(.songBand)
    }

    /// Player Bands at AX5 with the hard edge.
    @MainActor
    func testPlayerBandsFadeKeepsRowsAndPagerAccessible() throws {
        try assertBoardJourney(.playerBands)
    }

    // MARK: - iPhone Duo windows

    /// Band Rankings (the glass pager, which the vertical-bar chrome shows alone) and Song
    /// Leaderboard (the in-content pager, which moves beside the hinge when unfolded), with the
    /// ramps on, in the folded window and then each unfolded window.
    @MainActor
    func testBoardFadesInDuoWindows() throws {
        try requireFixture()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "Duo windows are simulated on an iPhone")
        for board in [Board.bandRankings, .songLeaderboard] {
            let app = launch(board.environment.merging(duoEnvironment("folded")) { $1 }, .standard)
            for window in ["folded", "unfolded-landscape", "unfolded-portrait"] {
                if window != "folded" { DuoWindowSwitch.post(window) }
                waitForDuoWindow(window, in: app)
                // The board keeps its scroll position across window changes.
                assertBoard(board, in: app, presentation: .standard, form: "Duo \(window)", atTop: window == "folded")
            }
            app.terminate()
        }
    }

    /// The Notifications sheet in the folded and unfolded-landscape Duo windows, ramps on.
    @MainActor
    func testNotificationsSheetInDuoWindows() throws {
        try requireFixture()
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "Duo windows are simulated on an iPhone")
        for window in ["folded", "unfolded-landscape"] {
            let app = launchNotifications(.standard, extra: duoEnvironment(window))
            waitForDuoWindow(window, in: app)
            assertNotificationsSheet(in: app, presentation: .standard, form: "Duo \(window)")
            app.terminate()
        }
    }

    // MARK: - Board assertions

    /// Launch `board` at AX5 with the hard edge and assert its accessibility.
    ///
    /// - Parameter board: The board to open.
    /// - Throws: A skip when the fixture service is down.
    @MainActor
    private func assertBoardJourney(_ board: Board) throws {
        try requireFixture()
        let app = launch(board.environment, .largestHardEdge)
        assertBoard(board, in: app, presentation: .largestHardEdge, form: "iOS AX5 hard edge")
    }

    /// Assert the board's rows and pager: names, state, order, targets, the protected pager
    /// area once rows scroll under it, and a scoped audit.
    ///
    /// - Parameters:
    ///   - board: The open board.
    ///   - app: The running app showing page 1 of `board`.
    ///   - presentation: The launch's text size and transparency.
    ///   - form: Label for failure messages and attachments.
    ///   - atTop: Whether the board is freshly loaded, so its first row is rank 1.
    @MainActor
    private func assertBoard(
        _ board: Board, in app: XCUIApplication, presentation: Presentation, form: String, atTop: Bool = true
    ) {
        let context = "\(board.rawValue) (\(form))"
        let info = app.descendants(matching: .any).matching(identifier: "\(board.pagerPrefix).page-info").firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: FestivalApp.budget(30)), "\(context): pager shown")
        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", board.rowPrefix)).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: FestivalApp.budget(30)), "\(context): rows loaded")
        settle()
        record(app, name: "scroll-edge-\(board.rawValue)-\(form)-loaded")

        // Names, roles and state.
        var nodes = Self.nodes(in: app)
        let pager = Self.pagerNodes(board, in: nodes)
        XCTAssertEqual(pager.map(\.id), Self.pagerControls.map { "\(board.pagerPrefix).\($0.id)" },
                       "\(context): pager reads First, Previous, Page, Next, Last")
        XCTAssertEqual(pager.map { $0.label.lowercased() }, Self.pagerControls.map(\.name),
                       "\(context): pager names")
        if pager.count == Self.pagerControls.count {
            XCTAssertEqual(pager.map(\.enabled), [false, false, true, true, true],
                           "\(context): page 1 disables First and Previous only")
            XCTAssertTrue(pager[2].value.hasPrefix("1 of "), "\(context): page badge value '\(pager[2].value)'")
            for control in pager where control.id.hasSuffix("page-info") == false {
                XCTAssertEqual(control.type, .button, "\(context): \(control.id) is a button")
                XCTAssertGreaterThanOrEqual(control.frame.width, Self.minimumTarget, "\(context): \(control.id) width \(control.frame)")
            }
            for control in pager {
                XCTAssertGreaterThanOrEqual(control.frame.height, Self.minimumTarget, "\(context): \(control.id) height \(control.frame)")
            }
        }

        // Reading order: rows in rank order, all before the pager.
        // At AX5 a song's header can leave room for one row; scrolling (below) reaches more.
        let rows = Self.rowNodes(board, in: nodes)
        XCTAssertGreaterThanOrEqual(rows.count, 1, "\(context): rows in the tree")
        XCTAssertTrue(rows.allSatisfy { !$0.name.isEmpty }, "\(context): every row is named \(rows.map(\.id))")
        if let lastRow = rows.last?.index, let firstControl = pager.first?.index {
            XCTAssertLessThan(lastRow, firstControl, "\(context): rows read before the pager")
        }
        let window = app.windows.firstMatch.frame
        for row in rows.prefix(3) {
            XCTAssertGreaterThanOrEqual(row.frame.minX, window.minX - 0.5, "\(context): \(row.id) fits the window width (\(row.frame) in \(window))")
            XCTAssertLessThanOrEqual(row.frame.maxX, window.maxX + 0.5, "\(context): \(row.id) fits the window width (\(row.frame) in \(window))")
        }
        if board.identifiersCarryRank {
            let ranks = rows.compactMap { Self.trailingRank($0.id) }
            XCTAssertEqual(ranks, ranks.sorted(), "\(context): rows read in rank order")
            if atTop { XCTAssertEqual(ranks.first, 1, "\(context): page 1 starts at rank 1") }
        }

        // Scroll to the end of page 1: rows pass under the pager and the last rests above it.
        let restingPagerTop = pager.map(\.frame.minY).min() ?? window.maxY
        let listTop = rows.first.map { max($0.frame.minY, window.minY) } ?? window.minY
        scrollToEnd(board, in: app, region: listTop ... restingPagerTop)
        nodes = Self.nodes(in: app)
        let settledPager = Self.pagerNodes(board, in: nodes)
        let pagerTop = settledPager.map(\.frame.minY).min() ?? .greatestFiniteMagnitude
        let onScreen = Self.rowNodes(board, in: nodes).filter { $0.frame.minY < window.maxY && $0.frame.maxY > window.minY }
        XCTAssertTrue(onScreen.allSatisfy { !$0.name.isEmpty }, "\(context): scrolled rows are named")
        if board.identifiersCarryRank {
            let ranks = onScreen.compactMap { Self.trailingRank($0.id) }
            XCTAssertEqual(ranks, ranks.sorted(), "\(context): scrolled rows read in rank order")
            // A wide two-column board can show the whole page at rest, so "no earlier" suffices.
            XCTAssertGreaterThanOrEqual(ranks.last ?? 0, rows.compactMap { Self.trailingRank($0.id) }.last ?? 0,
                                        "\(context): scrolling reached the page's later ranks")
        }
        if let last = onScreen.max(by: { $0.frame.minY < $1.frame.minY }) {
            XCTAssertLessThanOrEqual(last.frame.maxY, pagerTop + 0.5,
                                     "\(context): the last row \(last.id) rests above the pager (\(last.frame) vs top \(pagerTop))")
        }
        for id in ["page-info", "page-next", "page-last"] {
            let control = app.descendants(matching: .any).matching(identifier: "\(board.pagerPrefix).\(id)").firstMatch
            XCTAssertTrue(control.isHittable, "\(context): \(id) stays the hit target over scrolled rows")
        }
        record(app, name: "scroll-edge-\(board.rawValue)-\(form)")

        audit(app, presentation: presentation, context: context, fadeBand: pagerTop - Self.fadeBand ... pagerTop) { id, _ in
            id.hasPrefix(board.rowPrefix) || id.hasPrefix(board.pagerPrefix + ".page-")
        }
    }

    /// Fling the list until page 1's rows stop moving (its end).
    ///
    /// - Parameters:
    ///   - board: The open board.
    ///   - app: The running app.
    ///   - region: The list's visible span at rest, between the page header and the pager:
    ///     drags start and end inside it so they never press the pager or the navigation bar.
    @MainActor
    private func scrollToEnd(_ board: Board, in app: XCUIApplication, region: ClosedRange<CGFloat>) {
        let window = app.windows.firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let inset = min(12, (region.upperBound - region.lowerBound) / 4)
        var previous: [String: CGRect] = [:]
        for _ in 0..<30 {
            let start = origin.withOffset(CGVector(dx: window.midX, dy: region.upperBound - inset))
            let end = origin.withOffset(CGVector(dx: window.midX, dy: region.lowerBound + inset))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
            settle(0.6)
            let rows = Self.rowNodes(board, in: Self.nodes(in: app))
            let frames = Dictionary(rows.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
            if !frames.isEmpty, frames == previous { return }
            previous = frames
        }
    }

    // MARK: - Sheet assertions

    /// Launch with `fixture-player-1` selected and its feed split into "New" (notif-1) and
    /// "Older" (notif-2, seeded seen through the launch-argument defaults domain), then open
    /// the sheet from the bell.
    ///
    /// - Parameters:
    ///   - presentation: Text size and transparency.
    ///   - extra: More launch environment (Duo windows).
    /// - Returns: The app with the sheet's rows on screen.
    @MainActor
    private func launchNotifications(_ presentation: Presentation, extra: [String: String] = [:]) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ].merging(extra) { $1 })
        app.launchArguments += presentation.arguments
        app.launchArguments += ["-fst.notifications.seen", "{ \"fixture-player-1\" = ( \"fixture-notif-2\" ); }"]
        app.launch()
        XCTAssertTrue(app.buttons["fst.shell.notifications"].waitForExistence(timeout: FestivalApp.budget(30)), "bell shown")
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        XCTAssertTrue(app.buttons["fst.notifications.row.fixture-notif-1"].waitForExistence(timeout: FestivalApp.budget(20)),
                      "sheet rows loaded")
        settle(1)
        return app
    }

    /// Assert the sheet's header, pinned titles and rows.
    ///
    /// - Parameters:
    ///   - app: The running app showing the sheet.
    ///   - presentation: The launch's text size and transparency.
    ///   - form: Label for failure messages and attachments.
    @MainActor
    private func assertNotificationsSheet(in app: XCUIApplication, presentation: Presentation, form: String) {
        let context = "Notifications (\(form))"
        let close = app.buttons["fst.notifications.close"]
        XCTAssertTrue(close.waitForExistence(timeout: FestivalApp.budget(10)), "\(context): Close shown")
        XCTAssertFalse(close.label.isEmpty, "\(context): Close is named")
        XCTAssertTrue(close.isEnabled, "\(context): Close is enabled")
        XCTAssertTrue(close.isHittable, "\(context): Close is reachable")
        let bar = app.navigationBars["Notifications"]
        XCTAssertTrue(bar.exists, "\(context): the sheet header names the sheet")
        let header = bar.frame

        // Reading order inside the sheet: title, Close, New, its row, Older, its row. At AX5
        // the second section can start below the fold (a lazy list has no node for it yet),
        // so the rest of the order is read again after scrolling it into view.
        let markers: [(String, (Node) -> Bool)] = [
            ("title", { $0.type == .navigationBar && $0.id == "Notifications" }),
            ("Close", { $0.id == "fst.notifications.close" }),
            ("New", { $0.type == .staticText && $0.label == "New" }),
            ("row 1", { $0.id == "fst.notifications.row.fixture-notif-1" }),
            ("Older", { $0.type == .staticText && $0.label == "Older" }),
            ("row 2", { $0.id == "fst.notifications.row.fixture-notif-2" }),
        ]
        var nodes = sheetNodes(in: app)
        var positions = markers.map { marker in nodes.firstIndex(where: marker.1) }
        let atRest = positions.prefix(4)
        XCTAssertFalse(atRest.contains(nil),
                       "\(context): \(zip(markers, atRest).filter { $1 == nil }.map(\.0.0)) missing from the sheet")
        let restOrder = atRest.compactMap { $0 }
        XCTAssertEqual(restOrder, restOrder.sorted(), "\(context): reads title, Close, New, then its row")
        let window = app.windows.firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        // Drag inside the sheet: on iPad it is a centred form sheet shorter than the window.
        let sheetFrame = nodes.first?.frame ?? window
        let revealStart = min(sheetFrame.maxY, window.maxY) - 120
        var reveals = 0
        while positions.suffix(2).contains(nil), reveals < 6 {
            origin.withOffset(CGVector(dx: sheetFrame.midX, dy: revealStart))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: sheetFrame.midX, dy: header.maxY + 120)),
                       withVelocity: .slow, thenHoldForDuration: FestivalApp.budget(0.3))
            settle(0.6)
            nodes = sheetNodes(in: app)
            positions = markers.map { marker in nodes.firstIndex(where: marker.1) }
            reveals += 1
        }
        XCTAssertFalse(positions.suffix(2).contains(nil), "\(context): Older and its row reachable by scrolling")
        if reveals == 0 {
            let found = positions.compactMap { $0 }
            XCTAssertEqual(found, found.sorted(), "\(context): reads title, Close, New, row, Older, row")
        } else if let close = positions[1], let older = positions[4], let row2 = positions[5] {
            // Scrolled, UIKit reads a floating section header (here the pinned "New") after
            // the rows it floats over, as macOS does at rest; the next section keeps its order.
            XCTAssertLessThan(close, older, "\(context): Close reads before Older")
            XCTAssertLessThan(older, row2, "\(context): Older reads before its row")
        }
        for title in ["New", "Older"] {
            if let node = nodes.first(where: { $0.type == .staticText && $0.label == title }), let traits = node.traits {
                XCTAssertNotEqual(traits & UIAccessibilityTraits.header.rawValue, 0, "\(context): '\(title)' is a heading")
            }
        }
        // The list cell can carry the row's identifier too; the row VoiceOver reads is its button.
        for id in ["fst.notifications.row.fixture-notif-1", "fst.notifications.row.fixture-notif-2"] {
            let row = nodes.first { $0.id == id && $0.type == .button }
                ?? Self.nodes(in: app).first { $0.id == id && $0.type == .button }
            XCTAssertNotNil(row, "\(context): \(id) is a button")
            if let row {
                XCTAssertFalse(row.label.isEmpty, "\(context): \(id) is named")
                XCTAssertGreaterThanOrEqual(row.frame.height, Self.minimumTarget, "\(context): \(id) height \(row.frame)")
            }
        }

        // Rows scroll under the pinned title; it stays whole below the header.
        let row1 = app.buttons["fst.notifications.row.fixture-notif-1"]
        let before = row1.exists ? row1.frame : .null
        let startY = min(min(sheetFrame.maxY, window.maxY) - 80, header.maxY + 280)
        origin.withOffset(CGVector(dx: sheetFrame.midX, dy: startY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: sheetFrame.midX, dy: header.maxY + 60)),
                   withVelocity: .slow, thenHoldForDuration: FestivalApp.budget(0.5))
        settle(0.8)
        let pinned = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["New", "Older"]))
            .allElementsBoundByIndex.filter { $0.exists && $0.frame.minY < window.maxY && $0.frame.maxY > header.maxY }
            .min { $0.frame.minY < $1.frame.minY }
        if let pinned {
            XCTAssertGreaterThanOrEqual(pinned.frame.minY, header.maxY - 0.5,
                                        "\(context): the pinned '\(pinned.label)' stays below the sheet header (\(pinned.frame) vs \(header))")
        } else if row1.exists, !before.isNull, row1.frame.minY < before.minY - 1 {
            XCTFail("\(context): no section title visible after scrolling rows under it")
        }
        XCTAssertTrue(close.isHittable, "\(context): Close stays reachable over scrolled rows")
        record(app, name: "scroll-edge-notifications-\(form)")

        let fadeTop = header.maxY
        audit(app, presentation: presentation, context: context, fadeBand: fadeTop ... fadeTop + 2 * Self.fadeBand + 48) { id, label in
            id.hasPrefix("fst.notifications.") || ["New", "Older", "Notifications"].contains(label)
        }

        // The system Close (`Button(role: .close)`) draws a 36 pt glass circle whose hit region
        // is the bar's 44 pt: a press 21 pt below its centre (inside 44×44, outside the circle,
        // toward the rows) still closes the sheet (the probe `modal-shell` R3 uses on Windows).
        let frame = close.frame
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: 21)).tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: FestivalApp.budget(10)),
                      "\(context): a press 21 pt below Close's centre (\(frame)) closes the sheet: a 44 pt target")
    }

    /// The sheet's subtree (from the header down) in reading order: the deepest element
    /// holding both Close and the first row, so the page behind the sheet is left out.
    ///
    /// - Parameter app: The running app showing the sheet.
    /// - Returns: The sheet's nodes, or none when it is not in the snapshot.
    @MainActor
    private func sheetNodes(in app: XCUIApplication) -> [Node] {
        guard let snapshot = try? app.snapshot(),
              let sheet = Self.commonAncestor(of: ["fst.notifications.close", "fst.notifications.row.fixture-notif-1"], in: snapshot)
                ?? Self.commonAncestor(of: ["fst.notifications.close", "fst.notifications.row.fixture-notif-2"], in: snapshot)
        else { return [] }
        return Self.flatten(sheet)
    }

    // MARK: - Audit

    /// Run a scoped accessibility audit and fail on the region's issues.
    ///
    /// Contrast is accepted only at the standard size for an element that overlaps
    /// `fadeBand` (a ramp dims it by design, R2); with the hard edge (R7) none is accepted.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - presentation: The launch's text size and transparency.
    ///   - context: Label for failure messages.
    ///   - fadeBand: Vertical span, in window points, where a ramp may dim text.
    ///   - inRegion: Whether an issue's element (identifier, label) belongs to the region.
    @MainActor
    private func audit(
        _ app: XCUIApplication, presentation: Presentation, context: String,
        fadeBand: ClosedRange<CGFloat>, inRegion: @escaping (String, String) -> Bool
    ) {
        var failures: [String] = []
        var seen: [String] = []
        do {
            try app.performAccessibilityAudit(
                for: [.contrast, .dynamicType, .hitRegion, .sufficientElementDescription, .textClipped]
            ) { issue in
                let id = issue.element?.identifier ?? ""
                let label = issue.element?.label ?? ""
                seen.append("\(issue.auditType.rawValue) \(id) '\(label)': \(issue.compactDescription)")
                guard inRegion(id, label) else { return true }
                if issue.auditType == .contrast, !presentation.hardEdge, let frame = issue.element?.frame,
                   frame.maxY >= fadeBand.lowerBound, frame.minY <= fadeBand.upperBound {
                    return true
                }
                failures.append("\(id) '\(label)': \(issue.compactDescription)")
                return true
            }
        } catch {
            XCTFail("\(context): audit did not run: \(error)")
        }
        attach("audit-\(context)", seen.joined(separator: "\n"))
        XCTAssertEqual(failures, [], "\(context): accessibility audit issues")
    }

    // MARK: - Launch

    /// Skip unless the padded fixture service answers its publication read.
    private func requireFixture() throws {
        continueAfterFailure = false
        let url = try XCTUnwrap(URL(string: "\(Self.origin)/api/publication"))
        let done = expectation(description: "fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --large-rankings --port 8766` from this revision")
    }

    /// Launch the app against the fixture with `presentation`.
    ///
    /// - Parameters:
    ///   - environment: Debug launch hooks for the page.
    ///   - presentation: Text size and transparency.
    /// - Returns: The launched app.
    @MainActor
    private func launch(_ environment: [String: String], _ presentation: Presentation) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ].merging(environment) { $1 })
        app.launchArguments += presentation.arguments
        app.launch()
        return app
    }

    /// Launch environment that simulates a Duo window from the start.
    ///
    /// - Parameter window: `DebugDuoWindow` raw value.
    /// - Returns: The Debug switch entries.
    private func duoEnvironment(_ window: String) -> [String: String] {
        ["FST_DEBUG_DUO_WINDOW_REMOTE": "1", "FST_DEBUG_DUO_WINDOW": window]
    }

    /// Wait until the app reports the simulated Duo window (`fst.shell.debug.duo-window`).
    ///
    /// - Parameters:
    ///   - window: Expected `DebugDuoWindow` raw value.
    ///   - app: The running app.
    @MainActor
    private func waitForDuoWindow(_ window: String, in app: XCUIApplication) {
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let reached = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "\(window) "), object: readout)
        XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(15)), .completed,
                       "The app never simulated \(window): \(readout.exists ? readout.label : "no readout")")
        settle(1)
    }

    /// Let an animation or layout pass finish.
    ///
    /// - Parameter seconds: Settle time on a physical Mac.
    private func settle(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(seconds)))
    }

    // MARK: - Snapshot helpers

    /// One accessibility element as the snapshot reports it, with its depth-first position.
    private struct Node {
        let index: Int
        let id: String
        let label: String
        /// The label, or for a `.contain` container (a row card) its descendants' labels:
        /// what VoiceOver reads for the row.
        let name: String
        let value: String
        let type: XCUIElement.ElementType
        let frame: CGRect
        let enabled: Bool
        let traits: UInt64?
    }

    /// The whole app's elements in reading (depth-first) order.
    @MainActor
    private static func nodes(in app: XCUIApplication) -> [Node] {
        guard let snapshot = try? app.snapshot() else { return [] }
        return flatten(snapshot)
    }

    /// `root`'s subtree in depth-first order.
    @MainActor
    private static func flatten(_ root: XCUIElementSnapshot) -> [Node] {
        var nodes: [Node] = []
        func spoken(_ snapshot: XCUIElementSnapshot) -> [String] {
            snapshot.label.isEmpty ? snapshot.children.flatMap(spoken) : [snapshot.label]
        }
        func visit(_ snapshot: XCUIElementSnapshot) {
            nodes.append(Node(
                index: nodes.count, id: snapshot.identifier, label: snapshot.label,
                name: spoken(snapshot).joined(separator: ", "),
                value: (snapshot.value as? String) ?? "", type: snapshot.elementType, frame: snapshot.frame,
                enabled: snapshot.isEnabled, traits: traits(snapshot)
            ))
            snapshot.children.forEach(visit)
        }
        visit(root)
        return nodes
    }

    /// The board's pager controls, first occurrence of each identifier, in reading order.
    private static func pagerNodes(_ board: Board, in nodes: [Node]) -> [Node] {
        let ids = Set(pagerControls.map { "\(board.pagerPrefix).\($0.id)" })
        return unique(nodes.filter { ids.contains($0.id) })
    }

    /// The board's ranked rows, first occurrence of each identifier, in reading order.
    private static func rowNodes(_ board: Board, in nodes: [Node]) -> [Node] {
        unique(nodes.filter { $0.id.hasPrefix(board.rowPrefix) })
    }

    /// Keep the first (outermost) node of each identifier: SwiftUI can nest an element with
    /// the same one inside a row's container; ``Node/name`` reads through to it.
    private static func unique(_ nodes: [Node]) -> [Node] {
        var seen = Set<String>()
        return nodes.filter { seen.insert($0.id).inserted }
    }

    /// The deepest snapshot whose subtree holds every identifier in `ids`.
    @MainActor
    private static func commonAncestor(of ids: [String], in root: XCUIElementSnapshot) -> XCUIElementSnapshot? {
        func holds(_ snapshot: XCUIElementSnapshot) -> Set<String> {
            var found: Set<String> = ids.contains(snapshot.identifier) ? [snapshot.identifier] : []
            for child in snapshot.children { found.formUnion(holds(child)) }
            return found
        }
        guard holds(root).count == ids.count else { return nil }
        for child in root.children {
            if let deeper = commonAncestor(of: ids, in: child) { return deeper }
        }
        return root
    }

    /// The rank a row identifier ends in (`…fixture-team-12`, `…fixture-band-3:3`).
    private static func trailingRank(_ id: String) -> Int? {
        let digits = id.reversed().prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(String(digits.reversed()))
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
        let attachment = XCTAttachment(screenshot: app.screenshot())
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
