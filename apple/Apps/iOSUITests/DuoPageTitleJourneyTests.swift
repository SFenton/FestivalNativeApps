import UIKit
import XCTest

/// Every root page shows its complete system navigation title (pattern
/// page-tools-and-nav-chrome R14, issue #341), in whichever iPhone Duo pose the
/// simulator is in: run it once folded (the vertical bar, title at the top of the
/// page) and once unfolded (inner portrait, horizontal bar):
///
/// ```
/// python3 tools/mock_service.py --port 18341 &
/// python3 tools/ios_sim.py uitest --device duo --pose folded --set-pose --only DuoPageTitleJourneyTests
/// python3 tools/ios_sim.py uitest --device duo --pose unfolded --set-pose --rotate right --only DuoPageTitleJourneyTests
/// ```
///
/// On an ordinary iPhone it checks the same rule under the horizontal bar.
/// Item Shop, which phones push from Songs and the iPad sidebar shows as a root, keeps
/// the same system large title as the roots in every pose (#375): its title is exactly
/// as tall as Songs' and Settings', in the real pose and, on a Duo, in the simulated
/// unfolded windows (`FST_DEBUG_DUO_WINDOW`) for hosts that cannot script Device Hub.
/// Statistics, which phones push from the Profile button and drawer rather than show as a
/// tab (pattern R12, #337), opens through the same launch route the drawer uses. Its
/// no-profile state (momentary after Deselect) is held open with the Debug
/// `FST_DEBUG_KEEP_PROFILE_ROUTES=1` launch flag.
final class DuoPageTitleJourneyTests: XCTestCase {
    /// Loopback fixture service; `FST_TITLE_FIXTURE_URL` overrides the default port.
    private static let fixtureURL =
        ProcessInfo.processInfo.environment["FST_TITLE_FIXTURE_URL"] ?? "http://127.0.0.1:18341"

    /// The fixture player the profile-only roots are opened for.
    private static let player = (accountId: "fixture-player-1", displayName: "Fixture Player 1")

    /// Anonymous roots (Songs · Leaderboards · Settings).
    @MainActor
    func testAnonymousRootsShowFullTitle() throws {
        for (tab, title) in [("songs", "Songs"), ("leaderboards", "Leaderboards"), ("settings", "Settings")] {
            try assertRoot(tab: tab, title: title, withPlayer: false)
        }
    }

    /// Profile-only pages: Suggestions, and Statistics titled with the player's name.
    @MainActor
    func testPlayerRootsShowFullTitle() throws {
        try assertRoot(tab: "suggestions", title: "Suggestions", withPlayer: true)
        try assertRoot(tab: "statistics", title: Self.player.displayName, tabLabel: "Statistics",
                       withPlayer: true)
    }

    /// Statistics without a player (its "No Profile Selected" state) is titled
    /// "Statistics": the title comes from `festivalNavigationTitle("Statistics")` on that
    /// state alone, so dropping it fails here in both poses.
    @MainActor
    func testNoProfileStatisticsShowsFullTitle() throws {
        try assertRoot(tab: "statistics", title: "Statistics", withPlayer: false,
                       extraEnvironment: ["FST_DEBUG_KEEP_PROFILE_ROUTES": "1"],
                       requiredElement: "fst.statistics.empty")
    }

    /// Compete (every phone shell, Duo included) or Leaderboards and Rivals (the iPad
    /// sidebar set), whichever the tab policy shows for a selected player.
    @MainActor
    func testPlayerCompeteRootsShowFullTitle() throws {
        let app = launch(tab: "compete", withPlayer: true)
        if titleElement("Compete", in: app).waitForExistence(timeout: 15) {
            try assertFullTitle("Compete", in: app, tab: "compete")
            return
        }
        app.terminate()
        try assertRoot(tab: "leaderboards", title: "Leaderboards", withPlayer: true)
        try assertRoot(tab: "rivals", title: "Rivals", withPlayer: true)
    }

    /// Item Shop's title is the same size as the roots' in the simulator's real pose
    /// (#375): the system large title, never a larger or smaller custom one.
    @MainActor
    func testItemShopTitleMatchesRootTitleSize() throws {
        try assertItemShopMatchesRoots(environment: [:])
    }

    /// The same comparison in the unfolded inner landscape (vertical bar) and inner
    /// portrait (horizontal bar) layouts, simulated in the real window (`DebugDuoWindow`).
    /// Skips on a device that is not an iPhone Duo.
    @MainActor
    func testItemShopTitleMatchesRootTitleSizeUnfolded() throws {
        for window in ["unfolded-landscape", "unfolded-portrait"] {
            try assertItemShopMatchesRoots(environment: [
                "FST_DEBUG_DUO_WINDOW_REMOTE": "1",
                "FST_DEBUG_DUO_WINDOW": window,
            ])
        }
    }

    // MARK: - Helpers

