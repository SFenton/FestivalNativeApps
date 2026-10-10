import UIKit
import XCTest

/// iPhone accessibility evidence for the Suggestions row whose cover is drawn from the
/// session's decoded-artwork cache (issue #28's scroll fix, tests backfilled by #403).
///
/// The row is driven onto the cached path for real: its cover loads, the list scrolls
/// until the `LazyVStack` drops the row, and scrolls back so a rebuilt row draws the
/// already-decoded cover in its first frame. Then, at the default text size and at the
/// largest accessibility size (AX5, a second launch), the row must:
///
/// - be one button whose name is the song title then "artist · year", with no artwork
///   wording (the tile is decorative, HIG VoiceOver: "Exclude purely decorative images
///   that convey no useful or actionable information");
/// - read after its category's heading and in the card's visual order;
/// - offer at least a 44×44 pt hittable target (HIG Accessibility, iOS/iPadOS default
///   control size 44×44 pt; one pixel of tolerance, testing/apple/accessibility.md);
/// - at AX5, grow its title glyphs by more than 1.35× and keep its title and subtitle
///   wholly inside the row and the window (no clipping);
/// - pass `performAccessibilityAudit`: `.all` at the default size, all but contrast at AX5
///   (the iPad AX5 modes' split). No issue may land on the row, and every flagged text
///   outside the scroll-edge ramp and the bottom chrome must render ≥ 4.5:1 in the same run
///   (testing/apple/xcuitest.md#ci-journeys). Other issue types elsewhere on the page are
///   attached, not judged: the region under test is the row (the QuickLinks AX5 precedent).
///
/// The hosted `PowerSavingAccessibilityTests` stay the fast shared-control regression test
/// (ArtworkTile in every state, the backdrop slot, first-run pulses); this journey is what
/// only an iOS run proves: real Dynamic Type growth, the iPhone target and the audit.
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_SUGGESTIONS_A11Y_FIXTURE_URL` to use another mock): `fixture-player-1`
/// gets a populated mix of synthetic songs with generated `pulse`/`orbit` covers.
final class SuggestionsAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_SUGGESTIONS_A11Y_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    private static let standard = "UICTContentSizeCategoryL"
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let rowPrefix = "fst.suggestions.row."
    /// Words that would mean the artwork tile reached VoiceOver in one of its states.
    private static let artworkWords = ["artwork", "album art", "loading", "photo", "music.note"]

    /// What one size's row measured.
    struct RowEvidence: CustomStringConvertible {
        let identifier: String
        let label: String
        let frame: CGRect
        /// Rendered height of the title's bright glyphs, in pixels.
        let titleGlyphHeight: Int

        var description: String { "\(identifier) '\(label)' \(frame) title glyphs \(titleGlyphHeight) px" }
    }

    // MARK: - Journey

    /// The cached-cover row at the default size and at AX5: one named button in reading
    /// order, a 44×44 pt target, AX5 growth without clipping and a clean row audit.
    ///
    /// - Throws: A missing fixture, row or measurement.
    @MainActor
    func testCachedArtRowIsAccessibleAtDefaultSizeAndAX5() throws {
        try requireFixture()
        let standard = try cachedArtRow(category: Self.standard, name: "default")
        let largest = try cachedArtRow(category: Self.largest, name: "ax5")
        XCTAssertEqual(standard.identifier, largest.identifier, "The same row at both sizes")
        XCTAssertEqual(standard.label, largest.label, "The row's name does not depend on text size")
        XCTAssertGreaterThan(
            Double(largest.titleGlyphHeight), Double(standard.titleGlyphHeight) * 1.35,
            "The title did not grow at AX5: \(standard) → \(largest)"
        )
        XCTAssertGreaterThan(
            largest.frame.height, standard.frame.height * 1.35,
            "The row did not grow with its text at AX5: \(standard) → \(largest)"
        )
    }

    // MARK: - One size

    /// Launch at a text size, put the first row on its cached-cover path and check it.
    ///
    /// - Parameters:
    ///   - category: `UIPreferredContentSizeCategoryName` value.
    ///   - name: Attachment prefix for this size.
    /// - Returns: The row's measurements.
    /// - Throws: A missing list, row, cover or measurement.
    @MainActor
    private func cachedArtRow(category: String, name: String) throws -> RowEvidence {
        continueAfterFailure = false
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_TAB": "suggestions",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        app.launch()
        defer { app.terminate() }

        let list = app.scrollViews.matching(identifier: "fst.suggestions.list").firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: FestivalApp.budget(30)), "No Suggestions list")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
        let first = rows.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: FestivalApp.budget(15)), "No row with its own identifier")
        let identifier = first.identifier
        let row = app.buttons[identifier]
        XCTAssertTrue(waitForCover(of: row, in: app), "\(name): the cover never loaded")

        // Scroll until the lazy stack drops the row, then back: the rebuilt row draws the
        // cover this session already decoded (#28) in its first frame.
        for _ in 0..<12 where row.exists { list.swipeUp(velocity: .fast) }
        XCTAssertFalse(row.exists, "\(name): the row was never released, so it cannot be rebuilt")
        for _ in 0..<16 where !(row.exists && row.isHittable && row.frame.minY > 0) {
            list.swipeDown(velocity: .fast)
        }
        list.swipeDown(velocity: .fast)
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(5)), "\(name): the row did not come back")
        XCTAssertTrue(coverDrawn(of: row, in: app), "\(name): the rebuilt row did not draw its cached cover")
        SongsUITestSupport.record(app, name: "suggestions-cached-art-row-\(name)")

        let evidence = try assertRow(row, in: app, name: name)
        try auditRow(row, in: app, name: name, contrast: category == Self.standard)
        return evidence
    }

    // MARK: - Row checks

    /// Name, role, reading order, target size and (at AX5) clipping of one row.
    ///
    /// - Parameters:
    ///   - row: The row's button, on screen.
    ///   - app: The app on Suggestions.
    ///   - name: Size name for messages.
    /// - Returns: The row's measurements.
    /// - Throws: A missing title or measurement.
    @MainActor
    private func assertRow(_ row: XCUIElement, in app: XCUIApplication, name: String) throws -> RowEvidence {
        let label = row.label
        // Name: title, then "artist · year" (web `SongInfo`), and nothing about the cover.
        let parts = label.components(separatedBy: ", ")
        XCTAssertGreaterThanOrEqual(parts.count, 2, "\(name): '\(label)'")
        let title = parts[0]
        let subtitle = parts[1]
        XCTAssertFalse(title.isEmpty, "\(name): untitled row '\(label)'")
        XCTAssertNotNil(subtitle.range(of: #"^.+ · \d{4}$"#, options: .regularExpression),
                        "\(name): subtitle is not 'artist · year': '\(label)'")
        for word in Self.artworkWords {
            XCTAssertFalse(label.lowercased().contains(word), "\(name): the cover reached the row's name: '\(label)'")
        }
        XCTAssertEqual(row.elementType, .button, "\(name): role")
        XCTAssertTrue(row.isEnabled, "\(name): state")

        // Reading order: the snapshot (what VoiceOver walks; it omits hidden views) lists
        // the card's heading, then its rows top to bottom, and the tile adds no element.
        let snapshot = try app.snapshot()
        var ordered: [XCUIElementSnapshot] = []
        func walk(_ node: XCUIElementSnapshot) {
            ordered.append(node)
            node.children.forEach(walk)
        }
        walk(snapshot)
        let rowIndex = try XCTUnwrap(ordered.firstIndex { $0.identifier == row.identifier && $0.elementType == .button })
        let rowNode = ordered[rowIndex]
        var inRow: [XCUIElementSnapshot] = []
        func collect(_ node: XCUIElementSnapshot) { node.children.forEach { inRow.append($0); collect($0) } }
        collect(rowNode)
        for node in inRow {
            XCTAssertFalse(
                Self.artworkWords.contains { node.label.lowercased().contains($0) },
                "\(name): a row child names the cover: \(node.elementType) '\(node.label)'"
            )
            XCTAssertFalse(
                [.image, .activityIndicator].contains(node.elementType) && !node.label.isEmpty,
                "\(name): the tile is an accessible element: \(node.elementType) '\(node.label)'"
            )
        }
        let heading = ordered[..<rowIndex].last(where: {
            $0.elementType == .staticText && $0.frame.maxY <= rowNode.frame.minY
        })
        XCTAssertNotNil(heading, "\(name): no category heading reads before the row")
        let cardRows = ordered.filter {
            $0.elementType == .button && $0.identifier.hasPrefix(Self.rowPrefix)
                && abs($0.frame.minX - rowNode.frame.minX) < 1
        }
        XCTAssertEqual(
            cardRows.map(\.identifier), cardRows.sorted { $0.frame.minY < $1.frame.minY }.map(\.identifier),
            "\(name): rows do not read in visual order"
        )

        // Target: 44×44 pt with one pixel of tolerance, fully on screen and hittable.
        let frame = row.frame
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(row.isHittable, "\(name): not hittable \(frame)")
        XCTAssertGreaterThanOrEqual(frame.width, 43.6, "\(name): target width \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 43.6, "\(name): target height \(frame)")
        XCTAssertTrue(window.contains(frame), "\(name): the row leaves the window \(frame) \(window)")

        // Text: wholly inside the row (a clamped row would cut a wrapped title or subtitle).
        let titleText = row.staticTexts[title].firstMatch
        let subtitleText = row.staticTexts[subtitle].firstMatch
        XCTAssertTrue(titleText.exists, "\(name): no title text in the row")
        XCTAssertTrue(subtitleText.exists, "\(name): no subtitle text in the row")
        for text in [titleText, subtitleText] {
            XCTAssertTrue(
                frame.insetBy(dx: -0.5, dy: -0.5).contains(text.frame),
                "\(name): '\(text.label)' \(text.frame) is clipped by the row \(frame)"
            )
        }
        XCTAssertLessThanOrEqual(titleText.frame.maxY, subtitleText.frame.minY + 0.5,
                                 "\(name): the subtitle overlaps the title")
        return RowEvidence(
            identifier: row.identifier, label: label, frame: frame,
            titleGlyphHeight: try SongsUITestSupport.brightGlyphHeight(in: titleText)
        )
    }

    /// Audit the page: fail on any issue on the row, and on any contrast issue whose text
    /// does not render at least 4.5:1.
    ///
    /// Issues of other types on other elements are attached, not judged: this journey's
    /// region is the row (the QuickLinks AX5 audit scopes the same way). Contrast follows the
    /// CI handler rule (testing/apple/xcuitest.md#ci-journeys): text in the 40 pt scroll-edge
    /// ramp under the bar or behind the bottom chrome is dimmed by design (`scroll-edge`
    /// R2/R5); every other flagged text, on the row or not, must measure ≥ 4.5:1 with at least
    /// 20 glyph pixels in the app as the audit left it. An issue without an element passes on
    /// the row's own checks in this run (name, frame, clipping and every row text measured).
    ///
    /// - Parameters:
    ///   - row: The row's button, on screen.
    ///   - app: The app on Suggestions.
    ///   - name: Size name for attachments.
    ///   - contrast: Whether to include the contrast audit (default size only).
    /// - Throws: An audit error or a missing measurement.
    @MainActor
    private func auditRow(_ row: XCUIElement, in app: XCUIApplication, name: String, contrast: Bool) throws {
        let rowFrame = row.frame
        let rowId = row.identifier
        let window = app.windows.firstMatch.frame
        let rampEnd = app.navigationBars.firstMatch.frame.maxY + 40
        let chromeTop = [app.descendants(matching: .any)["fst.page-tools"], app.tabBars.firstMatch]
            .filter { $0.exists && $0.frame.minY > window.midY }
            .map(\.frame.minY).min() ?? window.maxY
        for text in row.staticTexts.allElementsBoundByIndex where !text.frame.isEmpty {
            let reading = try renderedContrast(of: text.frame, in: app)
            XCTAssertTrue(
                reading.ratio >= 4.5 && reading.brightPixels >= 20,
                "\(name): '\(text.label)' renders \(reading) on the row"
            )
        }
        var failures: [String] = []
        let types: XCUIAccessibilityAuditType = contrast ? .all : XCUIAccessibilityAuditType.all.subtracting(.contrast)
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            let element = issue.element
            let frame = element?.frame ?? .zero
            let inRow = element?.identifier == rowId
                || (!frame.isEmpty && rowFrame.insetBy(dx: -1, dy: -1).contains(frame))
            var verdict = "unattributed"
            defer {
                let attachment = XCTAttachment(string: "\(issue.auditType): \(issue.detailedDescription); "
                    + "element=\(element?.identifier ?? "none") label=\(element?.label ?? "none") frame=\(frame) "
                    + "inRow=\(inRow) row=\(rowFrame) ramp=\(rampEnd) chromeTop=\(chromeTop) verdict=\(verdict)")
                attachment.name = "suggestions-row-audit-\(name)"
                attachment.lifetime = .keepAlways
                self.add(attachment)
            }
            guard element != nil, !frame.isEmpty else { return true }
            if issue.auditType == .contrast {
                if !inRow, frame.minY < rampEnd || frame.maxY > chromeTop {
                    verdict = "dimmed by design (scroll-edge ramp or bottom chrome)"
                    return true
                }
                let reading = try? self.renderedContrast(of: frame, in: app)
                verdict = "rendered \(String(describing: reading))"
                if let reading, reading.ratio >= 4.5, reading.brightPixels >= 20 { return true }
                failures.append("contrast: '\(element?.label ?? "")' \(frame) \(verdict)")
                return true
            }
            guard inRow else {
                verdict = "outside the row"
                return true
            }
            verdict = "row issue"
            failures.append("\(issue.auditType): \(issue.compactDescription) ('\(element?.label ?? "")')")
            return true
        }
        do {
            try app.performAccessibilityAudit(for: types, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            // A runner audit can exceed XCTest's deadline (#388): retry once, then fail.
            failures.removeAll()
            try app.performAccessibilityAudit(for: types, handler)
        }
        XCTAssertEqual(failures, [], "\(name): Suggestions audit issues")
    }

    // MARK: - Pixels

    /// Wait until the row's tile shows its cover.
    ///
    /// - Parameters:
    ///   - row: The row's button.
    ///   - app: The app on Suggestions.
    /// - Returns: Whether the cover appeared in time.
    @MainActor
    private func waitForCover(of row: XCUIElement, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(FestivalApp.budget(15))
        while Date() < deadline {
            if row.exists, coverDrawn(of: row, in: app) { return true }
            usleep(250_000)
        }
        return false
    }

    /// Whether the row's 44 pt leading tile shows the generated cover, read from one
    /// screenshot: the fixture's dark blue-violet gradient, with no near-white glyph (the
    /// loading spinner and the failure or no-art symbols are white).
    ///
    /// - Parameters:
    ///   - row: The row's button.
    ///   - app: The app on Suggestions.
    /// - Returns: Whether the cover is drawn.
    @MainActor
    private func coverDrawn(of row: XCUIElement, in app: XCUIApplication) -> Bool {
        guard row.exists, let image = app.screenshot().image.cgImage else { return false }
        let window = app.windows.firstMatch.frame
        let scale = CGFloat(image.width) / window.width
        let frame = row.frame
        // The tile is the row's leading 44 pt square (XCUITest still lists the hidden view's
        // frame); read its inner 32 pt to skip the rounded corners.
        let image44 = row.images.firstMatch
        let square = image44.exists && !image44.frame.isEmpty
            ? image44.frame : CGRect(x: frame.minX, y: frame.midY - 22, width: 44, height: 44)
        let tile = square.insetBy(dx: 6, dy: 6)
        guard let crop = image.cropping(to: CGRect(
            x: tile.minX * scale, y: tile.minY * scale, width: tile.width * scale, height: tile.height * scale
        ).integral), let pixels = try? SongsUITestSupport.bitmapPixels(crop) else { return false }
        var white = 0
        var violet = 0
        let count = pixels.count / 4
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            if red > 200 && green > 200 && blue > 200 { white += 1 }
            if blue > red + 12 && blue > green + 8 { violet += 1 }
        }
        return white == 0 && violet > count / 2
    }

    /// Rendered contrast of the text in one frame, from a fresh app screenshot.
    ///
    /// - Parameters:
    ///   - frame: A text element's frame, in window points.
    ///   - app: The app on Suggestions.
    /// - Returns: The text-to-surface reading.
    /// - Throws: A missing screenshot or crop.
    @MainActor
    private func renderedContrast(
        of frame: CGRect, in app: XCUIApplication
    ) throws -> (ratio: Double, background: Double, text: Double, brightPixels: Int) {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let window = app.windows.firstMatch.frame
        let scale = CGFloat(image.width) / window.width
        let visible = frame.intersection(window)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(
            x: (visible.minX - window.minX) * scale, y: (visible.minY - window.minY) * scale,
            width: visible.width * scale, height: visible.height * scale
        ).integral))
        return try SongsUITestSupport.measuredTextContrast(in: SongsUITestSupport.bitmapPixels(crop))
    }

    /// Skip unless the fixture answers its publication read.
    private func requireFixture() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.origin)/api/publication"))
        let done = expectation(description: "fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --large-catalogue` on \(Self.origin)")
    }
}
