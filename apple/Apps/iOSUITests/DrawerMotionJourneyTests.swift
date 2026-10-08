import UIKit
import XCTest

/// The rendered open and close sequence of the navigation drawer (issue #362,
/// `page-tools-and-nav-chrome` R16 owner-approved variant): opening dims the whole
/// window in place and only then slides the panel in; closing slides the panel out and
/// only then fades the scrim; with Reduce Motion the panel fades in place.
///
/// The app runs the real sequence through the real root (`FestivalRootView` keeps the
/// drawer mounted until the scrim has faded) in slow motion
/// (`FST_DEBUG_DRAWER_SLOWMO`, Debug only), and the test samples screenshots throughout.
/// Each sample is compared with the closed window: the scrim's darkening is measured
/// beside the panel, and the panel's presence as the share of pixels that differ from a
/// uniformly dimmed window, in vertical strips across the panel's header and first
/// rows. Run with the fixture service on each in-scope shell:
///
/// ```
/// python3 tools/mock_service.py --port 18362 &
/// python3 tools/ios_sim.py uitest --only DrawerMotionJourneyTests
/// python3 tools/ios_sim.py uitest --device duo --pose folded --only DrawerMotionJourneyTests
/// python3 tools/ios_sim.py uitest --device ipad --only DrawerMotionJourneyTests
/// ```
///
/// The folded Duo run also covers the unfolded window (`FST_DEBUG_DUO_WINDOW`) through
/// ``testDuoUnfoldedDrawerDimsThenSlides()``. Skips without the fixture service.
final class DrawerMotionJourneyTests: XCTestCase {
    /// Loopback fixture service.
    private static let fixtureURL = "http://127.0.0.1:18362"

    /// Slow-motion factor: the 0.4 s sequence takes 8 s (scrim 3 s, panel 5 s).
    private static let slowMotion = 20.0

    /// Reduce Motion's panel fade eases out (most of it in its first fifth), so it runs
    /// slower still to catch part-faded frames.
    private static let reduceMotionSlowMotion = 40.0

    /// `DrawerMotion.totalDuration` and its scrim share, in seconds at normal speed.
    private static let sequence = 0.4

    /// Window points below the top kept out of the measured regions (the status bar).
    fileprivate static let statusBarClearance: CGFloat = 64

