import XCTest

/// Shell chrome journeys: the hamburger drawer, tab re-tap-to-root, and the
/// trailing bell/avatar capsule order — fixture-backed, never production.
///
/// Hosted (macOS) snapshot coverage for the drawer's per-profile content lives in
/// `ShellChromeHostedTests.swift`; this file covers what only a real device
/// navigation stack and toolbar layout can prove.
final class ShellJourneyTests: XCTestCase {
    /// Launch against the loopback fixture service with a selected profile and no
    /// first-run carousel in the way (`FST_DEBUG_FIRST_RUN` defaults to off in Debug).
    @MainActor
    private func fixtureApp(profile: Bool) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if profile {
            env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        }
        return FestivalApp.makeApp(env)
    }

    // MARK: - Drawer

    /// The drawer opens on the hamburger button and closes on its own close button.
    @MainActor
    func testDrawerOpensAndCloses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: false)
        app.launch()
        let open = app.buttons["fst.shell.drawer.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        let drawer = app.descendants(matching: .any).matching(identifier: "fst.shell.drawer").firstMatch
        XCTAssertTrue(drawer.waitForExistence(timeout: 10))
        app.buttons["fst.shell.drawer.close"].tap()
        XCTAssertTrue(waitForDisappearance(of: drawer, timeout: 10))
    }

    // MARK: - Tab re-tap pops to root

    /// Re-tapping the already-selected Leaderboards tab pops a pushed Full Rankings
    /// page back to the Leaderboards root, matching the web's tab semantics.
    @MainActor
    func testReTappingActiveTabPopsToRoot() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: false)
        app.launch()
        let leaderboardsTab = app.tabBars.buttons["Leaderboards"]
        XCTAssertTrue(leaderboardsTab.waitForExistence(timeout: 15))
        leaderboardsTab.tap()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        // Label is now "View all N rankings"; match the card's stable identifier.
        let viewAll = app.buttons.matching(
            NSPredicate(format: "identifier ENDSWITH '.view-all'")
        ).firstMatch
        XCTAssertTrue(viewAll.waitForExistence(timeout: 15))
        viewAll.tap()
        let rankingsTitle = app.navigationBars.matching(
            NSPredicate(format: "identifier CONTAINS 'Rankings'")
        ).firstMatch
        XCTAssertTrue(rankingsTitle.waitForExistence(timeout: 15))
        // Re-tap the same (already active) tab: this must pop back to the root,
        // not merely re-select an already-selected tab and do nothing.
        leaderboardsTab.tap()
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        XCTAssertFalse(rankingsTitle.exists)
    }

    // MARK: - Trailing capsule order

    /// With a profile selected, the bell sits left of the avatar in the trailing
    /// capsule (avatar rightmost), per the toolbar order rule in
    /// `.agents/controls/app-navigation/ios.md`.
    @MainActor
    func testBellSitsLeftOfAvatarInTrailingCapsule() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        let bell = app.buttons["fst.shell.notifications"]
        let avatar = app.buttons["fst.shell.profile"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        XCTAssertTrue(avatar.waitForExistence(timeout: 10))
        XCTAssertLessThan(
            bell.frame.minX, avatar.frame.minX,
            "The profile avatar must stay rightmost of the shared trailing capsule"
        )
    }

    /// Poll for an element to stop existing, since `XCTWaiter` has no
    /// "wait until it disappears" convenience on this Xcode version.
    ///
    /// - Parameters:
    ///   - element: Element expected to disappear.
    ///   - timeout: Seconds to poll.
    /// - Returns: True once the element no longer exists, false on timeout.
    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !element.exists
    }
}
