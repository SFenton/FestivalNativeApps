import UIKit
import XCTest

// MARK: - Duo split band at AX5 (issue #344, backfilled by #480)

/// Accessibility evidence for the band #344 changed, in the iPhone Duo's two split states:
/// the flat inner display, whose band is a 1 pt midpoint of the free space, and book pose,
/// whose band is the fold (split-panes R1, R2, R5). Each runs Rivals at AX5 with the app's
/// Increase Contrast (`fst.accessibility.moreContrast`), the state that draws the midpoint
/// hairline, and checks on device:
///
/// - **Band:** at the free space's midpoint when flat, on the fold in book pose (the
///   readout's `fold=`), with the trailing pane starting where it ends. The hairline shows
///   at the midpoint and never on the fold (screenshot pixels on the Debug flat backdrop).
///   The band gives VoiceOver nothing: no splitter, no labelled band node.
/// - **Reading order:** the opened row is selected and reads before the trailing pane.
/// - **Close:** named, inside the trailing pane, with a 44 × 44 pt hit region (every
///   near-miss tap closes the pane), or, when the vertical bar's pane overflows, the More
///   button gets those taps and its menu offers a named Close of at least 44 pt that closes
///   the pane (`SplitBandUITestSupport`).
/// - **Fold:** folding to book pose keeps the open item and re-places the band (R5).
///
/// The app simulates each Duo window through the Debug `FST_DEBUG_DUO_WINDOW` switch
/// (`DebugDuoWindow`: size classes, vertical bar and book fold). A split needs a window at
/// least 720 pt wide, which a portrait-only iPhone never has: `apple-ci` runs this iPhone
/// bundle journey on its landscape iPad (`uitest --app phone`, the iPad step's `JOURNEYS`),
/// and on an iPhone Duo simulator it runs on the unfolded inner display rotated to landscape
/// (`ios_sim.py uitest --device duo --pose unfolded --set-pose --rotate left`, Device Hub
/// scripting). Elsewhere it skips. On the iPad the Duo's layout signals drive the split
/// (its free span is the simulated 951 pt window's), but the shell is the iPad's flyout
/// and no system vertical bar is drawn.
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_FIXTURE_URL` for another mock).
///
/// HIG Buttons: "the hit region is at least 44x44 pt"; HIG Accessibility: provide a
/// higher-contrast scheme when Increase Contrast is on; HIG Designing for iPhone Duo:
/// "Folding region | Present when partially open".
final class DuoSplitBandAccessibilityJourneyTests: XCTestCase {
    /// The free space's midpoint band: 1 pt (`OnDemandSplitPolicy.midpointDividerWidth`).
    private static let midpointBandWidth: CGFloat = 1
    /// The simulated book fold's width (`DebugDuoPose.foldHeight`).
    private static let foldWidth: CGFloat = 24
    /// The narrowest window that splits: two 360 pt panes.
    private static let splittingWidth: CGFloat = 720

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    override func tearDown() {
        if Self.isPad { XCUIDevice.shared.orientation = .portrait }
    }

    private static var isPad: Bool {
        MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
    }

    // MARK: - Journeys

    /// The flat inner display: a 1 pt band at the free space's midpoint, with its hairline
    /// under the app's Increase Contrast at AX5.
    @MainActor
    func testFlatMidpointBandIsAccessibleAtAX5WithMoreContrastDuoUnfolded() throws {
        let app = try launchSplit()
        defer { app.terminate() }
        try assertBand(app, state: "flat", fold: nil)
    }

    /// Book pose: folding with Rival Detail open keeps it and moves the band onto the fold,
    /// which draws no hairline even under the app's Increase Contrast at AX5.
    @MainActor
    func testBookHingeBandIsAccessibleAtAX5WithMoreContrastDuoBook() throws {
        let app = try launchSplit()
        defer { app.terminate() }
        DuoWindowSwitch.post("book")
        let fold = try waitForFold(app)
        XCTAssertTrue(SplitBandUITestSupport.waitForPane(app, open: true), "book: folding keeps Rival Detail open")
        try assertBand(app, state: "book", fold: fold)
    }

    // MARK: - Steps

    /// Launch Rivals in the flat simulated inner display at AX5 with the app's Increase
    /// Contrast, and open the first rival beside it.
    @MainActor
    private func launchSplit() throws -> XCUIApplication {
        if Self.isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": SongsUITestSupport.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_ROUTE": "rivals",
            "FST_DEBUG_DUO_WINDOW_REMOTE": "1",
            "FST_DEBUG_DUO_WINDOW": "unfolded-landscape",
            // A flat grey backdrop, so the hairline's pixels are measurable.
            "FST_DEBUG_FLAT_BACKDROP": "1",
        ])
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            "-fst.accessibility.moreContrast", "YES",
        ]
        app.launch()
        let window = app.windows.firstMatch.frame
        if window.width < Self.splittingWidth {
            app.terminate()
            throw XCTSkip("A split needs a \(Int(Self.splittingWidth)) pt window (\(window.size)): run on a landscape "
                          + "iPad or the unfolded iPhone Duo in landscape")
        }
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let simulated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "unfolded-landscape "), object: readout
        )
        XCTAssertEqual(XCTWaiter().wait(for: [simulated], timeout: FestivalApp.budget(15)), .completed,
                       "the app never simulated the flat inner display (\(readout.label))")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.rivals.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(25)), "Rivals lists its rows")
        XCTAssertNil(SplitBandUITestSupport.trailingPane(app), "Rivals starts full width")
        XCTAssertFalse(SplitBandUITestSupport.element(app, SplitBandUITestSupport.bandID).exists,
                       "no band without a split")
        row.tap()
        SplitBandUITestSupport.waitForPane(app, open: true)
        _ = try XCTUnwrap(SplitBandUITestSupport.trailingPane(app), "Rival Detail opens beside Rivals")
        return app
    }

    /// The book fold's centre from the readout (`fold=<x>`).
    @MainActor
    private func waitForFold(_ app: XCUIApplication) throws -> CGFloat {
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let book = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "book ", "fold="),
            object: readout
        )
        XCTAssertEqual(XCTWaiter().wait(for: [book], timeout: FestivalApp.budget(15)), .completed,
                       "the app never simulated book pose (\(readout.label))")
        let value = readout.label.components(separatedBy: "fold=").last.flatMap { Double($0) }
        return CGFloat(try XCTUnwrap(value, "no fold in the readout '\(readout.label)'"))
    }

    /// Check the band's place, hairline, silence, the reading order and Close.
    ///
    /// - Parameters:
    ///   - app: The app with Rival Detail open beside Rivals.
    ///   - state: `flat` or `book`, for messages.
    ///   - fold: The book fold's centre, or nil when flat.
    @MainActor
    private func assertBand(_ app: XCUIApplication, state: String, fold: CGFloat?) throws {
        let window = app.windows.firstMatch.frame
        let pane = try XCTUnwrap(SplitBandUITestSupport.trailingPane(app), "\(state): Rival Detail opens beside Rivals")
        // The band ends where the trailing pane starts.
        let bandWidth = fold == nil ? Self.midpointBandWidth : Self.foldWidth
        let bandMidX = fold ?? (pane.minX - bandWidth / 2)
        XCTAssertEqual(pane.minX, bandMidX + bandWidth / 2, accuracy: 1, "\(state): the trailing pane starts at the band")
        XCTAssertGreaterThanOrEqual(bandMidX - window.minX, 360, "\(state): the leading pane keeps 360 pt")
        let band = SplitBandUITestSupport.element(app, SplitBandUITestSupport.bandID)
        if band.exists {
            XCTAssertEqual(band.frame.width, bandWidth, accuracy: 1, "\(state): band \(band.frame)")
            XCTAssertEqual(band.frame.midX, bandMidX, accuracy: 1, "\(state): band \(band.frame)")
        }
        try assertHairline(app, atX: bandMidX, drawn: fold == nil, state: state)

        let nodes = FestivalApp.snapshotNodesOrEmpty(in: app)
        SplitBandUITestSupport.assertBandIsSilent(nodes, "\(state), AX5, Increase Contrast")
        let selected = app.buttons.matching(NSPredicate(format: "isSelected == true"))
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.rivals.row.")).firstMatch
        XCTAssertTrue(selected.exists, "\(state): the opened row reads selected")
        let rowID = selected.identifier
        let rowIndex = nodes.firstIndex { $0.identifier == rowID }
        let paneIndex = nodes.firstIndex { $0.identifier == SplitBandUITestSupport.paneID }
        if let rowIndex, let paneIndex {
            XCTAssertLessThan(rowIndex, paneIndex, "\(state): the leading pane reads before the trailing pane")
        } else {
            XCTFail("\(state): row \(rowID) or the trailing pane is missing from the tree")
        }
        XCTAssertLessThan(selected.frame.maxX, bandMidX, "\(state): the opened row stays in the leading pane")

        let inBar = SplitBandUITestSupport.assertCloseHitRegion(app, "\(state), AX5") {
            SplitBandUITestSupport.reopen(app, row: rowID)
        }
        XCTContext.runActivity(named: "\(state): Close \(inBar ? "in the bar" : "in More")") { _ in }
        XCTAssertTrue(SplitBandUITestSupport.waitForPane(app, open: false), "\(state): Close returns to full width")
        XCTAssertFalse(band.exists, "\(state): no band without a split")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "duo-split-band-\(state)-closed-ax5"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The hairline (white at 16 %) brightens the band's column over the flat backdrop at a
    /// midpoint; on the fold the band is clear.
    ///
    /// Reads the whole screen (`XCUIScreen`): the app's own capture of a landscape iPad is
    /// cut off (`IPadAccessibilityAuditTests`). The simulator keeps its framebuffer in
    /// portrait while the interface turns (`IPadAuditRenderedContrast.upright`), so a
    /// portrait capture of a landscape window is read through that quarter turn.
    ///
    /// - Parameters:
    ///   - app: The app with the split open.
    ///   - x: The band's centre in window points.
    ///   - drawn: Whether the hairline must show.
    ///   - state: For messages.
    @MainActor
    private func assertHairline(_ app: XCUIApplication, atX x: CGFloat, drawn: Bool, state: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "duo-split-band-\(state)-ax5-more-contrast"
        shot.lifetime = .keepAlways
        add(shot)
        let window = app.windows.firstMatch.frame
        let cgImage = try XCTUnwrap(screenshot.image.cgImage)
        let longest = CGFloat(max(cgImage.width, cgImage.height))
        let scale = longest / max(window.width, window.height)
        let pixels = try XCTUnwrap(ButtonFillPixels(image: cgImage, pointWidth: CGFloat(cgImage.width) / scale))
        let capture = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        let turned = (capture.width > capture.height) != (window.width > window.height)
        XCTAssertEqual(max(capture.width, capture.height), max(window.width, window.height), accuracy: 2,
                       "\(state): the capture is the window's screen (\(capture), window \(window.size))")
        // The device's landscape left is the interface's landscape right: the window's top
        // runs down the capture's right edge (measured on iPad, 2026-10-12).
        let deviceLandscapeLeft = XCUIDevice.shared.orientation != .landscapeRight
        /// A window rect in the capture's (possibly portrait) points.
        func captured(_ rect: CGRect) -> CGRect {
            guard turned else { return rect }
            if deviceLandscapeLeft {
                return CGRect(x: capture.width - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
            }
            return CGRect(x: rect.minY, y: capture.height - rect.maxX, width: rect.height, height: rect.width)
        }
        func brightness(atX column: CGFloat) throws -> Double {
            let rect = CGRect(x: column - 0.5, y: window.midY - 120, width: 1, height: 240)
            return try XCTUnwrap(pixels.meanBrightness(in: captured(rect)), "\(state): \(rect) is off the capture")
        }
        let (band, left, right) = (try brightness(atX: x), try brightness(atX: x - 6.5), try brightness(atX: x + 6.5))
        let lift = band - max(left, right)
        let readings = "(band \(Int(band)), sides \(Int(left)), \(Int(right)); capture \(capture), turned \(turned))"
        if drawn {
            XCTAssertGreaterThan(lift, 6, "\(state): the hairline shows under Increase Contrast \(readings)")
        } else {
            XCTAssertLessThan(lift, 3, "\(state): the fold draws no hairline \(readings)")
        }
    }
}

extension ButtonFillPixels {
    /// The mean of a frame's pixels' channel means (0–255).
    ///
    /// - Parameter frame: The frame in screenshot points.
    /// - Returns: The mean brightness, or nil when the frame lies outside the bitmap.
    func meanBrightness(in frame: CGRect) -> Double? {
        let minX = max(Int((frame.minX * scale).rounded()), 0)
        let maxX = min(max(Int((frame.maxX * scale).rounded()) - 1, minX), width - 1)
        let minY = max(Int((frame.minY * scale).rounded()), 0)
        let maxY = min(max(Int((frame.maxY * scale).rounded()) - 1, minY), height - 1)
        guard minX <= maxX, minY <= maxY else { return nil }
        var total = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = (y * width + x) * 4
                total += Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])
            }
        }
        return Double(total) / Double(3 * (maxX - minX + 1) * (maxY - minY + 1))
    }
}

extension FestivalApp {
    /// Every node of one snapshot of the app, depth first; empty when XCTest cannot take one.
    @MainActor
    static func snapshotNodesOrEmpty(in app: XCUIApplication) -> [XCUIElementSnapshot] {
        (try? snapshotNodes(in: app) { _ in true }) ?? []
    }
}
