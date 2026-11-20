import XCTest

/// Song Detail's first row of instrument cards on device at the default text size and at
/// AX5 (issue #490, the region #365 changed): a tall Lead card (ten top scores) beside a
/// short, empty Bass card, which #365 top-aligned. Each launch checks that both card
/// headers are headings named by their instrument (Bass's with "No scores recorded yet");
/// that they start on one top edge, side by side, wholly on screen; that each card is one
/// container read whole (`fst.song-detail.card.*`: heading, rows, View Full Leaderboard),
/// so VoiceOver finishes Lead before Bass; that Lead's first row and View Full
/// Leaderboard are 44 pt targets inside Lead's column; and that each header's name is
/// drawn whole (Vision, ``RecognizedText``), with Lead's glyphs at least 1.35× taller at
/// AX5 than at the default size (`.agents/testing/apple/accessibility.md`).
///
/// iPad portrait (two card columns at both sizes), and the iPhone Duo inner display when
/// its window fits two columns (`ios_sim.py uitest --device duo --app ipad`; a narrower
/// pose skips). The hosted `SongDetailCardRowAccessibilityTests` pin the same row's names,
/// order, top edge and targets on every Apple layout, including the Duo book pose and the
/// Mac. Fixture-backed: `fixture-pulse` Lead and Bass (127.0.0.1:8765 or the runner's
/// `FST_FIXTURE_URL`), no selected player.
final class SongDetailCardRowAccessibilityJourneyTests: XCTestCase {
    private typealias Audit = IPadAccessibilityAuditTests

    static let leadHeader = "fst.song-detail.card-header.Solo_Guitar"
    static let bassHeader = "fst.song-detail.card-header.Solo_Bass"
    static let leadCard = "fst.song-detail.card.Solo_Guitar"
    static let bassCard = "fst.song-detail.card.Solo_Bass"
    static let leadFirstRow = "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
    static let leadViewFull = "fst.song-detail.leaderboard.Solo_Guitar"

