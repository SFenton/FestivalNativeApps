import UIKit
import XCTest

/// Accessibility of the navigation drawer with its concentric corners (#396, for #17).
///
/// #17 made the drawer panel's corners follow the display's own (`ConcentricRectangle`,
/// ≈54 pt on a 402 pt iPhone instead of the fixed 44 pt) and clips the panel's contents
/// to that shape. Each test opens the drawer over Songs against the fixture service with
/// a selected player (the footer's profile row and Deselect sit in the bottom corners),
/// audits it with `performAccessibilityAudit`, and checks what the audit
/// cannot: the heading first, every control named, 44 pt targets (HIG Accessibility,
/// Mobility: "Strive for the platform's recommended minimum control size", 44x44 pt on
/// iOS) wholly inside the panel's rounded corners, at the default text size and the
/// largest accessibility size. The hosted `DrawerCornersAccessibilityTests` pin the same
/// contract on every iPhone and iPhone Duo geometry in `apple-ci`. The page under the open
/// drawer must be gone from `app.snapshot()` (what VoiceOver reads); `debugDescription`
/// still prints SwiftUI views hidden with `accessibilityHidden`, so it is no evidence.
///
/// Needs `tools/mock_service.py --port 18790`, like `QuickLinksAccessibilityJourneyTests`.
final class DrawerAccessibilityJourneyTests: XCTestCase {
    // MARK: - Helpers

    /// The largest radius a panel corner takes on a current iPhone: concentric with a
    /// ≈62 pt display corner at the drawer's 8 pt margin.
    private static let panelCornerBound: CGFloat = 62 - 8

