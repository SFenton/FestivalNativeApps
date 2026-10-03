import UIKit
import XCTest

/// Fixture-backed native journey for the player-profile flow: search → view a
/// player → select them → the Statistics tab shows their own profile → deselect.
///
/// Named `ProfileStatisticsJourneyTests` (not `ProfileJourneyTests`) to avoid
/// colliding with Lane Z2's `ProfileJourneyTests.swift`, which guards the
/// wrong-account bug fix and already owns that class name.
///
/// Reuses `SongsUITestSupport`'s search/view/select/deselect helpers, which
/// Lane Z2 already updated for `ProfileSelectionSheet.swift`'s current
/// "dismiss-then-push" navigation (a search result dismisses the sheet
/// immediately and pushes `AppRoute.player` onto the presenting tab's own
/// stack; selecting a *different* profile while presented from Songs pops
/// back to the Songs tab root itself — "Selected profile changed. Returned to
/// Songs to avoid mixed scores.", `fst.songs.navigation-notice`). Confirmed
/// independently via `tools/ios_sim.py drive` while building this test before
/// the rebase that picked up Lane Z2's fix.
final class ProfileStatisticsJourneyTests: XCTestCase {
    @MainActor
    func testSearchViewSelectStatisticsThenDeselect() throws {
        continueAfterFailure = false
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:18790"
        app.launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "1"
        app.launch()

        SongsUITestSupport.viewFixturePlayer("fixture-player-1", query: "Fixture Player 1", in: app)
        let unverified = app.staticTexts["fst.player.unverified"]
        let selectButton = app.buttons["fst.player.select"]
        // A fresh publication read can briefly show the unverified notice before the
        // second, header-proven read arrives; wait for either terminal identity state.
        XCTAssertTrue(
            selectButton.waitForExistence(timeout: 15) || unverified.waitForExistence(timeout: 5),
            "Neither the Select action nor an honest unverified notice appeared"
        )
        if !selectButton.exists {
            // Publication caught up already, or a slow first read: give it one more beat.
            XCTAssertTrue(selectButton.waitForExistence(timeout: 10))
        }
        SongsUITestSupport.record(app, name: "profile-viewed-before-select")

        SongsUITestSupport.selectViewedPlayer(in: app)
        SongsUITestSupport.record(app, name: "profile-selected")

        SongsUITestSupport.openStatistics(in: app)
        XCTAssertTrue(
            SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: 15),
            "Statistics never reached the selected player's own profile: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        SongsUITestSupport.assertPlayerTitle("Fixture Player 1", in: app)
        // Issue #97: no avatar/name chip repeats the title above the content.
        XCTAssertFalse(app.staticTexts["fst.player.name"].exists)
        SongsUITestSupport.record(app, name: "statistics-selected-player")

        try SongsUITestSupport.deselectFixturePlayer(in: app)
        SongsUITestSupport.record(app, name: "profile-deselected")
        // The drawer hides Statistics again once no player is selected.
        app.buttons["fst.shell.drawer.open"].tap()
        XCTAssertFalse(app.buttons["fst.shell.drawer.statistics"].exists)
        app.buttons["fst.shell.drawer.close"].tap()
    }
}
