import XCTest

/// Notifications bell/sheet journeys against `tools/mock_service.py`'s
/// `/api/player/{id}/notifications` fixture (`fixture-player-1` seeds two rows,
/// both unread on first load).
///
/// Hosted (macOS) snapshot coverage for the sheet's loaded/empty/no-profile
/// states lives in `PlayerHistoryNotificationsRenderTests.swift`; this file
/// covers the bell's live unread badge, sheet presentation, seen-state after
/// dismissal, and a row opening its page in the main app (issue #75).
final class NotificationsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ])
    }

    /// The bell shows the unread count and opens the sheet; a row with a song destination
    /// dismisses the sheet and opens Song Detail on the main app's current tab (issue #75),
    /// and Back returns to the page that was showing before the sheet opened.
    @MainActor
    func testBellOpensSheetAndRowOpensSongDetailInMainApp() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        XCTAssertEqual(
            bell.label, "Notifications, 2 unread",
            "Two unseen fixture notifications must be announced with their count"
        )
        let songsRow = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(songsRow.waitForExistence(timeout: 15), "Songs is the page under the sheet")
        bell.tap()
        let sheetBar = app.navigationBars["Notifications"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 15))
        let rankRow = app.buttons["fst.notifications.row.fixture-notif-1"]
        XCTAssertTrue(rankRow.waitForExistence(timeout: 15))
        rankRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.song-detail.intensity").firstMatch
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(sheetBar.waitForNonExistence(timeout: 10), "The sheet closes before Song Detail shows")
        XCTAssertFalse(app.buttons["fst.notifications.close"].exists, "Song Detail is not inside the sheet")

        let system = app.buttons["BackButton"]
        let back = system.waitForExistence(timeout: 5) ? system : app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Song Detail sits on the tab's own stack")
        back.tap()
        XCTAssertTrue(songsRow.waitForExistence(timeout: 10), "Back returns to Songs")
        XCTAssertFalse(app.navigationBars["Notifications"].exists, "Back does not reopen the sheet")
        XCTAssertEqual(bell.label, "Notifications", "Opening a row and closing the sheet marks rows seen")
    }

    /// Opening and dismissing the sheet marks both rows seen, clearing the bell's count badge.
    @MainActor
    func testDismissingSheetClearsUnreadBadge() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        XCTAssertEqual(bell.label, "Notifications, 2 unread")
        XCTAssertEqual(
            bell.value as? String ?? "", "",
            "The system badge's count must not be read twice (label already has it)"
        )
        bell.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 15))
        app.buttons["fst.notifications.close"].tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        XCTAssertEqual(bell.label, "Notifications", "Viewing the sheet must mark rows seen")
        XCTAssertEqual(
            bell.value as? String ?? "", "",
            "A cleared badge must not leave a stale count for VoiceOver"
        )
    }
}