    /// Whether the tests run on the iPhone Duo simulator.
    private static var isDuo: Bool {
        (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo")
    }

    /// The drawer's controls in reading order with a selected player (anonymous shell
    /// tabs: Songs, Suggestions, Leaderboards, Settings; the rest are pushed).
    private static let controls: [(id: String, label: String)] = [
        ("close", "Close Navigation"), ("songs", "Songs"), ("suggestions", "Suggestions"),
        ("statistics", "Statistics"), ("rivals", "Rivals"), ("leaderboards", "Leaderboards"),
        ("shop", "Item Shop"), ("view-profile", "Fixture Player 1, Selected Player"),
        ("deselect-profile", "Deselect Profile"), ("settings", "Settings"),
    ]

    /// Fixture Songs with a selected player, at an optional Dynamic Type size.
    ///
    /// - Parameter contentSize: A `UIContentSizeCategory` raw value, or nil for the default.
    /// - Returns: The launched app.
    @MainActor
    private func launch(contentSize: String? = nil) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_API_BASE_URL": "http://127.0.0.1:18790",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ])
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    /// Open the drawer and wait for its panel to settle.
    @MainActor
    private func openDrawer(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.descendants(matching: .any)["fst.songs.list"].waitForExistence(timeout: 25),
                      "Songs never loaded", file: file, line: line)
        // iPhone Duo's vertical bar can move the button into the toolbar overflow.
        ShellUITestSupport.tapToolbarItem("fst.shell.drawer.open", overflowLabels: ["Menu", "Open Navigation"],
                                          in: app, file: file, line: line)
        let drawer = app.descendants(matching: .any).matching(identifier: "fst.shell.drawer").firstMatch
        XCTAssertTrue(drawer.waitForExistence(timeout: 10), "The drawer did not open", file: file, line: line)
        XCTAssertTrue(app.buttons["fst.shell.drawer.settings"].waitForExistence(timeout: 10), file: file, line: line)
        // Let the panel finish sliding in (`DrawerMotion`) before reading frames.
        let close = app.buttons["fst.shell.drawer.close"]
        let settled = NSPredicate { _, _ in close.isHittable && close.frame.minX > 0 }
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 5)
        Thread.sleep(forTimeInterval: 1)
    }

    /// Assert the drawer reads its heading and named controls first to last, and keeps
    /// each on-screen control a 44 pt target wholly inside the panel's corners.
    ///
    /// - Returns: The panel's and the Songs row's frames.
    @MainActor
    @discardableResult
    private func assertDrawer(
        _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) -> (panel: CGRect, songs: CGRect) {
        openDrawer(app, file: file, line: line)
        // Modal: the page behind leaves what VoiceOver reads (`app.snapshot()`, as
        // `IPadShellAccessibilityTests` checks the flyout).
        var identifiers: [String] = []
        var depth = 0
        func collect(_ node: XCUIElementSnapshot, level: Int) {
            identifiers.append(node.identifier)
            depth = max(depth, level)
            node.children.forEach { collect($0, level: level + 1) }
        }
        if let snapshot = try? app.snapshot() { collect(snapshot, level: 0) }
        // The drawer's own rows prove the snapshot reaches as deep as the page would. On the
        // iPhone Duo simulator it stops after a few levels (11 nodes, depth 6), so there
        // `DuoDrawerJourneyTests` proves the panel modal (`isModal`) instead.
        if identifiers.contains("fst.shell.drawer.songs") {
            XCTAssertFalse(identifiers.contains { $0.hasPrefix("fst.songs.") },
                           "The page behind the drawer is out of the accessibility tree", file: file, line: line)
        } else {
            XCTAssertTrue(Self.isDuo, "The snapshot (\(identifiers.count) nodes, depth \(depth)) lacks the drawer rows",
                          file: file, line: line)
        }
        let heading = app.staticTexts["Festival Score Tracker"]
        XCTAssertTrue(heading.exists, "No heading", file: file, line: line)
        XCTAssertTrue(heading.elementType == .staticText, file: file, line: line)

        // The `fst.shell.drawer` element spans the window. The panel runs the window's height
        // at the 8 pt `DrawerPlacement.margin`; its rows and close button sit 12 pt
        // (`contentInset`) inside its edges, after iPhone Duo's vertical bar when one shows.
        let window = app.windows.firstMatch.frame
        let close = app.buttons["fst.shell.drawer.close"].frame
        let leading = app.buttons["fst.shell.drawer.songs"].frame.minX - 12
        let panel = CGRect(x: leading, y: 8, width: close.maxX + 12 - leading, height: window.height - 16)
        XCTAssertGreaterThan(close.minY, panel.minY, "Close below the panel top: \(close)", file: file, line: line)
        let shape = UIBezierPath(roundedRect: panel, cornerRadius: Self.panelCornerBound)
        // The page rows scroll above the pinned footer (profile, Deselect, Settings).
        // The scroll view can run past the panel, which clips it (iPhone Duo at AX5).
        let scroller = app.scrollViews.containing(.button, identifier: "fst.shell.drawer.songs").firstMatch
        let list = scroller.frame.intersection(panel)
        // iPhone Duo scrolls the footer with the rows at accessibility sizes
        // (`footerScrollsAtAccessibilitySizes`); elsewhere it is pinned under the list.
        let footerScrolls = scroller.buttons["fst.shell.drawer.settings"].exists
        let footer: Set<String> = footerScrolls
            ? ["close"] : ["close", "view-profile", "deselect-profile", "settings"]
        var previousY = heading.frame.minY
        for (id, label) in Self.controls {
            let element = app.buttons["fst.shell.drawer.\(id)"]
            XCTAssertTrue(element.exists, "\(id) missing", file: file, line: line)
            XCTAssertEqual(element.label, label, "\(id) name", file: file, line: line)
            let frame = element.frame
            // Rows scrolled out of the list's viewport are reached by scrolling.
            let viewport = footer.contains(id) ? panel : list
            guard viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame), window.contains(frame) else { continue }
            XCTAssertTrue(element.isHittable, "\(id) hittable", file: file, line: line)
            // Within one pixel: the fixed 44 pt close button reports 43.67 pt (131 px at 3x)
            // where layout lands it off the pixel grid.
            XCTAssertGreaterThanOrEqual(frame.width, 44 - 0.5, "\(id) target width \(frame)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(frame.height, 44 - 0.5, "\(id) target height \(frame)", file: file, line: line)
            // Drawn order: each control starts below the previous one, or beside it (Deselect
            // next to the profile row until accessibility sizes stack it underneath).
            XCTAssertGreaterThanOrEqual(frame.midY, previousY, "\(id) reads in drawn order", file: file, line: line)
            previousY = frame.minY
            // A row's symbol stays in its leading column (8 pt inside the row) instead of
            // spilling over the title as text grows.
            if !["close", "deselect-profile"].contains(id), let icon = element.images.allElementsBoundByIndex.first {
                XCTAssertGreaterThanOrEqual(icon.frame.minX, frame.minX + 8 - 0.5,
                                            "\(id) symbol \(icon.frame) spills out of its column in \(frame)",
                                            file: file, line: line)
            }
            let inset = id == "close" ? frame.width / 2 * (1 - 1 / sqrt(2)) : 14 * (1 - 1 / sqrt(2))
            let target = frame.insetBy(dx: inset, dy: inset)
            for corner in [CGPoint(x: target.minX, y: target.minY), CGPoint(x: target.maxX, y: target.minY),
                           CGPoint(x: target.minX, y: target.maxY), CGPoint(x: target.maxX, y: target.maxY)] {
                XCTAssertTrue(shape.contains(corner), "\(id) \(frame) cut by the panel corner of \(panel)",
                              file: file, line: line)
            }
        }
        if footerScrolls {
            // The footer is reached by scrolling to the end of the list.
            let settings = app.buttons["fst.shell.drawer.settings"]
            for _ in 0..<6 where !(settings.isHittable && panel.contains(settings.frame)) { scroller.swipeUp() }
        }
        // The footer stays on screen (pinned, or once scrolled to).
        for id in ["view-profile", "settings"] {
            let frame = app.buttons["fst.shell.drawer.\(id)"].frame
            XCTAssertTrue(panel.contains(frame), "\(id) \(frame) within \(panel)", file: file, line: line)
        }
        return (panel, app.buttons["fst.shell.drawer.songs"].frame)
    }

    /// Run `performAccessibilityAudit` on the open drawer and fail on every open issue.
    ///
    /// A contrast issue is accepted only for a named element inside the drawer panel whose
    /// text this run measures at ≥ 4.5:1 in the app's own screenshot (the audit misjudges
    /// white rows on the dark glass; the iPad lane's `contrast-rendered` rule), or for page
    /// text behind the modal drawer that this run finds absent from `app.snapshot()`, what
    /// VoiceOver reaches (the iPad lane's `behind-modal-drawer` rule). Unattributed
    /// "may be clipped at larger sizes" predictions are returned for the caller to disprove
    /// at the largest size.
    ///
    /// - Parameters:
    ///   - app: Foreground app with the drawer open.
    ///   - types: Audit types to run.
    ///   - panel: The drawer panel's frame.
    /// - Returns: The number of unattributed text-clipping predictions.
    @MainActor
    @discardableResult
    private func audit(
        _ app: XCUIApplication, for types: XCUIAccessibilityAuditType, panel: CGRect,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> Int {
        let screenshot = app.screenshot().image.cgImage
        let window = app.windows.firstMatch.frame
        // Read the tree before auditing: on iPhone Duo `app.snapshot()` comes back empty after it.
        var reachable: Set<String> = []
        var reachesDrawer = false
        func collect(_ node: XCUIElementSnapshot) {
            reachable.insert("\(node.label)|\(node.frame)")
            reachesDrawer = reachesDrawer || node.identifier == "fst.shell.drawer.songs"
            node.children.forEach(collect)
        }
        collect(try app.snapshot())
        // The drawer's texts: its heading and rows (a row's label is its text; Close is a
        // symbol, held to 3:1, not text).
        let heading = app.staticTexts["Festival Score Tracker"]
        let texts = ([(heading.label, heading.frame)] + Self.controls.filter { $0.id != "close" }.map { control in
            let row = app.buttons["fst.shell.drawer.\(control.id)"]
            return (row.label, row.frame)
        }).filter { panel.contains($0.1) }.map { (label: $0.0, frame: $0.1) }
        var open: [String] = []
        var predictedClipping = 0
        var unattributedContrast = 0
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            if issue.auditType == .textClipped, element == nil {
                predictedClipping += 1
                return true
            }
            if issue.auditType == .contrast, element == nil {
                unattributedContrast += 1
                return true
            }
            let summary = "\(issue.compactDescription): \(element?.identifier ?? "") '\(element?.label ?? "")' \(element?.frame ?? .zero)"
            // Absence only counts in a snapshot deep enough to hold the drawer's own rows.
            if issue.auditType == .contrast, reachesDrawer, let element, window.contains(element.frame),
               !reachable.contains("\(element.label)|\(element.frame)") {
                return true
            }
            if issue.auditType == .contrast, let element, !element.label.isEmpty,
               panel.contains(element.frame), let screenshot,
               let ratio = Self.renderedTextContrast(of: element.frame, in: screenshot, window: window) {
                if ratio >= 4.5 { return true }
                open.append("\(summary), rendered \(String(format: "%.2f", ratio)):1")
                return true
            }
            open.append(summary)
            return true
        }
        if unattributedContrast > 0 {
            // No element to measure (iPhone Duo): every text the drawer shows must render
            // ≥ 4.5:1, so no node the audit could mean fails (iPad `unattributed-contrast-page-floor`).
            if texts.isEmpty { open.append("\(unattributedContrast) unattributed contrast issues, no text to measure") }
            for text in texts {
                let ratio = screenshot.flatMap { Self.renderedTextContrast(of: text.frame, in: $0, window: window) }
                if (ratio ?? 0) < 4.5 {
                    open.append("Unattributed contrast: '\(text.label)' \(text.frame) rendered \(ratio.map { String(format: "%.2f", $0) } ?? "unmeasured")")
                }
            }
        }
        XCTAssertEqual(open, [], "Open audit issues", file: file, line: line)
        return predictedClipping
    }

    /// Measure rendered text contrast in one element's crop of a screenshot: the median
    /// pixel is its surface and the 99th-percentile luminance its glyphs (as
    /// `FestivalMobileUITests.measuredTextContrast`).
    ///
    /// - Parameters:
    ///   - frame: The element's frame in points.
    ///   - image: The app screenshot.
    ///   - window: The window's frame in points.
    /// - Returns: The contrast ratio, or nil without enough glyph pixels to measure.
    private static func renderedTextContrast(of frame: CGRect, in image: CGImage, window: CGRect) -> Double? {
        let scale = Double(image.width) / window.width
        let rect = CGRect(x: (frame.minX - window.minX) * scale, y: (frame.minY - window.minY) * scale,
                          width: frame.width * scale, height: frame.height * scale).integral
        guard let crop = image.cropping(to: rect) else { return nil }
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8,
                bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        guard drawn else { return nil }
        let luminances = stride(from: 0, to: bytes.count, by: 4).map { offset -> Double in
            let channels = (0..<3).map { channel -> Double in
                let value = Double(bytes[offset + channel]) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }.sorted()
        guard !luminances.isEmpty else { return nil }
        let background = luminances[luminances.count / 2]
        let text = luminances[luminances.count * 99 / 100]
        guard luminances.filter({ $0 > background * 3 }).count > 100 else { return nil }
        return (text + 0.05) / (background + 0.05)
    }

    // MARK: - Tests

    /// Default text size: the open drawer passes the full audit, reads its heading and
    /// named controls in order and keeps each target inside the concentric corners.
    ///
    /// Unattributed predictions that text "may be clipped at larger sizes" are checked
    /// where they point: the drawer relaunched at the largest size must audit clean for
    /// clipping.
    @MainActor
    func testDrawerPassesAccessibilityAudit() throws {
        continueAfterFailure = false
        let app = launch()
        let panel = assertDrawer(app).panel
        SongsUITestSupport.record(app, name: "drawer-a11y-default")
        let predictions = try audit(app, for: .all, panel: panel)
        guard predictions > 0 else { return }
        app.terminate()
        let large = launch(contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        let largePanel = assertDrawer(large).panel
        let clipped = try audit(large, for: .textClipped, panel: largePanel)
        XCTAssertEqual(clipped, 0, "\(predictions) predicted clippings still clip at the largest size")
    }

    /// Largest accessibility text size: rows grow to the AX5 body line, the pinned footer stays inside the panel's corners and hittable, and the
    /// drawer passes the Dynamic Type, clipping and hit-region audits.
    @MainActor
    func testDrawerScalesToTheLargestTextSize() throws {
        continueAfterFailure = false
        let regular = launch()
        let regularHeight = assertDrawer(regular).songs.height
        regular.terminate()

        let app = launch(contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        let large = assertDrawer(app)
        let largeHeight = large.songs.height
        SongsUITestSupport.record(app, name: "drawer-a11y-ax5")
        // Rows have a 48 pt floor, so they grow to the AX5 body line (≈ 64 pt), not by a ratio.
        XCTAssertGreaterThan(largeHeight, 60, "Rows grow with text: \(regularHeight) → \(largeHeight)")
        let clipped = try audit(app, for: [.dynamicType, .textClipped, .hitRegion], panel: large.panel)
        XCTAssertEqual(clipped, 0, "Text predicted to clip at the largest size")
    }
}