    private var isPad: Bool { MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad } }

    override func setUpWithError() throws {
        try XCTSkipUnless(isPad || Audit.runningOnDuo, "two card columns need an iPad or iPhone Duo window")
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

    /// The first card row at the default size and at AX5, then the headers' glyph growth.
    @MainActor
    func testInstrumentCardRowAtAX5() throws {
        if !Audit.runningOnDuo { XCUIDevice.shared.orientation = .portrait }
        var heights: [CGFloat?] = []
        for contentSize in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            heights.append(try measure(contentSize: contentSize, name: contentSize == .large ? "default" : "ax5"))
        }
        if let standard = heights[0], let largest = heights[1] {
            XCTAssertGreaterThanOrEqual(
                largest / standard, RecognizedText.minimumGrowth,
                "the card headers grow at AX5 (\(standard) → \(largest) pt)"
            )
        } else {
            XCTFail("no whole header to compare (default \(String(describing: heights[0])), AX5 \(String(describing: heights[1])))")
        }
    }

    // MARK: - Verification

    /// One launch: open Song Detail, bring the first card row on screen, then check names,
    /// geometry, order, targets and the drawn headers.
    ///
    /// - Parameters:
    ///   - contentSize: The launch's preferred content size.
    ///   - name: Label for failures and attachments.
    /// - Returns: Lead's header line height (points) when drawn whole, else nil.
    @MainActor
    private func measure(contentSize: UIContentSizeCategory, name: String) throws -> CGFloat? {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": IPadShellJourneyTests.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
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
        // Two 360 pt columns, a 12 pt gutter and the page's 16 pt margins.
        if Audit.runningOnDuo, window.width < 2 * 360 + 12 + 32 {
            throw XCTSkip("this iPhone Duo window fits one card column (\(window))")
        }
        // Waits and reads come from retried snapshots, the drawn text from a screen capture:
        // live queries after the push stalled the iPad split journeys on the CI runner (#703).
        XCTAssertTrue(FestivalApp.waitForElement(Self.leadHeader, in: app, timeout: FestivalApp.budget(15)), "\(name): Lead's card")
        XCTAssertTrue(FestivalApp.waitForElement(Self.bassHeader, in: app, timeout: FestivalApp.budget(15)), "\(name): Bass's card")
        var lastFrame: CGRect?
        guard Audit.reveal(Self.leadHeader, in: app, column: window, steps: 10, lastFrame: &lastFrame) != nil else {
            XCTFail("\(name): the first card row never came wholly on screen (Lead \(lastFrame.map { "\($0)" } ?? "not in the tree"))")
            return nil
        }
        Thread.sleep(forTimeInterval: FestivalApp.budget(2.5)) // staggered card fade-in
        let root = try FestivalApp.snapshot(of: app, within: FestivalApp.budget(5), until: {
            FestivalApp.contains(Self.leadHeader, in: $0) && FestivalApp.contains(Self.bassHeader, in: $0)
        })
        guard let lead = FestivalApp.node(Self.leadHeader, in: root),
              let bass = FestivalApp.node(Self.bassHeader, in: root) else {
            XCTFail("\(name): the first card row's headers left the tree")
            return nil
        }

        // Names: each header is its instrument, then its subtitle.
        XCTAssertTrue(lead.label.hasPrefix("Lead"), "\(name): Lead's header is named: '\(lead.label)'")
        XCTAssertTrue(bass.label.hasPrefix("Bass") && bass.label.contains("No scores recorded yet"),
                      "\(name): Bass's header names its empty chart: '\(bass.label)'")

        // Geometry (#365): one top edge, side by side, both on screen.
        let leadFrame = lead.frame, bassFrame = bass.frame
        XCTAssertEqual(bassFrame.minY, leadFrame.minY, accuracy: 1,
                       "\(name): the row's headers start on one top edge (Lead \(leadFrame), Bass \(bassFrame))")
        XCTAssertGreaterThan(bassFrame.minX, leadFrame.maxX, "\(name): Bass sits beside Lead")
        XCTAssertTrue(window.contains(leadFrame) && window.contains(bassFrame), "\(name): both headers on screen")

        // Order: each card is one container, read whole, Lead before Bass.
        let nodes = IPadAuditPageEvidence.flatten(root)
        func index(_ id: String) -> Int? { nodes.firstIndex { $0.identifier == id } }
        let ids = [Self.leadCard, Self.leadHeader, Self.leadFirstRow, Self.leadViewFull, Self.bassCard, Self.bassHeader]
        let indices = ids.compactMap(index)
        XCTAssertEqual(indices.count, ids.count, "\(name): every card element is in the tree: \(zip(ids, ids.map(index)).map { "\($0)=\(String(describing: $1))" })")
        XCTAssertEqual(indices, indices.sorted(), "\(name): Lead's card reads whole before Bass's: \(indices)")
        if let leadCard = index(Self.leadCard) {
            let card = nodes[leadCard].frame
            for id in [Self.leadHeader, Self.leadFirstRow, Self.leadViewFull] {
                guard let node = index(id) else { continue }
                XCTAssertTrue(card.insetBy(dx: -0.5, dy: -0.5).contains(nodes[node].frame),
                              "\(name): \(id) \(nodes[node].frame) is inside Lead's card \(card)")
            }
            XCTAssertLessThan(card.maxX, bassFrame.minX, "\(name): Lead's card ends before Bass's column")
        }
        if Audit.traitsReadable(nodes) {
            for id in [Self.leadHeader, Self.bassHeader] {
                if let node = index(id) { XCTAssertTrue(Audit.isHeader(nodes[node]), "\(name): \(id) is a heading") }
            }
        }

        // Targets: Lead's first row and View Full Leaderboard are 44 pt tall in its column.
        for id in [Self.leadFirstRow, Self.leadViewFull] {
            guard let node = index(id) else { continue }
            let frame = nodes[node].frame
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(name): \(id) is a 44 pt target: \(frame)")
            XCTAssertLessThan(frame.maxX, bassFrame.minX, "\(name): \(id) stays in Lead's column: \(frame)")
        }

        // Drawn text: each header's name whole, and Lead's line height for the growth check.
        let landscape = window.width > window.height
        let (leadReading, capture) = IPadAuditPageEvidence.reading("Lead", within: leadFrame, landscape: landscape)
        let bassReading = IPadAuditPageEvidence.reading("Bass", within: bassFrame, landscape: landscape).reading
        if let capture { attach(capture, name: name) }
        XCTAssertTrue(RecognizedText.showsWhole("Lead", in: leadReading.text),
                      "\(name): Lead's header is drawn whole: '\(leadReading.text ?? "")'")
        XCTAssertTrue(RecognizedText.showsWhole("Bass", in: bassReading.text),
                      "\(name): Bass's header is drawn whole: '\(bassReading.text ?? "")'")
        return RecognizedText.showsWhole("Lead", in: leadReading.text) ? leadReading.lineHeight : nil
    }

    // MARK: - Helpers

    /// Keep the screen capture with the run's results.
    @MainActor
    private func attach(_ capture: IPadAuditRenderedContrast.Capture, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: capture.image))
        attachment.name = "song-detail-card-row-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
