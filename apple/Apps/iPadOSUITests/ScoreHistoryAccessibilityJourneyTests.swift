import XCTest

/// Score History at the largest text size on device (issue #385, the region #302
/// changed): the page root's heading reads before its score rows, the rows stay inside
/// their column, keep the 44 pt minimum, and draw their score and accuracy whole, each on
/// one recognized line (Vision, from the screen capture), with the score's glyphs at least
/// 1.35× taller at AX5 than at the default size. The one-line `ScoreHistoryListRow`
/// broke "850,000" between digits at AX5 while its label and frame stayed valid, so only
/// the drawn text proves the fix (`.agents/testing/apple/accessibility.md`).
///
/// - `testScoreHistoryPageAtAX5`: the full page View All Scores pushes on iPhone and in
///   iPad portrait (run on iPhone with `ios_sim.py uitest --device iphone --app ipad`).
/// - `testScoreHistorySplitPaneAtAX5`: the trailing pane beside Song Detail in iPad
///   landscape; VoiceOver focus also moves to the pane's heading.
///
/// Lives in the iPad bundle to reuse the audit's capture and recognition helpers
/// (`IPadAuditRenderedContrast`, `IPadAuditPageEvidence`). Fixture-backed:
/// `fixture-history-multi` has eight Lead scores on `fixture-pulse` (127.0.0.1:8765 or the
/// runner's `FST_FIXTURE_URL`).
final class ScoreHistoryAccessibilityJourneyTests: XCTestCase {
    /// What one launch measured.
    private struct Measure {
        /// The best row's recognized score word height (points), when it was drawn whole.
        var scoreGlyphHeight: CGFloat?
    }

    private typealias Audit = IPadAccessibilityAuditTests

