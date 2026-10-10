import UIKit
import Vision
import XCTest

// MARK: - View All Rivals at AX5 (issue #41, backfilled by #412)

/// The Rivals hub's purple "View All Rivals" button (#41: the shared button "View Full
/// Leaderboard" uses) on a real iPhone navigation stack with real Dynamic Type. macOS
/// has no Dynamic Type, so `FestivalUITests/RivalsViewAllAccessibilityTests` covers its
/// name, role, reading order and target against View Full Leaderboard in `apple-ci`, and
/// this journey is the iOS large-text evidence.
///
/// At AX5 the first View All Rivals must:
/// - read as one button named label first, then its card ("View All Rivals, … Rivals");
/// - grow its label (> 1.35× the default size's glyph height) and render every word of
///   it, wrapping instead of clipping or truncating;
/// - stay a full-width, hittable target at least 44 pt tall;
/// - pass a scoped audit (Dynamic Type, clipped text, hit region, description, contrast);
/// - open All Rivals when tapped.
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_RIVALS_A11Y_FIXTURE_URL` for another mock) with `fixture-riv` selected.
/// `apple-ci` runs it on its iPhone simulator (`testing/apple/xcuitest.md#ci-journeys`).
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases"; HIG
/// Accessibility: "Strive for the platform's recommended minimum control size" (iOS 44×44 pt).
final class RivalsViewAllAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_RIVALS_A11Y_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// The button's VoiceOver name: the visible label, then its card.
    private static let nameFormat = #"^View All Rivals, .+ Rivals$"#

    // MARK: - Journey

    /// At AX5 View All Rivals is named, grows, wraps whole, keeps its target and opens
    /// All Rivals.
    @MainActor
    func testViewAllRivalsIsReadableAtAX5() throws {
        continueAfterFailure = false
        let standard = try launchRivals(size: nil)
        let standardButton = try revealFirstViewAll(in: standard)
        let standardGlyphs = try SongsUITestSupport.brightGlyphHeight(in: standardButton)
        XCTAssertTrue(standardButton.label.hasPrefix("View All Rivals, "), "'\(standardButton.label)'")
        standard.terminate()

        let app = try launchRivals(size: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        let button = try revealFirstViewAll(in: app)
        let window = app.windows.firstMatch.frame
        let frame = button.frame
        record(button, name: "view-all-rivals-ax5")

        // Name, role and state.
        XCTAssertNotNil(button.label.range(of: Self.nameFormat, options: .regularExpression),
                        "label first, then the card: '\(button.label)'")
        XCTAssertEqual(button.elementType, .button)
        XCTAssertFalse(button.isSelected, "a push button has no selected state")

        // Target size.
        XCTAssertTrue(button.isHittable, "View All Rivals is reachable at AX5")
        XCTAssertGreaterThanOrEqual(frame.height, 44 - 1, "at least 44 pt tall: \(frame)")
        XCTAssertGreaterThan(frame.width, window.width * 0.75, "spans the card: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "starts on screen: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "ends on screen: \(frame)")

        // Text scaling: the label grows and every word renders whole.
        let glyphs = try SongsUITestSupport.brightGlyphHeight(in: button)
        XCTAssertGreaterThan(Double(glyphs), Double(standardGlyphs) * 1.35,
                             "the label grows at AX5: \(glyphs) px vs \(standardGlyphs) px")
        let lines = try Self.recognizeLines(button)
        XCTContext.runActivity(named: "Recognized: \(lines)") { _ in }
        let words = Set(lines.flatMap { $0.lowercased().split { !$0.isLetter }.map(String.init) })
        for word in ["view", "all", "rivals"] {
            XCTAssertTrue(words.contains(word), "'\(word)' renders whole: \(lines)")
        }
        XCTAssertFalse(lines.contains { $0.contains("…") || $0.contains("...") }, "no truncation: \(lines)")

        // Audit the button only: the rows and chrome have their own journeys.
        let identifier = button.identifier
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription, .contrast]
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            guard let element = issue.element, element.identifier == identifier else { return true }
            issues.append("\(element.identifier) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        do {
            try app.performAccessibilityAudit(for: audit, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            // The CI runner can exceed XCTest's audit deadline (#388): retry once.
            issues.removeAll()
            try app.performAccessibilityAudit(for: audit, handler)
        }
        XCTAssertEqual(issues, [], "View All Rivals audit issues at AX5")

        // Operable: it opens All Rivals.
        let reopened = app.buttons[identifier]
        XCTAssertTrue(reopened.waitForExistence(timeout: FestivalApp.budget(10)))
        if !reopened.isHittable { _ = try revealFirstViewAll(in: app) }
        reopened.tap()
        let allRivalsRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.all-rivals.row.")).firstMatch
        XCTAssertTrue(allRivalsRow.waitForExistence(timeout: FestivalApp.budget(20)), "View All Rivals opens All Rivals")
    }

    // MARK: - Launch and reveal

    /// Open Rivals with the fixture player at a text size.
    ///
    /// - Parameter size: A `UIContentSizeCategory` raw value; nil keeps the default.
    /// - Returns: The launched app on Rivals.
    @MainActor
    private func launchRivals(size: String?) throws -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
            "FST_DEBUG_ROUTE": "rivals",
        ])
        if let size {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: FestivalApp.budget(20)), "Rivals opens")
        return app
    }

    /// Scroll the first View All Rivals into the middle of the screen, clear of the
    /// scroll-edge fades and the bottom chrome, and let its card settle.
    ///
    /// - Parameter app: The app on Rivals.
    /// - Returns: The first View All Rivals button.
    @MainActor
    private func revealFirstViewAll(in app: XCUIApplication) throws -> XCUIElement {
        let button = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "fst.rivals.", ".view-all"
        )).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: FestivalApp.budget(20)), "Rivals shows a View All Rivals")
        let window = app.windows.firstMatch.frame
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<20 {
            let frame = button.frame
            if button.isHittable, frame.minY >= window.height * 0.2, frame.maxY <= window.height * 0.7 { break }
            // Move the button's centre towards the middle of the screen, at most half a screen per drag.
            let offset = max(-window.height * 0.4, min(window.height * 0.4, window.height * 0.45 - frame.midY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)))
        }
        // Let the drag's deceleration and the section's fade-in finish before reading pixels.
        sleep(UInt32(FestivalApp.budget(1)))
        XCTAssertTrue(button.isHittable, "View All Rivals scrolls on screen: \(button.frame)")
        return button
    }

    // MARK: - Rendered text

    /// Recognize the button's rendered lines, top to bottom.
    ///
    /// - Parameter element: The button on screen.
    /// - Returns: Each recognized line.
    /// - Throws: An unavailable capture.
    @MainActor
    private static func recognizeLines(_ element: XCUIElement) throws -> [String] {
        let image = try XCTUnwrap(element.screenshot().image.cgImage, "button capture")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        return (request.results ?? [])
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    /// Keep a capture of the element with the test result.
    @MainActor
    private func record(_ element: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
