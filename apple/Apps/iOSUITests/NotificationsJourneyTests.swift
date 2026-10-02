import XCTest

/// Notifications bell/sheet journeys against `tools/mock_service.py`'s
/// `/api/player/{id}/notifications` fixture (`fixture-player-1` seeds two rows,
/// both unread on first load).
///
/// Hosted (macOS) snapshot coverage for the sheet's loaded/empty/no-profile
/// states lives in `PlayerHistoryNotificationsRenderTests.swift`; this file
/// covers the bell's live unread badge, sheet presentation, seen-state after
/// dismissal, and a row's real push navigation.
final class NotificationsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ])
    }

    /// The bell shows the unread count, opens the sheet with both fixture rows, and
    /// a row with a song destination pushes to Song Detail inside the sheet.
    @MainActor
    func testBellOpensSheetAndRowNavigatesToSongDetail() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        XCTAssertEqual(
            bell.label, "Notifications, 2 unread",
            "Two unseen fixture notifications must be announced with their count"
        )
        bell.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 15))
        let rankRow = app.buttons["fst.notifications.row.fixture-notif-1"]
        XCTAssertTrue(rankRow.waitForExistence(timeout: 15))
        rankRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.song-detail.intensity").firstMatch
                .waitForExistence(timeout: 15)
        )
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
