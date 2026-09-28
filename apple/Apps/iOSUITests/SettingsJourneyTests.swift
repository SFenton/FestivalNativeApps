import UIKit
import XCTest

/// Native journeys for Settings: a toggle survives a cold relaunch, the visual-order
/// reorder sheet opens and closes from its own row, and Reset App Settings restores a
/// changed toggle to its registered default (`SettingsRegistry.defaults`).
///
/// **Re-investigated and un-skipped 2026-09-28 (Lane C):** all three methods
/// were previously skipped as "consistently hung the full 300s lock-hold
/// budget, inconclusive root cause." Ruled out a product bug on inspection:
/// unlike `Features/Songs` (see `Design/MarqueeText.swift`'s fix for
/// `FST_DEBUG_STILL_BACKGROUND` not stopping its `TimelineView`), nothing in
/// `Features/Settings/**` or `FirstRunSettingsSection.swift` uses
/// `TimelineView`/`repeatForever`/`Timer`, and a live `tools/ios_sim.py drive`
/// load-then-scroll-then-tap sequence against Settings completed in under 20s.
/// Re-run individually via `tools/ios_sim.py uitest` after this lane's
/// `FestivalApp` launch-helper fix (every journey now always gets
/// `FST_DEBUG_STILL_BACKGROUND=1`): all three passed alone —
/// `testSongRowOrderReorderSheetOpensAndCloses` in 267.8s (cold
/// build-for-testing), `testResetAppSettingsRestoresChangedToggle` in 68.2s,
/// `testAccessibilityToggleSurvivesRelaunch` (a full terminate+relaunch) in
/// 281.8s. Running two of them together in one 200s batch did time out once
/// during this investigation — consistent with the original finding being
/// shared-simulator contention (this Mac had 10+ other lanes' concurrent
/// `xcodebuild` processes at points during this session) rather than a
/// deterministic hang: batch multiple Settings tests with a generous
/// `--timeout` (300s+) or run them one at a time.
final class SettingsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_API_BASE_URL": "http://127.0.0.1:18790",
            "FST_DEBUG_TAB": "settings",
        ])
    }

    /// Toggling an accessibility override must still read back the same value after
    /// a full process relaunch (real `UserDefaults.standard`, not `FST_DEBUG_PROFILE`'s
    /// in-memory-only identity), then restore it so later tests see the default.
    @MainActor
    func testAccessibilityToggleSurvivesRelaunch() throws {
        continueAfterFailure = false
        let toggleId = "fst.settings.more-contrast"
        let firstLaunch = fixtureApp()
        firstLaunch.launch()
        let toggle = firstLaunch.switches[toggleId]
        SongsUITestSupport.reveal(toggle, in: firstLaunch, scrollingUp: true)
        let original = try XCTUnwrap(toggle.value as? String)
        let flipped = original == "1" ? "0" : "1"
        SongsUITestSupport.setSwitch(toggle, to: flipped)
        SongsUITestSupport.record(firstLaunch, name: "settings-toggle-before-relaunch")
        firstLaunch.terminate()

        let relaunched = fixtureApp()
        relaunched.launch()
        let restoredToggle = relaunched.switches[toggleId]
        SongsUITestSupport.reveal(restoredToggle, in: relaunched, scrollingUp: true)
        XCTAssertEqual(
            restoredToggle.value as? String, flipped,
            "Accessibility override did not survive a cold relaunch"
        )
        SongsUITestSupport.record(relaunched, name: "settings-toggle-after-relaunch")
        // Restore the original value so later tests/lanes see the registered default.
        SongsUITestSupport.setSwitch(restoredToggle, to: original)
    }

    /// The Song Row Order reorder sheet opens from its row once visual order is
    /// enabled, lists every metadata field, and Done returns to Settings.
    @MainActor
    func testSongRowOrderReorderSheetOpensAndCloses() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let enable = app.switches["fst.settings.enable-visual-order"]
        SongsUITestSupport.reveal(enable, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(enable, to: "1")

        let reorderRow = app.buttons["fst.settings.song-row-order"]
        SongsUITestSupport.reveal(reorderRow, in: app, scrollingUp: false)
        reorderRow.tap()

        let firstField = app.staticTexts["Score"]
        XCTAssertTrue(firstField.waitForExistence(timeout: 10), "Reorder sheet did not list its metadata fields")
        XCTAssertTrue(app.staticTexts["Percentage"].exists)
        SongsUITestSupport.record(app, name: "settings-reorder-sheet-open")

        app.buttons["Done"].tap()
        XCTAssertTrue(
            app.switches["fst.settings.enable-visual-order"].waitForExistence(timeout: 10),
            "Reorder sheet did not dismiss back to Settings"
        )
        // Leave visual order off for later tests/lanes.
        let enableAfter = app.switches["fst.settings.enable-visual-order"]
        SongsUITestSupport.reveal(enableAfter, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(enableAfter, to: "0")
    }

    /// Reset App Settings restores a changed toggle to its registered default.
    @MainActor
    func testResetAppSettingsRestoresChangedToggle() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let hideShop = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hideShop, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hideShop, to: "1")
        SongsUITestSupport.record(app, name: "settings-hide-shop-before-reset")

        let resetButton = app.buttons["fst.settings.reset"]
        SongsUITestSupport.reveal(resetButton, in: app, scrollingUp: false)
        resetButton.tap()
        let confirm = app.buttons["Reset App Settings"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()

        let restoredHideShop = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(restoredHideShop, in: app, scrollingUp: true)
        let settledOff = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "0"), object: restoredHideShop
        )
        XCTAssertEqual(XCTWaiter.wait(for: [settledOff], timeout: 10), .completed)
        SongsUITestSupport.record(app, name: "settings-hide-shop-after-reset")
    }
}
