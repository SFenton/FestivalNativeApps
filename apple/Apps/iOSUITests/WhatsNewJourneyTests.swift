import XCTest

/// "What's New" launch sheet, its persisted dismissal and Settings replay, plus the Settings
/// Service Info card against the loopback fixture (`tools/mock_service.py --port 18791`).
///
/// Launch presentation is off by default in Debug (`FST_DEBUG_WHATS_NEW`); these journeys
/// opt in with `fresh` (forget the stored dismissal, then use the real gate) and `on` (real
/// gate only), so the relaunch assertion exercises the actual persisted `{version, hash}`.
final class WhatsNewJourneyTests: XCTestCase {
    private static let fixture = "http://127.0.0.1:18791"

    @MainActor
    private func app(_ extra: [String: String]) -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixture,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ].merging(extra) { _, new in new })
    }

    /// A fresh changelog presents once at launch; Dismiss closes it and a relaunch with the
    /// real gate does not present it again.
    @MainActor
    func testWhatsNewShowsOnceAndDismissPersistsAcrossLaunches() throws {
        continueAfterFailure = false
        let first = app(["FST_DEBUG_WHATS_NEW": "fresh"])
        first.launch()
        let dismiss = first.buttons["fst.whats-new.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 20), "What's New did not present at launch")
        XCTAssertTrue(first.staticTexts["Item Shop"].exists)
        SongsUITestSupport.record(first, name: "whats-new-launch")
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 10))
        first.terminate()

        let second = app(["FST_DEBUG_WHATS_NEW": "on"])
        second.launch()
        XCTAssertTrue(second.tabBars.buttons["Settings"].waitForExistence(timeout: 20))
        XCTAssertFalse(
            second.buttons["fst.whats-new.dismiss"].waitForExistence(timeout: 4),
            "Dismissed changelog presented again"
        )
    }

    /// Settings → Version → What's New "Show" replays the sheet; Close dismisses it.
    @MainActor
    func testSettingsReplaysWhatsNew() throws {
        continueAfterFailure = false
        let app = app(["FST_DEBUG_TAB": "settings"])
        app.launch()
        let row = app.buttons["fst.settings.whats-new"]
        // Settings is a LazyVStack: lower rows exist only once scrolled near.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(row, in: app, scrollingUp: true)
        row.tap()
        let close = app.buttons["fst.whats-new.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["fst.whats-new.dismiss"].exists)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
    }

    /// Operator batch 6 (6.14): the full-height What's New closes when its list is pulled
    /// down past the top and released, and Dismiss is horizontally centred.
    @MainActor
    func testWhatsNewPullDownDismisses() throws {
        continueAfterFailure = false
        let app = app(["FST_DEBUG_TAB": "settings"])
        app.launch()
        let row = app.buttons["fst.settings.whats-new"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(row, in: app, scrollingUp: true)
        row.tap()
        let dismiss = app.buttons["fst.whats-new.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(dismiss.frame.midX, window.midX, accuracy: 2, "Dismiss is centred")
        SongsUITestSupport.record(app, name: "whats-new-settings-replay")
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(
            forDuration: 0.05,
            thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        )
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 10), "Pulling down did not dismiss")
    }

    /// Service Info shows the fixture's idle worker and last publication; the First Run Guides
    /// rows follow the web order with "Score History".
    @MainActor
    func testServiceInfoAndFirstRunGuidesRender() throws {
        continueAfterFailure = false
        let app = app(["FST_DEBUG_TAB": "settings"])
        app.launch()
        let state = app.descendants(matching: .any)
            .matching(identifier: "fst.settings.service-info.state").firstMatch
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(state, in: app, scrollingUp: true)
        let idle = NSPredicate(format: "label CONTAINS %@", "Idle")
        expectation(for: idle, evaluatedWith: state)
        waitForExpectations(timeout: 15)
        let published = app.descendants(matching: .any)
            .matching(identifier: "fst.settings.service-info.last-published").firstMatch
        XCTAssertTrue(published.label.contains("2026"), published.label)
        SongsUITestSupport.record(app, name: "settings-service-info")

        let history = app.buttons["fst.settings.first-run.playerhistory"]
        SongsUITestSupport.reveal(history, in: app, scrollingUp: true)
        XCTAssertTrue(history.label.contains("Score History"), history.label)
        SongsUITestSupport.record(app, name: "settings-first-run-guides")
    }
}
