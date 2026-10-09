import UIKit
import XCTest

/// Text scaling of the player profile's selection-pause notice on a real iPhone (issue
/// #446, backfilling #97).
///
/// #97 removed the avatar-and-name card from the top of the profile, so the only card
/// left above Global Statistics is the pause notice (`PlayerProfileIdentityNotice`),
/// drawn in `.footnote` gold. The hosted `PlayerProfileAccessibilityTests` pin its
/// VoiceOver order and wrapping on the macOS host, where text styles do not grow (HIG
/// Typography: "macOS doesn't support Dynamic Type"). This journey proves real growth:
/// the notice's rendered gold glyphs at AX5 are more than 1.35× their default-size height
/// (`.agents/testing/apple/accessibility.md`), every line the message needs is drawn, and
/// the whole notice is on screen between the navigation bar and the bottom chrome, above
/// the Global Statistics heading. HIG Accessibility: text enlargement "of at least 200%".
///
/// Needs an unpinned fixture listener, so the player read proves no publication and the
/// `.unverified` notice shows:
///
///     python3 tools/mock_service.py --port 18446 --unpinned
///
/// `TEST_RUNNER_FST_PROFILE_NOTICE_FIXTURE_URL=<origin>` points a run at another one.
final class ProfileNoticeTextSizeJourneyTests: XCTestCase {
    // MARK: - Fixture

