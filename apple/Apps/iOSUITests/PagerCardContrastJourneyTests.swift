import UIKit
import XCTest

// MARK: - Pager on the row card (issue #319, backfilled by #467)

/// The leaderboard pager on the rows' card (`festivalCard`, pattern `surface-materials`
/// R1; issue #319), rendered: on Player Bands (the CI fixture pages `fixture-player-1`'s
/// 30-band "All" group, 25 a page) the "page / total" badge's text keeps at least 4.5:1
/// against its card and each enabled arrow's chevron at least 3:1 against its capsule,
/// while the disabled arrows (First and Previous on page 1) are visibly dimmer than the
/// enabled ones yet still drawn. It holds on the translucent material (iOS composites
/// the backdrop blur, which macOS hosted capture skips), on the opaque card the app's
/// Reduce Transparency setting draws, and with its Increase Contrast setting.
///
/// Names, roles, states, reading order, 44 pt targets and AX5 for the same pager and
/// rows are `BoardFooterFadeJourneyTests`; the macOS hosted
/// `FestivalUITests/RankingsPagerCardAccessibilityTests` covers the card frames, the
/// opaque-card contrast and the band cards' VoiceOver press in every transparency mode.
///
/// Needs `tools/mock_service.py` (`apple-ci` serves it with `--large-catalogue` on the
/// default port 8765; `FST_BOARD_FADE_FIXTURE_URL`, as
/// `TEST_RUNNER_FST_BOARD_FADE_FIXTURE_URL`, points a local run at another port). Skips
/// when the board never loads.
///
/// HIG Accessibility: "Strive for a minimum contrast ratio of 4.5:1" for text;
/// WCAG 1.4.11 asks 3:1 for a control's graphical parts.
final class PagerCardContrastJourneyTests: XCTestCase {
    private static let fixtureService = ProcessInfo.processInfo.environment["FST_BOARD_FADE_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    /// The page badge.
    private static let pageInfo = "fst.player-bands.page-info"
    /// The arrows disabled on page 1, then the enabled ones.
    private static let disabledArrows = ["fst.player-bands.page-first", "fst.player-bands.page-previous"]
    private static let enabledArrows = ["fst.player-bands.page-next", "fst.player-bands.page-last"]

    // MARK: - Journeys

    /// The translucent material card (the default).
    @MainActor
    func testPagerCardKeepsContrastOnTheMaterial() throws {
        try assertPagerContrast(settings: [:], mode: "material")
    }

    /// The opaque card (Settings › Reduce Transparency) and Increase Contrast.
    @MainActor
    func testPagerCardKeepsContrastOpaqueAndIncreasedContrast() throws {
        try assertPagerContrast(settings: ["lessTransparency": true], mode: "Reduce Transparency")
        try assertPagerContrast(settings: ["moreContrast": true], mode: "Increase Contrast")
    }

    // MARK: - Assertions

    /// Launch Player Bands with the app's accessibility settings and measure the pager.
    ///
    /// - Parameters:
    ///   - settings: `fst.accessibility.*` settings to turn on or off.
    ///   - mode: Label for failure messages.
    /// - Throws: A skip when the board never loads, or a failed requirement.
    @MainActor
    private func assertPagerContrast(settings: [String: Bool], mode: String) throws {
        continueAfterFailure = false
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixtureService,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_ROUTE": "playerBands:fixture-player-1",
        ])
        for key in ["lessTransparency", "moreContrast"] {
            app.launchArguments += ["-fst.accessibility.\(key)", settings[key] == true ? "YES" : "NO"]
        }
        app.launch()
        defer { app.terminate() }
        let info = app.descendants(matching: .any)[Self.pageInfo]
        guard info.waitForExistence(timeout: FestivalApp.budget(20)) else {
            throw XCTSkip("Player Bands never loaded; run tools/mock_service.py on \(Self.fixtureService).")
        }
        XCTAssertEqual(info.value as? String, "1 of 2", "\(mode): not on page 1")
        // Let the card's entrance settle before reading pixels.
        let enabled = app.buttons[Self.enabledArrows[0]]
        XCTAssertTrue(enabled.waitForExistence(timeout: FestivalApp.budget(5)), "\(mode): no Next arrow")
        Thread.sleep(forTimeInterval: 1)

        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let window = app.windows.firstMatch.frame
        let badge = try measure(info, in: image, window: window)
        XCTAssertGreaterThanOrEqual(badge.ratio, 4.5, "\(mode): badge text \(badge)")
        XCTAssertGreaterThan(badge.brightPixels, 100, "\(mode): no badge text \(badge)")

        var enabledRatios: [Double] = []
        for id in Self.enabledArrows {
            let arrow = app.buttons[id]
            XCTAssertTrue(arrow.isEnabled, "\(mode): \(id) disabled on page 1")
            let measured = try measure(arrow, in: image, window: window)
            XCTAssertGreaterThanOrEqual(measured.ratio, 3, "\(mode): \(id) chevron \(measured)")
            XCTAssertGreaterThan(measured.brightPixels, 20, "\(mode): no \(id) chevron \(measured)")
            enabledRatios.append(measured.ratio)
        }
        for id in Self.disabledArrows {
            let arrow = app.buttons[id]
            XCTAssertFalse(arrow.isEnabled, "\(mode): \(id) enabled on page 1")
            let measured = try measure(arrow, in: image, window: window)
            XCTAssertGreaterThanOrEqual(measured.ratio, 1.3, "\(mode): \(id) chevron not drawn \(measured)")
            XCTAssertLessThan(
                measured.ratio * 1.3, enabledRatios.min() ?? 0,
                "\(mode): \(id) does not look disabled (\(measured.ratio) vs \(enabledRatios))"
            )
        }
    }

    /// Glyph-over-surface contrast inside one element's frame of a screenshot.
    ///
    /// - Parameters:
    ///   - element: The badge or an arrow, wholly on screen.
    ///   - image: The app's screenshot.
    ///   - window: The window's frame.
    /// - Returns: `SongsUITestSupport.measuredTextContrast` of the element's crop.
    /// - Throws: An off-screen element or unreadable crop.
    @MainActor
    private func measure(
        _ element: XCUIElement, in image: CGImage, window: CGRect
    ) throws -> (ratio: Double, background: Double, text: Double, brightPixels: Int) {
        let frame = element.frame
        XCTAssertTrue(window.contains(frame), "\(element.identifier) off screen: \(frame)")
        let scaleX = Double(image.width) / window.width
        let scaleY = Double(image.height) / window.height
        let crop = try XCTUnwrap(image.cropping(to: CGRect(
            x: (frame.minX - window.minX) * scaleX, y: (frame.minY - window.minY) * scaleY,
            width: frame.width * scaleX, height: frame.height * scaleY
        ).integral))
        return try SongsUITestSupport.measuredTextContrast(in: SongsUITestSupport.bitmapPixels(crop))
    }
}
