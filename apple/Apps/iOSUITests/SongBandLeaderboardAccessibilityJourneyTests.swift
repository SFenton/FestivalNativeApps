import XCTest

// MARK: - Band song leaderboard header accessibility (issue #317, backfilled by #465)

/// The Duos/Trios/Quads song leaderboard on a real iPhone, at the standard and the
/// largest accessibility text size (issue #317 gave it the solo board's song header with
/// the band size as its board line, the pinned song title after scrolling and the song's
/// static album-art background; patterns `song-header`, `song-leaderboard-header`).
///
/// Each run opens `fixture-pulse` Duos and checks: the header is one element whose label
/// reads the song title, the artist, then "Duos · N entries", each once, inside the
/// screen and above (and read before) the band rows; a scoped `performAccessibilityAudit`
/// on the header and the band rows (Dynamic Type, clipped text, hit regions and element
/// descriptions); and after scrolling, the bar's pinned title names the song and
/// Duos once each inside the navigation bar. The header's drawn text reads back whole
/// (`RecognizedText`) at both sizes, and at AX5 its glyphs grow by at least
/// `RecognizedText.minimumGrowth` and the header grows taller.
/// macOS hosting cannot scale text, so this journey is the iPhone text-size and audit
/// evidence; `FestivalUITests/SongBandLeaderboardHeaderAccessibilityTests` covers the
/// heading trait, reading order, every band size, the accessibility-size wrap and the
/// static backdrop in `apple-ci`'s hosted tests. Contrast over artwork belongs to the
/// whole-app audits (`testing/strategy.md`), so it is not audited here.
///
/// The Band Size tool is not checked: the `FST_DEBUG_SONG_BAND` route pushes the page
/// without `pageToolsScope(inSelectedTab:)`, so its page tools never reach the floating page tools
/// (`testing/apple/xcuitest.md` Pitfalls), and #317 did not change it.
///
/// Needs `tools/mock_service.py`; `apple-ci` serves it with `--large-catalogue` on the
/// default port 8765, and `FST_BAND_BOARD_FIXTURE_URL` points a local run at another port.
///
/// HIG VoiceOver: "Use titles and headings to convey hierarchy"; HIG Typography: "Keep
/// text truncation to a minimum as font size increases"; HIG Accessibility: iOS default
/// control size 44×44 pt (the band rows, through the `.hitRegion` audit).
final class SongBandLeaderboardAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_BAND_BOARD_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    private static let standard = "UICTContentSizeCategoryL"
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let headerID = "fst.song-band-leaderboard.header"
    private static let rowPrefix = "fst.song-band-leaderboard.row."
    private static let pinnedID = "fst.song-band-leaderboard.pinned-title"
    private static let songTitle = "Fixture Pulse"
    private static let artist = "Synthetic Quartet"

    // MARK: - Journeys

    /// At the standard size the header and the pinned title are named, ordered and drawn
    /// whole, and the scoped audit passes.
    @MainActor
    func testBandBoardHeaderIsAccessibleAtStandardSize() throws {
        try requireFixture()
        _ = try checkBoard(category: Self.standard)
    }

    /// At the largest accessibility size the header grows with the text (it does not clip
    /// or keep its standard height), keeps its whole label and stays inside the screen;
    /// the scoped audit passes and the title still pins.
    @MainActor
    func testBandBoardHeaderGrowsAtAX5() throws {
        try requireFixture()
        let standard = try checkBoard(category: Self.standard, pin: false)
        let largest = try checkBoard(category: Self.largest)
        XCTAssertGreaterThan(
            largest.header.height, standard.header.height * 1.3,
            "The header did not grow with the text: \(standard.header) → \(largest.header)"
        )
        XCTAssertEqual(largest.label, standard.label, "The header's label changed at AX5")
        let ratio = largest.lineHeight / standard.lineHeight
        XCTAssertGreaterThan(
            ratio, RecognizedText.minimumGrowth,
            "The header's glyphs did not grow at AX5: \(standard.lineHeight) → \(largest.lineHeight) pt"
        )
    }

    // MARK: - Helpers

    /// What one run measured.
    struct Measured {
        let header: CGRect
        let label: String
        /// Median recognized line height of the header's drawn text, in points.
        let lineHeight: CGFloat
    }

    /// Open `fixture-pulse` Duos at a text size and check its header region.
    ///
    /// - Parameters:
    ///   - category: `UIPreferredContentSizeCategoryName` value.
    ///   - pin: Also scroll the header away and check the bar's pinned title.
    /// - Returns: The header's frame, label and drawn line height.
    /// - Throws: A missing page, header or pinned title, or an audit failure.
    @MainActor
    private func checkBoard(category: String, pin: Bool = true) throws -> Measured {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_DEBUG_ANONYMOUS": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_SONG": "fixture-pulse",
            "FST_DEBUG_SONG_BAND": "Band_Duets",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        app.launch()
        defer { app.terminate() }
        SongsUITestSupport.collapseSidebarOnPad(app)

        let header = element(Self.headerID, in: app)
        XCTAssertTrue(header.waitForExistence(timeout: FestivalApp.budget(20)), "No band board header (\(category))")
        let loaded = NSPredicate(format: "label CONTAINS %@", "Duos · ")
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation(for: loaded, evaluatedWith: header)], timeout: FestivalApp.budget(20)),
            .completed, "The header never named Duos with its total (\(category)): \(header.label)"
        )
        let firstRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix)).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: FestivalApp.budget(15)), "No band rows (\(category))")
        SongsUITestSupport.record(app, name: "song-band-header-\(category)")

        // Name: one element reading title, artist, then the band size with its total.
        let label = header.label
        let parts = [Self.songTitle, Self.artist, "Duos · ", " entries"]
        var cursor = label.startIndex
        for part in parts {
            let range = try XCTUnwrap(
                label.range(of: part, range: cursor..<label.endIndex),
                "'\(part)' missing or out of order in the header (\(category)): \(label)"
            )
            cursor = range.upperBound
        }
        XCTAssertEqual(label.components(separatedBy: Self.songTitle).count, 2, "Title once: \(label)")
        XCTAssertFalse(label.contains("Trios") || label.contains("Quads"), "Only Duos is named: \(label)")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: Self.headerID).count, 1, "One header")
        XCTAssertFalse(app.staticTexts["Duos Scores"].exists, "The old '<Band> Scores' title is back")

        // Layout and reading order: inside the screen, above and read before the rows.
        let window = app.windows.firstMatch.frame
        let frame = header.frame
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "Header starts off screen (\(category)): \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "Header runs off screen (\(category)): \(frame)")
        XCTAssertLessThanOrEqual(frame.maxY, firstRow.frame.minY + 0.5, "Header is not above the rows: \(frame)")
        // Drawn: the title, artist and band size show whole (no truncation at either size).
        let reading = RecognizedText.recognize(header, label: Self.songTitle, frame: frame)
        for drawn in [Self.songTitle, Self.artist, "Duos"] {
            XCTAssertTrue(RecognizedText.showsWhole(drawn, in: reading.text),
                          "The header does not draw '\(drawn)' whole (\(category)): '\(reading.text ?? "nil")'")
        }
        let lineHeight = try XCTUnwrap(reading.lineHeight, "No header text recognized (\(category))")
        let ordered = try FestivalApp.snapshotNodes(in: app) {
            $0.identifier == Self.headerID || $0.identifier.hasPrefix(Self.rowPrefix)
        }.map(\.identifier)
        XCTAssertEqual(ordered.first, Self.headerID, "The header is not read before the rows: \(ordered.prefix(3))")

        try audit(app, category: category)

        if pin {
            let pinned = element(Self.pinnedID, in: app)
            var attempts = 0
            repeat {
                app.swipeUp()
                attempts += 1
            } while !(pinned.exists && pinned.isHittable) && attempts < 8
            XCTAssertTrue(pinned.waitForExistence(timeout: FestivalApp.budget(10)), "The title did not pin (\(category))")
            // Let the bar's fade-in finish (SongBarCaptionIconJourneyTests.pin).
            sleep(UInt32(FestivalApp.budget(1)))
            let bar = app.navigationBars.firstMatch.frame
            XCTAssertTrue(bar.insetBy(dx: 0, dy: -2).contains(pinned.frame), "\(pinned.frame) left the bar \(bar)")
            XCTAssertEqual(pinned.label.components(separatedBy: Self.songTitle).count, 2, "Title once: \(pinned.label)")
            XCTAssertEqual(pinned.label.components(separatedBy: "Duos").count, 2, "Duos once: \(pinned.label)")
            SongsUITestSupport.record(app, name: "song-band-pinned-\(category)")
        }
        return Measured(header: frame, label: label, lineHeight: lineHeight)
    }

    /// Audit the header, the pinned title and the band rows for Dynamic Type, clipped text,
    /// hit regions and element descriptions; other elements belong to their own journeys.
    ///
    /// - Parameters:
    ///   - app: The app on the band board.
    ///   - category: The text size, for messages.
    /// - Throws: An audit that cannot run.
    @MainActor
    private func audit(_ app: XCUIApplication, category: String) throws {
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription],
            name: "band board \(category)", reset: { issues.removeAll() }
        ) { issue in
            let id = issue.element?.identifier ?? ""
            guard id == Self.headerID || id == Self.pinnedID || id.hasPrefix(Self.rowPrefix) else { return true }
            issues.append("\(id) '\(issue.element?.label ?? "")': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Band board header audit issues at \(category)")
    }

    /// Any element with an identifier.
    @MainActor
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
