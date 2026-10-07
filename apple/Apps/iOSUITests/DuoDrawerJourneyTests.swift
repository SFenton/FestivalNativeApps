import UIKit
import XCTest

/// The navigation drawer is modal over the whole window on every phone shell, iPhone
/// Duo's system vertical bar included (pattern page-tools-and-nav-chrome R14, issue
/// #339): opening it dims the bar like the rest of the content, its panel runs to the
/// 8 pt floating margin at the bottom, a tap on the bar area hits the scrim and closes
/// it without switching tabs, and the panel stays modal with its accessibility order.
///
/// Run it on the real Duo in each pose (the simulated `FST_DEBUG_DUO_WINDOW` keeps the
/// real window's chrome, so only a real pose has the real bar and safe areas):
///
/// ```
/// python3 tools/mock_service.py --port 18339 &
/// python3 tools/ios_sim.py uitest --device duo --pose folded --set-pose --only DuoDrawerJourneyTests
/// python3 tools/ios_sim.py uitest --device duo --pose unfolded --set-pose --only DuoDrawerJourneyTests
/// python3 tools/ios_sim.py uitest --device duo --pose half --set-pose --only DuoDrawerJourneyTests
/// ```
///
/// Without Device Hub scripting, the folded run also covers the unfolded layout through
/// ``testDrawerInUnfoldedLayoutCoversBarAndReachesBottom()``.
///
/// On an ordinary iPhone (or unfolded portrait) the same rules hold for the horizontal
/// tab bar. Skips without the fixture service.
final class DuoDrawerJourneyTests: XCTestCase {
    /// Loopback fixture service; `FST_DRAWER_FIXTURE_URL` overrides the default port.
    private static let fixtureURL =
        ProcessInfo.processInfo.environment["FST_DRAWER_FIXTURE_URL"] ?? "http://127.0.0.1:18339"

    /// Tabs the anonymous phone shell shows (`FestivalTabPolicy`).
    private let anonymousTabs = ["Songs", "Leaderboards", "Settings"]

    /// `DrawerPlacement.margin`: the floating gap between the panel and the window edge.
    private let margin: CGFloat = 8

    /// Open the drawer from Songs in the simulator's real pose, check the bar's dimming
    /// and the panel's bottom edge in the rendered window, then tap the bar area to close it.
    @MainActor
    func testDrawerScrimCoversBarAndPanelReachesBottom() throws {
        try assertDrawerCoversWindow(environment: [:])
    }

    /// The same checks with the unfolded inner-landscape layout (`DebugDuoWindow`) laid
    /// out in the real window and vertical bar, for hosts that cannot script Device
    /// Hub's Open control. Skips on a device without a vertical bar.
    @MainActor
    func testDrawerInUnfoldedLayoutCoversBarAndReachesBottom() throws {
        try assertDrawerCoversWindow(environment: [
            "FST_DEBUG_DUO_WINDOW_REMOTE": "1",
            "FST_DEBUG_DUO_WINDOW": "unfolded-landscape",
        ], requiresVerticalBar: true)
    }

    // MARK: - Journey