    /// Measure Songs, Settings and Item Shop (pushed on Songs through its launch route)
    /// in one layout and require Item Shop's title to be exactly as tall as the roots'
    /// (within half a point) and at least the system large title's height.
    ///
    /// - Parameter environment: Extra launch environment (a simulated Duo window).
    @MainActor
    private func assertItemShopMatchesRoots(environment: [String: String],
                                            file: StaticString = #filePath, line: UInt = #line) throws {
        let songs = try assertRoot(tab: "songs", title: "Songs", withPlayer: false,
                                   extraEnvironment: environment, file: file, line: line)
        let settings = try assertRoot(tab: "settings", title: "Settings", withPlayer: false,
                                      extraEnvironment: environment, file: file, line: line)
        let shop = try assertRoot(tab: "songs", title: "Item Shop", withPlayer: false,
                                  extraEnvironment: environment.merging(["FST_DEBUG_ROUTE": "shop"]) { _, new in new },
                                  file: file, line: line)
        let layout = environment["FST_DEBUG_DUO_WINDOW"] ?? "real pose"
        XCTAssertEqual(shop, songs, accuracy: 0.5,
                       "\(layout): Item Shop title \(shop) pt tall, Songs \(songs) pt", file: file, line: line)
        XCTAssertEqual(shop, settings, accuracy: 0.5,
                       "\(layout): Item Shop title \(shop) pt tall, Settings \(settings) pt", file: file, line: line)
        // A collapsed or inline title is one 17 pt line; the large title's line is ~41 pt.
        let inline = UIFont.systemFont(ofSize: 17, weight: .semibold).lineHeight
        XCTAssertGreaterThan(shop, inline * 1.5,
                             "\(layout): Item Shop title \(shop) pt tall is not the large title", file: file, line: line)
    }

    /// Launch on `tab` and require its complete title at the top of the page.
    ///
    /// The launch tab is resolved against the first (standard phone) layout before the
    /// Duo's own one is published, so an unfolded launch can land on another root; the
    /// root is then selected from its visible tab, as a person would. With a simulated
    /// `FST_DEBUG_DUO_WINDOW` it first waits for the app to apply it, and skips when the
    /// device is not an iPhone Duo (no readout).
    ///
    /// - Returns: The title's height in points.
    @discardableResult
    @MainActor
    private func assertRoot(tab: String, title: String, tabLabel: String? = nil, withPlayer: Bool,
                            extraEnvironment: [String: String] = [:], requiredElement: String? = nil,
                            file: StaticString = #filePath, line: UInt = #line) throws -> CGFloat {
        let app = launch(tab: tab, withPlayer: withPlayer, extraEnvironment: extraEnvironment)
        defer { app.terminate() }
        if let window = extraEnvironment["FST_DEBUG_DUO_WINDOW"] {
            let real = app.windows.firstMatch
            XCTAssertTrue(real.waitForExistence(timeout: 15), file: file, line: line)
            guard Self.isDuoWindow(real.frame.size) else {
                throw XCTSkip("Not an iPhone Duo window (\(real.frame.size)): \(window) is not simulated")
            }
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "\(window) "), object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: 15), .completed,
                           "The app never simulated \(window)", file: file, line: line)
        }
        if let requiredElement {
            XCTAssertTrue(
                app.descendants(matching: .any)[requiredElement].waitForExistence(timeout: 15),
                "\(tab): the \(requiredElement) state never appeared", file: file, line: line
            )
        }
        if !titleElement(title, in: app).waitForExistence(timeout: 15) {
            let control = SongsUITestSupport.rootControl(tabLabel ?? title, app: app)
            if control.waitForExistence(timeout: 3), control.isHittable { control.tap() }
        }
        XCTAssertTrue(
            titleElement(title, in: app).waitForExistence(timeout: 10),
            "\(tab): no \"\(title)\" title; navigation bars \(app.navigationBars.allElementsBoundByIndex.map(\.identifier))",
            file: file, line: line
        )
        try assertFullTitle(title, in: app, tab: tab, file: file, line: line)
        return titleElement(title, in: app).frame.height
    }

    /// Whether a real window is one of the iPhone Duo's (outer 466 × 678 or inner
    /// 951 × 669 pt, either orientation; `DebugDuoWindow.size`).
    private static func isDuoWindow(_ size: CGSize) -> Bool {
        let sides = [min(size.width, size.height).rounded(), max(size.width, size.height).rounded()]
        return sides == [466, 678] || sides == [669, 951]
    }

    /// Launch the fixture app on a root tab, anonymous or with the fixture player.
    @MainActor
    private func launch(tab: String, withPlayer: Bool,
                        extraEnvironment: [String: String] = [:]) -> XCUIApplication {
        var env = ["FST_API_BASE_URL": Self.fixtureURL, "FST_DEBUG_TAB": tab]
        env.merge(extraEnvironment) { _, extra in extra }
        if withPlayer {
            env["FST_DEBUG_PROFILE"] = "\(Self.player.accountId):\(Self.player.displayName)"
        } else {
            env["FST_DEBUG_ANONYMOUS"] = "1"
        }
        return FestivalApp.launch(env)
    }

    /// The page title text: a static text labelled `title` inside a navigation bar
    /// (the system keeps one for the title even beside the Duo vertical bar).
    @MainActor
    private func titleElement(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Require the title to sit fully on screen near the top and to be at least as wide
    /// as the whole string set in the smallest system title font (17 pt semibold; the app
    /// uses 20 pt inline and the system 34 pt large), so a truncated "S…" fails.
    @MainActor
    private func assertFullTitle(_ title: String, in app: XCUIApplication, tab: String,
                                 file: StaticString = #filePath, line: UInt = #line) throws {
        let element = titleElement(title, in: app)
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "duo-title-\(tab)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(element.isHittable || !frame.isEmpty, "\(tab): title not visible", file: file, line: line)
        XCTAssertTrue(window.contains(frame), "\(tab): title \(frame) leaves the window \(window)",
                      file: file, line: line)
        XCTAssertLessThan(frame.minY, window.minY + window.height / 3,
                          "\(tab): title \(frame) is not at the top of the page", file: file, line: line)
        let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let minimum = (title as NSString).size(withAttributes: [.font: font]).width * 0.95
        XCTAssertGreaterThanOrEqual(
            frame.width, minimum,
            "\(tab): title \"\(title)\" is \(frame.width) pt wide, under the \(minimum) pt the whole string needs (truncated?)",
            file: file, line: line
        )
    }
}
