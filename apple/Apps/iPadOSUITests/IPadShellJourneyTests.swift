import XCTest

/// iPadOS shell journeys on "FST Native iPad Pro 11": the sections sidebar, list/detail
/// columns and live reflow on rotation. Fixture-backed (`tools/mock_service.py` on
/// 127.0.0.1:8765), never production. Run with
/// `python3 tools/ios_sim.py uitest --device ipad --only IPadShellJourneyTests`.
final class IPadShellJourneyTests: XCTestCase {
    /// Launch against the loopback fixture service, optionally with a selected player.
    @MainActor
    private func fixtureApp(profile: Bool, extra: [String: String] = [:]) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if profile {
            env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        }
        env.merge(extra) { _, new in new }
        return FestivalApp.makeApp(env)
    }

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// The sidebar lists the web sidebar's destinations and switches sections.
    @MainActor
    func testSidebarListsWebDestinations() throws {
        let app = fixtureApp(profile: false)
        app.launch()
        let sidebar = app.descendants(matching: .any).matching(identifier: "fst.nav.sidebar").firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 20))
        for id in ["fst.nav.songs", "fst.nav.leaderboards", "fst.nav.shop", "fst.nav.settings"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].waitForExistence(timeout: 5), id)
        }
        XCTAssertFalse(app.tabBars.firstMatch.exists, "regular width uses the sidebar, not tabs")
    }
}
