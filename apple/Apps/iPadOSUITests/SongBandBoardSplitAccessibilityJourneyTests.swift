import XCTest

/// Song Detail's Duos "View Full Leaderboard" opening the band board in the split's
/// trailing pane, on device at the default text size and at AX5 (issue #492, the region
/// #367 changed: the band button became a ``ListDetailLink``). Each launch opens the Duos
/// board from Song Detail and checks that the button is one named button that stays
/// **selected** while its board is open, keeps a 44 pt target inside the leading pane and
/// draws its label whole; that VoiceOver focus moves to the pane's heading, named by the
/// band size and never the song; and that the heading reads before the board's rows. The
/// button's glyphs must grow at least 1.35× from the default size to AX5
/// (`.agents/testing/apple/accessibility.md`).
///
/// iPad landscape, and the iPhone Duo in a pose whose window splits (run with
/// `ios_sim.py uitest --device duo --app ipad` after `pose --set open`; a pose that
/// cannot split skips). The hosted `SongBandSplitLinkAccessibilityTests` pin the same
/// links' names, selected state, activation and order in the Mac split.
/// Fixture-backed: `fixture-pulse` Duos (127.0.0.1:8765 or the runner's `FST_FIXTURE_URL`;
/// the fixture must serve `/api/leaderboard/{songId}/bands/all`).
final class SongBandBoardSplitAccessibilityJourneyTests: XCTestCase {
    private typealias Audit = IPadAccessibilityAuditTests

    static let ctaID = "fst.song-detail.band-leaderboard.Band_Duets"
    static let titleID = "fst.song-band-leaderboard.board-title"
    static let ctaText = "View Full Leaderboard"
    static let songTitle = "Fixture Pulse"
    static let bandSize = "Duos"

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

