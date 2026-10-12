import UIKit
import XCTest

// MARK: - Song Row Visual Order at AX5 (#372, backfilled by #494)

/// Settings' Enable Independent Song Row Visual Order switch and its inline
/// drag-to-reorder Song Row Visual Order list (#372) on a real iPhone with real Dynamic
/// Type. macOS has no Dynamic Type, so the hosted
/// `FestivalUITests/SettingsVisualOrderAccessibilityTests` pin names, roles, reading
/// order, Move Up / Move Down actions, Reduce Motion and the list/detail page in
/// `apple-ci`; this journey is the iOS large-text evidence.
///
/// At AX5, with Independent Visual Order on:
/// - the switch is a hittable switch named with the web's label, reading on, at least 44 pt;
/// - every row is named by the web's label (Score … Last Played), reads its position
///   ("n of 8"), spans the list and is at least 44 pt tall;
/// - row text grows (> 1.35× its default line height, `RecognizedText`) and the longest
///   label, Song Intensity, renders whole;
/// - a scoped audit (Dynamic Type, clipped text, hit region, description, contrast) finds
///   nothing in the switch or the list.
///
/// State comes from launch arguments (the argument domain), so nothing persists between
/// runs. Runs against the CI fixture origin (`tools/mock_service.py --large-catalogue`,
/// port 8765; set `TEST_RUNNER_FST_SETTINGS_A11Y_FIXTURE_URL` for another mock); Settings
/// makes no request this journey depends on. `apple-ci` runs it on its iPhone simulator
/// (`testing/apple/xcuitest.md#ci-journeys`).
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases"; HIG
/// Accessibility: "Strive for the platform's recommended minimum control size" (iOS 44×44 pt).
final class SettingsVisualOrderAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_SETTINGS_A11Y_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    private static let switchID = "fst.settings.enable-visual-order"
    private static let listID = "fst.settings.song-row-order"
    /// The web's `DEFAULT_METADATA_ORDER` with its row titles.
    private static let rows: [(key: String, label: String)] = [
        ("score", "Score"), ("percentage", "Percentage"), ("percentile", "Percentile"), ("stars", "Stars"),
        ("season", "Season Achieved"), ("intensity", "Song Intensity"), ("difficulty", "Difficulty"),
        ("lastPlayed", "Last Played"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Journey

    /// At AX5 the switch and every Song Row Visual Order row are named, keep their state
    /// and position, keep 44 pt targets, grow and render whole, and pass a scoped audit.
    @MainActor
    func testSongRowVisualOrderIsReadableAtAX5() throws {
        let standard = launchSettings(size: nil)
        let standardRow = try reveal(row("intensity", in: standard), in: standard)
        let standardHeight = try read(standardRow, drawn: "Song Intensity", "Song Intensity, default size")
        standard.terminate()

        let app = launchSettings(size: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        let window = app.windows.firstMatch.frame

        let toggle = app.switches[Self.switchID]
        XCTAssertTrue(toggle.waitForExistence(timeout: FestivalApp.budget(15)), "the switch shows")
        _ = try reveal(toggle, in: app)
        XCTAssertTrue(toggle.label.contains("Enable Independent Song Row Visual Order"), "'\(toggle.label)'")
        XCTAssertEqual(toggle.value as? String, "1", "the switch reads on")
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44 - 0.5, "switch target: \(toggle.frame)")
        record(app, name: "settings-visual-order-switch-ax5")

        for (index, item) in Self.rows.enumerated() {
            let element = try reveal(row(item.key, in: app), in: app)
            let frame = element.frame
            XCTAssertEqual(element.label, item.label, "\(item.key) is named by its web label")
            XCTAssertEqual(element.value as? String, "\(index + 1) of \(Self.rows.count)", "\(item.key) position")
            XCTAssertGreaterThanOrEqual(frame.height, 44 - 0.5, "\(item.key) is at least 44 pt tall: \(frame)")
            XCTAssertGreaterThan(frame.width, window.width * 0.6, "\(item.key) spans the list: \(frame)")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(item.key) starts on screen: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(item.key) ends on screen: \(frame)")
            if item.key == "intensity" {
                record(app, name: "settings-visual-order-rows-ax5")
                let height = try read(element, drawn: item.label, "Song Intensity, AX5")
                XCTAssertGreaterThan(height / standardHeight, RecognizedText.minimumGrowth,
                                     "row text grows at AX5: \(height) vs \(standardHeight) pt")
                try auditList(in: app)
            }
        }
    }

    // MARK: - Launch and reveal

    /// Open Settings with Independent Visual Order on and the default order, at a text size.
    ///
    /// - Parameter size: A `UIContentSizeCategory` raw value; nil keeps the default.
    /// - Returns: The launched app on Settings.
    @MainActor
    private func launchSettings(size: String?) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_DEBUG_TAB": "settings",
        ])
        // Argument-domain values: they win over saved settings and are never written back.
        app.launchArguments += [
            "-fst.settings.enableVisualOrder", "YES",
            "-fst.settings.songRowVisualOrder", Self.rows.map(\.key).joined(separator: ","),
            "-fst.accessibility.reduceMotion", "YES",
        ]
        for field in ["Score", "Percentage", "Percentile", "Season", "Intensity", "Difficulty", "Stars", "LastPlayed"] {
            app.launchArguments += ["-fst.settings.metadata\(field)", "YES"]
        }
        if let size {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        XCTAssertTrue(app.switches[Self.switchID].waitForExistence(timeout: FestivalApp.budget(30)), "Settings loads")
        return app
    }

    /// The Song Row Visual Order row for a field.
    @MainActor
    private func row(_ key: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "\(Self.listID).\(key)").firstMatch
    }

    /// Scroll an element into the middle of the screen, clear of the scroll-edge fades
    /// and the bottom chrome.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - app: The app on Settings.
    /// - Returns: The element, hittable.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: FestivalApp.budget(20)), "\(element.identifier) exists")
        let window = app.windows.firstMatch.frame
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<30 {
            let frame = element.frame
            if element.isHittable, frame.minY >= window.height * 0.2, frame.maxY <= window.height * 0.75 { break }
            // Drag from the middle (never a row's grip: the rows' leading edge), at most
            // 0.35 screen per drag, moving the element's centre towards the middle.
            let offset = max(-window.height * 0.35, min(window.height * 0.35, window.height * 0.45 - frame.midY))
            start.withOffset(CGVector(dx: window.width * 0.3, dy: 0))
                .press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.width * 0.3, dy: offset)))
        }
        sleep(UInt32(FestivalApp.budget(1)))
        XCTAssertTrue(element.isHittable, "\(element.identifier) scrolls on screen: \(element.frame)")
        return element
    }

    /// Read an element's drawn text back with the shared `RecognizedText`.
    ///
    /// - Parameters:
    ///   - element: The element on screen.
    ///   - drawn: The text it should draw whole.
    ///   - context: Names the reading in failures.
    /// - Returns: Its recognized line height in points.
    @MainActor
    private func read(_ element: XCUIElement, drawn: String, _ context: String) throws -> CGFloat {
        let reading = RecognizedText.recognize(element, label: drawn, frame: element.frame)
        XCTAssertTrue(RecognizedText.showsWhole(drawn, in: reading.text),
                      "\(context): '\(drawn)' renders whole: '\(reading.text ?? "nil")'")
        let height = try XCTUnwrap(reading.lineHeight, "\(context): recognized")
        XCTAssertGreaterThan(height, 4, "\(context): a measurable line height")
        return height
    }

    // MARK: - Audit

    /// Audit the screen and keep only issues in the switch and the list.
    ///
    /// - Parameter app: The app with the list on screen.
    @MainActor
    private func auditList(in app: XCUIApplication) throws {
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [
            .dynamicType, .textClipped, .hitRegion, .sufficientElementDescription, .contrast,
        ]
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, audit, name: "settings-visual-order-ax5", reset: { issues.removeAll() }
        ) { issue in
            guard let element = issue.element else { return true }
            let id = element.identifier
            guard id.hasPrefix(Self.listID) || id == Self.switchID else { return true }
            issues.append("\(id) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Song Row Visual Order audit issues at AX5")
    }

    // MARK: - Evidence

    /// Keep a capture of the screen with the test result.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