    /// Ratio tolerance for "the scrim is fully dark" (the 45 % scrim keeps ~55 %).
    private static let fullScrimTolerance = 0.05

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        // iPadOS remembers a resized window for the next launch.
        MainActor.assumeIsolated {
            let app = FestivalApp.makeApp()
            if Self.isPad, app.state == .runningForeground { WindowResize.fill(app) }
        }
    }

    /// Whether the tests run on an iPad, whose shell is the overlay flyout.
    private static var isPad: Bool {
        MainActor.assumeIsolated { UIDevice.current.userInterfaceIdiom == .pad }
    }

    /// Opening dims first and then slides; closing slides out and then fades. Runs on
    /// the simulator's own shell: iPhone tab bar, iPhone Duo pose, or the iPad flyout.
    @MainActor
    func testDrawerDimsThenSlidesAndReverses() throws {
        try runJourney(environment: [:], reduceMotion: false)
    }

    /// Reduce Motion (the in-app setting): the same two stages, but the panel fades in
    /// and out in place and never slides.
    @MainActor
    func testReduceMotionDrawerFadesWithoutSliding() throws {
        try runJourney(environment: [:], reduceMotion: true)
    }

    /// The unfolded iPhone Duo window laid out in the real folded window and vertical
    /// bar (`DebugDuoWindow`). Skips on a device without a vertical bar.
    @MainActor
    func testDuoUnfoldedDrawerDimsThenSlides() throws {
        try runJourney(environment: [
            "FST_DEBUG_DUO_WINDOW_REMOTE": "1",
            "FST_DEBUG_DUO_WINDOW": "unfolded-landscape",
        ], reduceMotion: false, requiresVerticalBar: true)
    }

    // MARK: - Journey

    /// One screenshot taken during a sequence.
    private struct Sample {
        /// Seconds since the open or close action returned.
        let time: TimeInterval
        let bitmap: ButtonFillPixels
        /// The screenshot, attached to the report for a few samples.
        var screenshot: XCUIScreenshot?
    }

    /// What one sample shows, measured against the closed window.
    private struct Reading: CustomStringConvertible {
        let time: TimeInterval
        /// Luminance kept beside the panel: 1 undimmed, ~0.55 under the full scrim.
        let scrim: Double
        /// Luminance kept in each strip across the panel's frame, as for ``scrim``.
        let strips: [Double]
        /// Panel presence per strip: 0 a uniformly dimmed window, 1 the open panel.
        let panel: [Double]

        /// Some strip shows the panel (an empty strip measures up to ~0.2: the closed
        /// window's glass adapts to the darker content, so the scrim is not purely
        /// multiplicative there).
        var panelVisible: Bool { (panel.max() ?? 0) > 0.35 }
        var panelGone: Bool { (panel.max() ?? 0) < 0.25 }

        var description: String {
            let strips = panel.map { String(format: "%.2f", $0) }.joined(separator: " ")
            return String(format: "t=%.2fs scrim %.3f panel [%@]", time, scrim, strips)
        }
    }

    /// Launch Songs, open the drawer and close it with a scrim tap, sampling both
    /// sequences.
    ///
    /// - Parameters:
    ///   - environment: Extra launch environment (a simulated Duo window).
    ///   - reduceMotion: Turn on the in-app Reduce Motion setting.
    ///   - requiresVerticalBar: Skip unless the window shows the Duo's vertical bar.
    @MainActor
    private func runJourney(environment: [String: String], reduceMotion: Bool, requiresVerticalBar: Bool = false) throws {
        try XCTSkipUnless(fixtureReachable(), "Start `mock_service.py --port 18362` from this revision")
        let slowMotion = reduceMotion ? Self.reduceMotionSlowMotion : Self.slowMotion
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixtureURL,
            "FST_DEBUG_ANONYMOUS": "1",
            "FST_DEBUG_TAB": "songs",
            "FST_DEBUG_DRAWER_SLOWMO": String(slowMotion),
        ].merging(environment) { _, extra in extra })
        app.launchArguments += ["-fst.accessibility.reduceMotion", reduceMotion ? "YES" : "NO"]
        app.launch()
        defer { app.terminate() }
        // The iPad flyout needs the full-screen (regular) window, not a remembered tile.
        if Self.isPad { WindowResize.fill(app) }
        if let window = environment["FST_DEBUG_DUO_WINDOW"] {
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "\(window) "), object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: 15), .completed, "The app never simulated \(window)")
        }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let opener = app.buttons["fst.shell.drawer.open"]
        XCTAssertTrue(opener.waitForExistence(timeout: 20), "No navigation menu button")
        if requiresVerticalBar {
            let tabs = ["Songs", "Leaderboards", "Settings"].compactMap {
                ShellUITestSupport.tabButtons($0, in: app).first?.frame
            }
            let bar = tabs.reduce(tabs.first ?? .null) { $0.union($1) }
            if tabs.count < 2 || bar.height <= bar.width {
                throw XCTSkip("No system vertical bar on this device (tabs \(bar))")
            }
        }
        // Songs has loaded and settled: the closed window is the reference.
        RunLoop.current.run(until: Date().addingTimeInterval(2.5))
        let windowFrame = window.frame
        let shell = "\(reduceMotion ? "reduce-motion" : "slide")-\(Int(windowFrame.width))x\(Int(windowFrame.height))"
        let closed = try bitmap(of: app, width: windowFrame.width, name: "drawer-motion-closed-\(shell)")

        // Open: sample the whole sequence, then read the panel's resting frame.
        ShellUITestSupport.tapToolbarItem("fst.shell.drawer.open", overflowLabels: ["Menu", "Open Navigation"], in: app)
        let opening = samples(of: app, width: windowFrame.width, slowMotion: slowMotion)
        let panelElement = app.descendants(matching: .any)["fst.shell.drawer"]
        XCTAssertTrue(panelElement.waitForExistence(timeout: 5), "\(shell): the drawer never opened")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let open = try bitmap(of: app, width: windowFrame.width, name: "drawer-motion-open-\(shell)")
        let panel = panelElement.frame
        let geometry = try Geometry(window: windowFrame, panel: panel, closed: closed, open: open)

        // Close with a tap on the scrim beside the panel.
        let tap = geometry.scrimTap
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: tap.x, dy: tap.y)).tap()
        let closing = samples(of: app, width: windowFrame.width, slowMotion: slowMotion)
        XCTAssertTrue(waitForDisappearance(of: panelElement), "\(shell): the drawer did not close")
        let after = try bitmap(of: app, width: windowFrame.width, name: "drawer-motion-after-\(shell)")

        let openReadings = opening.map(geometry.read)
        let closeReadings = closing.map(geometry.read)
        print("drawer-motion \(shell) panel \(panel) scrim sample \(geometry.scrimSample) full \(geometry.fullScrim)")
        print("drawer-motion \(shell) opening:\n" + openReadings.map(\.description).joined(separator: "\n"))
        print("drawer-motion \(shell) closing:\n" + closeReadings.map(\.description).joined(separator: "\n"))
        attach(opening, readings: openReadings, name: "drawer-motion-opening-\(shell)")
        attach(closing, readings: closeReadings, name: "drawer-motion-closing-\(shell)")

        assertOpening(openReadings, geometry: geometry, slides: !reduceMotion, shell: shell)
        assertClosing(closeReadings, geometry: geometry, slides: !reduceMotion, shell: shell)
        let restored = geometry.read(Sample(time: 0, bitmap: after))
        XCTAssertGreaterThan(restored.scrim, 0.95, "\(shell): the scrim stayed after closing (\(restored))")
    }

    // MARK: - Assertions

    /// Opening: the scrim fades in place while the panel is away, and the panel only
    /// moves once the scrim is fully dark.
    private func assertOpening(_ readings: [Reading], geometry: Geometry, slides: Bool, shell: String) {
        XCTAssertGreaterThanOrEqual(readings.count, 6, "\(shell): too few opening samples")
        for reading in readings where reading.panelVisible {
            XCTAssertLessThan(
                reading.scrim, geometry.fullScrim + Self.fullScrimTolerance,
                "\(shell) opening: the panel showed before the scrim was fully dark (\(reading))"
            )
        }
        let fading = readings.filter { isFading($0, geometry) && $0.panelGone }
        XCTAssertFalse(fading.isEmpty, "\(shell) opening: no frame with the scrim fading and the panel away")
        for reading in fading {
            // In place: every part of the window darkens together (a scrim moving with
            // the panel would leave strips undimmed, a spread near 0.4).
            let spread = (reading.strips + [reading.scrim]).max()! - (reading.strips + [reading.scrim]).min()!
            XCTAssertLessThan(spread, 0.1, "\(shell) opening: the scrim is not uniform while fading (\(reading))")
        }
        assertPanelMotion(readings, slides: slides, shell: "\(shell) opening")
        if let last = readings.last {
            XCTAssertLessThan(last.scrim, geometry.fullScrim + Self.fullScrimTolerance, "\(shell): not open at the end (\(last))")
        }
    }

    /// Closing: the panel leaves while the scrim stays fully dark, then the scrim fades
    /// with the panel gone (the root keeps the drawer mounted until then).
    private func assertClosing(_ readings: [Reading], geometry: Geometry, slides: Bool, shell: String) {
        XCTAssertGreaterThanOrEqual(readings.count, 6, "\(shell): too few closing samples")
        for reading in readings where reading.panelVisible {
            XCTAssertLessThan(
                reading.scrim, geometry.fullScrim + Self.fullScrimTolerance,
                "\(shell) closing: the scrim faded before the panel left (\(reading))"
            )
        }
        let leaving = readings.filter { reading in
            reading.panelVisible && (reading.panel.min() ?? 1) < 0.8
        }
        XCTAssertFalse(leaving.isEmpty, "\(shell) closing: no frame with the panel leaving under the full scrim")
        let fading = readings.filter { isFading($0, geometry) && $0.panelGone }
        XCTAssertFalse(fading.isEmpty, "\(shell) closing: no frame with the scrim fading after the panel left")
        if let leftAt = leaving.last?.time, let fadedAt = fading.first?.time {
            XCTAssertLessThan(leftAt, fadedAt, "\(shell) closing: the scrim faded before the panel left")
        }
        assertPanelMotion(readings, slides: slides, shell: "\(shell) closing")
    }

    /// Sliding: some frame shows the panel's leading strips while its trailing strips
    /// are still empty. Reduce Motion: no frame shows that hard edge (a fade), and
    /// some frame shows the panel partly faded.
    private func assertPanelMotion(_ readings: [Reading], slides: Bool, shell: String) {
        let partial = readings.filter { $0.panelVisible && ($0.panel.min() ?? 1) < 0.8 }
        if slides {
            let sliding = partial.contains { reading in
                (reading.panel.first ?? 0) > 0.5 && (reading.panel.last ?? 1) < 0.25
            }
            XCTAssertTrue(sliding, "\(shell): no frame shows the panel part-way in (it did not slide)")
        } else {
            // A slide always shows a hard edge: covered strips beside empty ones. A
            // fade changes every strip together (the changed share isn't linear in
            // opacity, so strips with text cross earlier than empty glass).
            for reading in readings where reading.panelVisible {
                let spread = reading.panel.max()! - reading.panel.min()!
                XCTAssertFalse(
                    spread > 0.7 || (reading.panel.max()! > 0.5 && reading.panel.min()! < 0.15),
                    "\(shell): the panel moved instead of fading (\(reading))"
                )
            }
            XCTAssertTrue(
                partial.contains { ($0.panel.max() ?? 0) < 0.85 },
                "\(shell): no frame shows the panel part-faded"
            )
        }
    }

    /// Whether the scrim is part-way between undimmed and fully dark.
    private func isFading(_ reading: Reading, _ geometry: Geometry) -> Bool {
        reading.scrim > geometry.fullScrim + 0.06 && reading.scrim < 0.96
    }

    // MARK: - Measurement

    /// The regions sampled in every screenshot, fixed from the open drawer.
    private struct Geometry {
        /// Beside the panel and clear of its shadow (window points).
        let scrimSample: CGRect
        /// A point on the scrim outside the drawer element, to dismiss it.
        let scrimTap: CGPoint
        /// Vertical strips across the panel's open frame.
        let strips: [CGRect]
        let closed: ButtonFillPixels
        /// Each strip's changed share against the dimmed closed window when fully open.
        let openDifference: [Double]
        /// Luminance kept beside the panel when fully open.
        let fullScrim: Double

        init(window: CGRect, panel: CGRect, closed: ButtonFillPixels, open: ButtonFillPixels) throws {
            let element = panel.offsetBy(dx: -window.minX, dy: -window.minY)
            // The status bar draws above the scrim and never dims: stay below it.
            let bandTop = max(element.minY + 24, DrawerMotionJourneyTests.statusBarClearance)
            let band = CGRect(x: element.minX, y: bandTop, width: element.width, height: min(element.maxY - 24 - bandTop, 240))
            let edgeGain = open.drawerMotionGain(
                in: CGRect(x: window.width - 14, y: window.height * 0.25, width: 12, height: window.height * 0.67),
                against: closed
            ) ?? 0.55
            // The drawer element can be wider than its glass (the Duo's spans to the
            // vertical bar, the iPad flyout's the window): find the glass's trailing
            // edge where the open window stops differing from the dimmed closed one.
            var glassMaxX = element.maxX
            for x in stride(from: element.maxX - 4, to: element.minX + 40, by: -4) {
                let column = CGRect(x: x, y: band.minY, width: 4, height: band.height)
                if (open.drawerMotionChanged(in: column, against: closed, gain: edgeGain) ?? 0) > 0.5 {
                    glassMaxX = x + 4
                    break
                }
            }
            let local = CGRect(x: element.minX, y: element.minY, width: glassMaxX - element.minX, height: element.height)
            // The shadow (radius 20, x 4) is negligible 28 pt past the panel.
            let scrimMinX = local.maxX + 28
            // Below the status bar, which runs down the Duo's trailing edge.
            scrimSample = CGRect(
                x: scrimMinX, y: window.height * 0.25,
                width: window.width - 2 - scrimMinX, height: window.height * 0.67
            )
            scrimTap = CGPoint(
                x: min(max(scrimSample.midX, element.maxX + 6), window.width - 4), y: scrimSample.midY
            )
            guard scrimSample.width >= 12 else {
                throw XCTSkip("No window area beside the panel \(panel) in \(window) to measure the scrim")
            }
            // The header and first rows (the current page's highlighted row spans the
            // panel): the empty glass below them can match a dark, dimmed window.
            let body = CGRect(x: local.minX + 10, y: band.minY, width: local.width - 20, height: band.height)
            let count = 6
            strips = (0..<count).map { index in
                CGRect(x: body.minX + body.width * CGFloat(index) / CGFloat(count), y: body.minY,
                       width: body.width / CGFloat(count), height: body.height)
            }
            self.closed = closed
            let lit = closed.drawerMotionMeanLuma(in: scrimSample) ?? 0
            guard lit > 6 else { throw XCTSkip("The window beside the panel is too dark to measure (\(lit))") }
            let full = open.drawerMotionGain(in: scrimSample, against: closed) ?? 1
            let difference = strips.map { open.drawerMotionChanged(in: $0, against: closed, gain: full) ?? 0 }
            fullScrim = full
            openDifference = difference
            XCTAssertLessThan(full, 0.75, "The open drawer did not dim the window (\(full))")
            XCTAssertGreaterThan(difference.min() ?? 0, 0.3, "The open panel is indistinguishable from the scrim (\(difference))")
        }

        /// Measure one sample.
        func read(_ sample: Sample) -> Reading {
            let scrim = sample.bitmap.drawerMotionGain(in: scrimSample, against: closed) ?? 1
            let panel = zip(strips, openDifference).map { strip, open in
                min(1.5, (sample.bitmap.drawerMotionChanged(in: strip, against: closed, gain: scrim) ?? 0) / open)
            }
            let gains = strips.map { sample.bitmap.drawerMotionGain(in: $0, against: closed) ?? 1 }
            return Reading(time: sample.time, scrim: scrim, strips: gains, panel: panel)
        }
    }

    /// Screenshots taken back to back for the sequence plus a margin.
    @MainActor
    private func samples(of app: XCUIApplication, width: CGFloat, slowMotion: Double) -> [Sample] {
        let start = Date()
        let end = Self.sequence * slowMotion + 1
        var samples: [Sample] = []
        while Date().timeIntervalSince(start) < end {
            let time = Date().timeIntervalSince(start)
            let screenshot = app.screenshot()
            if let image = screenshot.image.cgImage,
               let bitmap = ButtonFillPixels(image: image, pointWidth: width) {
                samples.append(Sample(time: time, bitmap: bitmap, screenshot: screenshot))
            }
        }
        return samples
    }

    // MARK: - Helpers

    /// Whether the fixture service answers.
    private func fixtureReachable() -> Bool {
        let probe = expectation(description: "fixture probe")
        URLSession.shared.dataTask(with: URL(string: "\(Self.fixtureURL)/api/features")!) { _, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { probe.fulfill() }
        }.resume()
        return XCTWaiter().wait(for: [probe], timeout: 5) == .completed
    }

    /// Screenshot the app into a bitmap and attach it to the report.
    @MainActor
    private func bitmap(of app: XCUIApplication, width: CGFloat, name: String) throws -> ButtonFillPixels {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(screenshot.image.cgImage, "\(name): no bitmap")
        return try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: width), "\(name): no bitmap context")
    }

    /// Attach the readings and every third frame of a sequence.
    private func attach(_ samples: [Sample], readings: [Reading], name: String) {
        for (index, sample) in samples.enumerated() where index % 3 == 0 {
            guard let screenshot = sample.screenshot else { continue }
            let frame = XCTAttachment(screenshot: screenshot)
            frame.name = String(format: "%@-%05.2fs", name, sample.time)
            frame.lifetime = .keepAlways
            add(frame)
        }
        let text = XCTAttachment(string: readings.map(\.description).joined(separator: "\n"))
        text.name = "\(name).txt"
        text.lifetime = .keepAlways
        add(text)
    }

    /// Wait until `element` leaves the hierarchy.
    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: 10) == .completed
    }
}