    private var isPad: Bool { MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad } }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    override func tearDown() {
        MainActor.assumeIsolated { IPadAuditRenderedContrast.interfaceIsLandscape = nil }
        guard isPad, !Audit.runningOnDuo else { return }
        MainActor.assumeIsolated {
            let app = FestivalApp.makeApp()
            if app.state == .runningForeground { WindowResize.fill(app) }
            XCUIDevice.shared.orientation = .portrait
        }
    }

    // MARK: - Journeys

    /// The full page (iPhone, iPad portrait) at the default size and at AX5.
    @MainActor
    func testScoreHistoryPageAtAX5() throws {
        if isPad, !Audit.runningOnDuo { XCUIDevice.shared.orientation = .portrait }
        try verify(split: false)
    }

    /// The trailing pane beside Song Detail (iPad landscape) at the default size and at AX5.
    @MainActor
    func testScoreHistorySplitPaneAtAX5() throws {
        try XCTSkipUnless(isPad, "the split needs a landscape iPad window")
        XCUIDevice.shared.orientation = .landscapeLeft
        try verify(split: true)
    }

    // MARK: - Verification

    /// Open Score History at the default size and at AX5 and check both, then the growth.
    ///
    /// - Parameter split: Open it in the trailing pane (else as a full page).
    @MainActor
    private func verify(split: Bool) throws {
        let name = split ? "split" : "page"
        var measures: [Measure] = []
        for contentSize in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let label = "\(name)-\(contentSize == .large ? "default" : "ax5")"
            measures.append(try measure(split: split, contentSize: contentSize, name: label))
        }
        let heights = measures.map(\.scoreGlyphHeight)
        if let standard = heights[0], let largest = heights[1] {
            XCTAssertGreaterThanOrEqual(
                largest / standard, 1.35, "\(name): the score's glyphs grow at AX5 (\(standard) → \(largest) pt)"
            )
        } else {
            XCTFail("\(name): no whole score to compare (default \(String(describing: heights[0])), AX5 \(String(describing: heights[1])))")
        }
    }

    /// One launch: open the page, then check order, frames and the drawn text.
    ///
    /// - Parameters:
    ///   - split: Open it in the trailing pane.
    ///   - contentSize: The launch's preferred content size.
    ///   - name: Label for failures and evidence.
    /// - Returns: The measurements growth is compared on.
    @MainActor
    private func measure(split: Bool, contentSize: UIContentSizeCategory, name: String) throws -> Measure {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": IPadShellJourneyTests.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-history-multi:Multi History",
            "FST_DEBUG_A11Y_FOCUS_TRACE": "1",
        ])
        app.launchArguments += ["-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
                                "-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        app.launch()
        defer { app.terminate() }
        if isPad, !Audit.runningOnDuo { WindowResize.fill(app) }
        XCTAssertTrue(Audit.anyElement(app, "fst.songs.list").waitForExistence(timeout: FestivalApp.budget(25)), "\(name): Songs")
        guard Audit.openSong(app, "fixture-pulse") else {
            XCTFail("\(name): Song Detail did not open")
            return Measure()
        }
        let window = app.windows.firstMatch.frame
        let column: CGRect
        let heading: String
        if split {
            guard window.width > window.height,
                  Audit.openSplit(app, ids: ["fst.song-detail.history.view-all"]) != nil,
                  let pane = Audit.trailingPane(app) else {
                XCTFail("\(name): Score History did not open in the trailing pane (window \(window))")
                return Measure()
            }
            column = pane
            heading = "fst.history.board-title"
        } else {
            guard openViewAll(app) else {
                XCTFail("\(name): View All Scores was not reached")
                return Measure()
            }
            XCTAssertNil(Audit.trailingPane(app), "\(name): a full page, not a pane")
            column = window
            heading = "fst.history.header"
        }
        let firstRow = Audit.anyElement(app, "fst.history.row.0")
        XCTAssertTrue(firstRow.waitForExistence(timeout: FestivalApp.budget(15)), "\(name): no score rows")
        Thread.sleep(forTimeInterval: FestivalApp.budget(2.5)) // staggered row fade-in

        if split {
            // VoiceOver focus moves to the pane's heading (`AccessibilityFocusMove`).
            let focus = waitForFocus(app) { $0.hasPrefix("heading: ") }
            let title = Audit.anyElement(app, heading)
            XCTAssertTrue(
                focus.hasPrefix("heading: ") && title.exists && focus.dropFirst("heading: ".count) == title.label,
                "\(name): focus moves to the pane's heading '\(title.label)' (\(focus))"
            )
        }

        // Reading order: the heading, then the rows in order, all inside the column.
        let nodes = IPadAuditPageEvidence.flatten(try app.snapshot())
        let headingIndex = nodes.firstIndex { $0.identifier == heading }
        let rowIndices = (0..<8).compactMap { index in nodes.firstIndex { $0.identifier == "fst.history.row.\(index)" } }
        XCTAssertNotNil(headingIndex, "\(name): no heading \(heading)")
        XCTAssertGreaterThanOrEqual(rowIndices.count, 1, "\(name): rows in the tree")
        if let headingIndex {
            if Audit.traitsReadable(nodes) {
                XCTAssertTrue(Audit.isHeader(nodes[headingIndex]), "\(name): \(heading) is a heading")
            }
            XCTAssertTrue(rowIndices.allSatisfy { $0 > headingIndex }, "\(name): the heading reads before the rows")
        }
        XCTAssertEqual(rowIndices, rowIndices.sorted(), "\(name): rows read in order")
        for index in rowIndices {
            let row = nodes[index]
            XCTAssertTrue(row.label.contains("score "), "\(name): \(row.identifier) is named: '\(row.label)'")
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(name): \(row.identifier) height")
            XCTAssertTrue(
                row.frame.minX >= column.minX - 0.5 && row.frame.maxX <= column.maxX + 0.5,
                "\(name): \(row.identifier) \(row.frame) inside its column \(column)"
            )
        }

        // Drawn text of the best row, brought wholly into the measurable area.
        guard let row = reveal(firstRow, in: app, column: column) else {
            XCTFail("\(name): row 0 never came wholly on screen (\(firstRow.frame))")
            return Measure()
        }
        let numbers = Self.drawnNumbers(row.label)
        XCTAssertEqual(numbers.count, 2, "\(name): the row names its score and accuracy: '\(row.label)'")
        IPadAuditRenderedContrast.interfaceIsLandscape = window.width > window.height
        guard let capture = IPadAuditRenderedContrast.Capture.screen() else {
            XCTFail("\(name): no screen capture")
            return Measure()
        }
        attach(capture, name: name)
        let frame = row.frame
        let lines = IPadAuditPageEvidence.recognizedLines(in: capture).filter {
            frame.insetBy(dx: -4, dy: -4).contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
        }
        let texts = lines.map(\.text)
        var measure = Measure()
        for (offset, digits) in numbers.enumerated() {
            let line = lines.first { Self.digits($0.text).contains(digits) }
            XCTAssertNotNil(line, "\(name): row 0 draws \(digits) whole on one line: \(texts)")
            if offset == 0, let line {
                measure.scoreGlyphHeight = line.words.first { Self.digits($0.text).contains(digits) }?.frame.height
                    ?? line.frame.height
            }
        }
        XCTAssertFalse(texts.contains { $0.contains("\u{2026}") || $0.contains("...") }, "\(name): row 0 truncated: \(texts)")
        record(capture, name: name, row: frame, lines: texts, measure: measure)
        return measure
    }

    // MARK: - Helpers

    /// Scroll Song Detail until View All Scores is on screen and tap it.
    ///
    /// - Returns: True once the Score History page shows its rows.
    @MainActor
    private func openViewAll(_ app: XCUIApplication) -> Bool {
        let viewAll = Audit.anyElement(app, "fst.song-detail.history.view-all")
        let window = app.windows.firstMatch.frame
        for _ in 0..<14 {
            if viewAll.exists, viewAll.isHittable,
               window.insetBy(dx: 0, dy: 100).contains(CGPoint(x: viewAll.frame.midX, y: viewAll.frame.midY)) {
                viewAll.tap()
                return Audit.anyElement(app, "fst.history.row.0").waitForExistence(timeout: FestivalApp.budget(15))
            }
            // The trailing margin: a drag that starts on the chart selects a bar.
            Audit.slowDrag(app, x: window.maxX - 12, fromY: window.minY + window.height * 0.75,
                                toY: window.minY + window.height * 0.35)
        }
        return false
    }

    /// Bring `row` wholly into the column's measurable area (below its top bar, above the
    /// tab bar and page tools) with slow drags.
    ///
    /// - Returns: The row's snapshot once it is there, else nil.
    @MainActor
    private func reveal(_ row: XCUIElement, in app: XCUIApplication, column: CGRect) -> XCUIElementSnapshot? {
        for _ in 0..<8 {
            let area = IPadAuditPageEvidence.contentRect(app)
            if row.exists, area.contains(row.frame), let snapshot = try? row.snapshot() {
                return snapshot
            }
            let top = area.top(for: row.frame), bottom = area.bottom(for: row.frame)
            let distance = row.frame.minY < top ? -min(400, top - row.frame.minY + 40)
                : min(400, row.frame.maxY - bottom + 40)
            let x = column.maxX - 12, midY = column.midY
            Audit.slowDrag(app, x: x, fromY: midY + distance / 2, toY: midY - distance / 2)
        }
        return nil
    }

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

    /// Keep the capture with the run's results.
    @MainActor
    private func attach(_ capture: IPadAuditRenderedContrast.Capture, name: String) {
        let attachment = XCTAttachment(image: UIImage(cgImage: capture.image))
        attachment.name = "score-history-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Write the capture and what was read to `FST_AUDIT_OUT` (`TEST_RUNNER_FST_AUDIT_OUT`) when set.
    @MainActor
    private func record(_ capture: IPadAuditRenderedContrast.Capture, name: String, row: CGRect,
                        lines: [String], measure: Measure) {
        guard let dir = ProcessInfo.processInfo.environment["FST_AUDIT_OUT"] else { return }
        let base = URL(fileURLWithPath: dir).appendingPathComponent("score-history-\(name)")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? UIImage(cgImage: capture.image).pngData()?.write(to: base.appendingPathExtension("png"))
        let summary: [String: Any] = [
            "row": [row.minX, row.minY, row.width, row.height],
            "lines": lines,
            "scoreGlyphHeight": measure.scoreGlyphHeight.map { Double($0) } ?? NSNull(),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: base.appendingPathExtension("json"))
        }
    }

    /// The digits of the score and accuracy a row's label names
    /// ("Feb 8, 2024, score 850,000, accuracy 99.1 percent, best score" → ["850000", "991"]).
    static func drawnNumbers(_ label: String) -> [String] {
        ["score ", "accuracy "].compactMap { key in
            guard let start = label.range(of: key)?.upperBound else { return nil }
            let found = digits(String(label[start...].prefix { $0 != " " }))
            return found.isEmpty ? nil : found
        }
    }

    /// The decimal digits of `text`.
    static func digits(_ text: String) -> String {
        String(text.filter(\.isWholeNumber))
    }
}