    /// The unpinned fixture origin.
    private static let fixtureURL = ProcessInfo.processInfo.environment["FST_PROFILE_NOTICE_FIXTURE_URL"]
        ?? "http://127.0.0.1:18446"
    /// `PlayerProfileIdentityNotice.unverified.message`.
    private static let message = "These scores have no verified publication. Selection is paused."
    /// The page's first section heading (`PlayerProfileContent.overallSection`).
    private static let firstHeading = "Global Statistics"
    /// Horizontal padding of a card row (`FestivalRowPadding`) around the notice text.
    private static let rowInset: CGFloat = 16
    /// Smallest AX5 / default growth of the rendered glyphs.
    private static let minimumGrowth = 1.35

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// Whether the fixture answers as an unpinned service.
    ///
    /// - Returns: True when `/api/publication` reports pinning off.
    private func unpinnedFixtureReachable() -> Bool {
        let probe = expectation(description: "fixture probe")
        var unpinned = false
        let url = URL(string: "\(Self.fixtureURL)/api/publication")!
        URLSession.shared.dataTask(with: url) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                unpinned = object["pinningEnabled"] as? Bool == false
            }
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 5)
        return unpinned
    }

    // MARK: - Measurement

    /// One launch's measurement of the notice.
    private struct NoticeReading {
        /// The notice's frame in points.
        let frame: CGRect
        /// The tallest gold text line, in screenshot pixels.
        let glyphHeight: Int
        /// Gold text lines drawn.
        let lines: Int
        /// Lines the message needs at the notice's width and text size.
        let neededLines: Int
    }

    /// Open Fixture Player 1's profile (anonymous, unpinned) and measure the notice.
    ///
    /// - Parameter contentSize: Dynamic Type category the app launches at.
    /// - Returns: The measurement; the app is terminated afterwards.
    /// - Throws: A missing notice or heading, or an unreadable capture.
    @MainActor
    private func readNotice(at contentSize: UIContentSizeCategory) throws -> NoticeReading {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_DEBUG_TAB": "settings",
            "FST_DEBUG_ROUTE": "player:fixture-player-1",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        app.launch()
        defer { app.terminate() }
        let name = contentSize == .large ? "default" : "ax5"

        let page = app.scrollViews["fst.player.available"]
        XCTAssertTrue(page.waitForExistence(timeout: 30), "The fixture profile did not load")
        let notice = page.staticTexts["fst.player.unverified"]
        XCTAssertTrue(notice.waitForExistence(timeout: 15), "No unverified notice on an unpinned read")
        XCTAssertEqual(notice.label, Self.message)
        let heading = page.staticTexts[Self.firstHeading]
        XCTAssertTrue(heading.waitForExistence(timeout: 15), "No \(Self.firstHeading) heading")
        // Let the notice's fade-in (`festivalFadeIn`, stagger slot 0) finish.
        Thread.sleep(forTimeInterval: 1.5)
        SongsUITestSupport.record(app, name: "profile-unverified-notice-\(name)")

        let frame = notice.frame
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(frame), "\(name): notice \(frame) leaves the window \(window)")
        let bar = app.navigationBars.firstMatch
        if bar.exists {
            XCTAssertGreaterThanOrEqual(frame.minY, bar.frame.maxY - 0.5,
                                        "\(name): notice \(frame) starts under the navigation bar \(bar.frame)")
        }
        let bottomChrome = [app.tabBars.firstMatch, app.buttons["fst.quick-links.open"]]
            .filter { $0.exists && !$0.frame.isEmpty && $0.frame.minY > frame.minY }
            .map(\.frame.minY).min() ?? window.maxY
        XCTAssertLessThanOrEqual(frame.maxY, bottomChrome + 0.5,
                                 "\(name): notice \(frame) runs under the bottom chrome at \(bottomChrome)")
        XCTAssertLessThanOrEqual(frame.maxY, heading.frame.minY + 0.5,
                                 "\(name): notice \(frame) overlaps \(Self.firstHeading) \(heading.frame)")

        let ink = try Self.goldLines(in: notice)
        let font = UIFont.preferredFont(
            forTextStyle: .footnote,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: contentSize)
        )
        // The notice's frame is its card row; the text column sits inside the row padding.
        let needed = (Self.message as NSString).boundingRect(
            with: CGSize(width: frame.width - 2 * Self.rowInset, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
        ).height
        let neededLines = Int((needed / font.lineHeight).rounded())
        return NoticeReading(frame: frame, glyphHeight: ink.tallest, lines: ink.lines, neededLines: neededLines)
    }

    /// Gold (`BrandTokens.gold`, the notice ink) text lines in an element's capture.
    ///
    /// - Parameter element: The notice text.
    /// - Returns: The number of separate runs of gold pixel rows and the tallest run.
    /// - Throws: An unavailable capture or no gold ink.
    @MainActor
    private static func goldLines(in element: XCUIElement) throws -> (lines: Int, tallest: Int) {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let pixels = try SongsUITestSupport.bitmapPixels(image)
        var lines = 0
        var run = 0
        var tallest = 0
        for y in 0..<image.height {
            let gold = (0..<image.width).contains { x in
                let offset = (y * image.width + x) * 4
                return pixels[offset] > 180 && pixels[offset + 1] > 140 && pixels[offset + 2] < 90
            }
            if gold {
                if run == 0 { lines += 1 }
                run += 1
                tallest = max(tallest, run)
            } else {
                run = 0
            }
        }
        XCTAssertGreaterThan(lines, 0, "No gold notice ink in \(element.frame)")
        return (lines, tallest)
    }

    // MARK: - Tests

    /// The notice's glyphs grow more than 1.35× at AX5, and at both sizes the whole
    /// message is drawn on screen above Global Statistics.
    @MainActor
    func testUnverifiedNoticeGrowsAndStaysWholeAtLargestText() throws {
        try XCTSkipUnless(
            unpinnedFixtureReachable(),
            "Start `mock_service.py --port 18446 --unpinned` from this revision"
        )
        let normal = try readNotice(at: .large)
        let large = try readNotice(at: .accessibilityExtraExtraExtraLarge)
        let summary = XCTAttachment(string: """
            default: frame \(normal.frame), glyphs \(normal.glyphHeight) px, lines \(normal.lines)/\(normal.neededLines)
            AX5: frame \(large.frame), glyphs \(large.glyphHeight) px, lines \(large.lines)/\(large.neededLines)
            """)
        summary.name = "profile-unverified-notice-readings"
        summary.lifetime = .keepAlways
        add(summary)

        XCTAssertGreaterThan(
            Double(large.glyphHeight), Double(normal.glyphHeight) * Self.minimumGrowth,
            "Notice glyphs \(normal.glyphHeight) → \(large.glyphHeight) px did not grow with Dynamic Type"
        )
        XCTAssertEqual(normal.lines, normal.neededLines, "Default notice draws \(normal.lines) of \(normal.neededLines) lines")
        XCTAssertGreaterThanOrEqual(large.neededLines, 3, "At AX5 the message wraps at \(large.frame.width) pt")
        XCTAssertEqual(large.lines, large.neededLines, "AX5 notice draws \(large.lines) of \(large.neededLines) lines")
        XCTAssertGreaterThan(large.frame.height, normal.frame.height * Self.minimumGrowth,
                             "The notice's frame \(normal.frame) → \(large.frame) did not grow")
    }
}
