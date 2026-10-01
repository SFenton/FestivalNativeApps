import UIKit
import XCTest

/// Native journeys for Settings: a toggle survives a cold relaunch, the inline reorder
/// lists drag to reorder, View Licenses opens a third-party-only page, and Reset App
/// Settings restores a changed toggle to its registered default
/// (`SettingsRegistry.defaults`). Needs `tools/mock_service.py --port 18790`.
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

    /// Operator batch 6 (6.11): enabling Independent Song Row Visual Order shows its
    /// reorder list inline (no sheet), and CHOpt Text Path Column Order rows reorder by
    /// dragging their grip handle; Reset restores the default order.
    @MainActor
    func testInlineReorderListsDragToReorder() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let enable = app.switches["fst.settings.enable-visual-order"]
        SongsUITestSupport.reveal(enable, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(enable, to: "1")
        let visualScore = app.descendants(matching: .any)
            .matching(identifier: "fst.settings.song-row-order.score").firstMatch
        XCTAssertTrue(visualScore.waitForExistence(timeout: 10), "Visual order list is not inline")
        XCTAssertFalse(app.buttons["Done"].exists, "No reorder sheet")

        func row(_ key: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(identifier: "fst.settings.path-column-order.\(key)").firstMatch
        }
        // Earlier runs may have left a custom order: find the current first and last rows.
        let keys = ["note", "beat", "time", "od", "score"]
        SongsUITestSupport.reveal(row("score"), in: app, scrollingUp: true)
        SongsUITestSupport.reveal(row("note"), in: app, scrollingUp: false)
        let first = try XCTUnwrap(keys.map(row).first { $0.value as? String == "1 of 5" })
        let last = try XCTUnwrap(keys.map(row).first { $0.value as? String == "5 of 5" })
        XCTAssertLessThan(first.frame.minY, last.frame.minY)
        SongsUITestSupport.record(app, name: "settings-path-columns-before-drag")

        // Drag the last row by its leading grip handle onto the first.
        last.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).press(
            forDuration: 0.3,
            thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.3))
        )
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1 of 5"), object: last
        )
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed, "Row was not dragged to the top")
        XCTAssertEqual(first.value as? String, "2 of 5")
        SongsUITestSupport.record(app, name: "settings-path-columns-after-drag")
        let score = row("score")

        // A quick swipe that starts on the list still scrolls the page.
        let before = score.frame.minY
        app.swipeUp()
        XCTAssertNotEqual(score.frame.minY, before, "Swiping over a reorder list must scroll the page")

        let resetButton = app.buttons["fst.settings.reset"]
        SongsUITestSupport.reveal(resetButton, in: app, scrollingUp: true)
        resetButton.tap()
        // The page button shares the dialog button's label; tap the dialog's.
        let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "Reset App Settings"))
        let dialog = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 1"), object: confirmations
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dialog], timeout: 10), .completed)
        let confirm = try XCTUnwrap(
            confirmations.allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "fst.settings.reset" }
        )
        confirm.tap()
        SongsUITestSupport.reveal(score, in: app, scrollingUp: false)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "5 of 5"), object: score
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
        XCTAssertFalse(visualScore.exists, "Reset turns the independent visual order off")
    }

    /// Operator batch 6 (6.17): View Licenses opens the Licenses page without a Bundled
    /// Assets section or iconography entry.
    @MainActor
    func testLicensesRowOpensThirdPartyOnlyPage() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let licenses = app.buttons["fst.settings.licenses"]
        SongsUITestSupport.reveal(licenses, in: app, scrollingUp: true)
        licenses.tap()
        XCTAssertTrue(app.staticTexts["Third-Party Software"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Bundled Assets"].exists)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Iconography")).firstMatch.exists)
        SongsUITestSupport.record(app, name: "settings-licenses-page")
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
        let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "Reset App Settings"))
        let dialog = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 1"), object: confirmations
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dialog], timeout: 10), .completed)
        let confirm = try XCTUnwrap(
            confirmations.allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "fst.settings.reset" }
        )
        confirm.tap()

        let restoredHideShop = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(restoredHideShop, in: app, scrollingUp: true)
        let settledOff = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "0"), object: restoredHideShop
        )
        XCTAssertEqual(XCTWaiter.wait(for: [settledOff], timeout: 10), .completed)
        SongsUITestSupport.record(app, name: "settings-hide-shop-after-reset")
    }

    /// **Fixed bug (#6):** the iPhone Quick Links menu opens upward from the bottom
    /// dock, and iOS reversed an `.automatic`-order menu there, so the menu listed
    /// Settings' sections bottom-to-top. `QuickLinksMenu` now uses `.menuOrder(.fixed)`.
    /// Rows must stack top-to-bottom in page order, the active section stays checked,
    /// and choosing a row still jumps to it.
    @MainActor
    func testQuickLinksMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        quickLinks.tap()

        let pageOrder = [
            "app-settings", "diagnostics", "accessibility", "item-shop", "show-instruments",
            "show-metadata", "version", "service-info", "first-run", "licenses", "reset",
        ]
        let rows = pageOrder.map { app.buttons["fst.quick-links.item.\($0)"] }
        XCTAssertTrue(rows[0].waitForExistence(timeout: 10))
        let tops = rows.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "Quick Links rows are not in page order: \(zip(pageOrder, tops).map { "\($0.0)@\(Int($0.1))" })")
        XCTAssertLessThan(tops[0], tops[tops.count - 1])
        XCTAssertTrue(rows[0].isSelected, "The active (first) section is not checked")
        SongsUITestSupport.record(app, name: "settings-quick-links-menu-order")

        let itemShop = app.buttons["fst.quick-links.item.item-shop"]
        itemShop.tap()
        let jumped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Item Shop"), object: quickLinks
        )
        XCTAssertEqual(XCTWaiter.wait(for: [jumped], timeout: 10), .completed)
    }
}
