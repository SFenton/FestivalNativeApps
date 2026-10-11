import UIKit
import Vision
import XCTest

// MARK: - Rival rows at AX5 (issue #40, backfilled by #411)

/// The shared rival row on the Rivals page at the largest accessibility text size (AX5), on a
/// real iPhone navigation stack with real Dynamic Type. macOS hosting can't scale text, so
/// `FestivalUITests/RivalRowAccessibilityTests` covers names, order, target size and the
/// restack in `apple-ci`, and this journey is the iOS AX5 evidence for #40's row.
///
/// The first Common Rivals row must:
/// - read as one button named by the rival and both pills, with no "shared" count (#40);
/// - stay a full-width target at least 44 pt tall;
/// - render "ahead" and "behind" as whole words (#411: side by side, the green pill split
///   "ahea/d");
/// - keep the wrapped name leading-aligned (#411: the row link centred it);
/// - pass a scoped audit (Dynamic Type, clipped text, hit region, description, contrast).
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_RIVALS_A11Y_FIXTURE_URL` for another mock) with `fixture-riv` selected.
/// `apple-ci` runs it on its iPhone simulator (`testing/apple/xcuitest.md#ci-journeys`).
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases"; HIG
/// Accessibility: 44×44 pt default control size.
final class RivalsAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_RIVALS_A11Y_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// A row's VoiceOver name: rival, then both pills, and nothing else.
    private static let rowLabel = #"^.+, \d+ songs ahead, \d+ songs behind$"#

    // MARK: - Journey

    /// At AX5 the first rival row reads, sizes and renders accessibly, without a shared count.
    @MainActor
    func testRivalRowsAreReadableAtAX5() throws {
        continueAfterFailure = false
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
            "FST_DEBUG_ROUTE": "rivals",
        ])
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["Rivals"].waitForExistence(timeout: FestivalApp.budget(20)), "Rivals opens")

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.rivals.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(20)), "Rivals lists a rival")
        // Let the section's fade-in finish before reading pixels.
        sleep(UInt32(FestivalApp.budget(1)))
        let window = app.windows.firstMatch.frame
        let frame = row.frame
        record(row, name: "rival-row-ax5")

        // Name, role and state.
        XCTAssertNotNil(row.label.range(of: Self.rowLabel, options: .regularExpression),
                        "the row reads the rival and both pills: '\(row.label)'")
        XCTAssertFalse(row.label.localizedCaseInsensitiveContains("shared"), "no shared count: '\(row.label)'")
        let sharedTexts = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@ OR label ENDSWITH[c] %@", "shared", " shared"))
        XCTAssertEqual(sharedTexts.count, 0, "no 'N shared' text on Rivals")

        // Target size.
        XCTAssertTrue(row.isHittable, "the row is reachable at AX5")
        XCTAssertGreaterThanOrEqual(frame.height, 44, "the row is at least 44 pt tall: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "the row starts on screen: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "the row ends on screen: \(frame)")
        XCTAssertGreaterThan(frame.width, window.width * 0.75, "the row spans the card: \(frame)")

        // Rendered text: whole pill words, leading-aligned name.
        let lines = try Self.recognizeLines(row)
        XCTContext.runActivity(named: "Recognized: \(lines.map(\.text))") { _ in }
        let words = Set(lines.flatMap { Self.words($0.text) })
        XCTAssertTrue(words.contains("ahead"), "'ahead' renders whole: \(lines.map(\.text))")
        XCTAssertTrue(words.contains("behind"), "'behind' renders whole: \(lines.map(\.text))")
        let name = String(row.label.prefix { $0 != "," })
        let nameWords = Set(Self.words(name))
        let nameLines = lines.filter { line in
            let found = Self.words(line.text)
            return !found.isEmpty && found.allSatisfy(nameWords.contains)
        }
        XCTAssertFalse(nameLines.isEmpty, "the name renders: \(lines.map(\.text))")
        let starts = nameLines.map { $0.minX * frame.width }
        if let first = starts.min(), let last = starts.max() {
            XCTAssertLessThanOrEqual(last - first, 6, "the wrapped name is leading-aligned: \(nameLines)")
        }

        // Audit the row (rivals higher up the page included, none below it: those run
        // under the bottom chrome's fade).
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription, .contrast]
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            guard let element = issue.element, element.identifier.hasPrefix("fst.rivals.row."),
                  element.frame.maxY <= frame.maxY + 1 else { return true }
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
        XCTAssertEqual(issues, [], "rival row audit issues at AX5")
    }

    // MARK: - Recognition

    /// One recognized line: its text and leading edge (fraction of the capture's width).
    private struct Line: CustomStringConvertible {
        let text: String
        let minX: CGFloat
        var description: String { String(format: "'%@' @%.3f", text, minX) }
    }

    /// Recognize the row's rendered lines, top to bottom.
    ///
    /// - Parameter element: The row on screen.
    /// - Returns: Each recognized line with its leading edge.
    /// - Throws: An unavailable capture.
    @MainActor
    private static func recognizeLines(_ element: XCUIElement) throws -> [Line] {
        let image = try XCTUnwrap(element.screenshot().image.cgImage, "row capture")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        return (request.results ?? [])
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { observation in
                observation.topCandidates(1).first.map { Line(text: $0.string, minX: observation.boundingBox.minX) }
            }
    }

    /// Lower-cased letter words of a recognized line (digits dropped).
    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
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
