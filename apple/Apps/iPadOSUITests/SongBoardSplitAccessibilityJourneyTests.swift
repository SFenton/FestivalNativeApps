import XCTest

/// The Song Leaderboard opened in the split's trailing pane beside Song Detail, on device
/// at the default text size and at AX5 (issue #478, the region #342 changed): the pane is
/// titled by its chart (`fst.song-leaderboard.board-title`, ``InstrumentPageTitle``)
/// instead of a second song header. Each launch checks that the title is a heading named
/// by the chart, never the song; that VoiceOver focus moves to it when the pane opens;
/// that it reads before the board's rows and stays inside the pane; and that it is drawn
/// whole (Vision, ``RecognizedText``), with glyphs at least 1.35× taller at AX5 than at
/// the default size (`.agents/testing/apple/accessibility.md`).
///
/// iPad landscape, and the iPhone Duo in a pose whose window splits (run with
/// `ios_sim.py uitest --device duo --app ipad` after `pose --set open`; a pose that
/// cannot split skips). The hosted `SplitBoardTitleAccessibilityTests` pin the same
/// title's name, order and narrow-pane wrapping on every Apple split, including the Mac.
/// Fixture-backed: `fixture-pulse` Lead (127.0.0.1:8765 or the runner's `FST_FIXTURE_URL`).
final class SongBoardSplitAccessibilityJourneyTests: XCTestCase {
    private typealias Audit = IPadAccessibilityAuditTests

    static let titleID = "fst.song-leaderboard.board-title"
    static let songTitle = "Fixture Pulse"
    static let chart = "Lead"

