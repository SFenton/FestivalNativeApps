import UIKit
import XCTest

/// Accessibility journeys for the full band board's selected-band reveal (issue #386, for
/// #327's change): opened from Song Detail's selected Duos band, the board waits for its
/// reload gate to grow the list before it scrolls the band's row into view
/// (load-transition R5), and jumps instantly under Reduce Motion (R6). Each journey checks
/// what VoiceOver and touch get once the reveal ends: the spinner gone, the band's row a
/// button that speaks the highlight ("Your band, Rank 29, …"), hittable and at least
/// 44×44 pt, the page reading song header, rows, pinned row, then pager, and a clean
/// `performAccessibilityAudit`; at AX5 the row grows rather than clipping, and the band's
/// own row follows the cards instead of covering them (leaderboard-row R11).
///
/// Needs `python3 tools/mock_service.py --port 18934` from this revision (apple-ci starts
/// it). Fails, rather than skips, without it, so CI cannot pass by skipping.
final class SongBandRevealAccessibilityJourneyTests: XCTestCase {
    /// Loopback fixture origin (the band fixture's own port, as `SongDetailJourneyTests`).
    private static let origin = "http://127.0.0.1:18934"
    /// The selected player's Duos band on page 2 of the fixture board.
    private static let focusedRow = "fst.song-band-leaderboard.row.fixture-band-fixture-player-1:29"
    private static let boardPrefix = "fst.song-band-leaderboard."
    /// The motion journeys audit every type but the text-size ones, which do not depend on
    /// motion: ``testRevealedBandRowGrowsAtLargestTextSize()`` audits those at the default
    /// size and AX5 with this run's measurements as evidence.
    private static let motionAudit = XCUIAccessibilityAuditType.all.subtracting([.dynamicType, .textClipped])

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try requireFixture()
    }

    // MARK: - Journeys

    /// Standard motion with the load fades kept on, so the gate's animated reveal and
    /// the reveal's wait for it run as in production.
    ///
    /// - Throws: A missing element, a failed assertion or an audit issue.
    @MainActor
    func testRevealedBandRowIsAccessibleWithStandardMotion() throws {
        let app = openFocusedBoard(environment: ["FST_DEBUG_KEEP_FADES": "1"])
        let revealed = try assertRevealedRow(in: app, minimumSide: 44, footerPinned: true)
        try audit(app, types: Self.motionAudit, chromeTop: revealed.chromeTop, name: "standard")
    }

    /// The app's own Reduce Motion: the jump is instant and waits on no fade.
    ///
    /// - Throws: A missing element, a failed assertion or an audit issue.
    @MainActor
    func testRevealedBandRowIsAccessibleWithReduceMotion() throws {
        let app = openFocusedBoard(
            environment: ["FST_DEBUG_KEEP_FADES": "1"],
            arguments: ["-fst.accessibility.reduceMotion", "YES"]
        )
        let revealed = try assertRevealedRow(in: app, minimumSide: 44, footerPinned: true)
        try audit(app, types: Self.motionAudit, chromeTop: revealed.chromeTop, name: "reduce-motion")
    }

    /// AX5: the revealed row keeps its label, stays hittable and inside the screen, and
    /// grows past 1.35× its default height to fit its larger, stacked text rather than
    /// clipping it (accessibility.md: real growth at AX5; leaderboard-row R2). The band's
    /// own row, which at AX5 would cover the whole board, follows the cards instead of
    /// pinning (R11), so the revealed row is in view above the pager.
    ///
    /// Text-size audits run at both sizes. At the default size the auditor reports the
    /// rows' rank, score and accuracy texts as "partially unsupported"; each is accepted
    /// only when the same kind of row text measures ≥ 1.35× taller in the AX5 launch
    /// (`dynamic-type-grows`), and an unattributed "Text clipped" only while a name on
    /// screen is drawn narrower than its one-line width: R3's tail truncation under Reduce
    /// Motion, whose full name VoiceOver reads and which wraps at AX5. The AX5 audit
    /// (everything but contrast, as the other AX5 modes) must come back clean.
    ///
    /// - Throws: A missing element, a failed assertion or an audit issue.
    @MainActor
    func testRevealedBandRowGrowsAtLargestTextSize() throws {
        let standard = openFocusedBoard(arguments: ["-fst.accessibility.reduceMotion", "YES"])
        let baseline = try assertRevealedRow(in: standard, minimumSide: 44, footerPinned: true)
        let standardText = rowTextHeights(in: standard)
        var flagged: Set<String> = []
        try standard.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            let detail = self.attach(issue, name: "default-text")
            if issue.auditType == .dynamicType, let frame = issue.element?.frame,
               Self.isSystemBadge(frame, in: self.systemBadgeFrame(in: standard)) {
                return true
            }
            if issue.auditType == .dynamicType, let label = issue.element?.label,
               standardText[Self.textKind(label)] != nil {
                flagged.insert(Self.textKind(label))
                return true
            }
            if issue.auditType == .textClipped, issue.element == nil,
               let name = self.truncatedName(in: standard) {
                self.attach(note: "Unattributed clip with the R3-truncated name \(name)", name: "default-text")
                return true
            }
            XCTFail("Band board text audit (default): \(detail)")
            return false
        }
        standard.terminate()

        let large = openFocusedBoard(arguments: [
            "-fst.accessibility.reduceMotion", "YES",
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ])
        let grown = try assertRevealedRow(in: large, minimumSide: 44, footerPinned: false)
        XCTAssertEqual(grown.label, baseline.label, "The spoken label must not depend on text size")
        let width = large.windows.firstMatch.frame.width
        XCTAssertGreaterThanOrEqual(grown.frame.minX, 0, "The row starts off screen at AX5: \(grown.frame)")
        XCTAssertLessThanOrEqual(grown.frame.maxX, width, "The row runs off screen at AX5: \(grown.frame)")
        XCTAssertGreaterThan(
            grown.frame.height, baseline.frame.height * 1.35,
            "The row did not grow at AX5 (\(baseline.frame.height) → \(grown.frame.height))"
        )
        let largeText = rowTextHeights(in: large)
        for kind in flagged.sorted() {
            let before = try XCTUnwrap(standardText[kind]), after = try XCTUnwrap(largeText[kind], "No \(kind) text at AX5")
            XCTAssertGreaterThanOrEqual(after, before * 1.35, "\(kind) text grew only \(before) → \(after) pt at AX5")
        }
        try audit(large, types: .all.subtracting(.contrast), chromeTop: grown.chromeTop, name: "ax5")
    }

    // MARK: - Steps

    /// Fail early, with instructions, unless this revision's band fixture answers.
    private func requireFixture() throws {
        let probe = expectation(description: "band fixture probe")
        var reachable = false
        let board = "\(Self.origin)/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=25&accountId=fixture-player-1"
        URLSession.shared.dataTask(with: URL(string: board)!) { data, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
                && data.map { String(decoding: $0, as: UTF8.self).contains("\"selectedPlayerEntry\":{") } == true
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: FestivalApp.budget(5))
        _ = try XCTUnwrap(
            reachable ? true : nil, "Start `python3 tools/mock_service.py --port 18934` from this revision"
        )
    }

    /// Launch with the fixture player and open their Duos band's row on the full board,
    /// the way a reader does: Song Detail → Quick Links → Duos → the appended band row.
    ///
    /// - Parameters:
    ///   - environment: Extra launch environment.
    ///   - arguments: Extra launch arguments (user-default overrides).
    /// - Returns: The running app on the revealed board.
    @MainActor
    private func openFocusedBoard(
        environment: [String: String] = [:], arguments: [String] = []
    ) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_API_BASE_URL": Self.origin,
        ].merging(environment) { $1 })
        app.launchArguments += arguments
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(20)), "No fixture song row")
        // At AX5 the second song's card starts below the floating tab bar: drag it up first.
        // Judge by frame: asking an off-screen row whether it is hittable fails the test.
        let list = app.windows.firstMatch
        for _ in 0..<6 where !Self.isInView(song, window: list.frame, below: 0.8) {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        }
        waitHittable(song, in: app, "The fixture song row did not come into view")
        song.tap()
        XCTAssertTrue(
            any("fst.song-detail.intensity", in: app).waitForExistence(timeout: FestivalApp.budget(20)),
            "Song Detail did not open"
        )
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: FestivalApp.budget(15)))
        quickLinks.tap()
        let duos = app.buttons["fst.quick-links.item.band-Band_Duets"]
        XCTAssertTrue(duos.waitForExistence(timeout: FestivalApp.budget(10)), "Quick Links has no Duos section")
        duos.tap()
        let selected = app.buttons["fst.song-detail.band-selected.Band_Duets"]
        // Quick Links lands on the Duos header; at AX5 the ten preview rows push the
        // appended band row below the bars, so move it up in short, momentum-free drags.
        for _ in 0..<12 where !Self.isInView(selected, window: list.frame, below: 0.75) {
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        waitHittable(selected, in: app, "Quick Links did not bring the appended Duos band into view")
        selected.tap()
        waitHittable(app.buttons[Self.focusedRow], in: app, "The board did not reveal the selected band's row")
        return app
    }

    /// Check the revealed row and the page around it.
    ///
    /// - Parameters:
    ///   - app: Running app on the revealed board.
    ///   - minimumSide: Minimum hit-target side, in points.
    ///   - footerPinned: The band's own row is pinned above the pager (true), or follows
    ///     the cards because it would cover the board (R11, AX5).
    /// - Returns: The row's label and frame, and the top of the pinned chrome.
    /// - Throws: A failed requirement.
    @MainActor
    @discardableResult
    private func assertRevealedRow(
        in app: XCUIApplication, minimumSide: CGFloat, footerPinned: Bool
    ) throws -> (label: String, frame: CGRect, chromeTop: CGFloat) {
        let row = app.buttons[Self.focusedRow]
        XCTAssertEqual(row.elementType, .button, "The band's row is not a button")
        XCTAssertTrue(row.label.hasPrefix("Your band, Rank 29, "), "The highlight is not spoken: \(row.label)")
        XCTAssertGreaterThanOrEqual(row.frame.width, minimumSide, "Row narrower than \(minimumSide) pt: \(row.frame)")
        XCTAssertGreaterThanOrEqual(row.frame.height, minimumSide, "Row shorter than \(minimumSide) pt: \(row.frame)")
        XCTAssertFalse(
            any("\(Self.boardPrefix)loading", in: app).exists, "The spinner is still in the tree after the reveal"
        )
        // Every other band on the page reads its rank first: only this one is highlighted.
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "\(Self.boardPrefix)row.")
        ).allElementsBoundByIndex
        XCTAssertGreaterThan(rows.count, 1, "The board shows no other band")
        for other in rows where other.identifier != Self.focusedRow {
            XCTAssertTrue(other.label.hasPrefix("Rank "), "\(other.identifier) reads \(other.label)")
        }

        // Reading order, from the layout (XCUITest lists descendants depth first, the pinned
        // chrome before the scrolling rows; `DuoDrawerJourneyTests` precedent): the song header,
        // rows by rank, then the band's own row, then the pager. The revealed row sits fully
        // above the pinned chrome, not under its fade.
        let footer = any("\(Self.boardPrefix)spotlight-footer", in: app)
        let pager = any("\(Self.boardPrefix)page-info", in: app).frame
        XCTAssertFalse(pager.isEmpty, "No pager")
        let chromeTop: CGFloat
        if footerPinned {
            XCTAssertTrue(footer.exists, "No pinned band row")
            XCTAssertLessThanOrEqual(footer.frame.maxY, pager.minY + 1, "The pinned band row is not above the pager")
            chromeTop = footer.frame.minY
        } else {
            // R11: the band's row comes after the cards, so it never covers the revealed one.
            if footer.exists {
                XCTAssertGreaterThanOrEqual(
                    footer.frame.minY, row.frame.maxY, "The band's own row covers the board at this size"
                )
            }
            chromeTop = pager.minY
        }
        XCTAssertLessThanOrEqual(row.frame.maxY, chromeTop + 1, "The revealed row is under the pinned chrome")
        let barBottom = app.navigationBars.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0
        XCTAssertGreaterThanOrEqual(row.frame.minY, barBottom - 1, "The revealed row is under the bar")
        let window = app.windows.firstMatch.frame
        let visible = rows.filter { $0.frame.minY >= window.minY && $0.frame.maxY <= chromeTop + 1 }
            .sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertTrue(visible.contains { $0.identifier == Self.focusedRow }, "The revealed row is off screen")
        let ranks = visible.compactMap { $0.identifier.split(separator: ":").last.flatMap { Int($0) } }
        XCTAssertEqual(ranks, ranks.sorted(), "Rows do not read by rank: \(visible.map(\.identifier))")
        let header = any("\(Self.boardPrefix)header", in: app).frame
        if header.maxY > window.minY, let first = visible.first {
            XCTAssertLessThanOrEqual(header.maxY, first.frame.minY + 1, "The song header does not read first")
        }
        return (row.label, row.frame, chromeTop)
    }

    /// Run the audit, attaching every issue. Every type but contrast must come back clean,
    /// except a Dynamic Type issue on the bell's system badge (``systemBadgeFrame(in:)``).
    /// Contrast follows the audit-waiver rules (testing/apple/accessibility.md): the shell's
    /// system toolbar badge is accepted (`system-toolbar-badge`), text in a bar's 8 pt
    /// scroll-edge band or the 36 pt fade above the pinned chrome is dimmed by design
    /// (`auditSoloPage`, issue #93), and any other flagged text, or the page when the
    /// auditor names no element, must render at least 4.5:1 in this run's capture
    /// (`contrast-rendered`, `unattributed-contrast-page-floor`).
    ///
    /// - Parameters:
    ///   - app: Running app on the revealed board.
    ///   - types: Audit types to run.
    ///   - chromeTop: Top of the pinned chrome (the band's row or the pager).
    ///   - name: Attachment name suffix.
    /// - Throws: An audit failure.
    @MainActor
    private func audit(
        _ app: XCUIApplication, types: XCUIAccessibilityAuditType, chromeTop: CGFloat, name: String
    ) throws {
        SongsUITestSupport.record(app, name: "song-band-reveal-\(name)")
        let badge = systemBadgeFrame(in: app)
        try app.performAccessibilityAudit(for: types.subtracting(.contrast)) { issue in
            let detail = self.attach(issue, name: name)
            if issue.auditType == .dynamicType, let frame = issue.element?.frame, Self.isSystemBadge(frame, in: badge) {
                return true
            }
            XCTFail("Band board audit (\(name)): \(detail)")
            return false
        }
        guard types.contains(.contrast) else { return }
        let window = app.windows.firstMatch.frame
        let barBottom = app.navigationBars.allElementsBoundByIndex.map(\.frame.maxY).max() ?? window.minY
        let content = CGRect(
            x: window.minX, y: barBottom + 8, width: window.width, height: chromeTop - 36 - barBottom - 8
        )
        try app.performAccessibilityAudit(for: .contrast) { issue in
            let detail = self.attach(issue, name: name)
            guard let element = issue.element, element.exists, !element.frame.isEmpty else {
                try self.assertRenderedContrastFloor(in: app, content: content)
                return true
            }
            let frame = element.frame
            if Self.isSystemBadge(frame, in: badge) { return true }
            guard content.contains(frame) else { return true }
            let ratio = try self.renderedContrast(of: frame, in: app)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "Band board contrast (\(name)): \(detail), rendered \(ratio):1")
            return true
        }
    }

    /// Every board row and the song header's text in `content` must render 4.5:1.
    ///
    /// - Parameters:
    ///   - app: Running app on the revealed board.
    ///   - content: The page area outside the bars' scroll-edge band and the pager fade.
    /// - Throws: A missing screenshot.
    @MainActor
    private func assertRenderedContrastFloor(in app: XCUIApplication, content: CGRect) throws {
        let targets = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ OR identifier == %@",
                        "\(Self.boardPrefix)row.", "\(Self.boardPrefix)header")
        ).allElementsBoundByIndex.map(\.frame).filter { content.contains($0) }
        XCTAssertFalse(targets.isEmpty, "No board text to measure")
        for frame in targets {
            let ratio = try renderedContrast(of: frame, in: app)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "Board text at \(frame) renders \(ratio):1")
        }
    }

    /// Rendered contrast of one screen region (`SongsUITestSupport.measuredTextContrast`).
    ///
    /// - Parameters:
    ///   - frame: Region in window points.
    ///   - app: Foreground app providing the composited screenshot.
    /// - Returns: The text-to-surface contrast ratio.
    /// - Throws: A missing screenshot or crop.
    @MainActor
    private func renderedContrast(of frame: CGRect, in app: XCUIApplication) throws -> Double {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let window = app.windows.firstMatch.frame
        let scale = Double(image.width) / window.width
        let crop = try XCTUnwrap(image.cropping(to: CGRect(
            x: (frame.minX - window.minX) * scale, y: (frame.minY - window.minY) * scale,
            width: frame.width * scale, height: frame.height * scale
        ).integral))
        return try SongsUITestSupport.measuredTextContrast(in: SongsUITestSupport.bitmapPixels(crop)).ratio
    }

    /// Whether an element's frame is on screen: its centre (where a tap lands) below the top
    /// 10% (the bars) and its bottom above a fraction of the window's height. Judged by
    /// frame, without asking whether it is hittable.
    ///
    /// - Parameters:
    ///   - element: Element to check.
    ///   - window: The app window's frame.
    ///   - below: Fraction of the window height the element must end above.
    /// - Returns: True when the element exists and its frame is in that band.
    @MainActor
    private static func isInView(_ element: XCUIElement, window: CGRect, below: CGFloat) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        return !frame.isEmpty && frame.midY >= window.minY + window.height * 0.1
            && frame.maxY <= window.minY + window.height * below
    }

    // MARK: - System badge

    /// The Notifications bell's frame when its system toolbar-item badge is the only place
    /// its count is drawn and the bell's own label speaks the count ("Notifications, 2
    /// unread"), so VoiceOver never needs the badge (`system-toolbar-badge`: UIKit draws
    /// and sizes the badge, as it caps what a bar hosts, `system-bar-title-size`).
    ///
    /// - Parameter app: Running app.
    /// - Returns: The bell's frame, or `.null` when the bell does not speak its count.
    @MainActor
    private func systemBadgeFrame(in app: XCUIApplication) -> CGRect {
        let bell = app.buttons["fst.shell.notifications"]
        guard bell.exists, bell.label.hasSuffix("unread") else { return .null }
        return bell.frame
    }

    /// Whether a flagged element lies on the bell's system badge.
    ///
    /// - Parameters:
    ///   - frame: The flagged element's frame.
    ///   - bell: ``systemBadgeFrame(in:)``.
    /// - Returns: True inside the bell's frame (4 pt slack for the badge's overhang).
    private static func isSystemBadge(_ frame: CGRect, in bell: CGRect) -> Bool {
        !bell.isNull && !bell.isEmpty && !frame.isEmpty && bell.insetBy(dx: -4, dy: -4).contains(frame)
    }

    // MARK: - Text evidence

    /// The kind of a board row's text, so the same text can be found at another size: a
    /// rank (`#29`), a score (`80,500`), an accuracy (`96.5%`), or the text itself.
    ///
    /// - Parameter label: The text's accessibility label.
    /// - Returns: The kind.
    private static func textKind(_ label: String) -> String {
        if label.range(of: #"^#[\d,]+$"#, options: .regularExpression) != nil { return "rank" }
        if label.range(of: #"^[\d,]+$"#, options: .regularExpression) != nil { return "score" }
        if label.hasSuffix("%") { return "accuracy" }
        return label
    }

    /// The tallest static text of each kind inside the board's band cards.
    ///
    /// - Parameter app: Running app on the revealed board.
    /// - Returns: Height by ``textKind(_:)``.
    @MainActor
    private func rowTextHeights(in app: XCUIApplication) -> [String: CGFloat] {
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "\(Self.boardPrefix)row.")
        ).allElementsBoundByIndex.map(\.frame)
        var heights: [String: CGFloat] = [:]
        for text in app.staticTexts.allElementsBoundByIndex {
            let frame = text.frame
            guard !frame.isEmpty, rows.contains(where: { $0.contains(frame) }) else { continue }
            let kind = Self.textKind(text.label)
            heights[kind] = max(heights[kind] ?? 0, frame.height)
        }
        attach(note: heights.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n"), name: "row-text-heights")
        return heights
    }

    /// A name on the board (card members or the band's own row) drawn narrower than its
    /// one-line width at the body style: R3's tail truncation.
    ///
    /// - Parameter app: Running app on the revealed board.
    /// - Returns: The truncated name, nil when every name fits.
    @MainActor
    private func truncatedName(in app: XCUIApplication) -> String? {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let footer = any("\(Self.boardPrefix)spotlight-footer", in: app)
        let board = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "\(Self.boardPrefix)row.")
        ).allElementsBoundByIndex.map(\.frame) + (footer.exists ? [footer.frame] : [])
        return app.staticTexts.allElementsBoundByIndex.first { text in
            let frame = text.frame
            guard !frame.isEmpty, Self.textKind(text.label) == text.label,
                  board.contains(where: { $0.contains(frame) }) else { return false }
            return (text.label as NSString).size(withAttributes: [.font: font]).width > frame.width + 2
        }?.label
    }

    // MARK: - Helpers

    /// Attach one audit issue to the run.
    ///
    /// - Parameters:
    ///   - issue: The issue.
    ///   - name: Attachment name suffix.
    /// - Returns: The issue's description.
    @discardableResult
    private func attach(_ issue: XCUIAccessibilityAuditIssue, name: String) -> String {
        let detail = "\(issue.compactDescription); element=\(issue.element?.identifier ?? "unidentified"), "
            + "label=\(issue.element?.label ?? "unidentified"), frame=\(String(describing: issue.element?.frame))"
        attach(note: detail, name: "audit-\(name)")
        return detail
    }

    /// Attach a note to the run.
    ///
    /// - Parameters:
    ///   - note: Text to keep.
    ///   - name: Attachment name suffix.
    private func attach(note: String, name: String) {
        let attachment = XCTAttachment(string: note)
        attachment.name = "song-band-reveal-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The first element of any type with an identifier.
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier.
    ///   - app: Running app.
    /// - Returns: The element query's first match.
    @MainActor
    private func any(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Wait up to 20 s (`FestivalApp.budget`) for an element to be hittable; on timeout record the screen and fail
    /// with its frame.
    ///
    /// - Parameters:
    ///   - element: Element to wait for.
    ///   - app: Running app, for the failure capture.
    ///   - message: Failure message.
    @MainActor
    private func waitHittable(_ element: XCUIElement, in app: XCUIApplication, _ message: String) {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: element
        )
        guard XCTWaiter().wait(for: [hittable], timeout: FestivalApp.budget(20)) != .completed else { return }
        SongsUITestSupport.record(app, name: "song-band-reveal-not-hittable")
        XCTFail("\(message): exists=\(element.exists), frame=\(element.frame), window=\(app.windows.firstMatch.frame)")
    }
}
