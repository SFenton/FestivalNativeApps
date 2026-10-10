import Vision
import XCTest

// MARK: - Song page season at the largest text size (issue #32, backfilled by #406)

/// The season a score was achieved in (issue #32) on a real iPhone Song page, at the
/// standard and the largest accessibility text size.
///
/// A portrait iPhone page is narrower than the web's 520 pt season breakpoint, so the
/// Score History list rows never speak a season, while the tapped bar's detail row always
/// does (web `renderDetailCard`). The journey selects a bar, then checks the detail row: it is
/// static text whose label names the season between the date and the score, it spans the
/// card at least 44 pt tall, it grows with the text into one column (date, "Season N",
/// score, accuracy), stays inside the screen and Vision reads every drawn word whole on one
/// line (#406: side by side at AX5 they split a letter per line); a scoped audit covers Dynamic Type,
/// clipped text, hit regions and descriptions on the Score History rows. macOS hosting
/// cannot scale text, so this journey is the iPhone text-size evidence;
/// `FestivalUITests/SongSeasonAccessibilityTests` covers names, roles, order, frames and the
/// wide-page and top-score forms in `apple-ci`'s hosted tests.
///
/// Needs `tools/mock_service.py` (its `fixture-history-multi` account: eight Lead scores on
/// `fixture-pulse`, all season 40); `apple-ci` serves it with `--large-catalogue` on the
/// default port 8765, and `FST_SEASON_FIXTURE_URL` points a local run at another port.
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases"; HIG
/// Accessibility: "Never rely on color alone" and a 44×44 pt default control size.
final class SongSeasonAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_SEASON_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    private static let standard = "UICTContentSizeCategoryL"
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let detailId = "fst.song-detail.history.detail"

    /// The tapped bar's row speaks its season at both sizes, grows at the largest size,
    /// stays on screen, and passes the scoped audit; list rows on a phone speak none.
    @MainActor
    func testTappedScoreSeasonIsReadableAtLargestText() throws {
        try requireFixture()
        let standard = try tappedDetailRow(category: Self.standard)
        let largest = try tappedDetailRow(category: Self.largest, audit: true)
        XCTAssertGreaterThan(
            largest.height, standard.height + 20,
            "The detail row did not grow with the text: \(standard) → \(largest)"
        )
    }

    // MARK: - Helpers

    /// Open `fixture-pulse` as `fixture-history-multi` at a text size, select a Score History
    /// bar and check its detail row.
    ///
    /// - Parameters:
    ///   - category: `UIPreferredContentSizeCategoryName` value.
    ///   - audit: Run the scoped accessibility audit on the Score History rows.
    /// - Returns: The detail row's frame.
    /// - Throws: A missing page, chart or detail row, or an audit failure.
    @MainActor
    private func tappedDetailRow(category: String, audit: Bool = false) throws -> CGRect {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_PROFILE": "fixture-history-multi:Multi History",
            "FST_DEBUG_SONG": "fixture-pulse",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        app.launchArguments += ["-fst.accessibility.reduceMotion", "YES"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(element("fst.song-detail.hero-title", in: app).waitForExistence(timeout: FestivalApp.budget(20)))

        let chart = element("fst.song-detail.history.chart", in: app)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(chart.waitForExistence(timeout: FestivalApp.budget(15)), "No Score History chart (\(category))")
        scroll(app, toTop: chart, window: window)
        XCTAssertTrue(
            chart.frame.maxY <= window.maxY - 120,
            "Score History chart is not on screen (\(category)): \(chart.frame)"
        )

        // Narrower than 520 pt: the list rows speak no season (web `QUERY_SHOW_SEASON`).
        let row = element("fst.song-detail.history.row.0", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(10)), "No best-score row")
        if window.width < 520 {
            XCTAssertFalse(row.label.contains("season"), "A phone list row speaks the season: \(row.label)")
        }

        // Swift Charts' x selection follows a touch; a short press selects the middle bar.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 0.4)
        let detail = element(Self.detailId, in: app)
        XCTAssertTrue(
            detail.waitForExistence(timeout: FestivalApp.budget(10)),
            "Selecting a bar shows no detail row (\(category))"
        )
        XCTAssertEqual(detail.elementType, .staticText, "The detail row is not read as text (\(category))")
        scroll(app, toTop: detail, window: window)
        XCTAssertTrue(
            detail.frame.minY >= window.minY + 100 && detail.frame.minY <= window.minY + 320,
            "The detail row cannot be scrolled into view: \(detail.frame)"
        )
        let label = detail.label
        let season = try XCTUnwrap(label.range(of: "season 40"), "The tapped score's season is not spoken: \(label)")
        let score = try XCTUnwrap(label.range(of: ", score "), "No score in \(label)")
        XCTAssertLessThan(season.lowerBound, score.lowerBound, "Season reads before the score: \(label)")
        XCTAssertFalse(label.range(of: #"\bS40\b"#, options: .regularExpression) != nil, "Abbreviated season spoken: \(label)")

        let frame = detail.frame
        XCTAssertGreaterThanOrEqual(frame.height, 44, "The detail row's frame is not the whole row: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX, "The detail row starts off screen: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX, "The detail row runs off screen: \(frame)")
        XCTAssertGreaterThan(frame.width, window.width * 0.7, "The detail row's frame is not the whole row: \(frame)")
        SongsUITestSupport.record(app, name: "song-season-detail-\(category)")
        // No word of the date, season, score or accuracy is split across lines: at AX5 a
        // side-by-side row broke "Feb", "Season" and "850,000" a letter or two per line.
        let lines = Self.recognizedLines(detail)
        for word in try Self.visibleWords(label, spelledSeason: category == Self.largest) {
            XCTAssertTrue(
                lines.contains { Self.normalized($0).contains(Self.normalized(word)) },
                "'\(word)' is split across lines or unreadable (\(category)): \(lines)"
            )
        }

        if audit {
            var issues: [String] = []
            try app.performAccessibilityAudit(
                for: [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
            ) { issue in
                let id = issue.element?.identifier ?? ""
                guard id.hasPrefix("fst.song-detail.history.row.") || id == Self.detailId else { return true }
                issues.append("\(id) '\(issue.element?.label ?? "")': \(issue.compactDescription)")
                return true
            }
            XCTAssertEqual(issues, [], "Score History row audit issues at \(category)")
        }
        return frame
    }

    /// The words a detail row draws, from its spoken label ("Feb 7, 2024, season 40, score
    /// 850,000, accuracy 99.1 percent" draws "Feb 7, 2024", "S40" or "Season 40", "850,000"
    /// and "99.1%").
    ///
    /// - Parameters:
    ///   - label: The row's accessibility label.
    ///   - spelledSeason: Accessibility sizes spell the pill out ("Season 40", not "S40").
    /// - Returns: Each drawn word.
    /// - Throws: A label without a date, season, score or accuracy.
    private static func visibleWords(_ label: String, spelledSeason: Bool) throws -> [String] {
        func capture(_ pattern: String) throws -> String {
            let match = try XCTUnwrap(label.firstMatch(of: try Regex(pattern)), "No \(pattern) in \(label)")
            return try XCTUnwrap(match.output[1].substring.map(String.init))
        }
        let date = try capture("^(.+?), (?:current )?season ")
        let season = try capture("season ([0-9]+)")
        return date.split(separator: " ").map(String.init)
            + (spelledSeason ? ["Season", season] : ["S" + season])
            + [try capture("score ([0-9,]+)"), try capture("accuracy ([0-9.]+) percent") + "%"]
    }

    /// Lines of text Vision reads from an element's capture, top to bottom.
    ///
    /// - Parameter element: A row on screen.
    /// - Returns: The recognized lines.
    @MainActor
    private static func recognizedLines(_ element: XCUIElement) -> [String] {
        guard let image = element.screenshot().image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
        return (request.results ?? [])
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    /// Letters and digits only, lowercased.
    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Bring an element's top just under the navigation bar with short drags that carry no
    /// momentum. At the largest size the detail row is taller than the band a swipe lands
    /// in; the drags start in the trailing page margin (the leading edge pops the page), since
    /// the chart's selection gesture would take a drag that starts on it.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - element: The element to bring up.
    ///   - window: The app window's frame.
    @MainActor
    private func scroll(_ app: XCUIApplication, toTop element: XCUIElement, window: CGRect) {
        let from = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.8))
        for _ in 0..<24 where element.frame.minY > window.minY + 320 {
            from.press(
                forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -160)),
                withVelocity: .slow, thenHoldForDuration: 0.2
            )
        }
    }

    /// Any element with this accessibility identifier.
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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
