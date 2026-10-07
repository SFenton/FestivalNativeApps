import UIKit
import XCTest

/// Every root page shows its complete system navigation title (pattern
/// page-tools-and-nav-chrome R12, issue #341), in whichever iPhone Duo pose the
/// simulator is in: run it once folded (the vertical bar, title at the top of the
/// page) and once unfolded (inner portrait, horizontal bar):
///
/// ```
/// python3 tools/mock_service.py --port 18341 &
/// python3 tools/ios_sim.py uitest --device duo --pose folded --set-pose --only DuoPageTitleJourneyTests
/// python3 tools/ios_sim.py uitest --device duo --pose unfolded --set-pose --only DuoPageTitleJourneyTests
/// ```
///
/// On an ordinary iPhone it checks the same rule under the horizontal bar.
/// Statistics' no-profile state is not routable (`ProfileRoutePolicy`); its title is
/// pinned by `statisticsScreenNoProfileGuardKeepsStatisticsTitle` instead.
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

    /// Profile-only roots: Suggestions, and Statistics titled with the player's name.
    @MainActor
    func testPlayerRootsShowFullTitle() throws {
        try assertRoot(tab: "suggestions", title: "Suggestions", withPlayer: true)
        try assertRoot(tab: "statistics", title: Self.player.displayName, tabLabel: "Statistics",
                       withPlayer: true)
    }

    /// Compete (compact widths) or Leaderboards and Rivals (regular widths), whichever
    /// the pose's tab policy shows for a selected player.
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

    // MARK: - Helpers

    /// Launch on `tab` and require its complete title at the top of the page.
    ///
    /// The launch tab is resolved against the first (standard phone) layout before the
    /// Duo's own one is published, so an unfolded launch can land on another root; the
    /// root is then selected from its visible tab, as a person would.
    @MainActor
    private func assertRoot(tab: String, title: String, tabLabel: String? = nil, withPlayer: Bool,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let app = launch(tab: tab, withPlayer: withPlayer)
        defer { app.terminate() }
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
    }

    /// Launch the fixture app on a root tab, anonymous or with the fixture player.
    @MainActor
    private func launch(tab: String, withPlayer: Bool) -> XCUIApplication {
        var env = ["FST_API_BASE_URL": Self.fixtureURL, "FST_DEBUG_TAB": tab]
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
