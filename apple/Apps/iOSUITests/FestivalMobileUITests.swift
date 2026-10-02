import XCTest
import UIKit

/// Fixture-backed native flows, never production or privileged endpoints.
///
/// Songs, Song Detail, Item Shop and CHOpt Paths journeys moved to ``SongsJourneyTests``,
/// ``SongDetailJourneyTests`` and ``ShopJourneyTests`` (Wave 3 UX-test triage); their shared
/// helpers moved to ``SongsUITestSupport``. What remains here is profile search/selection
/// chrome, artwork/background, shell navigation, the Duo pose probe and the one Solo
/// leaderboard warm-offline case, none of which this triage owned.
final class FestivalMobileUITests: XCTestCase {
    /// Start each fixture journey without a previously selected app profile.
    ///
    /// - Returns: Native app launcher that clears only the Debug selected-identity key.
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
    }

    // MARK: - Navigation and orientation

    /// A searched player is only viewed until explicitly selected, then changes Song rows.
    ///
    /// - Throws: Missing native search, contradictory score cards or an unconfirmed switch.
    @MainActor
    func testPlayerSearchViewSelectSwitchAndDeselectChangeSongsCards() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        showSelectedScoreMetadata(in: app)
        let action = app.buttons["fst.profile.open"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertTrue(action.isHittable)
        action.tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Fixture Player\n")
        let first = app.buttons["fst.profile.result.fixture-player-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["fst.profile.search-retry"].exists)
        record(app, name: "profile-player-search-results")
        first.tap()
        XCTAssertTrue(app.staticTexts["fst.profile.viewed"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["fst.profile.score-count"]
            .waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Already selected"].exists)
        app.buttons["fst.profile.select"].tap()
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        XCTAssertTrue(action.label.contains("Fixture Player 1"))
        XCTAssertTrue(song.label.contains("99,900"), "The first selected score did not paint")
        XCTAssertFalse(song.label.contains("Full combo"))
        record(app, name: "songs-player-one-available-score")

        action.tap()
        let secondSearch = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch
        XCTAssertTrue(secondSearch.waitForExistence(timeout: 10))
        secondSearch.tap()
        secondSearch.typeText("Fixture Player\n")
        let second = app.buttons["fst.profile.result.fixture-player-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 15))
        second.tap()
        XCTAssertTrue(app.buttons["fst.profile.select"].waitForExistence(timeout: 10))
        app.buttons["fst.profile.select"].tap()
        let switchPlayer = app.buttons["Switch Profile"]
        XCTAssertTrue(switchPlayer.waitForExistence(timeout: 10))
        switchPlayer.tap()
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        XCTAssertTrue(action.label.contains("Fixture Player 2"))
        XCTAssertTrue(song.label.contains("99,800"), "The switched score stayed on player one")
        XCTAssertTrue(song.label.contains("Full combo"), "Explicit FC was not announced")
        record(app, name: "songs-player-two-full-combo")

        try deselectFixturePlayer(in: app)
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        XCTAssertEqual(action.label, "Choose Profile")
        XCTAssertFalse(song.label.contains("99,800"))
        record(app, name: "songs-anonymous-after-deselect")
    }

    /// A subsequent XCTest launch cannot inherit identity from an interrupted selection.
    ///
    /// - Throws: Missing fixture accounts or a profile persisting into a fresh journey.
    @MainActor
    func testFreshFixtureLaunchDiscardsPreviouslySelectedProfile() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let original = fixtureApp()
        original.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        original.launch()
        XCTAssertTrue(original.buttons["fst.songs.row.fixture-pulse"]
            .waitForExistence(timeout: 15))
        viewFixturePlayer("fixture-player-1", query: "Fixture Player", in: original)
        XCTAssertTrue(original.buttons["fst.profile.select"].waitForExistence(timeout: 10))
        original.buttons["fst.profile.select"].tap()
        XCTAssertTrue(original.buttons["fst.profile.open"].label.contains("Fixture Player 1"))
        original.terminate()

        let next = fixtureApp()
        next.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        next.launch()
        XCTAssertTrue(next.buttons["fst.songs.row.fixture-pulse"]
            .waitForExistence(timeout: 15))
        XCTAssertEqual(next.buttons["fst.profile.open"].label, "Choose Profile")
        XCTAssertFalse(next.buttons["fst.songs.row.fixture-pulse"].label.contains("99,900"))
        XCTAssertFalse(next.descendants(matching: .any).matching(
            identifier: "fst.songs.instrument-status.fixture-pulse"
        ).firstMatch.exists)
        XCTAssertFalse(next.descendants(matching: .any)
            .matching(identifier: "fst.songs.profile-status").firstMatch.exists)
    }

    /// Access-denied search, syncing/empty previews and blocked band reads stay distinct.
    ///
    /// - Throws: A fabricated empty success or unsafe band/selected-profile request.
    @MainActor
    func testProfileSearchErrorsSyncingAndBandsStayExplicit() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"]
            .waitForExistence(timeout: 15))
        app.buttons["fst.profile.open"].tap()
        let bands = app.buttons["Bands"]
        XCTAssertTrue(bands.waitForExistence(timeout: 10))
        bands.tap()
        let bandStatus = app.staticTexts["fst.profile.bands-unavailable"]
        XCTAssertTrue(bandStatus.waitForExistence(timeout: 10))
        XCTAssertTrue(bandStatus.label.contains("Band search is paused"))
        XCTAssertFalse(app.buttons["fst.profile.select"].exists)
        app.buttons["Players"].tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("blocked")
        let denied = app.descendants(matching: .any)
            .matching(identifier: "fst.profile.search-error").firstMatch
        XCTAssertTrue(denied.waitForExistence(timeout: 15))
        XCTAssertTrue(
            denied.label.contains("HTTP 403"),
            "Search failure lost access-denied status: \(denied.label)"
        )
        XCTAssertFalse(app.staticTexts["fst.profile.search-empty"].exists)
        XCTAssertTrue(app.buttons["fst.profile.search-retry"].exists)
        record(app, name: "profile-player-search-access-denied")
        app.buttons["fst.profile.close"].tap()

        app.buttons["fst.profile.open"].tap()
        let emptySearch = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch
        XCTAssertTrue(emptySearch.waitForExistence(timeout: 10))
        emptySearch.tap()
        emptySearch.typeText("missing\n")
        XCTAssertTrue(app.staticTexts["fst.profile.search-empty"]
            .waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fst.profile.search-retry"].exists)
        record(app, name: "profile-player-search-empty-envelope")
        app.buttons["fst.profile.close"].tap()

        viewFixturePlayer("fixture-syncing", query: "Syncing", in: app)
        XCTAssertTrue(app.staticTexts["fst.profile.syncing"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fst.profile.select"].exists)
        XCTAssertTrue(app.buttons["fst.profile.preview-retry"].exists)
        record(app, name: "profile-player-syncing-not-empty")
        app.buttons["fst.profile.close"].tap()

        viewFixturePlayer("fixture-empty", query: "Empty", in: app)
        XCTAssertTrue(app.staticTexts["fst.profile.empty-status"]
            .waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["fst.profile.select"].exists)
        record(app, name: "profile-player-available-empty")
        app.buttons["fst.profile.select"].tap()
        let emptyRow = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(emptyRow.waitForExistence(timeout: 10))
        let emptyChips = chipEntries(for: "fixture-pulse", in: app)
        XCTAssertEqual(emptyChips.count, 9)
        XCTAssertEqual(Array(emptyChips.prefix(4)), [
            "Lead, no score", "Bass, no score",
            "Drums, no score", "Tap Vocals, no score",
        ])
        XCTAssertTrue(emptyChips.contains("Pro Lead, not charted"))
        XCTAssertFalse(emptyRow.label.contains("Score 0"))
        record(app, name: "songs-selected-available-empty-chips")
        try deselectFixturePlayer(in: app)

        viewFixturePlayer("fixture-denied", query: "Denied", in: app)
        let scoreError = app.descendants(matching: .any)
            .matching(identifier: "fst.profile.preview-error").firstMatch
        XCTAssertTrue(scoreError.waitForExistence(timeout: 10))
        XCTAssertTrue(scoreError.label.contains("HTTP 403"))
        XCTAssertFalse(app.buttons["fst.profile.select"].exists)
        record(app, name: "profile-player-scores-access-denied")
        app.buttons["fst.profile.close"].tap()
        XCTAssertEqual(app.buttons["fst.profile.open"].label, "Choose Profile")
    }

    /// Root sections keep a profile action, while wide sidebars show the actual name.
    ///
    /// - Throws: Hidden header/sidebar controls or selection changing the active section.
    @MainActor
    func testProfileActionsRemainReachableAcrossRootSections() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"]
            .waitForExistence(timeout: 15))
        rootControl("Settings", app: app).tap()
        try rootProfileAction(in: app).tap()
        XCTAssertTrue(app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["fst.profile.close"].tap()
        XCTAssertTrue(app.switches["fst.settings.filter-invalid-scores"].waitForExistence(timeout: 10))

        rootControl("Leaderboards", app: app).tap()
        try rootProfileAction(in: app).tap()
        XCTAssertTrue(app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["fst.profile.close"].tap()
        XCTAssertTrue(app.staticTexts["Leaderboards overview migration in progress"].exists)

        let sidebar = app.buttons["fst.profile.sidebar"]
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
            XCTAssertEqual(sidebar.label, "Choose Profile")
            sidebar.tap()
        } else {
            try rootProfileAction(in: app).tap()
        }
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Fixture Player")
        let result = app.buttons["fst.profile.result.fixture-player-1"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        XCTAssertTrue(app.buttons["fst.profile.select"].waitForExistence(timeout: 10))
        app.buttons["fst.profile.select"].tap()
        XCTAssertTrue(
            app.staticTexts["Leaderboards overview migration in progress"]
                .waitForExistence(timeout: 10),
            "Opening a profile silently left the current native root section"
        )
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(sidebar.label.contains("Fixture Player 1"))
            record(app, name: "ipad-visible-selected-sidebar-profile")
        }

        rootControl("Settings", app: app).tap()
        let action = try rootProfileAction(in: app)
        XCTAssertTrue(action.label.contains("Fixture Player 1"))
        action.tap()
        // No selected-profile container in the finder (the web's modal has none).
        XCTAssertTrue(app.buttons["fst.profile.close"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["fst.profile.selected"].exists)
        app.buttons["fst.profile.close"].tap()
        rootControl("Songs", app: app).tap()
        try deselectFixturePlayer(in: app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(sidebar.label, "Choose Profile")
        }
    }

    /// Audit the loaded iPhone page; retain iPad's unnamed full-audit failure as an open gate.
    ///
    /// - Throws: A phone manufacturer audit or named tablet visible-text contrast failure.
    @MainActor
    func testSelectedPlayerPreviewAndSongsAccessibilityEvidence() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launchArguments += [
            "-fst.songs.sortMode", "title",
            "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["fst.songs.sort"].value as? String, "Title, ascending")
        showSelectedScoreMetadata(in: app)
        viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        XCTAssertTrue(app.staticTexts["fst.profile.score-count"]
            .waitForExistence(timeout: 10))
        record(app, name: "profile-player-two-preview-audit")
        if UIDevice.current.userInterfaceIdiom == .pad {
            try assertHeaderContrast(app.staticTexts["fst.profile.viewed"], in: app)
            try assertHeaderContrast(app.staticTexts["fst.profile.score-count"], in: app)
            try assertHeaderContrast(app.buttons["fst.profile.select"], in: app)
            try assertHeaderContrast(app.buttons["fst.profile.back"], in: app)
            try assertHeaderContrast(app.buttons["fst.profile.close"], in: app)
        } else {
            try app.performAccessibilityAudit(for: .all)
        }
        app.buttons["fst.profile.select"].tap()
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        XCTAssertTrue(song.label.contains("Score 99,800"))
        XCTAssertTrue(song.label.contains("Full combo"))
        record(app, name: "songs-player-two-selected-audit")
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Split-view rows and the search field can both report a full-window AX frame.
            let detailOrigin = app.windows.firstMatch.frame.midX
            try assertHeaderContrast(
                song, in: app, leadingTextWidth: 320,
                horizontalOrigin: detailOrigin
            )
        } else {
            try app.performAccessibilityAudit(for: .all)
        }
        try deselectFixturePlayer(in: app)
    }

    /// Measure actual profile-action glyph growth when Dynamic Type becomes largest.
    ///
    /// - Throws: An unchanged rendered font size, clipped preview or unreachable action.
    @MainActor
    func testProfilePreviewTextScalesAtLargestDynamicType() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        let scoreCount = app.staticTexts["fst.profile.score-count"]
        XCTAssertTrue(scoreCount.waitForExistence(timeout: 10))
        let select = app.buttons["fst.profile.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        let normalCountHeight = scoreCount.frame.height
        let normalGlyphHeight = try brightGlyphHeight(in: select)
        record(app, name: "profile-preview-normal-type")

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        XCTAssertTrue(scoreCount.waitForExistence(timeout: 10))
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(scoreCount.frame.height, normalCountHeight * 1.2)
        let largeGlyphHeight = try brightGlyphHeight(in: select)
        XCTAssertGreaterThan(
            Double(largeGlyphHeight), Double(normalGlyphHeight) * 1.35,
            "Select Profile rendered glyphs did not scale with Dynamic Type"
        )
        XCTAssertTrue(select.isHittable)
        let back = app.buttons["fst.profile.back"]
        let window = app.windows.firstMatch.frame
        for _ in 0..<6 {
            if back.isHittable && back.frame.maxY <= window.maxY - 16 { break }
            app.swipeUp()
        }
        XCTAssertTrue(back.isHittable)
        XCTAssertLessThanOrEqual(back.frame.maxY, window.maxY - 16)
        let close = app.buttons["fst.profile.close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(close.label, "Close")
        record(app, name: "profile-preview-largest-type")
    }

    /// Audit exposed Songs and solo text, and record Settings over pure-white art.
    ///
    /// - Throws: Missing art, text or contrast on Songs, Settings or a failed score.
    @MainActor
    func testWhiteArtworkExposedTextAccessibility() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "art-white"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-white"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        try await assertWhiteArtVisible(in: app)
        let search = SongsUITestSupport.songsSearchField(in: app)
        search.tap()
        search.typeText("zzzz\n")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "No Results for")
        ).firstMatch.waitForExistence(timeout: 10))
        record(app, name: "songs-empty-white-cover")
        try app.performAccessibilityAudit(for: .all)

        rootControl("Settings", app: app).tap()
        XCTAssertTrue(app.staticTexts["App Settings"].waitForExistence(timeout: 10))
        try await assertWhiteArtVisible(in: app)
        try assertHeaderContrast(app.staticTexts["App Settings"], in: app)
        try assertHeaderContrast(app.staticTexts["Accessibility"], in: app)
        record(app, name: "settings-headers-white-cover-top")
        app.swipeUp()
        let itemShop = app.staticTexts["Item Shop"]
        XCTAssertTrue(itemShop.isHittable)
        try assertHeaderContrast(itemShop, in: app)
        record(app, name: "settings-headers-white-cover-scrolled")

        app.terminate()
        app.launch()
        let whiteRow = app.buttons["fst.songs.row.fixture-white"]
        XCTAssertTrue(whiteRow.waitForExistence(timeout: 15))
        whiteRow.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Scores unavailable:")
        ).firstMatch.waitForExistence(timeout: 10))
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        lead.tap()
        XCTAssertTrue(app.staticTexts["Leaderboard unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry"].exists)
        try await assertWhiteArtVisible(in: app)
        record(app, name: "solo-failure-white-cover")
        try app.performAccessibilityAudit(for: .all)
    }

    /// Cache one score page across a warm resume but not after process termination.
    ///
    /// - Throws: Missing solo row, false publication provenance, or cold-cache persistence.
    @MainActor
    func testHeaderlessSoloScoresRemainReadableAfterConnectionLoss() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8772"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let preview = app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).firstMatch
        XCTAssertTrue(
            preview.waitForExistence(timeout: 10),
            "Full chart fixture closed before its ten-row Detail preview"
        )
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        XCTAssertTrue(lead.isHittable, "View Full must be reachable above the score preview")
        let tabs = app.tabBars.firstMatch
        if tabs.exists {
            XCTAssertLessThan(lead.frame.maxY, tabs.frame.minY)
        }
        record(app, name: "song-detail-view-full-leading")
        lead.tap()
        collapseSidebarOnPad(app)
        let score = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-1").firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Showing live scores without publication verification"
            )
        ).firstMatch.exists)
        try app.performAccessibilityAudit(for: .all)
        try await awaitClosedFixture(port: 8772)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Offline - last seen scores (publication unverified)"
            )
        ).firstMatch.waitForExistence(timeout: 10))
        lead.tap()
        let offline = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Offline - last seen scores (publication unverified)"
            )
        ).firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10))
        XCTAssertTrue(score.waitForExistence(timeout: 10))
        XCTAssertTrue(score.isHittable, "Warm-offline score rows must remain reachable")
        record(app, name: "solo-headerless-warm-offline")
        try app.performAccessibilityAudit(for: .all)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Songs unavailable"].waitForExistence(timeout: 15))
        XCTAssertFalse(offline.exists)
        record(app, name: "solo-headerless-cold-no-cache")
    }

    /// Search and tab state must remain accessible across native section changes.
    ///
    /// - Throws: A missing search, Settings or Leaderboards destination.
    @MainActor
    func testSearchAndRootTabDestinations() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let search = SongsUITestSupport.songsSearchField(in: app)
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("zzzz")
        let noMatches = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "No Results for")
        ).firstMatch
        XCTAssertTrue(
            noMatches.waitForExistence(timeout: 10),
            "Search result labels: \(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        XCTAssertTrue(noMatches.label.contains("zzzz"))
        record(app, name: "songs-search-empty")
        search.typeText("\n")

        let settingsTab = rootControl("Settings", app: app)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertGreaterThan(try sidebarAccentPixels(rootControl("Songs", app: app)), 12)
            XCTAssertEqual(try sidebarAccentPixels(settingsTab), 0)
        }
        settingsTab.tap()
        XCTAssertTrue(
            settingsTab.isSelected,
            "Tab value: \(String(describing: settingsTab.value)); labels: \(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        XCTAssertTrue(
            app.staticTexts["App Settings"].waitForExistence(timeout: 10),
            "Settings labels: \(app.staticTexts.allElementsBoundByIndex.prefix(24).map(\.label))"
        )
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertEqual(try sidebarAccentPixels(rootControl("Songs", app: app)), 0)
            XCTAssertGreaterThan(try sidebarAccentPixels(settingsTab), 12)
        }
        record(app, name: "settings-portrait")
        rootControl("Leaderboards", app: app).tap()
        XCTAssertTrue(app.staticTexts["Leaderboards overview migration in progress"].exists)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertGreaterThan(
                try sidebarAccentPixels(rootControl("Leaderboards", app: app)), 12
            )
            XCTAssertEqual(try sidebarAccentPixels(settingsTab), 0)
        }
        record(app, name: "leaderboards-portrait")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10))
    }

    /// Additive motion preference survives a true app relaunch, then is restored.
    ///
    /// - Throws: An unavailable switch or lost preference across process lifetime.
    @MainActor
    func testAccessibilitySettingPersistsAcrossRelaunch() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        rootControl("Settings", app: app).tap()
        let motion = app.switches["fst.settings.reduce-motion"]
        XCTAssertTrue(motion.waitForExistence(timeout: 10))
        let original = try XCTUnwrap(motion.value as? String)
        XCTAssertTrue(["0", "1"].contains(original))
        motion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = original == "0" ? "1" : "0"
        let changedValue = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", changed), object: motion
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [changedValue], timeout: 5),
            .completed,
            "Motion switch frame: \(motion.frame), value: \(String(describing: motion.value))"
        )
        record(app, name: "settings-motion-override")

        app.terminate()
        app.launch()
        rootControl("Settings", app: app).tap()
        let restored = app.switches["fst.settings.reduce-motion"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.value as? String, changed)
        restored.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(restored.value as? String, original)
    }

    /// Validate actual background motion, static-art override and opaque UI pixels.
    ///
    /// - Throws: Missing original art, failed five-second transition or inert Settings.
    @MainActor
    func testArtworkAnimationAndAccessibilityOverrides() async throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launchArguments += [
            "-fst.songs.sortMode", "title",
            "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["fst.songs.sort"].value as? String, "Title, ascending")
        rootControl("Settings", app: app).tap()
        let motion = app.switches["fst.settings.reduce-motion"]
        let disableArt = app.switches["fst.settings.disable-artwork-animation"]
        let opaque = app.switches["fst.settings.less-transparency"]
        reveal(motion, in: app, scrollingUp: true)
        let originalMotion = try XCTUnwrap(motion.value as? String)
        setSwitch(motion, to: "0")
        reveal(disableArt, in: app, scrollingUp: true)
        let originalArt = try XCTUnwrap(disableArt.value as? String)
        setSwitch(disableArt, to: "0")
        reveal(opaque, in: app, scrollingUp: true)
        let originalOpaque = try XCTUnwrap(opaque.value as? String)
        setSwitch(opaque, to: "0")
        rootControl("Songs", app: app).tap()

        let brand: [UInt8] = [26, 8, 48]
        let base: [UInt8] = Array(repeating: brand, count: 256).flatMap { $0 }
        var painted = base
        for _ in 0..<20 {
            painted = try backgroundSignature(app)
            if pixelDistance(painted, base) > 1_500 { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertGreaterThan(pixelDistance(painted, base), 1_500)
        let moving = try backgroundSignature(app)
        record(app, name: "songs-artwork-motion-start")
        try await Task.sleep(for: .seconds(7))
        let transitioned = try backgroundSignature(app)
        record(app, name: "songs-artwork-motion-next")
        XCTAssertGreaterThan(
            pixelDistance(moving, transitioned), 200,
            "The five-second cover rotation did not change the empty page region"
        )

        rootControl("Settings", app: app).tap()
        reveal(disableArt, in: app, scrollingUp: true)
        setSwitch(disableArt, to: "1")
        rootControl("Songs", app: app).tap()
        try await Task.sleep(for: .seconds(1))
        let staticFirst = try backgroundSignature(app)
        XCTAssertGreaterThan(pixelDistance(staticFirst, base), 1_500)
        record(app, name: "songs-artwork-animation-disabled")
        try await Task.sleep(for: .seconds(6))
        XCTAssertLessThanOrEqual(
            pixelDistance(staticFirst, try backgroundSignature(app)), 80,
            "Disabling artwork animation did not hold the same cover"
        )

        rootControl("Settings", app: app).tap()
        reveal(motion, in: app, scrollingUp: true)
        setSwitch(motion, to: "1")
        reveal(disableArt, in: app, scrollingUp: true)
        setSwitch(disableArt, to: "0")
        rootControl("Songs", app: app).tap()
        try await Task.sleep(for: .seconds(1))
        let reducedFirst = try backgroundSignature(app)
        XCTAssertGreaterThan(pixelDistance(reducedFirst, base), 1_500)
        try await Task.sleep(for: .seconds(6))
        XCTAssertLessThanOrEqual(
            pixelDistance(reducedFirst, try backgroundSignature(app)), 80,
            "Reduce Motion failed to stop the artwork carousel"
        )
        record(app, name: "songs-artwork-reduced-motion")

        rootControl("Settings", app: app).tap()
        reveal(opaque, in: app, scrollingUp: true)
        setSwitch(opaque, to: "1")
        rootControl("Songs", app: app).tap()
        record(app, name: "songs-artwork-opaque-override")
        XCTAssertLessThanOrEqual(
            pixelDistance(try backgroundSignature(app), base), 100,
            "Reduce Transparency failed to remove the image and dark overlay"
        )

        rootControl("Settings", app: app).tap()
        reveal(opaque, in: app, scrollingUp: true)
        setSwitch(opaque, to: originalOpaque)
        reveal(disableArt, in: app, scrollingUp: false)
        setSwitch(disableArt, to: originalArt)
        reveal(motion, in: app, scrollingUp: false)
        setSwitch(motion, to: originalMotion)
    }

    /// Unavailable covers leave catalogue controls usable and never synthesize art.
    ///
    /// - Throws: An unexpected image, missing song action or rapid retry state.
    @MainActor
    func testUnavailableArtworkKeepsOpaqueCatalogueUsable() async throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "art-error"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launchArguments += [
            "-fst.songs.sortMode", "title",
            "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["fst.songs.sort"].value as? String, "Title, ascending")
        let brand: [UInt8] = [26, 8, 48]
        let base: [UInt8] = Array(repeating: brand, count: 256).flatMap { $0 }
        XCTAssertLessThanOrEqual(pixelDistance(try backgroundSignature(app), base), 100)
        try await Task.sleep(for: .seconds(6))
        XCTAssertLessThanOrEqual(pixelDistance(try backgroundSignature(app), base), 100)
        XCTAssertTrue(song.isHittable)
        record(app, name: "songs-all-artwork-unavailable")
    }

    /// A bad middle cover cannot strand an otherwise animated native catalogue.
    ///
    /// - Throws: Lost rows or a carousel with no second visible art state.
    @MainActor
    func testBadCoverStillAllowsTheNextCarouselImage() async throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "art-skip"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-missing"].waitForExistence(timeout: 15))
        let brand: [UInt8] = [26, 8, 48]
        let base: [UInt8] = Array(repeating: brand, count: 256).flatMap { $0 }
        var first = base
        for _ in 0..<20 {
            first = try backgroundSignature(app)
            if pixelDistance(first, base) > 1_500 { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertGreaterThan(pixelDistance(first, base), 1_500)
        try await Task.sleep(for: .seconds(7))
        XCTAssertGreaterThan(
            pixelDistance(first, try backgroundSignature(app)), 200,
            "A missing cover stopped all future artwork transitions"
        )
        record(app, name: "songs-artwork-404-skipped")
    }

    /// Probe Duo outer-window aspect and reachable controls; camera cutouts need pose tests.
    ///
    /// - Throws: A nonrotating simulator window or unreachable fixture control.
    @MainActor
    func testDuoOuterFourRotations() throws {
        continueAfterFailure = false
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))

        let orientations: [(UIDeviceOrientation, String, Bool)] = [
            (.portrait, "portrait", false),
            (.landscapeLeft, "landscape-left", true),
            (.portraitUpsideDown, "portrait-upside-down", false),
            (.landscapeRight, "landscape-right", true),
        ]
        for (orientation, name, isLandscape) in orientations {
            XCUIDevice.shared.orientation = orientation
            let aspect = NSPredicate(block: { _, _ in
                let frame = app.windows.firstMatch.frame
                return isLandscape
                    ? frame.width > frame.height : frame.height > frame.width
            })
            let geometry = XCTNSPredicateExpectation(
                predicate: aspect, object: app
            )
            let settled = XCTWaiter.wait(for: [geometry], timeout: 5)
            record(app, name: "duo-outer-\(name)")
            let frame = app.windows.firstMatch.frame
            XCTAssertEqual(
                settled, .completed,
                "\(name) never reached the expected aspect; window: \(frame)"
            )
            if isLandscape {
                XCTAssertGreaterThan(frame.width, frame.height, name)
            } else {
                XCTAssertGreaterThan(frame.height, frame.width, name)
            }
            XCTAssertTrue(row.isHittable, "Song row obscured in \(name)")
            XCTAssertTrue(
                app.buttons["fst.songs.instrument-filter"].isHittable,
                "Filter action obscured in \(name)"
            )
        }
    }

    // MARK: - Evidence

    /// Select a visible header action even when an inactive tab retains its toolbar.
    ///
    /// - Parameter app: Fixture app on any root navigation section.
    /// - Returns: The current root's hittable profile action.
    /// - Throws: An obscured or absent action.
    @MainActor
    private func rootProfileAction(in app: XCUIApplication) throws -> XCUIElement {
        try XCTUnwrap(
            app.buttons.matching(identifier: "fst.profile.open")
                .allElementsBoundByIndex.first(where: \.isHittable),
            "No root profile action is hittable in the current section"
        )
    }

    /// Choose the source's icons-off variant for tests of numeric score metadata.
    ///
    /// - Parameter app: Launched fixture app before selecting an account.
    @MainActor
    private func showSelectedScoreMetadata(in app: XCUIApplication) {
        rootControl("Settings", app: app).tap()
        let icons = app.switches["fst.settings.show-instrument-icons"]
        XCTAssertTrue(icons.waitForExistence(timeout: 10))
        XCTAssertTrue(icons.isEnabled)
        reveal(icons, in: app, scrollingUp: false)
        setSwitch(icons, to: "0")
        rootControl("Songs", app: app).tap()
    }

    /// Read each status as an exact instrument/meaning pair, not a row substring.
    ///
    /// - Parameters:
    ///   - songId: Synthetic catalogue key whose chip group is currently shown.
    ///   - app: Foreground Songs fixture after the player score settles.
    /// - Returns: Source-ordered spoken entries with no Pro Drums/Drums ambiguity.
    @MainActor
    private func chipEntries(for songId: String, in app: XCUIApplication) -> [String] {
        let chips = app.descendants(matching: .any).matching(
            identifier: "fst.songs.instrument-status.\(songId)"
        ).firstMatch
        XCTAssertTrue(chips.waitForExistence(timeout: 10))
        let entries = chips.label.components(separatedBy: "; ")
        XCTAssertFalse(entries.contains(where: \.isEmpty))
        return entries
    }

    /// Address one score field without matching similarly named metadata or chart chips.
    ///
    /// - Parameters:
    ///   - key: Source-ordered field kind, such as score or intensity.
    ///   - songId: Synthetic catalogue key, defaulting to the paired player fixture.
    ///   - app: Foreground fixture app showing the selected Songs destination.
    /// - Returns: Exact visible per-song accessibility element.
    @MainActor
    private func metadataElement(
        _ key: String, songId: String = "fixture-pulse", in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any).matching(
            identifier: "fst.songs.metadata.\(key).\(songId)"
        ).firstMatch
    }

    /// Reach one synthetic player from a fresh profile sheet without selecting it.
    ///
    /// - Parameters:
    ///   - accountId: Fixture search result key.
    ///   - query: Source-like player name or state to type.
    ///   - app: Already launched native fixture app on Songs.
    @MainActor
    private func viewFixturePlayer(
        _ accountId: String, query: String, in app: XCUIApplication
    ) {
        let action = app.buttons["fst.profile.open"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        let search = app.searchFields.matching(NSPredicate(format: "placeholderValue == %@", "Find Player")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText(query + "\n")
        let result = app.buttons["fst.profile.result.\(accountId)"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        for _ in 0..<5 {
            if result.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(result.isHittable, "Player result stayed outside the visible sheet")
        result.tap()
        let viewed = app.staticTexts["fst.profile.viewed"]
        XCTAssertTrue(
            viewed.waitForExistence(timeout: 10),
            "Viewed player never replaced search results: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(14).map(\.label))"
        )
    }

    /// Remove only the app's selected identity through its own confirmation action.
    ///
    /// - Parameter app: Foreground Songs screen with a selected player.
    /// - Throws: Missing accessible confirmation or stale selection.
    @MainActor
    private func deselectFixturePlayer(in app: XCUIApplication) throws {
        // The profile sheet has no selected-profile summary; deselect from Statistics.
        try SongsUITestSupport.deselectFixturePlayer(in: app)
    }

    /// Open Shop from the native Songs overflow while keeping three phone tabs.
    ///
    /// - Parameter app: Fixture app on the root Songs destination.
    @MainActor
    private func openItemShop(in app: XCUIApplication) {
        let shop = app.buttons["fst.songs.shop"]
        if !shop.isHittable {
            let more = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "more")
            ).firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 10))
            more.tap()
        }
        XCTAssertTrue(
            shop.waitForExistence(timeout: 10),
            "Shop action missing; toolbar controls: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(16).map(\.label))"
        )
        shop.tap()
    }

    /// Keep fixture Shop status independent of another test's saved Hide setting.
    ///
    /// - Parameter app: Running synthetic Songs app with a reachable Settings tab.
    /// - Returns: Original Hide Shop switch value to restore after the journey.
    /// - Throws: An unreadable native Settings switch.
    @MainActor
    private func showFixtureShop(in app: XCUIApplication) throws -> String {
        rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        reveal(hidden, in: app, scrollingUp: true)
        let original = try XCTUnwrap(hidden.value as? String)
        setSwitch(hidden, to: "0")
        rootControl("Songs", app: app).tap()
        return original
    }

    /// Restore only the fixture Shop visibility preference after observing rows.
    ///
    /// - Parameters:
    ///   - original: Switch value captured before this synthetic journey.
    ///   - app: Running app with the native Settings tab.
    @MainActor
    private func restoreFixtureShopVisibility(
        _ original: String, in app: XCUIApplication
    ) {
        rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        reveal(hidden, in: app, scrollingUp: true)
        setSwitch(hidden, to: original)
    }

    /// Open the native Filter through platform toolbar overflow.
    ///
    /// - Parameter app: Fixture app with a selected Songs profile or a saved filter.
    /// - Returns: The accessible action that launched the presented sheet.
    @MainActor
    private func openFilterSheet(in app: XCUIApplication) -> XCUIElement {
        let filter = app.buttons["fst.songs.filter"]
        if !filter.isHittable {
            let more = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "more")
            ).firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 10))
            more.tap()
        }
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        XCTAssertTrue(app.buttons["fst.songs.filter.done"].waitForExistence(timeout: 10))
        return filter
    }

    /// Open and scroll to the source's public Shop toggles.
    ///
    /// - Parameter app: Fixture app with a selected Songs profile or a saved filter.
    @MainActor
    private func openSongsFilter(in app: XCUIApplication) {
        _ = openFilterSheet(in: app)
        _ = revealFilterOption(app.switches["fst.songs.filter.in-shop"], in: app)
    }

    /// Scroll the native Filter Form until a score control clears its pinned actions.
    ///
    /// - Parameters:
    ///   - element: Named global switch, chart disclosure or chart switch.
    ///   - app: Active fixture app with the full-height native Filter Form.
    /// - Returns: A visibly hittable control above the Cancel/Apply footer.
    @MainActor
    private func revealFilterOption(
        _ element: XCUIElement, in app: XCUIApplication
    ) -> XCUIElement {
        let form = app.descendants(matching: .any).matching(
            identifier: "fst.songs.filter.form"
        ).firstMatch
        let footer = app.buttons["fst.songs.filter.done"]
        XCTAssertTrue(
            form.exists && footer.exists,
            "Missing Filter Form or pinned actions: "
                + "\(app.collectionViews.allElementsBoundByIndex.prefix(4).map(\.identifier))"
        )
        for _ in 0..<12 {
            if element.isHittable && element.frame.maxY <= SongsUITestSupport.sheetVisibleBottom(in: app) { break }
            form.swipeUp()
        }
        XCTAssertTrue(
            element.isHittable && element.frame.maxY <= SongsUITestSupport.sheetVisibleBottom(in: app),
            "\(element.identifier) is not reachable above the Filter footer"
        )
        return element
    }

    /// Reach a short disclosure or Song row above the native tab with small drags.
    ///
    /// - Parameters:
    ///   - element: List action that may still be lazily offscreen.
    ///   - list: The loaded Songs List, not the app's outer navigation view.
    ///   - app: Fixture application supplying real visible chrome.
    ///   - failureName: Private diagnostic screenshot identifier if unreachable.
    ///   - bottomMargin: Desired gap above the tab; zero permits an edge-to-edge row.
    @MainActor
    private func revealSongsControlAboveTab(
        _ element: XCUIElement, in list: XCUIElement,
        app: XCUIApplication, failureName: String,
        bottomMargin: CGFloat = 8
    ) {
        let tabs = app.tabBars.firstMatch
        let visibleBottom = (tabs.exists
            ? tabs.frame.minY : app.windows.firstMatch.frame.maxY) - bottomMargin
        for _ in 0..<12 {
            if element.isHittable && element.frame.maxY <= visibleBottom { break }
            let above = element.exists && element.frame.maxY < list.frame.minY
            let startY: CGFloat = above ? 0.42 : 0.70
            let endY: CGFloat = above ? 0.54 : 0.58
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                .press(
                    forDuration: 0.1,
                    thenDragTo: list.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: endY)
                    )
                )
        }
        if !element.isHittable || element.frame.maxY > visibleBottom {
            record(app, name: failureName)
        }
        XCTAssertTrue(element.isHittable, "\(element.identifier) stayed outside Songs")
        XCTAssertLessThanOrEqual(element.frame.maxY, visibleBottom)
    }

    /// Scroll the modal Form until Reset is above the always-visible action footer.
    ///
    /// - Parameter app: Foreground Songs Sort sheet on phone or tablet.
    /// - Returns: Hittable Reset button within the visible scroll viewport.
    @MainActor
    private func revealSortReset(in app: XCUIApplication) -> XCUIElement {
        revealSheetReset(
            "fst.songs.sort.reset", cancelId: "fst.songs.sort.done",
            sheetName: "Sort", in: app
        )
    }

    /// Keep Filter Reset entirely visible above its pinned footer at large text.
    ///
    /// - Parameter app: Native Filter sheet showing score and Shop toggles.
    /// - Returns: A fully visible, hittable Reset action.
    @MainActor
    private func revealFilterReset(in app: XCUIApplication) -> XCUIElement {
        revealFilterOption(app.buttons["fst.songs.filter.reset"], in: app)
    }

    /// Scroll the sheet's own Form instead of skipping Reset with root gestures.
    ///
    /// - Parameters:
    ///   - identifier: Saved-sort or Shop-filter Reset action.
    ///   - cancelId: Pinned footer control defining visible content height.
    ///   - sheetName: Named native sheet for a precise failure message.
    ///   - app: Foreground fixture app presenting that sheet.
    /// - Returns: Reset once completely above the footer.
    @MainActor
    private func revealSheetReset(
        _ identifier: String, cancelId: String,
        sheetName: String, in app: XCUIApplication
    ) -> XCUIElement {
        let reset = app.buttons[identifier]
        let table = app.tables.containing(.button, identifier: identifier)
            .firstMatch
        let list = table.exists ? table : app.tables.firstMatch.exists
            ? app.tables.firstMatch : app.collectionViews.containing(
                .button, identifier: identifier
            ).firstMatch
        let footer = app.buttons[cancelId]
        XCTAssertTrue(list.exists && footer.exists)
        for _ in 0..<8 {
            if reset.isHittable && reset.frame.maxY <= SongsUITestSupport.sheetVisibleBottom(in: app) { break }
            list.swipeUp()
        }
        XCTAssertTrue(
            reset.isHittable && reset.frame.maxY <= SongsUITestSupport.sheetVisibleBottom(in: app),
            "Reset is hidden by the \(sheetName) action footer"
        )
        return reset
    }

    /// Move the public-Shop option above the sheet footer before selecting it.
    ///
    /// - Parameter app: Foreground native Songs Sort sheet.
    /// - Returns: A hittable, validated Item Shop sort row.
    @MainActor
    private func revealShopSort(in app: XCUIApplication) -> XCUIElement {
        let choice = app.buttons.matching(
            identifier: "fst.songs.sort.mode"
        ).matching(NSPredicate(format: "label == %@", "Item Shop")).firstMatch
        let table = app.tables.containing(
            .button, identifier: "fst.songs.sort.reset"
        ).firstMatch
        let form = table.exists ? table : app.collectionViews.containing(
            .button, identifier: "fst.songs.sort.reset"
        ).firstMatch
        let footer = app.buttons["fst.songs.sort.done"]
        XCTAssertTrue(form.exists && footer.exists)
        for _ in 0..<8 {
            if choice.isHittable && choice.frame.maxY <= SongsUITestSupport.sheetVisibleBottom(in: app) { break }
            form.swipeUp()
        }
        XCTAssertTrue(
            choice.isHittable && choice.frame.maxY <= SongsUITestSupport.sheetVisibleBottom(in: app),
            "Item Shop sort option is hidden by the sheet footer"
        )
        return choice
    }

    /// Expose the full detail pane before auditing iPad's split-view destination.
    ///
    /// - Parameter app: Foreground native Songs detail or leaderboard screen.
    @MainActor
    private func collapseSidebarOnPad(_ app: XCUIApplication) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let toggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "sidebar")
        ).firstMatch
        XCTAssertTrue(toggle.exists, "Native sidebar control is missing")
        toggle.tap()
    }

    /// Scroll the native chart, not its fixed pager, until a large score is visible.
    ///
    /// - Parameters:
    ///   - accountID: Synthetic player on the currently loaded chart page.
    ///   - fullCombo: True only for a response-proven full-combo row.
    ///   - app: Foreground chart at AccessibilityXXXL.
    /// - Returns: The visible, explicitly labeled accuracy element.
    @MainActor
    private func revealSoloAccuracy(
        _ accountID: String, fullCombo: Bool = false, app: XCUIApplication
    ) -> XCUIElement {
        let accuracy = app.staticTexts
            .matching(identifier: "fst.score.accuracy.\(accountID)")
            .matching(NSPredicate(
                format: "label == %@",
                fullCombo ? "Full combo, accuracy 98%" : "Accuracy 98%"
            ))
            .firstMatch
        let table = app.tables.firstMatch
        let list = table.exists ? table : app.collectionViews.firstMatch
        XCTAssertTrue(list.exists, "Native score list is missing")
        for _ in 0..<8 {
            if accuracy.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(
            accuracy.isHittable,
            "Score \(accountID) is not visible after scrolling its native list"
        )
        return accuracy
    }

    /// Detect a score whose final digit wraps onto its own accessibility line.
    ///
    /// - Parameters:
    ///   - accountID: Synthetic player on the current chart page.
    ///   - rank: Visible fixture rank on this score row.
    ///   - score: Expected, formatted fixture score for the same player.
    ///   - app: Foreground chart at AccessibilityXXXL.
    @MainActor
    private func assertWholeSoloScore(
        _ accountID: String, rank: Int, score: Int, app: XCUIApplication
    ) {
        let row = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.\(accountID)").firstMatch
        XCTAssertTrue(row.exists)
        let rankText = row.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "#\(rank)")).firstMatch
        let scoreText = row.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", score.formatted())).firstMatch
        XCTAssertTrue(rankText.exists)
        XCTAssertTrue(scoreText.exists)
        XCTAssertLessThanOrEqual(
            scoreText.frame.height, rankText.frame.height * 1.25,
            "A numeric score must remain on one line at the largest native text size"
        )
    }

    /// Select native sidebar buttons on iPad, system tab buttons on iPhone.
    ///
    /// - Parameters:
    ///   - name: Root section's visible label.
    ///   - app: Launched Festival fixture app.
    /// - Returns: Accessible native destination control for the current idiom.
    @MainActor
    private func rootControl(_ name: String, app: XCUIApplication) -> XCUIElement {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return app.descendants(matching: .any)
                .matching(identifier: "fst.nav.\(name.lowercased())").firstMatch
        }
        return app.tabBars.buttons[name]
    }

    /// Scroll a large-type error until Retry is both tappable and above native navigation.
    ///
    /// - Parameter app: Foreground error scenario on a phone or tablet simulator.
    /// - Throws: Retry remains outside the usable viewport after eight deliberate swipes.
    @MainActor
    private func revealFailureAction(_ app: XCUIApplication) throws {
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        let tabs = app.tabBars.firstMatch
        let errorScroll = app.scrollViews.containing(.button, identifier: "Retry").firstMatch
        for _ in 0..<8 {
            let limit = tabs.exists
                ? tabs.frame.minY : app.windows.firstMatch.frame.maxY - 16
            if retry.isHittable && retry.frame.maxY <= limit { break }
            if errorScroll.exists && errorScroll.isHittable {
                errorScroll.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        let limit = tabs.exists
            ? tabs.frame.minY : app.windows.firstMatch.frame.maxY - 16
        XCTAssertTrue(
            retry.isHittable,
            "Retry \(retry.frame) is not reachable; window \(app.windows.firstMatch.frame), "
                + "scroll \(errorScroll.exists ? errorScroll.frame : .zero), "
                + "tabs \(tabs.exists ? tabs.frame : .zero)"
        )
        XCTAssertLessThanOrEqual(
            retry.frame.maxY, limit,
            "Retry falls under native navigation at accessibility text size"
        )
    }

    /// Count accent-blue pixels in a sidebar button's leading, vertically centered band.
    ///
    /// - Parameter control: One visible, opaque iPad navigation row.
    /// - Returns: Visible selected-marker pixels, independent of accessibility traits.
    /// - Throws: Missing or unreadable screenshot pixels.
    @MainActor
    private func sidebarAccentPixels(_ control: XCUIElement) throws -> Int {
        let image = try XCTUnwrap(control.screenshot().image.cgImage)
        let strip = try XCTUnwrap(image.cropping(to: CGRect(
            x: 0, y: image.height / 3,
            width: min(60, image.width / 5), height: image.height / 3
        )))
        let bytes = try bitmapPixels(strip)
        var count = 0
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            let red = Int(bytes[pixel])
            let green = Int(bytes[pixel + 1])
            let blue = Int(bytes[pixel + 2])
            if green > 65 && blue > 140 && green > red + 30
                && blue > green + 40 {
                count += 1
            }
        }
        return count
    }

    /// Require a real gold FC outline or graded green fill in rendered score pixels.
    ///
    /// - Parameters:
    ///   - element: Fully visible, separately accessible native accuracy pill.
    ///   - fullCombo: Whether the validated score explicitly reports a full combo.
    /// - Throws: An absent or visually incorrect accent on the named badge.
    @MainActor
    private func assertScoreAccuracyAccent(
        _ element: XCUIElement, fullCombo: Bool
    ) throws {
        XCTAssertTrue(element.isHittable)
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let pixels = try bitmapPixels(image)
        var gold = 0
        var graded = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            if red >= 220 && green >= 170 && blue <= 65 {
                gold += 1
            }
            if green >= 50 && green >= red + 25 && green >= blue + 5 {
                graded += 1
            }
        }
        if fullCombo {
            XCTAssertGreaterThan(gold, 40, "FC outline is not visibly gold")
            XCTAssertEqual(graded, 0, "FC badge shows a graded non-FC fill")
        } else {
            XCTAssertEqual(gold, 0, "Non-FC accuracy is misleadingly gold")
            XCTAssertGreaterThan(graded, 80, "Non-FC accuracy lacks graded fill")
        }
        let inset = max(8, min(image.width, image.height) / 12)
        let content = try XCTUnwrap(image.cropping(to: CGRect(
            x: inset, y: inset,
            width: image.width - inset * 2,
            height: image.height - inset * 2
        )))
        let contrast = try measuredTextContrast(in: bitmapPixels(content))
        XCTAssertGreaterThan(
            contrast.brightPixels, 80,
            "\(element.label) has no visible accuracy text"
        )
        XCTAssertGreaterThanOrEqual(
            contrast.ratio, 4.5,
            "\(element.label) text contrast \(contrast.ratio):1 is below 4.5:1"
        )
    }

    /// Keep equal-digit scores in one column despite the visible FC prefix.
    ///
    /// - Parameters:
    ///   - firstScore: Fully visible non-FC numeric score.
    ///   - secondScore: Equal-width full-combo numeric score.
    ///   - firstBadge: Graded non-FC accuracy pill.
    ///   - secondBadge: Gold full-combo accuracy pill.
    @MainActor
    private func assertAlignedScoreColumn(
        firstScore: XCUIElement, secondScore: XCUIElement,
        firstBadge: XCUIElement, secondBadge: XCUIElement
    ) {
        XCTAssertTrue(firstScore.isHittable && secondScore.isHittable)
        assertAlignedScoreEnds(firstScore, secondScore)
        XCTAssertLessThanOrEqual(
            abs(firstBadge.frame.minX - secondBadge.frame.minX), 1,
            "FC and non-FC badges must occupy the same column"
        )
    }

    /// Keep equal-width numeric scores aligned even when accuracy is absent.
    ///
    /// - Parameters:
    ///   - first: Source-proven score on the first visible chart row.
    ///   - second: Score of the same digit length with or without a badge.
    @MainActor
    private func assertAlignedScoreEnds(_ first: XCUIElement, _ second: XCUIElement) {
        XCTAssertTrue(first.exists && second.exists)
        XCTAssertLessThanOrEqual(
            abs(first.frame.maxX - second.frame.maxX), 1,
            "An FC or missing accuracy must not shift the numeric score column"
        )
    }

    /// Check actual rendered text contrast against its median surface.
    ///
    /// - Parameters:
    ///   - element: A completely visible text action or header.
    ///   - app: Foreground app providing the composited screenshot.
    ///   - leadingTextWidth: For wide rows, limit the crop to its leading text.
    ///   - horizontalOrigin: A visible detail-pane anchor when iPadOS reports full-window bounds.
    /// - Throws: A missing screenshot or insufficient 4.5:1 rendered contrast.
    @MainActor
    private func assertHeaderContrast(
        _ element: XCUIElement, in app: XCUIApplication,
        leadingTextWidth: CGFloat? = nil, horizontalOrigin: CGFloat? = nil
    ) throws {
        XCTAssertTrue(element.isHittable)
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        let scaleX = Double(image.width) / window.width
        let scaleY = Double(image.height) / window.height
        let width = min(frame.width, leadingTextWidth ?? frame.width)
        if let horizontalOrigin {
            XCTAssertGreaterThanOrEqual(horizontalOrigin, window.minX)
            XCTAssertLessThanOrEqual(horizontalOrigin + width, window.maxX)
        }
        let cropRect = CGRect(
            x: ((horizontalOrigin ?? frame.minX) - window.minX) * scaleX,
            y: (frame.minY - window.minY) * scaleY,
            width: width * scaleX,
            height: frame.height * scaleY
        ).integral
        let crop = try XCTUnwrap(image.cropping(to: cropRect))
        let measured = try measuredTextContrast(in: bitmapPixels(crop))
        XCTAssertGreaterThan(
            measured.brightPixels, 100,
            "\(element.label) has no readable text pixels in its rendered section"
        )
        XCTAssertGreaterThanOrEqual(
            measured.ratio, 4.5,
            "\(element.label) lacks readable rendered contrast "
                + "(background \(measured.background), text \(measured.text), "
                + "element \(frame), window \(window), crop \(cropRect))"
        )
    }

    /// Measure actual text and background luminance from one composited crop.
    ///
    /// - Parameter bytes: Opaque RGBA screenshot pixels of the intended text surface.
    /// - Returns: Contrast ratio, median surface, bright glyphs and their count.
    /// - Throws: A screenshot without any readable pixels.
    @MainActor
    private func measuredTextContrast(
        in bytes: [UInt8]
    ) throws -> (ratio: Double, background: Double, text: Double, brightPixels: Int) {
        let luminances = stride(from: 0, to: bytes.count, by: 4).map { offset in
            (0..<3).map { channel -> Double in
                let value = Double(bytes[offset + channel]) / 255
                return value <= 0.04045
                    ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
        }.map { channels in
            0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }.sorted()
        _ = try XCTUnwrap(luminances.first)
        let background = luminances[luminances.count / 2]
        let text = luminances[luminances.count * 99 / 100]
        return (
            (text + 0.05) / (background + 0.05),
            background, text,
            luminances.filter { $0 > background * 3 }.count
        )
    }

    /// Decode one native screenshot into opaque RGBA bytes for visual assertions.
    ///
    /// - Parameter image: Screenshot or cropped screenshot on the current simulator.
    /// - Returns: Row-major red, green, blue and alpha bytes.
    /// - Throws: Unavailable bitmap context.
    @MainActor
    private func bitmapPixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(
                x: 0, y: 0, width: image.width, height: image.height
            ))
        }
        return bytes
    }

    /// Measure real rendered text height instead of assuming a SwiftUI font modifier scales.
    ///
    /// - Parameter element: A visible opaque Form button with bright text.
    /// - Returns: Vertical extent of its near-white glyph pixels.
    /// - Throws: A missing element screenshot or inaccessible text pixels.
    @MainActor
    private func brightGlyphHeight(in element: XCUIElement) throws -> Int {
        let image = try XCTUnwrap(element.screenshot().image.cgImage)
        let pixels = try bitmapPixels(image)
        var first: Int?
        var last: Int?
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4
                if pixels[offset] > 200 && pixels[offset + 1] > 200
                    && pixels[offset + 2] > 200 {
                    if first == nil { first = y }
                    last = y
                    break
                }
            }
        }
        let initial = try XCTUnwrap(first)
        let final = try XCTUnwrap(last)
        return final - initial + 1
    }

    /// Sample an interior 16-by-16 grid from one screenshot, avoiding native chrome.
    ///
    /// - Parameter app: Visible native Songs destination.
    /// - Returns: 768 sRGB bytes from visible background behind the song list.
    /// - Throws: Missing screenshot backing pixels.
    @MainActor
    private func backgroundSignature(_ app: XCUIApplication) throws -> [UInt8] {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let left = image.width * 56 / 100
        let top = image.height * 52 / 100
        let width = image.width * 95 / 100 - left
        let height = image.height * 83 / 100 - top
        let crop = try XCTUnwrap(image.cropping(to: CGRect(
            x: left, y: top, width: width, height: height
        )))
        let bytes = try bitmapPixels(crop)
        var signature: [UInt8] = []
        for row in 0..<16 {
            for column in 0..<16 {
                let x = (column * crop.width + crop.width / 2) / 16
                let y = (row * crop.height + crop.height / 2) / 16
                let index = (y * crop.width + x) * 4
                signature.append(contentsOf: bytes[index..<(index + 3)])
            }
        }
        return signature
    }

    /// Prove original synthetic Shop stripes were actually painted before loss.
    ///
    /// - Parameter app: Loaded Shop page on a compact phone or regular tablet.
    /// - Throws: Artwork still absent after visible rows or an invalid screenshot crop.
    @MainActor
    private func assertShopArtworkVisible(in app: XCUIApplication) async throws {
        let tablet = UIDevice.current.userInterfaceIdiom == .pad
        let item = app.descendants(matching: .any).matching(
            identifier: tablet
                ? "fst.shop.external.fixture-pulse"
                : "fst.shop.song.fixture-pulse"
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        let frame = item.frame
        let window = app.windows.firstMatch.frame
        var spread = 0
        var sample = [Int]()
        var cropSize = CGSize.zero
        for _ in 0..<30 {
            let image = try XCTUnwrap(app.screenshot().image.cgImage)
            let scaleX = Double(image.width) / window.width
            let scaleY = Double(image.height) / window.height
            let originX = frame.minX + (tablet ? 12 : 4)
            let originY = tablet ? frame.minY + 12 : frame.midY - 8
            let sampleWidth = tablet ? frame.width * 0.6 : min(44, frame.width / 4)
            let crop = try XCTUnwrap(image.cropping(to: CGRect(
                x: (originX - window.minX) * scaleX,
                y: (originY - window.minY) * scaleY,
                width: sampleWidth * scaleX, height: 16 * scaleY
            ).integral))
            let pixels = try bitmapPixels(crop)
            cropSize = CGSize(width: crop.width, height: crop.height)
            let greens = (0..<16).map { column -> Int in
                let x = (column * crop.width + crop.width / 2) / 16
                let offset = ((crop.height / 2) * crop.width + x) * 4
                return Int(pixels[offset + 1])
            }
            sample = greens
            spread = (greens.max() ?? 0) - (greens.min() ?? 0)
            if spread > 15 { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        record(app, name: "shop-art-after-sampling")
        let healthURL = URL(string: "http://127.0.0.1:8773/__fixture__/health")!
        let listener: String
        do {
            let (_, response) = try await URLSession.shared.data(from: healthURL)
            listener = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
        } catch {
            listener = error.localizedDescription
        }
        XCTFail(
            "Original Shop artwork never painted; green spread \(spread), "
                + "samples \(sample), crop \(cropSize), item \(frame), "
                + "window \(window), listener \(listener)"
        )
    }

    private struct ShopStopConfirmation: Decodable {
        let stopping: Bool
    }

    /// Only an explicitly signaled local fixture may move publication seven to eight.
    private struct FixturePublicationAdvance: Decodable {
        let publicationId: Int
    }

    /// Numeric-only diagnostic for a dedicated, locally owned rollover fixture.
    private struct FixturePublicationJoinReads: Decodable {
        let shop: Int?
        let player: Int?
        let failedSongs: Int?
    }

    /// Advance only an exact fixture port after the native before-state is visible.
    ///
    /// - Parameter port: Runner-owned command-rollover listener on loopback.
    /// - Throws: Missing local endpoint, invalid publication or non-200 result.
    @MainActor
    private func advanceFixturePublication(port: Int) async throws {
        let url = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(port)/__fixture__/advance-publication")
        )
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(
            try JSONDecoder().decode(FixturePublicationAdvance.self, from: data).publicationId, 8
        )
    }

    /// Read sanitized request generations without inspecting profile or Shop content.
    ///
    /// - Parameter port: Dedicated pinned Join fixture for this simulator family.
    /// - Returns: New Shop/player successes and an explicit new Songs failure.
    /// - Throws: Invalid JSON, nonlocal endpoint or unexpected HTTP response.
    @MainActor
    private func fixturePublicationJoinReads(
        port: Int
    ) async throws -> FixturePublicationJoinReads {
        let url = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(port)/__fixture__/publication-join-reads")
        )
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode(FixturePublicationJoinReads.self, from: data)
    }

    /// Trigger only the fixture's one-shot loss after visible Shop artwork proof.
    ///
    /// - Throws: An unarmed listener, unexpected HTTP response or invalid acknowledgement.
    @MainActor
    private func disconnectVisibleShopFixture() async throws {
        let url = try XCTUnwrap(
            URL(string: "http://127.0.0.1:8773/__fixture__/shop-visible")
        )
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(try JSONDecoder().decode(ShopStopConfirmation.self, from: data).stopping)
    }

    /// Require visible neutral-white fixture pixels after native 0.7 dimming.
    ///
    /// - Parameter app: Foreground page with one fixture-white artwork path.
    /// - Throws: A screenshot without at least 32 uncovered white-art grid cells.
    @MainActor
    private func assertWhiteArtVisible(in app: XCUIApplication) async throws {
        var uncoveredCells = 0
        for _ in 0..<25 {
            let colors = try backgroundSignature(app)
            uncoveredCells = stride(from: 0, to: colors.count, by: 3).filter { offset in
                let red = Int(colors[offset])
                let green = Int(colors[offset + 1])
                let blue = Int(colors[offset + 2])
                return (55...95).contains(red) && abs(red - green) <= 10
                    && abs(red - blue) <= 10
            }.count
            if uncoveredCells > 32 { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertGreaterThan(
            uncoveredCells, 32,
            "Accessibility audit did not display a dimmed pure-white original cover"
        )
    }

    /// Compare equally sized sRGB signatures without including the device clock.
    ///
    /// - Parameters:
    ///   - first: Initial pixel.
    ///   - second: Later pixel.
    /// - Returns: Total channel distance between the two colors.
    private func pixelDistance(_ first: [UInt8], _ second: [UInt8]) -> Int {
        zip(first, second).reduce(0) { total, channels in
            total + abs(Int(channels.0) - Int(channels.1))
        }
    }

    /// Wait for an approved one-shot fixture to stop listening before offline actions.
    ///
    /// - Parameter port: Loopback one-shot fixture (8771-8775).
    /// - Throws: Unexpected transport failure or listener that never closes.
    @MainActor
    private func awaitClosedFixture(port: Int) async throws {
        let health = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(port)/__fixture__/health")
        )
        var disconnected = false
        for _ in 0..<40 {
            do {
                _ = try await URLSession.shared.data(
                    for: URLRequest(url: health, timeoutInterval: 1)
                )
            } catch let error as URLError where error.code == .cannotConnectToHost {
                disconnected = true
                break
            } catch let error as URLError where
                error.code == .networkConnectionLost || error.code == .timedOut {
                try await Task.sleep(for: .milliseconds(100))
                continue
            } catch {
                XCTFail("Unexpected local fixture failure: \(error.localizedDescription)")
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(disconnected, "One-shot headerless fixture did not close its listener")
    }

    private struct FixtureScoreQuery: Decodable {
        let last: Request?

        struct Request: Decodable {
            let top: Int
            let offset: Int
            let leeway: Double?
        }
    }

    /// Inspect only loopback fixture query numbers, never a service account.
    ///
    /// - Parameter fullOnly: Exclude ten-row Detail previews when auditing the full chart.
    /// - Returns: The most recent validated synthetic query in the selected channel.
    /// - Throws: A missing fixture listener or invalid diagnostic response.
    @MainActor
    private func latestFixtureScoreQuery(
        fullOnly: Bool = false
    ) async throws -> FixtureScoreQuery.Request {
        let name = fullOnly ? "last-full-score-query" : "last-score-query"
        let url = URL(string: "http://127.0.0.1:8765/__fixture__/\(name)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONDecoder().decode(FixtureScoreQuery.self, from: data).last)
    }

    /// Scroll the lazily created native Settings Form to a visible control.
    ///
    /// - Parameters:
    ///   - element: Settings action to reveal before tapping or asserting.
    ///   - app: Fixture app with the Settings Form visible.
    ///   - scrollingUp: Preferred direction, reversed if Settings retained its scroll position.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool) {
        for direction in [scrollingUp, !scrollingUp] {
            for _ in 0..<8 {
                if element.isHittable { return }
                if direction {
                    app.swipeUp()
                } else {
                    app.swipeDown()
                }
            }
        }
        XCTAssertTrue(
            element.isHittable,
            "Settings control not reachable: \(element.identifier); visible controls: "
                + "\(app.buttons.allElementsBoundByIndex.prefix(16).map(\.label))"
        )
    }

    /// Toggle the trailing native switch only when its current value differs.
    ///
    /// - Parameters:
    ///   - element: Settings switch, not the surrounding static-text label.
    ///   - value: Expected accessibility value, `0` or `1`.
    @MainActor
    private func setSwitch(_ element: XCUIElement, to value: String) {
        if element.value as? String != value {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", value), object: element
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [changed], timeout: 3), .completed,
                "Settings switch \(element.identifier) did not settle after one tap; "
                    + "current value \(element.value as? String ?? "unavailable")"
            )
        }
        XCTAssertEqual(
            element.value as? String, value,
            "Settings control \(element.identifier), frame \(element.frame), "
                + "hittable \(element.isHittable)"
        )
    }

    /// Attach only the app's current display to the Xcode result bundle.
    ///
    /// - Parameters:
    ///   - app: Launched Festival fixture app.
    ///   - name: Named page/state/orientation for the evidence matrix.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        XCTContext.runActivity(named: name) { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }
}