    /// Launch Songs anonymously, open the drawer and check it covers the whole window.
    ///
    /// - Parameters:
    ///   - environment: Extra launch environment (a simulated Duo window).
    ///   - requiresVerticalBar: Skip unless the window shows the system vertical bar.
    @MainActor
    private func assertDrawerCoversWindow(environment: [String: String], requiresVerticalBar: Bool = false) throws {
        continueAfterFailure = false
        try XCTSkipUnless(fixtureReachable(), "Start `mock_service.py --port 18339` from this revision")
        let app = FestivalApp.launch([
            "FST_API_BASE_URL": Self.fixtureURL,
            "FST_DEBUG_ANONYMOUS": "1",
            "FST_DEBUG_TAB": "songs",
        ].merging(environment) { _, extra in extra })
        defer { app.terminate() }
        if let window = environment["FST_DEBUG_DUO_WINDOW"] {
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "\(window) "), object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: 15), .completed,
                           "The app never simulated \(window)")
        }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let tabs = waitForTabs(in: app)
        XCTAssertGreaterThanOrEqual(tabs.count, 2, "No section tabs: \(tabs.map(\.title))")
        let windowFrame = window.frame
        let bar = tabs.map(\.frame).reduce(tabs[0].frame) { $0.union($1) }
        let vertical = bar.height > bar.width
        if requiresVerticalBar, !vertical {
            throw XCTSkip("No system vertical bar on this device (tabs \(bar))")
        }
        let pose = "\(vertical ? "vertical-bar" : "tab-bar")-\(Int(windowFrame.width))x\(Int(windowFrame.height))"
        settle()
        let before = try bitmap(of: app, pointWidth: windowFrame.width, name: "duo-drawer-closed-\(pose)")

        ShellUITestSupport.tapToolbarItem("fst.shell.drawer.open", overflowLabels: ["Menu", "Open Navigation"], in: app)
        let panel = app.descendants(matching: .any)["fst.shell.drawer"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "The drawer never opened")
        settle()
        let after = try bitmap(of: app, pointWidth: windowFrame.width, name: "duo-drawer-open-\(pose)")
        let panelFrame = panel.frame

        // The panel runs to the floating margin at the bottom (rows clear the home
        // indicator inside it), as on iPhone and the iPad flyout.
        XCTAssertLessThanOrEqual(
            windowFrame.maxY - panelFrame.maxY, margin + 1,
            "\(pose): the panel \(panelFrame) stops \(windowFrame.maxY - panelFrame.maxY) pt above the window bottom"
        )
        XCTAssertFalse(panelFrame.intersects(vertical ? bar : .null), "\(pose): the panel \(panelFrame) covers the bar \(bar)")

        // The bar (and the art behind it) is dimmed by the scrim like the content. The
        // sample leaves out the panel and its shadow; a phone's horizontal tab bar can lie
        // wholly under the panel, and the Duo vertical bar never does.
        let sample = barSample(bar, excluding: panelFrame, vertical: vertical)
        XCTAssertTrue(!vertical || !sample.isEmpty, "\(pose): no bar area outside the panel (\(bar), \(panelFrame))")
        if !sample.isEmpty {
            let lit = try XCTUnwrap(before.meanLuminance(in: sample))
            let dimmed = try XCTUnwrap(after.meanLuminance(in: sample))
            print("drawer-scrim \(pose): bar \(sample) luma \(lit) -> \(dimmed); panel \(panelFrame) in \(windowFrame)")
            XCTAssertGreaterThan(lit, 8, "\(pose): the bar sample \(sample) is too dark to measure")
            // The scrim is 45 % black, so a covered bar keeps about 55 % of its luminance;
            // an uncovered one keeps ~100 %.
            XCTAssertLessThan(
                dimmed / lit, 0.75,
                "\(pose): the bar \(sample) kept \(Int(dimmed / lit * 100)) % of its luminance (\(lit) → \(dimmed)): not dimmed"
            )
        }

        // Modal (VoiceOver order unchanged): the panel carries the modal trait, which
        // XCUITest reports as an alert and VoiceOver uses to skip the shell behind it,
        // the bar included; inside it, Close and the rows read in the web sidebar's order.
        let modal = app.alerts["fst.shell.drawer"]
        XCTAssertTrue(modal.exists, "\(pose): the drawer panel is not modal")
        // XCUITest lists descendants depth first (scrolling rows after the pinned footer),
        // so the reading order is checked from the layout, top to bottom.
        let order = ["fst.shell.drawer.close", "fst.shell.drawer.songs", "fst.shell.drawer.leaderboards",
                     "fst.shell.drawer.shop", "fst.shell.drawer.select-profile", "fst.shell.drawer.settings"]
        let buttons = modal.buttons.allElementsBoundByIndex.map { ($0.identifier, $0.frame) }
        XCTAssertEqual(Set(buttons.map(\.0)), Set(order), "\(pose): the drawer's buttons changed")
        XCTAssertEqual(
            buttons.sorted { $0.1.minY < $1.1.minY }.map(\.0), order,
            "\(pose): the drawer's reading order changed"
        )

        // A tap on a tab's position in the bar lands on the scrim: the drawer closes and
        // the selection stays on Songs. Where every tab is under the panel (a phone's
        // tab bar), the tap goes to the scrim beside the panel at the bar's height.
        let target = tabs.last { $0.title != "Songs" && !panelFrame.insetBy(dx: -24, dy: 0).contains(center($0.frame)) }
        XCTAssertTrue(!vertical || target != nil, "\(pose): every tab is under the panel")
        let point = target.map { center($0.frame) }
            ?? CGPoint(x: (panelFrame.maxX + windowFrame.maxX) / 2, y: bar.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
        XCTAssertTrue(waitForDisappearance(of: panel), "\(pose): tapping the bar area did not close the drawer")
        let songs = waitForTabs(in: app).first { $0.title == "Songs" }
        XCTAssertEqual(songs?.isSelected, true, "\(pose): the tap at \(point) reached a tab under the scrim")
        if let target {
            XCTAssertFalse(app.navigationBars[target.title].exists, "\(pose): the tap opened \(target.title)")
        }
    }

    // MARK: - Helpers

    /// One section tab in the bar.
    private struct Tab {
        let title: String
        let frame: CGRect
        let isSelected: Bool
    }

    /// Whether the fixture service answers.
    private func fixtureReachable() -> Bool {
        let probe = expectation(description: "fixture probe")
        var reachable = false
        URLSession.shared.dataTask(with: URL(string: "\(Self.fixtureURL)/api/features")!) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 5)
        return reachable
    }

    /// The anonymous shell's tabs once they are on screen (expanding a minimized bar).
    @MainActor
    private func waitForTabs(in app: XCUIApplication) -> [Tab] {
        let deadline = Date().addingTimeInterval(15)
        var tabs: [Tab] = []
        repeat {
            let collapsed = app.tabBars.buttons.matching(NSPredicate(format: "value == %@", "Collapsed")).firstMatch
            if collapsed.exists { collapsed.tap() }
            tabs = anonymousTabs.compactMap { title in
                ShellUITestSupport.tabButtons(title, in: app).first.map {
                    Tab(title: title, frame: $0.frame, isSelected: $0.isSelected)
                }
            }
            if tabs.count == anonymousTabs.count { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return tabs
    }

    /// The part of the bar to measure: the bar outside the panel and its 20 pt shadow,
    /// inset from the bar's own rounded edges.
    private func barSample(_ bar: CGRect, excluding panel: CGRect, vertical: Bool) -> CGRect {
        var sample = bar.insetBy(dx: 4, dy: 4)
        if !vertical, sample.minX < panel.maxX + 32 {
            sample = CGRect(x: panel.maxX + 32, y: sample.minY,
                            width: max(0, sample.maxX - panel.maxX - 32), height: sample.height)
        }
        return sample.width > 4 && sample.height > 4 ? sample : .null
    }

    /// Screenshot the app into a bitmap and attach it to the report.
    @MainActor
    private func bitmap(of app: XCUIApplication, pointWidth: CGFloat, name: String) throws -> ButtonFillPixels {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(screenshot.image.cgImage, "\(name): no bitmap")
        return try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: pointWidth), "\(name): no bitmap context")
    }

    /// Let transitions finish (the drawer slides in over ~0.35 s).
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }

    /// Wait until `element` leaves the hierarchy.
    private func waitForDisappearance(of element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: 5) == .completed
    }

    /// The centre of a frame.
    private func center(_ frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

// MARK: - Luminance

extension ButtonFillPixels {
    /// Mean Rec. 709 luma (0–255) of a frame, for comparing how dark one region renders
    /// in two screenshots (the drawer scrim over the Duo vertical bar, #339).
    ///
    /// - Parameter frame: The region in screenshot points.
    /// - Returns: The mean luma, or nil when the frame lies outside the bitmap.
    func meanLuminance(in frame: CGRect) -> Double? {
        let minX = max(Int((frame.minX * scale).rounded(.up)), 0)
        let maxX = min(Int((frame.maxX * scale).rounded(.down)), width) - 1
        let minY = max(Int((frame.minY * scale).rounded(.up)), 0)
        let maxY = min(Int((frame.maxY * scale).rounded(.down)), height) - 1
        guard minX < maxX, minY < maxY else { return nil }
        var total = 0.0
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = (y * width + x) * 4
                total += 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1])
                    + 0.0722 * Double(pixels[offset + 2])
            }
        }
        return total / Double((maxX - minX + 1) * (maxY - minY + 1))
    }
}