    private var isPad: Bool { MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad } }

    override func setUpWithError() throws {
        try XCTSkipUnless(isPad || Audit.runningOnDuo, "the split needs an iPad or iPhone Duo window")
        continueAfterFailure = true
    }

    override func tearDown() {
        guard isPad, !Audit.runningOnDuo else { return }
        MainActor.assumeIsolated {
            let app = FestivalApp.makeApp()
            if app.state == .runningForeground { WindowResize.fill(app) }
            XCUIDevice.shared.orientation = .portrait
        }
    }

    // MARK: - Journey

    /// The trailing pane's title at the default size and at AX5, then its glyphs' growth.
    @MainActor
    func testSongBoardSplitTitleAtAX5() throws {
        if !Audit.runningOnDuo { XCUIDevice.shared.orientation = .landscapeLeft }
        var heights: [CGFloat?] = []
        for contentSize in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            heights.append(try measure(contentSize: contentSize, name: contentSize == .large ? "default" : "ax5"))
        }
        if let standard = heights[0], let largest = heights[1] {
            XCTAssertGreaterThanOrEqual(
                largest / standard, RecognizedText.minimumGrowth,
                "the pane's title grows at AX5 (\(standard) → \(largest) pt)"
            )
        } else {
            XCTFail("no whole title to compare (default \(String(describing: heights[0])), AX5 \(String(describing: heights[1])))")
        }
    }

    // MARK: - Verification

    /// One launch: open the board beside Song Detail, then check name, focus, order and
    /// frame, and read the drawn title back.
    ///
    /// - Parameters:
    ///   - contentSize: The launch's preferred content size.
    ///   - name: Label for failures and attachments.
    /// - Returns: The title's recognized line height (points) when drawn whole, else nil.
    @MainActor
    private func measure(contentSize: UIContentSizeCategory, name: String) throws -> CGFloat? {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": IPadShellJourneyTests.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_A11Y_FOCUS_TRACE": "1",
        ])
        app.launchArguments += ["-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
                                "-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        app.launch()
        defer { app.terminate() }
        if !Audit.runningOnDuo { WindowResize.fill(app) }
        XCTAssertTrue(FestivalApp.waitForElement("fst.songs.list", in: app, timeout: FestivalApp.budget(25)), "\(name): Songs")
        guard Audit.openSong(app, "fixture-pulse") else {
            XCTFail("\(name): Song Detail did not open")
            return nil
        }
        let window = app.windows.firstMatch.frame
        if Audit.runningOnDuo, window.width <= window.height {
            throw XCTSkip("this iPhone Duo pose does not split (window \(window))")
        }
        guard window.width > window.height,
              Audit.openSplit(app, ids: ["fst.song-detail.leaderboard.Solo_Guitar"]) != nil,
              let pane = Audit.trailingPane(app) else {
            XCTFail("\(name): the board did not open in the trailing pane (window \(window))")
            return nil
        }
        // After the split opens, every read comes from a retried snapshot and the drawn
        // text from a screen capture: live queries here stalled on the CI runner (#703).
        XCTAssertTrue(FestivalApp.waitForElement(Self.titleID, in: app, timeout: FestivalApp.budget(15)),
                      "\(name): the pane's title")
        let rowPrefix = "fst.song-leaderboard.row."
        func hasRows(_ root: XCUIElementSnapshot) -> Bool {
            !FestivalApp.nodes(in: root) { $0.identifier.hasPrefix(rowPrefix) }.isEmpty
        }
        let shown = try? FestivalApp.snapshot(of: app, within: FestivalApp.budget(15), until: hasRows)
        XCTAssertTrue(shown.map(hasRows) ?? false, "\(name): the board's rows")
        Thread.sleep(forTimeInterval: FestivalApp.budget(2.5)) // staggered row fade-in

        // Focus: VoiceOver moves to the pane's heading (`AccessibilityFocusMove`).
        let focus = waitForFocus(app) { $0.hasPrefix("heading: ") }
        let root = try FestivalApp.snapshot(
            of: app, within: FestivalApp.budget(5), until: { FestivalApp.contains(Self.titleID, in: $0) }
        )
        let title = FestivalApp.node(Self.titleID, in: root)
        let titleLabel = title?.label ?? ""

        // Name: the chart, never the song beside it.
        XCTAssertTrue(titleLabel.hasPrefix(Self.chart), "\(name): named by its chart: '\(titleLabel)'")
        XCTAssertFalse(titleLabel.contains(Self.songTitle), "\(name): the title does not repeat the song: '\(titleLabel)'")
        XCTAssertFalse(FestivalApp.contains("fst.song-leaderboard.header", in: root), "\(name): no repeated song header")
        XCTAssertEqual(focus, "heading: \(titleLabel)", "\(name): focus moves to the pane's title")

        // Order and frames: the heading, then the rows, all inside the pane.
        let nodes = IPadAuditPageEvidence.flatten(root)
        let titleIndex = nodes.firstIndex { $0.identifier == Self.titleID }
        let rows = nodes.indices.filter { nodes[$0].identifier.hasPrefix(rowPrefix) }
        XCTAssertNotNil(titleIndex, "\(name): the title in the tree")
        XCTAssertFalse(rows.isEmpty, "\(name): rows in the tree")
        if let titleIndex {
            if Audit.traitsReadable(nodes) {
                XCTAssertTrue(Audit.isHeader(nodes[titleIndex]), "\(name): the title is a heading")
            }
            XCTAssertTrue(rows.allSatisfy { $0 > titleIndex }, "\(name): the title reads before the rows")
            let frame = nodes[titleIndex].frame
            XCTAssertTrue(
                frame.minX >= pane.minX - 0.5 && frame.maxX <= pane.maxX + 0.5,
                "\(name): the title \(frame) stays inside the pane \(pane)"
            )
        }
        let inPane = nodes.filter { pane.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        XCTAssertFalse(inPane.contains { $0.label.contains(Self.songTitle) },
                       "\(name): nothing in the pane names the song again")

        // Drawn text: the title whole, and its line height for the growth check.
        guard let title else { return nil }
        let (reading, capture) = IPadAuditPageEvidence.reading(
            Self.chart, within: title.frame, landscape: window.width > window.height
        )
        if let capture { attach(capture, name: name) }
        XCTAssertTrue(RecognizedText.showsWhole(Self.chart, in: reading.text),
                      "\(name): the title is drawn whole: '\(reading.text ?? "")'")
        return RecognizedText.showsWhole(Self.chart, in: reading.text) ? reading.lineHeight : nil
    }

    // MARK: - Helpers

    /// The app's last traced VoiceOver focus move once it satisfies `predicate`, read from
    /// retried snapshots (as Score History's journey reads it, #693).
    @MainActor
    private func waitForFocus(_ app: XCUIApplication, timeout: TimeInterval = 6, _ predicate: (String) -> Bool) -> String {
        func focus(_ root: XCUIElementSnapshot) -> String {
            FestivalApp.node("fst.nav.a11y-focus", in: root)?.label ?? ""
        }
        let root = try? FestivalApp.snapshot(of: app, within: FestivalApp.budget(timeout), until: { predicate(focus($0)) })
        return root.map(focus) ?? ""
    }

    /// Keep the title's capture with the run's results.
    @MainActor
    private func attach(_ capture: IPadAuditRenderedContrast.Capture, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: capture.image))
        attachment.name = "song-board-split-title-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
