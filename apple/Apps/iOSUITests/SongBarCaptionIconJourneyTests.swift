import XCTest

/// The pinned song title's instrument caption is led by the instrument's icon (pattern
/// `song-header` R4, `song-leaderboard-header` R3, issue #542), measured in the rendered
/// pixels of the real iPhone navigation bar, because the icon is hidden from VoiceOver
/// and so has no element, frame or label to assert on.
///
/// Each check finds the caption line (the lowest band of bright pixels right of the
/// 28 pt art), then its first glyph run: with the icon that is the white instrument
/// disc, square and clearly taller than the caption's letters, about 4 pt before the
/// name; without it, the run is the name's first letters, no taller than the text, and
/// the check fails. At the largest accessibility size the disc must grow by the same
/// factor as the caption text (the bar caps its text at a size above the standard one,
/// and the icon follows the caption's text style), so a fixed-size icon fails too.
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765;
/// set `TEST_RUNNER_FST_CAPTION_ICON_FIXTURE_URL` to use another mock): `fixture-pulse`
/// Lead has 26 rows, so its header scrolls away at every size, and
/// `fixture-history-multi` has eight Lead scores, which overflow at the largest size.
final class SongBarCaptionIconJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_CAPTION_ICON_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    private static let standard = "UICTContentSizeCategoryL"
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    /// What the caption line of a pinned title rendered, in points.
    struct CaptionLine {
        /// Width and height of the first glyph run (the icon when present).
        let leadWidth: CGFloat
        let leadHeight: CGFloat
        /// Height of the caption's first word after the first run ("Lead": cap and
        /// ascender height, no descender).
        let textHeight: CGFloat
        /// Gap between the first run and the text.
        let gap: CGFloat
    }

    // MARK: - Song Leaderboard

    /// The Song Leaderboard's pinned caption shows the Lead icon at the standard size and
    /// at the largest accessibility size, scaled with the caption text, and the title
    /// still reads as one element naming the song and the instrument once (its heading
    /// trait is asserted by the hosted `SongHeaderTextTests`, which can read traits).
    @MainActor
    func testSongLeaderboardCaptionIconScalesWithText() throws {
        try requireFixture()
        let standard = try leaderboardCaption(category: Self.standard)
        let largest = try leaderboardCaption(category: Self.largest)
        assertIconLeads(standard, "standard size")
        assertIconLeads(largest, "largest size")
        // The art's white disc spans 120 of its 144 px, so a 14 pt icon shows about 11.7 pt.
        XCTAssertGreaterThanOrEqual(standard.leadHeight, 10.5, "The icon is smaller than its 14 pt default: \(standard)")
        XCTAssertGreaterThan(
            largest.leadHeight, standard.leadHeight * 1.15,
            "The icon did not grow at the largest size: \(standard) → \(largest)"
        )
        let textGrowth = largest.textHeight / standard.textHeight
        let iconGrowth = largest.leadHeight / standard.leadHeight
        XCTAssertEqual(
            iconGrowth, textGrowth, accuracy: 0.2,
            "The icon does not scale with the caption text: \(standard) → \(largest)"
        )
    }

    // MARK: - Player History

    /// Player History's pinned caption ("Lead · Score History") shares the same title, so
    /// at the largest accessibility size it is also led by the scaled Lead icon.
    @MainActor
    func testPlayerHistoryCaptionIconAtLargestText() throws {
        try requireFixture()
        let app = launch(category: Self.largest, route: [
            "FST_DEBUG_PROFILE": "fixture-history-multi:Multi History",
        ])
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        for _ in 0..<30 where !(song.exists && song.isHittable) { app.swipeUp() }
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(15)), "No fixture-pulse row")
        song.tap()
        XCTAssertTrue(element("fst.song-detail.hero-title", in: app).waitForExistence(timeout: FestivalApp.budget(20)))
        let viewAll = element("fst.song-detail.history.view-all", in: app)
        for _ in 0..<12 where !(viewAll.exists && viewAll.isHittable) { app.swipeUp() }
        XCTAssertTrue(viewAll.waitForExistence(timeout: FestivalApp.budget(10)), "No View All Scores")
        viewAll.tap()
        XCTAssertTrue(
            element("fst.history.row.0", in: app).waitForExistence(timeout: FestivalApp.budget(15)),
            "No Player History page"
        )
        let pinned = try pin("fst.history.pinned-title", in: app)
        XCTAssertEqual(pinned.label.components(separatedBy: "Lead").count, 2, "Instrument once: \(pinned.label)")
        let caption = try measureCaption(pinned, name: "history-caption-icon-axxxl")
        assertIconLeads(caption, "Player History, largest size")
    }

    // MARK: - Helpers

    /// Open `fixture-pulse` Lead at a text size, pin its title and measure the caption.
    ///
    /// - Parameter category: `UIPreferredContentSizeCategoryName` value.
    /// - Returns: The caption line's measurements.
    @MainActor
    private func leaderboardCaption(category: String) throws -> CaptionLine {
        let app = launch(category: category, route: [
            "FST_DEBUG_ANONYMOUS": "1",
            "FST_DEBUG_SONG": "fixture-pulse",
            "FST_DEBUG_SONG_INSTRUMENT": "Solo_Guitar",
        ])
        let pinned = try pin("fst.song-leaderboard.pinned-title", in: app)
        XCTAssertTrue(pinned.label.hasPrefix("Fixture Pulse"), pinned.label)
        XCTAssertEqual(pinned.label.components(separatedBy: "Fixture Pulse").count, 2, "Title once: \(pinned.label)")
        XCTAssertEqual(pinned.label.components(separatedBy: "Lead").count, 2, "Instrument once: \(pinned.label)")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "fst.song-leaderboard.pinned-title").count, 1,
            "One pinned title"
        )
        let caption = try measureCaption(pinned, name: "leaderboard-caption-icon-\(category)")
        app.terminate()
        return caption
    }

    /// Launch the app at a Dynamic Type category with fixture route keys.
    ///
    /// - Parameters:
    ///   - category: `UIPreferredContentSizeCategoryName` value.
    ///   - route: Extra launch environment.
    /// - Returns: The launched app.
    @MainActor
    private func launch(category: String, route: [String: String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ].merging(route) { $1 })
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        app.launch()
        SongsUITestSupport.collapseSidebarOnPad(app)
        return app
    }

    /// Scroll the page until its header pins its title to the bar.
    ///
    /// - Parameters:
    ///   - identifier: The pinned title's identifier.
    ///   - app: The app on the page.
    /// - Returns: The pinned title, inside the bar.
    @MainActor
    private func pin(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let pinned = element(identifier, in: app)
        var attempts = 0
        repeat {
            sleep(2)
            app.swipeUp()
            attempts += 1
        } while !(pinned.exists && pinned.isHittable) && attempts < 8
        XCTAssertTrue(pinned.waitForExistence(timeout: FestivalApp.budget(10)), "The title did not pin: \(identifier)")
        // Let the bar's fade-in finish before reading pixels.
        sleep(UInt32(FestivalApp.budget(1)))
        let bar = app.navigationBars.firstMatch.frame
        XCTAssertTrue(bar.insetBy(dx: 0, dy: -2).contains(pinned.frame), "\(pinned.frame) left the bar \(bar)")
        return pinned
    }

    /// Measure the caption line of a pinned title from its screenshot.
    ///
    /// - Parameters:
    ///   - pinned: The pinned title element.
    ///   - name: Attachment name for the captured title.
    /// - Returns: The caption line's first run and text, in points.
    @MainActor
    private func measureCaption(_ pinned: XCUIElement, name: String) throws -> CaptionLine {
        let shot = pinned.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(shot.image.cgImage)
        let scale = CGFloat(image.width) / max(pinned.frame.width, 1)
        let pixels = try SongsUITestSupport.bitmapPixels(image)
        let caption = try XCTUnwrap(
            Self.captionLine(pixels, width: image.width, height: image.height, scale: scale),
            "No caption line in \(name)"
        )
        XCTContext.runActivity(named: "\(name): \(caption)") { _ in }
        return caption
    }

    /// Find the caption line and its first glyph run in a pinned title's pixels.
    ///
    /// - Parameters:
    ///   - pixels: RGBA bytes, row-major from the top.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - scale: Pixels per point.
    /// - Returns: The caption measurements in points, or nil when no caption is drawn.
    static func captionLine(_ pixels: [UInt8], width: Int, height: Int, scale: CGFloat) -> CaptionLine? {
        func bright(_ x: Int, _ y: Int) -> Bool {
            let offset = (y * width + x) * 4
            return pixels[offset] > 215 && pixels[offset + 1] > 215 && pixels[offset + 2] > 215
        }
        // Right of the 28 pt art and its 8 pt spacing.
        let left = min(width, Int((31 * scale).rounded()))
        let rows = (0..<height).map { y in (left..<width).contains { bright($0, y) } }
        // Bands of bright rows; a one-point gap separates the title from the caption.
        var bands: [ClosedRange<Int>] = []
        var y = 0
        while y < height {
            guard rows[y] else { y += 1; continue }
            var end = y
            var gap = 0
            var cursor = y + 1
            while cursor < height, gap < Int(scale.rounded()) {
                if rows[cursor] { end = cursor; gap = 0 } else { gap += 1 }
                cursor += 1
            }
            bands.append(y...end)
            y = end + 1
        }
        guard bands.count >= 2, let line = bands.last else { return nil }
        let columns = (left..<width).map { x in line.contains { bright(x, $0) } }
        // A glyph run from `start`, tolerating sub-point gaps from antialiasing.
        let tolerance = max(1, Int((scale * 0.7).rounded()))
        func runEnd(from start: Int) -> Int {
            var end = start
            var cursor = start + 1
            while cursor < columns.count, cursor - end <= tolerance {
                if columns[cursor] { end = cursor }
                cursor += 1
            }
            return end
        }
        guard let first = columns.firstIndex(of: true) else { return nil }
        let leadEnd = runEnd(from: first)
        guard let textStart = columns[(leadEnd + 1)...].firstIndex(of: true) else { return nil }
        let textEnd = runEnd(from: textStart)
        func verticalExtent(_ xs: ClosedRange<Int>) -> Int {
            let ys = line.filter { y in xs.contains { bright(left + $0, y) } }
            return (ys.max() ?? 0) - (ys.min() ?? 0) + 1
        }
        return CaptionLine(
            leadWidth: CGFloat(leadEnd - first + 1) / scale,
            leadHeight: CGFloat(verticalExtent(first...leadEnd)) / scale,
            textHeight: CGFloat(verticalExtent(textStart...textEnd)) / scale,
            gap: CGFloat(textStart - leadEnd - 1) / scale
        )
    }

    /// Assert the caption's first run is the instrument icon immediately before the name.
    ///
    /// - Parameters:
    ///   - caption: The measured caption line.
    ///   - context: Which page and size, for messages.
    private func assertIconLeads(_ caption: CaptionLine, _ context: String) {
        XCTAssertEqual(
            caption.leadWidth, caption.leadHeight, accuracy: max(1.5, caption.leadHeight * 0.15),
            "\(context): the caption's first glyph is not the square icon: \(caption)"
        )
        XCTAssertGreaterThan(
            caption.leadHeight, caption.textHeight * 1.15,
            "\(context): no icon taller than the caption text leads it: \(caption)"
        )
        XCTAssertGreaterThanOrEqual(caption.gap, 2, "\(context): the icon touches the name: \(caption)")
        XCTAssertLessThanOrEqual(caption.gap, 10, "\(context): the icon is not immediately left of the name: \(caption)")
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