    /// The Duos button and its board beside Song Detail at the default size and at AX5,
    /// then the button's glyph growth.
    @MainActor
    func testSongBandBoardSplitLinkAtAX5() throws {
        if !Audit.runningOnDuo { XCUIDevice.shared.orientation = .landscapeLeft }
        var heights: [CGFloat?] = []
        for contentSize in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            heights.append(try measure(contentSize: contentSize, name: contentSize == .large ? "default" : "ax5"))
        }
        if let standard = heights[0], let largest = heights[1] {
            XCTAssertGreaterThanOrEqual(
                largest / standard, RecognizedText.minimumGrowth,
                "the button's label grows at AX5 (\(standard) → \(largest) pt)"
            )
        } else {
            XCTFail("no whole label to compare (default \(String(describing: heights[0])), AX5 \(String(describing: heights[1])))")
        }
    }

    // MARK: - Verification

    /// One launch: open the Duos board beside Song Detail, then check the button's name,
    /// selected state, target and drawn label, and the pane's heading, focus and order.
    ///
    /// - Parameters:
    ///   - contentSize: The launch's preferred content size.
    ///   - name: Label for failures and attachments.
    /// - Returns: The button's recognized line height (points) when drawn whole, else nil.
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
        XCTAssertTrue(Audit.anyElement(app, "fst.songs.list").waitForExistence(timeout: FestivalApp.budget(25)), "\(name): Songs")
        guard Audit.openSong(app, "fixture-pulse") else {
            XCTFail("\(name): Song Detail did not open")
            return nil
        }
        let window = app.windows.firstMatch.frame
        if Audit.runningOnDuo, window.width <= window.height {
            throw XCTSkip("this iPhone Duo pose does not split (window \(window))")
        }
        // Quick Links lands on the Duos section, so the button is a short scroll away even
        // at AX5.
        let quickLinks = app.buttons["fst.quick-links.open"]
        if quickLinks.waitForExistence(timeout: FestivalApp.budget(15)) {
            quickLinks.tap()
            let duos = FestivalApp.quickLinkRow("band-Band_Duets", label: "Duos", in: app)
            if duos.waitForExistence(timeout: FestivalApp.budget(10)) { duos.tap() }
        }
        guard window.width > window.height,
              Audit.openSplit(app, ids: [Self.ctaID]) != nil,
              let pane = Audit.trailingPane(app) else {
            XCTFail("\(name): the Duos board did not open in the trailing pane (window \(window))")
            return nil
        }
        let title = Audit.anyElement(app, Self.titleID)
        XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(15)), "\(name): the pane's title")
        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.song-band-leaderboard.row.")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: FestivalApp.budget(15)), "\(name): the board's rows")
        Thread.sleep(forTimeInterval: FestivalApp.budget(2.5)) // staggered row fade-in

        // The button: named with its band size, selected while its board is open, a full
        // target in the leading pane.
        let cta = app.buttons[Self.ctaID]
        XCTAssertTrue(cta.exists, "\(name): the Duos button stays on Song Detail")
        XCTAssertEqual(cta.label, "\(Self.ctaText), \(Self.bandSize)", "\(name): the button's name")
        XCTAssertTrue(cta.isSelected, "\(name): the button is selected while its board is open")
        XCTAssertGreaterThanOrEqual(cta.frame.height, 44 - 0.5, "\(name): a 44 pt target \(cta.frame)")
        XCTAssertLessThanOrEqual(cta.frame.maxX, pane.minX + 0.5, "\(name): the button \(cta.frame) is in the leading pane \(pane)")

        // The pane: titled by the band size, never the song; focus moves to that heading.
        XCTAssertTrue(title.label.hasPrefix(Self.bandSize), "\(name): named by its band size: '\(title.label)'")
        XCTAssertFalse(title.label.contains(Self.songTitle), "\(name): the title does not repeat the song: '\(title.label)'")
        XCTAssertFalse(Audit.anyElement(app, "fst.song-band-leaderboard.header").exists, "\(name): no repeated song header")
        let focus = waitForFocus(app) { $0.hasPrefix("heading: ") }
        XCTAssertEqual(focus, "heading: \(title.label)", "\(name): focus moves to the pane's title")

        // Order: Song Detail's button, then the pane's heading, then its rows.
        let nodes = IPadAuditPageEvidence.flatten(try app.snapshot())
        let ctaIndex = nodes.firstIndex { $0.identifier == Self.ctaID }
        let titleIndex = nodes.firstIndex { $0.identifier == Self.titleID }
        let rows = nodes.indices.filter { nodes[$0].identifier.hasPrefix("fst.song-band-leaderboard.row.") }
        XCTAssertFalse(rows.isEmpty, "\(name): rows in the tree")
        if let ctaIndex, let titleIndex {
            XCTAssertLessThan(ctaIndex, titleIndex, "\(name): Song Detail's button reads before the pane")
            if Audit.traitsReadable(nodes) {
                XCTAssertTrue(Audit.isHeader(nodes[titleIndex]), "\(name): the title is a heading")
            }
            XCTAssertTrue(rows.allSatisfy { $0 > titleIndex }, "\(name): the title reads before the rows")
        } else {
            XCTFail("\(name): the button (\(String(describing: ctaIndex))) and title (\(String(describing: titleIndex))) in the tree")
        }

        // Drawn text: the button's label whole, and its line height for the growth check.
        // The split narrows Song Detail and reflows it, so the button may have moved off
        // screen; a capture of an off-screen element is black.
        let column = CGRect(x: window.minX, y: window.minY, width: pane.minX - window.minX, height: window.height)
        XCTAssertTrue(reveal(cta, in: app, column: column),
                      "\(name): the button \(cta.frame) scrolls into view in the leading pane \(column)")
        XCTAssertTrue(cta.isSelected, "\(name): the button stays selected after scrolling")
        let reading = RecognizedText.recognize(cta, label: Self.ctaText, frame: cta.frame)
        attach(cta, name: name)
        XCTAssertTrue(RecognizedText.showsWhole(Self.ctaText, in: reading.text),
                      "\(name): the button's label is drawn whole: '\(reading.text ?? "")'")
        return RecognizedText.showsWhole(Self.ctaText, in: reading.text) ? reading.lineHeight : nil
    }

    // MARK: - Helpers

    /// The app's last traced VoiceOver focus move once it satisfies `predicate`.
    @MainActor
    private func waitForFocus(_ app: XCUIApplication, timeout: TimeInterval = 6, _ predicate: (String) -> Bool) -> String {
        let deadline = Date.now.addingTimeInterval(FestivalApp.budget(timeout))
        var last = ""
        repeat {
            let node = Audit.anyElement(app, "fst.nav.a11y-focus")
            last = node.exists ? node.label : ""
            if predicate(last) { return last }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date.now < deadline
        return last
    }

    /// Bring `element` wholly into the leading column's measurable area (below its top bar,
    /// above the tab bar) with slow drags at the column's trailing margin, clear of Song
    /// Detail's score-history chart (same as `ScoreHistoryAccessibilityJourneyTests`).
    ///
    /// - Returns: Whether the element is there.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, column: CGRect) -> Bool {
        for _ in 0..<8 {
            let area = IPadAuditPageEvidence.contentRect(app)
            if element.exists, area.contains(element.frame) { return true }
            let top = area.top(for: element.frame), bottom = area.bottom(for: element.frame)
            let distance = element.frame.minY < top ? -min(400, top - element.frame.minY + 40)
                : min(400, element.frame.maxY - bottom + 40)
            let x = Audit.dragX(column.maxX - 12, in: app), midY = column.midY
            Audit.slowDrag(app, x: x, fromY: midY + distance / 2, toY: midY - distance / 2)
        }
        return element.exists && IPadAuditPageEvidence.contentRect(app).contains(element.frame)
    }

    /// Keep the button's capture with the run's results.
    @MainActor
    private func attach(_ element: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = "song-band-board-split-link-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