// MARK: - Scrim and panel measurement

extension ButtonFillPixels {
    /// Rec. 709 luma (0–255) of one pixel.
    private func drawerMotionLuma(x: Int, y: Int) -> Double {
        let offset = (y * width + x) * 4
        return 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])
    }

    /// Pixel bounds of a frame in points, sampled every other pixel.
    private func drawerMotionPixels(in frame: CGRect) -> (xs: StrideTo<Int>, ys: StrideTo<Int>)? {
        let minX = max(Int((frame.minX * scale).rounded(.up)), 0)
        let maxX = min(Int((frame.maxX * scale).rounded(.down)), width)
        let minY = max(Int((frame.minY * scale).rounded(.up)), 0)
        let maxY = min(Int((frame.maxY * scale).rounded(.down)), height)
        guard minX < maxX - 1, minY < maxY - 1 else { return nil }
        return (stride(from: minX, to: maxX, by: 2), stride(from: minY, to: maxY, by: 2))
    }

    /// Mean luma of a frame (issue #362).
    ///
    /// - Parameter frame: The region in screenshot points.
    /// - Returns: The mean luma, or nil when the frame lies outside the bitmap.
    func drawerMotionMeanLuma(in frame: CGRect) -> Double? {
        guard let (xs, ys) = drawerMotionPixels(in: frame) else { return nil }
        var total = 0.0
        var count = 0
        for y in ys { for x in xs { total += drawerMotionLuma(x: x, y: y); count += 1 } }
        return total / Double(count)
    }

    /// How much of `reference`'s luma this bitmap keeps in a frame: the least-squares
    /// gain, 1 for the same image and ~0.55 under the drawer's 45 % black scrim.
    ///
    /// - Parameters:
    ///   - frame: The region in screenshot points.
    ///   - reference: The same window with the drawer closed.
    /// - Returns: The gain, or nil when the frame lies outside the bitmap or is black.
    func drawerMotionGain(in frame: CGRect, against reference: ButtonFillPixels) -> Double? {
        guard let (xs, ys) = drawerMotionPixels(in: frame) else { return nil }
        var product = 0.0
        var square = 0.0
        for y in ys {
            for x in xs {
                let base = reference.drawerMotionLuma(x: x, y: y)
                product += drawerMotionLuma(x: x, y: y) * base
                square += base * base
            }
        }
        return square > 0 ? product / square : nil
    }

    /// The share of pixels in a frame that differ from `reference` dimmed by `gain` by
    /// more than `threshold` luma: near 0 where only a uniform scrim covers the window
    /// (rounding stays within ±2), high where the panel is drawn even when its dark
    /// glass sits over a dark page.
    ///
    /// - Parameters:
    ///   - frame: The region in screenshot points.
    ///   - reference: The same window with the drawer closed.
    ///   - gain: The scrim's measured gain (``drawerMotionGain(in:against:)``).
    ///   - threshold: The luma difference that counts as changed.
    /// - Returns: The changed share (0–1), or nil when the frame lies outside the bitmap.
    func drawerMotionChanged(
        in frame: CGRect, against reference: ButtonFillPixels, gain: Double, threshold: Double = 8
    ) -> Double? {
        guard let (xs, ys) = drawerMotionPixels(in: frame) else { return nil }
        var changed = 0
        var count = 0
        for y in ys {
            for x in xs {
                if abs(drawerMotionLuma(x: x, y: y) - gain * reference.drawerMotionLuma(x: x, y: y)) > threshold {
                    changed += 1
                }
                count += 1
            }
        }
        return Double(changed) / Double(count)
    }
}
