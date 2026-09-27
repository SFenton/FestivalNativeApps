import XCTest
import UIKit

/// Fixture-backed native flows, never production or privileged endpoints.
final class FestivalMobileUITests: XCTestCase {
    /// Start each fixture journey without a previously selected app profile.
    ///
    /// - Returns: Native app launcher that clears only the Debug selected-identity key.
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FST_UI_TEST_CLEAR_PROFILE"] = "1"
        app.launchEnvironment["FST_UI_TEST_RESET_SONG_CARDS"] = "1"
        return app
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
        let search = app.textFields["fst.profile.search"]
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
        let secondSearch = app.textFields["fst.profile.search"]
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

    /// Source-default chips follow two players, Drums data and saved Settings.
    ///
    /// - Throws: A stale profile, first-chart-only lookup or hidden metadata that leaks through.
    @MainActor
    func testSelectedInstrumentChipsFollowProfileAndSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        viewFixturePlayer("fixture-player-1", query: "Fixture Player", in: app)
        app.buttons["fst.profile.select"].tap()
        let first = chipEntries(for: "fixture-pulse", in: app)
        XCTAssertEqual(first.count, 9)
        XCTAssertEqual(Array(first.prefix(4)), [
            "Lead, scored", "Bass, no score",
            "Drums, no score", "Tap Vocals, no score",
        ])
        XCTAssertTrue(first.contains("Pro Lead, not charted"))
        XCTAssertFalse(row.label.contains("Score 99,900"))
        record(app, name: "songs-player-one-default-instrument-chips")

        viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        app.buttons["fst.profile.select"].tap()
        let switchPlayer = app.buttons["Switch Profile"]
        XCTAssertTrue(switchPlayer.waitForExistence(timeout: 10))
        switchPlayer.tap()
        let second = chipEntries(for: "fixture-pulse", in: app)
        XCTAssertEqual(second.count, 9)
        XCTAssertEqual(Array(second.prefix(4)), [
            "Lead, full combo", "Bass, no score",
            "Drums, scored", "Tap Vocals, no score",
        ])
        XCTAssertFalse(row.label.contains("Score 99,800"))
        record(app, name: "songs-player-two-drums-scored-in-chips")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        }

        rootControl("Settings", app: app).tap()
        let icons = app.switches["fst.settings.show-instrument-icons"]
        XCTAssertTrue(icons.waitForExistence(timeout: 10))
        XCTAssertTrue(icons.isEnabled)
        XCTAssertEqual(icons.value as? String, "1")
        let lead = app.switches["fst.settings.instrument.Solo_Guitar"]
        reveal(lead, in: app, scrollingUp: true)
        setSwitch(lead, to: "0")
        rootControl("Songs", app: app).tap()
        let hidden = chipEntries(for: "fixture-pulse", in: app)
        XCTAssertEqual(hidden.count, 8)
        XCTAssertFalse(hidden.contains(where: { $0.hasPrefix("Lead, ") }))
        XCTAssertTrue(hidden.contains("Drums, scored"))
        record(app, name: "songs-hidden-lead-keeps-scored-drums-chip")

        rootControl("Settings", app: app).tap()
        reveal(lead, in: app, scrollingUp: true)
        setSwitch(lead, to: "1")
        rootControl("Songs", app: app).tap()
        let filter = app.buttons["fst.songs.instrument-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        XCTAssertTrue(app.buttons["Drums"].waitForExistence(timeout: 10))
        app.buttons["Drums"].tap()
        XCTAssertTrue(row.label.contains("Score 88,800"))
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.instrument-status.fixture-pulse"
        ).firstMatch.exists)
        record(app, name: "songs-filtered-drums-real-score-instead-of-chips")

        filter.tap()
        XCTAssertTrue(app.buttons["All instruments"].waitForExistence(timeout: 10))
        app.buttons["All instruments"].tap()
        XCTAssertTrue(chipEntries(for: "fixture-pulse", in: app).contains("Drums, scored"))
        rootControl("Settings", app: app).tap()
        reveal(icons, in: app, scrollingUp: false)
        setSwitch(icons, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.label.contains("Score 99,800"))
        XCTAssertTrue(row.label.contains("Full combo"))
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.instrument-status.fixture-pulse"
        ).firstMatch.exists)
        record(app, name: "songs-icons-off-restores-profile-score")

        rootControl("Settings", app: app).tap()
        reveal(icons, in: app, scrollingUp: false)
        setSwitch(icons, to: "1")
        let invalid = app.switches["Filter Invalid Scores"]
        reveal(invalid, in: app, scrollingUp: false)
        setSwitch(invalid, to: "1")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.label.contains("Filtered player score display is not available yet"))
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.instrument-status.fixture-pulse"
        ).firstMatch.exists)
        record(app, name: "songs-invalid-filter-does-not-fabricate-status-chips")

        rootControl("Settings", app: app).tap()
        reveal(invalid, in: app, scrollingUp: false)
        setSwitch(invalid, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(chipEntries(for: "fixture-pulse", in: app).contains("Drums, scored"))
        try deselectFixturePlayer(in: app)
        let clearedChips = app.descendants(matching: .any).matching(
            identifier: "fst.songs.instrument-status.fixture-pulse"
        ).firstMatch
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: clearedChips
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [cleared], timeout: 10), .completed,
            "A deselected profile left the previous player's chip states visible"
        )
    }

    /// A selected card grows when actual largest Dynamic Type reaches native layout.
    ///
    /// - Throws: A missing icon state or accessibility-size row clipped at its old height.
    @MainActor
    func testSelectedInstrumentChipsRemainReachableAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        app.buttons["fst.profile.select"].tap()
        XCTAssertTrue(chipEntries(for: "fixture-pulse", in: app).contains("Drums, scored"))
        let normalHeight = row.frame.height
        record(app, name: "songs-default-chips-normal-type")

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_CLEAR_PROFILE")
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let enlarged = app.buttons["fst.songs.row.fixture-pulse"]
        let list = app.collectionViews["fst.songs.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if enlarged.exists && enlarged.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(enlarged.waitForExistence(timeout: 10))
        XCTAssertTrue(enlarged.isHittable, "The selected Pulse row could not be scrolled into view")
        let scoreLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Drums, scored"),
            object: enlarged
        )
        XCTAssertEqual(XCTWaiter.wait(for: [scoreLoaded], timeout: 15), .completed)
        let loadedChips = chipEntries(for: "fixture-pulse", in: app)
        XCTAssertEqual(loadedChips.count, 9)
        XCTAssertTrue(loadedChips.contains("Lead, full combo"))
        XCTAssertTrue(loadedChips.contains("Drums, scored"))
        XCTAssertGreaterThan(enlarged.frame.height, normalHeight * 1.2)
        let chipGroup = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.instrument-status.fixture-pulse").firstMatch
        let visibleTop = list.frame.minY + 8
        let tabBar = app.tabBars.firstMatch
        let visibleBottom = (tabBar.exists
            ? tabBar.frame.minY : app.windows.firstMatch.frame.maxY) - 8
        for _ in 0..<6 {
            if !chipGroup.exists {
                list.swipeUp()
                continue
            }
            let frame = chipGroup.frame
            if frame.minY >= visibleTop && frame.maxY <= visibleBottom { break }
            if frame.maxY > visibleBottom {
                list.swipeUp()
            } else {
                list.swipeDown()
            }
        }
        XCTAssertTrue(chipGroup.isHittable, "Visible chip status stayed behind system navigation")
        XCTAssertGreaterThanOrEqual(chipGroup.frame.minY, visibleTop)
        XCTAssertLessThanOrEqual(chipGroup.frame.maxY, visibleBottom)
        record(app, name: "songs-default-chips-accessibility-xxxlarge")
        try deselectFixturePlayer(in: app)
    }

    /// The chip-only AX layout must not replace anonymous row navigation.
    ///
    /// - Throws: A clipped anonymous catalogue row or offscreen Detail destination.
    @MainActor
    func testAnonymousSongsRowAtLargestTextRetainsDetailNavigation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let list = app.collectionViews["fst.songs.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        for _ in 0..<6 {
            if orbit.exists && orbit.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(orbit.isHittable)
        XCTAssertTrue(orbit.label.contains("Fixture Orbit"))
        XCTAssertTrue(orbit.label.contains("Synthetic Quartet"))
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.instrument-status.fixture-orbit"
        ).firstMatch.exists)
        record(app, name: "songs-anonymous-row-largest-text")
        orbit.tap()
        XCTAssertTrue(app.staticTexts["Fixture Orbit"].waitForExistence(timeout: 10))
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

    /// Anonymous users can restore the filtered Songs meter without selecting a profile.
    ///
    /// - Throws: A disabled Intensity switch or a meter that ignores its stored state.
    @MainActor
    func testAnonymousIntensityCanBeHiddenAndRestored() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        rootControl("Settings", app: app).tap()
        let intensity = app.switches["fst.settings.metadata.intensity"]
        reveal(intensity, in: app, scrollingUp: true)
        XCTAssertTrue(intensity.isEnabled)
        let original = try XCTUnwrap(intensity.value as? String)
        setSwitch(intensity, to: "1")

        rootControl("Songs", app: app).tap()
        let filter = app.buttons["fst.songs.instrument-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        XCTAssertTrue(app.buttons["Lead"].waitForExistence(timeout: 10))
        app.buttons["Lead"].tap()
        let meter = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.difficulty-meter").firstMatch
        XCTAssertTrue(meter.waitForExistence(timeout: 10))

        rootControl("Settings", app: app).tap()
        reveal(intensity, in: app, scrollingUp: true)
        setSwitch(intensity, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertFalse(meter.exists)
        rootControl("Settings", app: app).tap()
        reveal(intensity, in: app, scrollingUp: true)
        XCTAssertTrue(intensity.isEnabled)
        setSwitch(intensity, to: "1")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(meter.waitForExistence(timeout: 10))
        rootControl("Settings", app: app).tap()
        reveal(intensity, in: app, scrollingUp: true)
        setSwitch(intensity, to: original)
    }

    /// Applied Settings and cold launch must affect one chosen player's real score card.
    ///
    /// - Throws: Stale anonymous rows, ignored switches, or disk-cached scores.
    @MainActor
    func testSelectedPlayerMetadataAndColdRelaunchRespectSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        showSelectedScoreMetadata(in: app)
        viewFixturePlayer("fixture-player-1", query: "Fixture Player", in: app)
        let select = app.buttons["fst.profile.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        rootControl("Settings", app: app).tap()
        let score = app.switches["fst.settings.metadata.score"]
        reveal(score, in: app, scrollingUp: true)
        XCTAssertTrue(score.isEnabled)
        let originalScore = try XCTUnwrap(score.value as? String)
        setSwitch(score, to: "1")
        let percentage = app.switches["fst.settings.metadata.percentage"]
        reveal(percentage, in: app, scrollingUp: true)
        let originalPercentage = try XCTUnwrap(percentage.value as? String)
        setSwitch(percentage, to: "1")
        let lead = app.switches["fst.settings.instrument.Solo_Guitar"]
        reveal(lead, in: app, scrollingUp: false)
        let originalLead = try XCTUnwrap(lead.value as? String)
        setSwitch(lead, to: "1")
        let filtering = app.switches["Filter Invalid Scores"]
        reveal(filtering, in: app, scrollingUp: false)
        let originalFilter = try XCTUnwrap(filtering.value as? String)
        setSwitch(filtering, to: "0")

        rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Score 99,900"))
        XCTAssertTrue(row.label.contains("Accuracy 97.9 percent"))
        record(app, name: "songs-player-score-and-percentage-enabled")

        rootControl("Settings", app: app).tap()
        reveal(score, in: app, scrollingUp: true)
        setSwitch(score, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertFalse(row.label.contains("Score 99,900"))
        XCTAssertTrue(row.label.contains("Accuracy 97.9 percent"))
        record(app, name: "songs-profile-score-hidden-percentage-retained")

        rootControl("Settings", app: app).tap()
        reveal(score, in: app, scrollingUp: true)
        setSwitch(score, to: "1")
        reveal(percentage, in: app, scrollingUp: true)
        setSwitch(percentage, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.label.contains("Score 99,900"))
        XCTAssertFalse(row.label.contains("Accuracy 97.9 percent"))

        rootControl("Settings", app: app).tap()
        reveal(percentage, in: app, scrollingUp: true)
        setSwitch(percentage, to: "1")
        reveal(lead, in: app, scrollingUp: false)
        setSwitch(lead, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.label.contains("No Bass score"))
        XCTAssertTrue(
            app.buttons["fst.songs.row.fixture-orbit"].label
                .contains("Bass is not charted"),
            "A hidden Lead score reappeared on an uncharted Bass song"
        )
        record(app, name: "songs-hidden-lead-reveals-bass-status")

        rootControl("Settings", app: app).tap()
        reveal(lead, in: app, scrollingUp: false)
        setSwitch(lead, to: "1")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.label.contains("Score 99,900"))

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_CLEAR_PROFILE")
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launch()
        let restored = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(restored.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fst.profile.open"].label.contains("Fixture Player 1"))
        let restoredScore = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Score 99,900"),
            object: restored
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restoredScore], timeout: 15), .completed)
        record(app, name: "songs-player-identity-restored-scores-refetched")

        rootControl("Settings", app: app).tap()
        reveal(score, in: app, scrollingUp: true)
        setSwitch(score, to: originalScore)
        reveal(percentage, in: app, scrollingUp: true)
        setSwitch(percentage, to: originalPercentage)
        reveal(lead, in: app, scrollingUp: false)
        setSwitch(lead, to: originalLead)
        reveal(filtering, in: app, scrollingUp: false)
        setSwitch(filtering, to: originalFilter)
        rootControl("Songs", app: app).tap()
        try deselectFixturePlayer(in: app)
    }

    /// An icons-off card must paint separate, ordered pills with one charted meter.
    ///
    /// - Throws: Incorrect score alignment, missing FC or Settings changes that do not reflow.
    @MainActor
    func testSelectedSongScorePillsFollowSettingsAndFilteredDrums() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        showSelectedScoreMetadata(in: app)
        viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        app.buttons["fst.profile.select"].tap()
        let score = metadataElement("score", in: app)
        let accuracy = metadataElement("accuracy", in: app)
        let percentile = metadataElement("percentile", in: app)
        let stars = metadataElement("stars", in: app)
        let season = metadataElement("season", in: app)
        let intensity = metadataElement("intensity", in: app)
        let difficulty = metadataElement("difficulty", in: app)
        for field in [score, accuracy, percentile, stars, season, intensity, difficulty] {
            XCTAssertTrue(field.waitForExistence(timeout: 10), field.identifier)
        }
        XCTAssertEqual(score.label, "Score 99,800")
        XCTAssertEqual(accuracy.label, "Full combo, accuracy 97.9 percent")
        XCTAssertEqual(percentile.label, "Top 10%")
        XCTAssertEqual(stars.label, "5 stars")
        XCTAssertEqual(season.label, "Current season 9")
        XCTAssertEqual(intensity.label, "Song intensity 3 of 7")
        XCTAssertEqual(difficulty.label, "Expert difficulty")
        let spoken = [
            score.label, accuracy.label, percentile.label,
            stars.label, season.label, intensity.label, difficulty.label,
        ]
        var offset = row.label.startIndex
        for field in spoken {
            guard let range = row.label.range(of: field, range: offset..<row.label.endIndex)
            else {
                XCTFail("Source-order metadata was not spoken in order: \(row.label)")
                return
            }
            offset = range.upperBound
        }
        let trailingEdge = score.frame.maxX
        XCTAssertLessThanOrEqual(abs(trailingEdge - difficulty.frame.maxX), 2)
        let shop = app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-badge.fixture-pulse"
        ).firstMatch
        XCTAssertTrue(shop.waitForExistence(timeout: 10))
        XCTAssertFalse(shop.frame.intersects(score.frame))
        try assertScoreAccuracyAccent(accuracy, fullCombo: true)
        record(app, name: "songs-fc-metadata-ordered-and-trailing")

        rootControl("Settings", app: app).tap()
        let scoreSwitch = app.switches["fst.settings.metadata.score"]
        reveal(scoreSwitch, in: app, scrollingUp: true)
        setSwitch(scoreSwitch, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertFalse(score.exists)
        XCTAssertTrue(accuracy.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(abs(trailingEdge - accuracy.frame.maxX), 2)
        record(app, name: "songs-hidden-score-promotes-fc-primary")

        rootControl("Settings", app: app).tap()
        let percentage = app.switches["fst.settings.metadata.percentage"]
        reveal(percentage, in: app, scrollingUp: true)
        setSwitch(percentage, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertEqual(accuracy.label, "Full combo")
        XCTAssertFalse(row.label.contains("97.9"))
        record(app, name: "songs-percentage-hidden-keeps-fc-only")

        rootControl("Settings", app: app).tap()
        reveal(scoreSwitch, in: app, scrollingUp: true)
        setSwitch(scoreSwitch, to: "1")
        reveal(percentage, in: app, scrollingUp: true)
        setSwitch(percentage, to: "1")
        rootControl("Songs", app: app).tap()
        let filter = app.buttons["fst.songs.instrument-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        XCTAssertTrue(app.buttons["Drums"].waitForExistence(timeout: 10))
        app.buttons["Drums"].tap()
        XCTAssertEqual(score.label, "Score 88,800")
        XCTAssertEqual(accuracy.label, "Accuracy 90.5 percent")
        XCTAssertEqual(percentile.label, "Top 100%")
        XCTAssertEqual(stars.label, "4 stars")
        XCTAssertEqual(intensity.label, "Song intensity 5 of 7")
        XCTAssertEqual(difficulty.label, "Expert difficulty")
        XCTAssertEqual(row.label.components(separatedBy: "Song intensity").count - 1, 1)
        try assertScoreAccuracyAccent(accuracy, fullCombo: false)
        record(app, name: "songs-filtered-drums-graded-accuracy-and-one-meter")

        filter.tap()
        XCTAssertTrue(app.buttons["All instruments"].waitForExistence(timeout: 10))
        app.buttons["All instruments"].tap()
        rootControl("Settings", app: app).tap()
        let lead = app.switches["fst.settings.instrument.Solo_Guitar"]
        let bass = app.switches["fst.settings.instrument.Solo_Bass"]
        reveal(lead, in: app, scrollingUp: false)
        setSwitch(lead, to: "0")
        reveal(bass, in: app, scrollingUp: false)
        setSwitch(bass, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertEqual(score.label, "Score 88,800")
        let chart = metadataElement("chart", in: app)
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertEqual(chart.label, "Drums chart")
        XCTAssertTrue(row.label.contains("Drums chart"))
        record(app, name: "songs-hidden-lead-and-bass-names-visible-drums-score")
        rootControl("Settings", app: app).tap()
        reveal(lead, in: app, scrollingUp: false)
        setSwitch(lead, to: "1")
        reveal(bass, in: app, scrollingUp: false)
        setSwitch(bass, to: "1")
        rootControl("Songs", app: app).tap()
        try deselectFixturePlayer(in: app)
    }

    /// A coherent long-title, seven-digit and Shop case must reflow without a new API.
    ///
    /// - Throws: An unavailable edge profile, clipped score/pill or stalled iPad sidebar.
    @MainActor
    func testLongScoreMetadataAndShopRemainReachableAcrossWidths() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8776"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-marathon"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        showSelectedScoreMetadata(in: app)
        viewFixturePlayer("fixture-edge", query: "Fixture Edge", in: app)
        XCTAssertTrue(app.buttons["fst.profile.select"].waitForExistence(timeout: 10))
        app.buttons["fst.profile.select"].tap()
        let score = metadataElement("score", songId: "fixture-marathon", in: app)
        let accuracy = metadataElement("accuracy", songId: "fixture-marathon", in: app)
        let difficulty = metadataElement("difficulty", songId: "fixture-marathon", in: app)
        XCTAssertTrue(score.waitForExistence(timeout: 15))
        XCTAssertTrue(accuracy.waitForExistence(timeout: 10))
        XCTAssertTrue(difficulty.waitForExistence(timeout: 10))
        XCTAssertEqual(score.label, "Score 1,234,567")
        XCTAssertEqual(accuracy.label, "Full combo, accuracy 97.9 percent")
        XCTAssertTrue(row.label.contains(
            "A Very Long Synthetic Festival Anthem with an Extended Encore"
        ))
        XCTAssertTrue(row.label.contains(
            "Synthetic Quartet Featuring an Extended Ensemble"
        ))
        XCTAssertTrue(row.label.contains("2026 · 6:06"))
        let lastPlayed = metadataElement(
            "lastPlayed", songId: "fixture-marathon", in: app
        )
        XCTAssertTrue(lastPlayed.waitForExistence(timeout: 10))
        XCTAssertTrue(lastPlayed.label.contains("Last played"))
        XCTAssertTrue(lastPlayed.label.contains("2026"))
        let fieldLabels = row.label
        let difficultyIndex = try XCTUnwrap(
            fieldLabels.range(of: difficulty.label)
        ).lowerBound
        let lastPlayedIndex = try XCTUnwrap(
            fieldLabels.range(of: lastPlayed.label)
        ).lowerBound
        XCTAssertLessThan(difficultyIndex, lastPlayedIndex)
        XCTAssertFalse(difficulty.frame.intersects(lastPlayed.frame))
        XCTAssertLessThanOrEqual(abs(score.frame.maxX - lastPlayed.frame.maxX), 2)
        let shop = app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-badge.fixture-marathon"
        ).firstMatch
        XCTAssertTrue(shop.waitForExistence(timeout: 10))
        XCTAssertFalse(shop.frame.intersects(score.frame))
        XCTAssertTrue(row.isHittable)
        record(app, name: "songs-long-title-seven-digit-shop-score")

        if UIDevice.current.userInterfaceIdiom == .pad {
            collapseSidebarOnPad(app)
            XCTAssertTrue(score.waitForExistence(timeout: 10))
            XCTAssertEqual(score.label, "Score 1,234,567")
            XCTAssertLessThanOrEqual(abs(score.frame.maxX - lastPlayed.frame.maxX), 2)
            record(app, name: "ipad-long-metadata-sidebar-hidden")
            let restore = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "sidebar")
            ).firstMatch
            XCTAssertTrue(restore.waitForExistence(timeout: 10))
            restore.tap()
            XCTAssertTrue(shop.isHittable)
        }

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_CLEAR_PROFILE")
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let list = app.collectionViews["fst.songs.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let restored = app.buttons["fst.songs.row.fixture-marathon"]
        for _ in 0..<5 {
            if restored.exists && restored.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(restored.isHittable)
        let scoreLoaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Score 1,234,567"),
            object: restored
        )
        XCTAssertEqual(XCTWaiter.wait(for: [scoreLoaded], timeout: 15), .completed)
        XCTAssertTrue(restored.label.contains("Full combo, accuracy 97.9 percent"))
        XCTAssertTrue(restored.label.contains("Song intensity 3 of 7"))
        XCTAssertTrue(restored.label.contains("Last played"))
        XCTAssertTrue(restored.label.contains("2026 · 6:06"))
        let tabs = app.tabBars.firstMatch
        let visibleBottom = (tabs.exists
            ? tabs.frame.minY : app.windows.firstMatch.frame.maxY) - 8
        for _ in 0..<6 {
            if shop.exists && shop.frame.maxY <= visibleBottom { break }
            list.swipeUp()
        }
        XCTAssertTrue(shop.isHittable)
        XCTAssertLessThanOrEqual(shop.frame.maxY, visibleBottom)
        XCTAssertTrue(lastPlayed.isHittable)
        let axStars = metadataElement(
            "stars", songId: "fixture-marathon", in: app
        )
        XCTAssertTrue(axStars.isHittable)
        XCTAssertEqual(axStars.label, "5 stars")
        XCTAssertFalse(shop.frame.intersects(lastPlayed.frame))
        XCTAssertLessThanOrEqual(
            abs(shop.frame.maxX - lastPlayed.frame.maxX), 2,
            "Wrapped Last Played must share the Shop badge's trailing card edge"
        )
        record(app, name: "songs-long-metadata-accessibility-xxxlarge")
        try deselectFixturePlayer(in: app)
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
        let search = app.textFields["fst.profile.search"]
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
        let emptySearch = app.textFields["fst.profile.search"]
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
        XCTAssertTrue(app.textFields["fst.profile.search"].waitForExistence(timeout: 10))
        app.buttons["fst.profile.close"].tap()
        XCTAssertTrue(app.switches["Filter Invalid Scores"].waitForExistence(timeout: 10))

        rootControl("Leaderboards", app: app).tap()
        try rootProfileAction(in: app).tap()
        XCTAssertTrue(app.textFields["fst.profile.search"].waitForExistence(timeout: 10))
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
        let search = app.textFields["fst.profile.search"]
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
        let selectedName = app.staticTexts["fst.profile.selected"]
        XCTAssertTrue(selectedName.waitForExistence(timeout: 10))
        XCTAssertEqual(selectedName.label, "Fixture Player 1")
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
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
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

    /// A public Shop feed opens without adding a fourth compact tab.
    ///
    /// - Throws: Missing real fixture offers, unsafe outbound action or broken Song Detail.
    @MainActor
    func testPublicShopOffersAndSongDetailNavigation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        openItemShop(in: app)
        let leaving = app.descendants(matching: .any).matching(
            identifier: "fst.shop.badge.leaving.fixture-orbit"
        ).firstMatch
        let fresh = app.descendants(matching: .any).matching(
            identifier: "fst.shop.badge.new.fixture-pulse"
        ).firstMatch
        XCTAssertTrue(leaving.waitForExistence(timeout: 15))
        XCTAssertTrue(fresh.exists)
        let official = app.descendants(matching: .any).matching(
            identifier: "fst.shop.external.fixture-pulse"
        ).firstMatch
        XCTAssertTrue(official.exists)
        XCTAssertTrue(official.label.contains("Official Item Shop"))
        if UIDevice.current.userInterfaceIdiom == .pad {
            let toggle = app.buttons["fst.shop.view-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            let current = toggle.label
            toggle.tap()
            XCTAssertNotEqual(toggle.label, current)
            toggle.tap()
            XCTAssertEqual(toggle.label, current)
        } else {
            XCTAssertEqual(app.tabBars.buttons.count, 3)
        }
        record(app, name: "shop-populated-offers")
        try app.performAccessibilityAudit(for: .all)
        let detail = app.buttons["fst.shop.song.fixture-pulse"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        detail.tap()
        XCTAssertTrue(app.staticTexts["Intensity"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["fst.song-detail.paths"].exists)
    }

    /// Empty Shop and a real service failure must never look like the same state.
    ///
    /// - Throws: Hidden empty text, silent HTTP error or unreadable Retry action.
    @MainActor
    func testPublicShopEmptyAndErrorStayDistinct() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "empty"
        app.launch()
        openItemShop(in: app)
        XCTAssertTrue(app.staticTexts["No songs in the Item Shop"]
            .waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Item Shop unavailable"].exists)
        record(app, name: "shop-genuinely-empty")
        try app.performAccessibilityAudit(for: .all)

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        app.launch()
        openItemShop(in: app)
        XCTAssertTrue(app.staticTexts["Item Shop unavailable"]
            .waitForExistence(timeout: 15))
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.isHittable)
        record(app, name: "shop-service-error")
        try app.performAccessibilityAudit(for: .all)
    }

    /// Show validated Shop offers after an actual listener loss, never after cold launch.
    ///
    /// - Throws: False freshness, hidden warm rows or disk-like cold-cache persistence.
    @MainActor
    func testHeaderlessShopOffersRemainReadableAfterConnectionLoss() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8773"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        openItemShop(in: app)
        collapseSidebarOnPad(app)
        let offer = app.descendants(matching: .any).matching(
            identifier: "fst.shop.external.fixture-pulse"
        ).firstMatch
        XCTAssertTrue(offer.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Showing live shop without publication verification"
            )
        ).firstMatch.exists)
        record(app, name: "shop-art-before-disconnect")
        try await assertShopArtworkVisible(in: app)
        try await disconnectVisibleShopFixture()
        try await awaitClosedFixture(port: 8773)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        let back = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.exists)
        back.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        openItemShop(in: app)
        let offline = app.descendants(matching: .any)
            .matching(identifier: "fst.shop.offline").firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10))
        XCTAssertEqual(offline.label, "Offline - last seen shop (publication unverified)")
        XCTAssertTrue(offer.waitForExistence(timeout: 10))
        try await assertShopArtworkVisible(in: app)
        record(app, name: "shop-headerless-warm-offline")
        try app.performAccessibilityAudit(for: .all)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Songs unavailable"].waitForExistence(timeout: 15))
        openItemShop(in: app)
        XCTAssertTrue(app.staticTexts["Item Shop unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(offline.exists)
        XCTAssertFalse(offer.exists)
        record(app, name: "shop-headerless-cold-no-cache")
    }

    /// Settings hide/highlight switches change Shop controls without losing saved values.
    ///
    /// - Throws: Badges ignoring the setting, a hidden Shop action or lost preference.
    @MainActor
    func testPublicShopSettingsHideAndHighlightPropagation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        reveal(hidden, in: app, scrollingUp: true)
        let originalHidden = try XCTUnwrap(hidden.value as? String)
        setSwitch(hidden, to: "0")
        let highlights = app.switches["fst.settings.shop-highlights"]
        reveal(highlights, in: app, scrollingUp: true)
        let originalHighlights = try XCTUnwrap(highlights.value as? String)
        setSwitch(highlights, to: "1")

        rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        openItemShop(in: app)
        let fresh = app.descendants(matching: .any).matching(
            identifier: "fst.shop.badge.new.fixture-pulse"
        ).firstMatch
        XCTAssertTrue(fresh.waitForExistence(timeout: 15))
        rootControl("Settings", app: app).tap()
        reveal(highlights, in: app, scrollingUp: true)
        setSwitch(highlights, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "fst.shop.external.fixture-pulse"
        ).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(fresh.exists, "Disabled highlighting left a New badge visible")

        rootControl("Settings", app: app).tap()
        reveal(hidden, in: app, scrollingUp: true)
        setSwitch(hidden, to: "1")
        XCTAssertFalse(highlights.isEnabled)
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.staticTexts[
            "Item Shop was hidden. Returned to Songs."
        ].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fst.songs.shop"].exists)
        rootControl("Settings", app: app).tap()
        reveal(hidden, in: app, scrollingUp: true)
        setSwitch(hidden, to: "0")
        reveal(highlights, in: app, scrollingUp: true)
        setSwitch(highlights, to: originalHighlights)
        setSwitch(hidden, to: originalHidden)
    }

    /// Valid Shop offers change anonymous Songs cards and their Detail action.
    ///
    /// - Throws: Missing Shop badges, stale disabled state or an unsafe external action.
    @MainActor
    func testPublicShopMembershipDecoratesSongsAndDetail() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        reveal(hidden, in: app, scrollingUp: true)
        let originalHidden = try XCTUnwrap(hidden.value as? String)
        setSwitch(hidden, to: "0")
        let highlights = app.switches["fst.settings.shop-highlights"]
        reveal(highlights, in: app, scrollingUp: true)
        let originalHighlights = try XCTUnwrap(highlights.value as? String)
        setSwitch(highlights, to: "1")

        rootControl("Songs", app: app).tap()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let newBadge = app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-badge.fixture-pulse"
        ).firstMatch
        let leaving = app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-badge.fixture-orbit"
        ).firstMatch
        XCTAssertTrue(newBadge.waitForExistence(timeout: 15))
        XCTAssertTrue(leaving.exists)
        record(app, name: "songs-public-shop-membership")
        try app.performAccessibilityAudit(for: .all)
        row.tap()
        let official = app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.shop"
        ).firstMatch
        XCTAssertTrue(official.waitForExistence(timeout: 10))
        XCTAssertTrue(official.label.contains("Item Shop"))

        rootControl("Settings", app: app).tap()
        reveal(highlights, in: app, scrollingUp: true)
        setSwitch(highlights, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(official.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.shop-badge"
        ).firstMatch.exists)
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Songs", "Back")
        ).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertFalse(newBadge.exists)
        XCTAssertFalse(leaving.exists)

        rootControl("Settings", app: app).tap()
        reveal(highlights, in: app, scrollingUp: true)
        setSwitch(highlights, to: originalHighlights)
        setSwitch(hidden, to: originalHidden)
    }

    /// Shop 503 is disclosed on Songs/Detail, never treated as an empty membership set.
    ///
    /// - Throws: A missing error/retry, invented Shop action or false empty-feed state.
    @MainActor
    func testShopFeedFailureAndEmptyStaySeparateFromSongs() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let unavailable = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-error").firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fst.songs.shop-retry"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-badge.fixture-pulse"
        ).firstMatch.exists)
        record(app, name: "songs-shop-service-unavailable")
        row.tap()
        let detailError = app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.shop-error"
        ).firstMatch
        XCTAssertTrue(detailError.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.shop"
        ).firstMatch.exists)

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-empty"
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertFalse(unavailable.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-badge.fixture-pulse"
        ).firstMatch.exists)
        openItemShop(in: app)
        XCTAssertTrue(app.staticTexts["No songs in the Item Shop"]
            .waitForExistence(timeout: 15))
        record(app, name: "songs-populated-shop-genuinely-empty")
    }

    /// Prove the Songs Shop Retry text actually scales on a real iPhone.
    ///
    /// - Throws: Missing 503 action, clipped large text or unreadable rendered glyphs.
    @MainActor
    func testSongsShopRetryScalesAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let retry = app.buttons["fst.songs.shop-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        let normalGlyphHeight = try brightGlyphHeight(in: retry)
        try assertHeaderContrast(retry, in: app, leadingTextWidth: 220)
        record(app, name: "songs-shop-retry-normal-text")

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let list = app.collectionViews["fst.songs.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let retryReturned = retry.waitForExistence(timeout: 15)
        if !retryReturned {
            record(app, name: "songs-shop-retry-ax5-missing")
        }
        XCTAssertTrue(retryReturned, "Shop Retry did not return after AX5 relaunch")
        record(app, name: "songs-shop-retry-ax5-before-scroll")
        let tabs = app.tabBars.firstMatch
        let visibleBottom = (tabs.exists
            ? tabs.frame.minY : app.windows.firstMatch.frame.maxY) - 8
        for _ in 0..<8 {
            if retry.isHittable && retry.frame.maxY <= visibleBottom { break }
            // A full swipe can skip the short Retry row between an AX5 banner and songs.
            let above = retry.frame.maxY < list.frame.minY
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
        if !retry.isHittable {
            record(app, name: "songs-shop-retry-ax5-unreachable")
        }
        XCTAssertTrue(retry.isHittable, "Shop Retry must remain reachable in AX5 Songs")
        XCTAssertLessThanOrEqual(retry.frame.maxY, visibleBottom)
        let largeGlyphHeight = try brightGlyphHeight(in: retry)
        XCTAssertGreaterThan(
            Double(largeGlyphHeight), Double(normalGlyphHeight) * 1.35,
            "Shop Retry rendered glyphs did not grow with Dynamic Type"
        )
        try assertHeaderContrast(retry, in: app, leadingTextWidth: 220)
        record(app, name: "songs-shop-retry-accessibility-xxxlarge")
    }

    /// Native Sort stages changes, persists rows and audits reachable modal text.
    ///
    /// - Throws: Wrong row order, silent discard, lost preference or visible contrast.
    @MainActor
    func testAnonymousSongsSortDraftApplyDiscardAndRelaunch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        if (sort.value as? String) != "Title, ascending" {
            let savedSort = try XCTUnwrap(sort.value as? String)
            sort.tap()
            let initialDirection = app.segmentedControls["fst.songs.sort.direction"]
            XCTAssertTrue(initialDirection.waitForExistence(timeout: 10))
            XCTAssertTrue(
                initialDirection.buttons[
                    savedSort.hasSuffix("descending") ? "Descending" : "Ascending"
                ].isSelected,
                "Saved \(savedSort) did not initialize the modal draft"
            )
            record(app, name: "songs-sort-before-baseline-reset")
            revealSortReset(in: app).tap()
            record(app, name: "songs-sort-after-baseline-reset")
            let initialApply = app.buttons["fst.songs.sort.apply"]
            for _ in 0..<30 {
                if initialApply.isEnabled { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertTrue(initialApply.isEnabled, "Could not restore the default sort")
            initialApply.tap()
            XCTAssertEqual(sort.value as? String, "Title, ascending")
        }
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))
        XCTAssertTrue(pulse.exists)
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)

        sort.tap()
        record(app, name: "songs-sort-default-sheet")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try assertHeaderContrast(app.staticTexts["Sort Songs"], in: app)
        }
        let direction = app.segmentedControls["fst.songs.sort.direction"]
        XCTAssertTrue(direction.waitForExistence(timeout: 10))
        let descending = direction.buttons["Descending"]
        XCTAssertTrue(descending.exists)
        let apply = app.buttons["fst.songs.sort.apply"]
        XCTAssertFalse(apply.isEnabled)
        let artist = app.buttons["Artist"]
        XCTAssertTrue(artist.exists)
        artist.tap()
        XCTAssertTrue(apply.isEnabled, "Choosing Artist did not change the sort draft")
        app.buttons["Title"].tap()
        XCTAssertFalse(apply.isEnabled, "Restoring Title did not clear the sort draft")
        descending.tap()
        XCTAssertTrue(descending.isSelected)
        record(app, name: "songs-sort-draft-descending")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try assertHeaderContrast(app.buttons["fst.songs.sort.cancel"], in: app)
        }
        XCTAssertTrue(apply.isEnabled, "Changing direction did not create a draft")
        app.buttons["fst.songs.sort.cancel"].tap()
        let continueEditing = app.buttons["Continue Editing"]
        XCTAssertTrue(continueEditing.waitForExistence(timeout: 10))
        continueEditing.tap()
        XCTAssertTrue(descending.isSelected)
        XCTAssertTrue(apply.isEnabled)
        app.buttons["fst.songs.sort.cancel"].tap()
        let discard = app.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        discard.tap()
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)

        sort.tap()
        XCTAssertTrue(direction.buttons["Ascending"].isSelected)
        descending.tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        for _ in 0..<30 {
            if pulse.frame.minY < orbit.frame.minY { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)
        XCTAssertEqual(sort.value as? String, "Title, descending")
        record(app, name: "songs-title-descending")

        app.terminate()
        app.launch()
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)
        sort.tap()
        XCTAssertTrue(direction.buttons["Descending"].isSelected)
        revealSortReset(in: app).tap()
        app.buttons["fst.songs.sort.cancel"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 10))
        app.buttons["Discard Changes"].tap()
        XCTAssertEqual(sort.value as? String, "Title, descending")
        sort.tap()
        XCTAssertTrue(direction.buttons["Descending"].isSelected)
        revealSortReset(in: app).tap()
        let resetApply = app.buttons["fst.songs.sort.apply"]
        for _ in 0..<30 {
            if resetApply.isEnabled { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(resetApply.isEnabled, "Reset did not create a changed sort draft")
        app.buttons["fst.songs.sort.apply"].tap()
        for _ in 0..<30 {
            if orbit.frame.minY < pulse.frame.minY { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)
        XCTAssertEqual(sort.value as? String, "Title, ascending")
    }

    /// Item Shop sorting uses validated membership and retains paused saved preferences.
    ///
    /// - Throws: Wrong order, unreadable headings, unavailable Shop as empty or lost sort.
    @MainActor
    func testAnonymousItemShopSortRestoresAfterHideAndFeedFailure() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launch()
        rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        reveal(hidden, in: app, scrollingUp: true)
        let originallyHidden = try XCTUnwrap(hidden.value as? String)
        setSwitch(hidden, to: "0")
        rootControl("Songs", app: app).tap()

        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        if (sort.value as? String) != "Title, ascending" {
            sort.tap()
            revealSortReset(in: app).tap()
            let resetApply = app.buttons["fst.songs.sort.apply"]
            XCTAssertTrue(resetApply.isEnabled)
            resetApply.tap()
            XCTAssertEqual(sort.value as? String, "Title, ascending")
        }
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))
        XCTAssertTrue(pulse.exists)
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)

        sort.tap()
        let inShop = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-section.in-shop").firstMatch
        let notInShop = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-section.not-in-shop").firstMatch
        let leaving = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-section.leaving-tomorrow").firstMatch
        let shopMode = app.buttons.matching(
            identifier: "fst.songs.sort.mode"
        ).matching(NSPredicate(format: "label == %@", "Item Shop")).firstMatch
        XCTAssertTrue(
            shopMode.waitForExistence(timeout: 10),
            "Sort picker options: \(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
        )
        for _ in 0..<100 {
            if shopMode.isEnabled { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(shopMode.isEnabled, "Shop mode was never backed by its public feed")
        let readyShop = revealShopSort(in: app)
        record(app, name: "songs-shop-sort-choice")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try assertHeaderContrast(readyShop, in: app, leadingTextWidth: 180)
        }
        readyShop.tap()
        let apply = app.buttons["fst.songs.sort.apply"]
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        for _ in 0..<30 {
            if pulse.frame.minY < orbit.frame.minY { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)
        XCTAssertEqual(sort.value as? String, "Item Shop, ascending")
        XCTAssertTrue(inShop.waitForExistence(timeout: 10))
        XCTAssertTrue(notInShop.exists)
        XCTAssertLessThan(inShop.frame.minY, notInShop.frame.minY)
        record(app, name: "songs-shop-sort-ascending")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try assertHeaderContrast(inShop, in: app, leadingTextWidth: 180)
            try assertHeaderContrast(notInShop, in: app, leadingTextWidth: 180)
        } else {
            let search = app.textFields["fst.songs.search"]
            XCTAssertTrue(search.exists)
            let contentX = search.frame.minX
            XCTAssertGreaterThan(contentX, app.windows.firstMatch.frame.minX)
            try assertHeaderContrast(
                inShop, in: app, leadingTextWidth: 180, horizontalOrigin: contentX
            )
            try assertHeaderContrast(
                notInShop, in: app, leadingTextWidth: 180, horizontalOrigin: contentX
            )
        }
        pulse.tap()
        let official = app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.shop"
        ).firstMatch
        XCTAssertTrue(official.waitForExistence(timeout: 10))
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Songs", "Back")
        ).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        back.tap()
        XCTAssertTrue(inShop.waitForExistence(timeout: 10))

        sort.tap()
        let direction = app.segmentedControls["fst.songs.sort.direction"]
        XCTAssertTrue(direction.buttons["Ascending"].isSelected)
        direction.buttons["Descending"].tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        for _ in 0..<30 {
            if orbit.frame.minY < pulse.frame.minY { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)
        XCTAssertEqual(sort.value as? String, "Item Shop, descending")
        XCTAssertLessThan(notInShop.frame.minY, inShop.frame.minY)

        rootControl("Settings", app: app).tap()
        reveal(hidden, in: app, scrollingUp: true)
        setSwitch(hidden, to: "1")
        rootControl("Songs", app: app).tap()
        let paused = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.sort-paused").firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 10))
        XCTAssertTrue(paused.label.contains("while Shop is hidden"))
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)
        XCTAssertTrue((sort.value as? String)?.contains("paused; showing Title") == true)
        XCTAssertFalse(inShop.exists)
        XCTAssertFalse(notInShop.exists)
        record(app, name: "songs-shop-sort-paused-hidden")
        sort.tap()
        XCTAssertFalse(shopMode.exists, "Hidden Shop is still a selectable sort option")
        app.buttons["fst.songs.sort.cancel"].tap()

        rootControl("Settings", app: app).tap()
        reveal(hidden, in: app, scrollingUp: true)
        setSwitch(hidden, to: "0")
        rootControl("Songs", app: app).tap()
        for _ in 0..<40 {
            if (sort.value as? String) == "Item Shop, descending" { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(sort.value as? String, "Item Shop, descending")
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)
        XCTAssertLessThan(notInShop.frame.minY, inShop.frame.minY)

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launch()
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))
        XCTAssertTrue(paused.waitForExistence(timeout: 10))
        XCTAssertTrue(paused.label.contains("until public Shop data loads"))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-error"
        ).firstMatch.exists)
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)
        XCTAssertTrue((sort.value as? String)?.contains("paused; showing Title") == true)
        XCTAssertFalse(inShop.exists)
        XCTAssertFalse(notInShop.exists)
        sort.tap()
        let unavailableShop = app.buttons.matching(
            identifier: "fst.songs.sort.mode"
        ).matching(NSPredicate(format: "label == %@", "Item Shop")).firstMatch
        XCTAssertTrue(unavailableShop.exists, "Unavailable Shop choice disappeared")
        XCTAssertFalse(unavailableShop.isEnabled, "A failed Shop feed can be selected")
        XCTAssertFalse(app.buttons["fst.songs.sort.apply"].isEnabled)
        app.buttons["fst.songs.sort.cancel"].tap()

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-empty"
        app.launch()
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))
        for _ in 0..<40 {
            if (sort.value as? String) == "Item Shop, descending" { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(sort.value as? String, "Item Shop, descending")
        XCTAssertFalse(paused.exists, "Known-empty Shop was treated as an unavailable feed")
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)
        XCTAssertFalse(inShop.exists)
        XCTAssertFalse(notInShop.exists, "One Shop bucket should have no visible heading")
        sort.tap()
        XCTAssertTrue(revealShopSort(in: app).isEnabled)
        app.buttons["fst.songs.sort.cancel"].tap()

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launch()
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        for _ in 0..<40 {
            if (sort.value as? String) == "Item Shop, descending" { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(sort.value as? String, "Item Shop, descending")
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)
        XCTAssertLessThan(notInShop.frame.minY, inShop.frame.minY)

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "demo"
        app.launch()
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertTrue(leaving.waitForExistence(timeout: 10))
        XCTAssertEqual(sort.value as? String, "Item Shop, descending")
        XCTAssertLessThan(inShop.frame.minY, leaving.frame.minY)
        XCTAssertFalse(notInShop.exists)
        sort.tap()
        revealSortReset(in: app).tap()
        XCTAssertTrue(app.buttons["fst.songs.sort.apply"].isEnabled)
        app.buttons["fst.songs.sort.apply"].tap()
        XCTAssertEqual(sort.value as? String, "Title, ascending")
        rootControl("Settings", app: app).tap()
        reveal(hidden, in: app, scrollingUp: true)
        setSwitch(hidden, to: originallyHidden)
    }

    /// Public CHOpt paths switch image/text and difficulty without stale content.
    ///
    /// - Throws: Missing selectors, unsafe zoom, stale path, hidden error or unreachable close.
    @MainActor
    func testSongPathsImageTextSwitchAndMissingDifficulty() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        collapseSidebarOnPad(app)
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: 2) {
            XCTAssertTrue(warning.staticTexts[
                "Karaoke is not available for path visualization yet."
            ].exists)
            warning.buttons["OK"].tap()
        }

        let display = app.segmentedControls["fst.paths.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        display.buttons["Image"].tap()
        let image = app.images["fst.paths.image"]
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try assertHeaderContrast(app.staticTexts["Paths"], in: app)
            try assertHeaderContrast(app.buttons["fst.paths.close"], in: app)
        }
        let fittedWidth = image.frame.width
        let zoom = app.buttons["fst.paths.zoom-in"]
        XCTAssertTrue(zoom.isHittable)
        zoom.tap()
        XCTAssertGreaterThan(image.frame.width, fittedWidth, "Zoom did not resize the path")
        record(app, name: "song-path-expert-image")
        zoom.tap()
        zoom.tap()
        XCTAssertFalse(zoom.isEnabled, "Zoom in did not stop at the supported scale")
        let zoomOut = app.buttons["fst.paths.zoom-out"]
        XCTAssertTrue(zoomOut.isEnabled)
        zoomOut.tap()
        XCTAssertTrue(zoom.isEnabled)

        display.buttons["Text"].tap()
        let summary = app.staticTexts["fst.paths.text-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertEqual(summary.label, "Two synthetic Expert activations")
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "fst.paths.activation.1"
        ).firstMatch.exists)
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try assertHeaderContrast(summary, in: app)
        }
        record(app, name: "song-path-expert-text")

        let difficulty = app.segmentedControls["fst.paths.difficulty"]
        XCTAssertTrue(difficulty.buttons["Expert"].isSelected)
        difficulty.buttons["Hard"].tap()
        for _ in 0..<40 {
            if summary.label.contains("Hard") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(summary.label, "Two synthetic Hard activations")
        difficulty.buttons["Medium"].tap()
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Retry"].exists)
        difficulty.buttons["Expert"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        for _ in 0..<40 {
            if summary.label.contains("Expert") { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(summary.label, "Two synthetic Expert activations")
        let instrument = app.descendants(matching: .any).matching(
            identifier: "fst.paths.instrument"
        ).firstMatch
        XCTAssertTrue(instrument.exists)
        instrument.tap()
        let bass = app.buttons["Bass"]
        XCTAssertTrue(bass.waitForExistence(timeout: 10))
        bass.tap()
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertFalse(summary.exists, "Lead content remained visible for a missing Bass path")
        instrument.tap()
        app.buttons["Lead"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        app.buttons["fst.paths.close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 10))
    }

    /// A saved Settings path default initializes the next modal without erasing it.
    ///
    /// - Throws: A disconnected setting, unavailable modal or lost original preference.
    @MainActor
    func testSongPathsDefaultViewFollowsSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        rootControl("Settings", app: app).tap()
        let setting = app.descendants(matching: .any).matching(
            identifier: "fst.settings.path-default-view"
        ).firstMatch
        XCTAssertTrue(setting.waitForExistence(timeout: 10))
        reveal(setting, in: app, scrollingUp: false)
        let original = try XCTUnwrap(setting.value as? String)
        XCTAssertTrue(
            ["Image", "Text"].contains(original),
            "Unexpected path picker value \(original); label: \(setting.label)"
        )
        let changed = original == "Image" ? "Text" : "Image"
        setting.tap()
        let option = app.buttons[changed]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        XCTAssertEqual(setting.value as? String, changed)

        rootControl("Songs", app: app).tap()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        collapseSidebarOnPad(app)
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: 2) {
            warning.buttons["OK"].tap()
        }
        let display = app.segmentedControls["fst.paths.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        XCTAssertTrue(display.buttons[changed].isSelected)
        if changed == "Text" {
            XCTAssertTrue(app.staticTexts["fst.paths.text-summary"]
                .waitForExistence(timeout: 15))
        } else {
            XCTAssertTrue(app.images["fst.paths.image"].waitForExistence(timeout: 15))
        }
        app.buttons["fst.paths.close"].tap()

        if UIDevice.current.userInterfaceIdiom == .pad {
            let sidebar = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "sidebar")
            ).firstMatch
            XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
            sidebar.tap()
        }
        rootControl("Settings", app: app).tap()
        reveal(setting, in: app, scrollingUp: false)
        setting.tap()
        app.buttons[original].tap()
        XCTAssertEqual(setting.value as? String, original)
    }

    /// Show ten real fixture score rows, then open the independent full Solo page.
    ///
    /// - Throws: Missing native top-score rows, incorrect top parameter or hidden action.
    @MainActor
    func testSongDetailShowsTopScorePreviewAndFullChart() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        collapseSidebarOnPad(app)
        let viewFull = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(viewFull.waitForExistence(timeout: 15))
        let first = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "#1")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Fixture Player 1"].exists)
        let previewNonFC = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "Accuracy 98%")).firstMatch
        let previewFC = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-2"
        ).matching(NSPredicate(
            format: "label == %@", "Full combo, accuracy 98%"
        )).firstMatch
        XCTAssertTrue(previewNonFC.waitForExistence(timeout: 10))
        XCTAssertEqual(previewNonFC.label, "Accuracy 98%")
        XCTAssertTrue(previewFC.exists)
        XCTAssertEqual(previewFC.label, "Full combo, accuracy 98%")
        try assertScoreAccuracyAccent(previewNonFC, fullCombo: false)
        try assertScoreAccuracyAccent(previewFC, fullCombo: true)
        let previewScoreOne = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "99,900")).firstMatch
        let previewScoreTwo = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-2"
        ).matching(NSPredicate(format: "label == %@", "99,800")).firstMatch
        assertAlignedScoreColumn(
            firstScore: previewScoreOne, secondScore: previewScoreTwo,
            firstBadge: previewNonFC, secondBadge: previewFC
        )
        let previewRowThree = "fst.song-detail.preview-row.Solo_Guitar.fixture-player-3"
        let previewRowFour = "fst.song-detail.preview-row.Solo_Guitar.fixture-player-4"
        let previewScoreThree = app.staticTexts.matching(identifier: previewRowThree)
            .matching(NSPredicate(format: "label == %@", "99,700")).firstMatch
        let previewScoreFour = app.staticTexts.matching(identifier: previewRowFour)
            .matching(NSPredicate(format: "label == %@", "99,600")).firstMatch
        assertAlignedScoreEnds(previewScoreOne, previewScoreThree)
        assertAlignedScoreEnds(previewScoreOne, previewScoreFour)
        XCTAssertFalse(app.staticTexts.matching(identifier: previewRowThree)
            .matching(NSPredicate(
                format: "label CONTAINS[c] %@", "accuracy"
            )).firstMatch.exists)
        let previewFCWithoutAccuracy = app.staticTexts.matching(identifier: previewRowFour)
            .matching(NSPredicate(
                format: "label == %@", "Full combo; accuracy unavailable"
            )).firstMatch
        XCTAssertTrue(previewFCWithoutAccuracy.exists)
        let previewQuery = try await latestFixtureScoreQuery()
        XCTAssertEqual(previewQuery.top, 10)
        XCTAssertEqual(previewQuery.offset, 0)
        XCTAssertNil(previewQuery.leeway)
        XCTAssertFalse(app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-11"
        ).matching(NSPredicate(format: "label == %@", "#11")).firstMatch.exists)
        record(app, name: "song-detail-real-top-scores")
        try assertHeaderContrast(app.staticTexts["Fixture Player 1"], in: app)

        viewFull.tap()
        XCTAssertTrue(app.buttons["fst.song-leaderboard.page-next"].waitForExistence(timeout: 10))
        let fullQuery = try await latestFixtureScoreQuery(fullOnly: true)
        XCTAssertEqual(fullQuery.top, 25)
        XCTAssertEqual(fullQuery.offset, 0)
        let fullNonFC = app.staticTexts["fst.score.accuracy.fixture-player-1"]
        let fullFC = app.staticTexts["fst.score.accuracy.fixture-player-2"]
        XCTAssertTrue(fullNonFC.waitForExistence(timeout: 10))
        XCTAssertEqual(fullNonFC.label, "Accuracy 98%")
        XCTAssertTrue(fullFC.exists)
        XCTAssertEqual(fullFC.label, "Full combo, accuracy 98%")
        try assertScoreAccuracyAccent(fullNonFC, fullCombo: false)
        try assertScoreAccuracyAccent(fullFC, fullCombo: true)
        let fullRowOne = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-1").firstMatch
        let fullRowTwo = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-2").firstMatch
        let fullScoreOne = fullRowOne.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "99,900")).firstMatch
        let fullScoreTwo = fullRowTwo.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "99,800")).firstMatch
        assertAlignedScoreColumn(
            firstScore: fullScoreOne, secondScore: fullScoreTwo,
            firstBadge: fullNonFC, secondBadge: fullFC
        )
        let fullRowThree = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-3").firstMatch
        let fullRowFour = app.descendants(matching: .any)
            .matching(identifier: "fst.song-leaderboard.row.fixture-player-4").firstMatch
        let fullScoreThree = fullRowThree.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "99,700")).firstMatch
        let fullScoreFour = fullRowFour.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label == %@", "99,600")).firstMatch
        assertAlignedScoreEnds(fullScoreOne, fullScoreThree)
        assertAlignedScoreEnds(fullScoreOne, fullScoreFour)
        XCTAssertFalse(app.staticTexts["fst.score.accuracy.fixture-player-3"].exists)
        let fullFCWithoutAccuracy = app.staticTexts["fst.score.accuracy.fixture-player-4"]
        XCTAssertTrue(fullFCWithoutAccuracy.exists)
        XCTAssertEqual(fullFCWithoutAccuracy.label, "Full combo; accuracy unavailable")
        try assertScoreAccuracyAccent(fullFCWithoutAccuracy, fullCombo: true)
        XCTAssertLessThanOrEqual(
            abs(fullNonFC.frame.minX - fullFCWithoutAccuracy.frame.minX), 1,
            "FC without accuracy must retain the same badge column"
        )
        record(app, name: "solo-fc-versus-graded-accuracy")
    }

    /// Probe system accessibility scrolling to the last score in a populated preview.
    ///
    /// - Throws: A stalled offscreen score target or missing painted preview row.
    @MainActor
    func testOffscreenDetailScoreRemainsReachable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8774"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let first = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "#1")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let tenth = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-10"
        ).matching(NSPredicate(format: "label == %@", "#10")).firstMatch
        XCTAssertTrue(tenth.waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(tenth.isHittable, "The last score did not start offscreen")
        }
        tenth.tap()
        XCTAssertTrue(tenth.isHittable, "Offscreen score could not be brought into view")
        record(app, name: "song-detail-offscreen-score-revealed")
    }

    /// Probe an offscreen empty-chart action without inventing a successful score.
    ///
    /// - Throws: A stalled native scroll or missing genuinely empty Bass chart.
    @MainActor
    func testOffscreenEmptyChartActionRemainsReachable() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8775"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let first = app.staticTexts.matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).matching(NSPredicate(format: "label == %@", "#1")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let bass = app.buttons["fst.song-detail.leaderboard.Solo_Bass"]
        XCTAssertTrue(bass.waitForExistence(timeout: 15))
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(bass.isHittable, "Bass action did not start offscreen")
        }
        bass.tap()
        XCTAssertTrue(app.staticTexts["0 Bass entries"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.buttons["fst.song-leaderboard.page-next"].waitForExistence(timeout: 10),
            "Bass full chart did not finish loading"
        )
        try await awaitClosedFixture(port: 8775)
        record(app, name: "song-detail-offscreen-bass-opened")
    }

    /// Traverse Songs, Detail and page two, then verify landscape layout survives.
    ///
    /// - Throws: An XCTest failure for missing accessible actions or screen state.
    @MainActor
    func testSongsDetailScoresInPortraitAndLandscape() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()

        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Fixture song row did not load")
        record(app, name: "songs-portrait")
        row.tap()

        XCTAssertTrue(app.staticTexts["Intensity"].waitForExistence(timeout: 10))
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10), "Lead leaderboard action is missing")
        record(app, name: "song-detail-portrait")
        lead.tap()

        let next = app.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "Pagination is not reachable")
        collapseSidebarOnPad(app)
        XCTAssertTrue(app.staticTexts["1 / 2"].exists)
        let first = app.buttons["fst.song-leaderboard.page-first"]
        XCTAssertFalse(first.isEnabled)
        XCTAssertTrue(next.isEnabled)
        try app.performAccessibilityAudit(for: .all) { issue in
            XCTFail(
                "Solo page audit: \(issue.compactDescription); "
                    + "element=\(issue.element?.identifier ?? "unidentified"), "
                    + "label=\(issue.element?.label ?? "unidentified"), "
                    + "frame=\(String(describing: issue.element?.frame))"
            )
            return false
        }
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(first.isEnabled)
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.song-leaderboard.row.fixture-player-26")
                .firstMatch.waitForExistence(timeout: 10)
        )
        try app.performAccessibilityAudit(for: .all)
        record(app, name: "song-leaderboard-page2-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(
            app.windows.firstMatch.frame.width,
            app.windows.firstMatch.frame.height,
            "App window failed to reflow to landscape"
        )
        let leaderboardLists = [app.collectionViews.firstMatch, app.tables.firstMatch]
        let listWidth = leaderboardLists.filter(\.exists).map { $0.frame.width }.max() ?? 0
        XCTAssertGreaterThan(
            listWidth,
            app.windows.firstMatch.frame.width * 0.6,
            "The actual score list did not expand in landscape"
        )
        record(app, name: "song-leaderboard-page2-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// Keep solo rows and pagination reachable at the largest native text size.
    ///
    /// - Throws: Missing score text or a page action outside the visible viewport.
    @MainActor
    func testSoloScoresAtLargestTextSize() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let lead = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(lead.waitForExistence(timeout: 10))
        lead.tap()
        collapseSidebarOnPad(app)
        let next = app.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let accuracy = revealSoloAccuracy("fixture-player-1", app: app)
        assertWholeSoloScore("fixture-player-1", rank: 1, score: 99_900, app: app)
        record(app, name: "solo-largest-text-page1")
        XCTAssertTrue(accuracy.isHittable)
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(app.buttons["fst.song-leaderboard.page-first"].isEnabled)
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        let lastAccuracy = revealSoloAccuracy(
            "fixture-player-26", fullCombo: true, app: app
        )
        assertWholeSoloScore("fixture-player-26", rank: 26, score: 97_400, app: app)
        XCTAssertTrue(lastAccuracy.isHittable)
        XCTAssertTrue(app.buttons["fst.song-leaderboard.page-first"].isEnabled)
        XCTAssertFalse(next.isEnabled)
        record(app, name: "solo-largest-text-page2")
    }

    /// Run the system audit against a visible fixture-backed native screen.
    ///
    /// - Throws: An accessibility audit issue for actionable labels/contrast/order.
    @MainActor
    func testSongsAccessibilityAudit() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let screenshot = try XCTUnwrap(app.screenshot().image.cgImage)
        let simulator = ProcessInfo.processInfo.environment
        let width = try XCTUnwrap(Int(simulator["SIMULATOR_MAINSCREEN_WIDTH"] ?? ""))
        let height = try XCTUnwrap(Int(simulator["SIMULATOR_MAINSCREEN_HEIGHT"] ?? ""))
        XCTAssertEqual(
            screenshot.width, width,
            "App capture does not match the native device display"
        )
        XCTAssertEqual(screenshot.height, height)
        let brand: [UInt8] = [26, 8, 48]
        let base = Array(repeating: brand, count: 256).flatMap { $0 }
        var painted = base
        for _ in 0..<20 {
            painted = try backgroundSignature(app)
            if pixelDistance(painted, base) > 1_500 { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertGreaterThan(
            pixelDistance(painted, base), 1_500,
            "Cannot audit artwork contrast before original fixture art is visible"
        )
        record(app, name: "songs-before-accessibility-audit")
        try app.performAccessibilityAudit(for: .all)
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
        let search = app.textFields["fst.songs.search"]
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

    /// Exercise real native no-results and service-error presentation.
    ///
    /// - Throws: A missing fixture-only state or retry action.
    @MainActor
    func testEmptyAndErrorCatalogueStates() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "empty"
        app.launch()
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 15))
        record(app, name: "songs-empty")
        app.terminate()

        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        app.launch()
        XCTAssertTrue(app.staticTexts["Songs unavailable"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Retry"].exists)
        record(app, name: "songs-service-error")
        try app.performAccessibilityAudit(for: .all)
        rootControl("Settings", app: app).tap()
        let publication = app.buttons["Check Publication"]
        reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        reveal(status, in: app, scrollingUp: true)
        XCTAssertTrue(
            status.label.hasPrefix("Publication 7; songs update failed:"),
            "A successful publication check must not hide a failed song refresh"
        )
    }

    /// Keep Retry reachable when large accessibility fonts exceed the visible page.
    ///
    /// - Throws: An ignored text-size override or an action hidden behind native chrome.
    @MainActor
    func testFailureActionRemainsReachableAtLargestTypeAndLandscape() throws {
        continueAfterFailure = false
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        app.launch()
        let title = app.staticTexts["Songs unavailable"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        let normalHeight = title.frame.height
        app.terminate()

        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(title.frame.height, normalHeight * 1.2)
        try revealFailureAction(app)
        record(app, name: "songs-error-largest-text-portrait")
        let errorScroll = app.scrollViews.containing(.button, identifier: "Retry").firstMatch
        XCTAssertTrue(errorScroll.exists)
        errorScroll.swipeDown()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.staticTexts["Loading songs"].exists)

        XCUIDevice.shared.orientation = .landscapeLeft
        for _ in 0..<30 {
            let frame = app.windows.firstMatch.frame
            if frame.width > frame.height { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        record(app, name: "songs-error-largest-text-landscape-before-scroll")
        try revealFailureAction(app)
        record(app, name: "songs-error-largest-text-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// An initial 503 can recover on the same publication without a stuck Songs error.
    ///
    /// - Throws: Failed fixture-only retry, missing white art or inaccessible error state.
    @MainActor
    func testSongsRecoversAfterSamePublicationSettingsCheck() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8769"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "art-white"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Songs unavailable"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Retry"].exists)
        record(app, name: "songs-first-catalogue-503")
        try app.performAccessibilityAudit(for: .all)

        rootControl("Settings", app: app).tap()
        let publication = app.buttons["Check Publication"]
        reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "Publication 7")
        reveal(app.staticTexts["App Settings"], in: app, scrollingUp: false)
        try await assertWhiteArtVisible(in: app)
        record(app, name: "settings-recovered-white-art")

        rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-white"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Songs unavailable"].exists)
        try await assertWhiteArtVisible(in: app)
        record(app, name: "songs-recovered-same-publication")
        try app.performAccessibilityAudit(for: .all)
    }

    /// Keep unpinned Songs through warm resume with an independent Shop retry.
    ///
    /// - Throws: Missing offline disclosure, unreadable Shop retry or persisted cold bytes.
    @MainActor
    func testHeaderlessWarmOfflineSurvivesBackgroundButNotColdLaunch() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8771"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let shopRetry = app.buttons["fst.songs.shop-retry"]
        XCTAssertTrue(shopRetry.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Showing live songs without publication verification"
            )
        ).firstMatch.exists)

        try await awaitClosedFixture(port: 8771)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let table = app.tables.firstMatch
        let list = table.exists ? table : app.collectionViews.firstMatch
        XCTAssertTrue(list.exists)
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14))
            .press(
                forDuration: 0.1,
                thenDragTo: list.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.87)
                )
            )
        record(app, name: "songs-after-warm-refresh-gesture")
        let offline = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.offline").firstMatch
        XCTAssertTrue(
            offline.waitForExistence(timeout: 10),
            "Refreshing \(list.frame) left labels: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(18).map(\.label))"
        )
        XCTAssertEqual(offline.label, "Offline - last seen songs (publication unverified)")
        XCTAssertTrue(row.exists)
        XCTAssertTrue(shopRetry.waitForExistence(timeout: 10))
        try assertHeaderContrast(shopRetry, in: app, leadingTextWidth: 220)
        record(app, name: "songs-headerless-warm-offline")
        var acceptedShopContrast = false
        var acceptedShopDynamicType = false
        try app.performAccessibilityAudit(for: .all) { issue in
            // Pixels pass 4.5:1 and a separate AX5 case proves >1.35x glyph growth.
            guard UIDevice.current.userInterfaceIdiom == .phone,
                  UIDevice.current.systemVersion == "26.5",
                  issue.element?.identifier == "fst.songs.shop-retry",
                  issue.element?.label == "Retry Item Shop status" else {
                return false
            }
            if issue.auditType == .contrast && !acceptedShopContrast {
                acceptedShopContrast = true
                return true
            }
            if issue.auditType == .dynamicType && !acceptedShopDynamicType {
                acceptedShopDynamicType = true
                return true
            }
            return false
        }

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Songs unavailable"].waitForExistence(timeout: 15))
        XCTAssertFalse(offline.exists)
        record(app, name: "songs-headerless-cold-no-cache")
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
        let search = app.textFields["fst.songs.search"]
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
        app.launch()
        app.activate()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
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
        XCTAssertLessThanOrEqual(
            pixelDistance(try backgroundSignature(app), base), 100,
            "Reduce Transparency failed to remove the image and dark overlay"
        )
        record(app, name: "songs-artwork-opaque-override")

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
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
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

    /// A hidden chart disappears from navigation, but remains in song Intensity.
    ///
    /// - Throws: A broken Settings-to-screen dependency or missing slider value.
    @MainActor
    func testInstrumentVisibilityAndScoreFilterPropagation() async throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        rootControl("Settings", app: app).tap()

        let filter = app.switches["Filter Invalid Scores"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        let originalFilter = try XCTUnwrap(filter.value as? String)
        setSwitch(filter, to: "1")
        let leeway = app.sliders["fst.settings.leeway"]
        XCTAssertTrue(leeway.waitForExistence(timeout: 10))
        XCTAssertTrue(
            (leeway.value as? String)?.contains("%") == true,
            "The slider must announce a numeric score tolerance"
        )

        let bass = app.switches["fst.settings.instrument.Solo_Bass"]
        reveal(bass, in: app, scrollingUp: true)
        let originalBass = try XCTUnwrap(bass.value as? String)
        setSwitch(bass, to: "0")

        rootControl("Songs", app: app).tap()
        let menu = app.buttons["fst.songs.instrument-filter"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        XCTAssertFalse(app.buttons["Bass"].exists)
        XCTAssertTrue(app.buttons["Lead"].exists, "Instrument menu did not open")
        let menuItem = app.collectionViews.buttons["All instruments"].firstMatch
        if menuItem.exists {
            menuItem.tap()
        } else {
            app.buttons["All instruments"].firstMatch.tap()
        }

        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.staticTexts["Bass"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fst.song-detail.leaderboard.Solo_Bass"].exists)
        let leadChart = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(leadChart.exists)
        let paths = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(paths.waitForExistence(timeout: 10))
        paths.tap()
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: 2) {
            warning.buttons["OK"].tap()
        }
        let pathInstrument = app.descendants(matching: .any).matching(
            identifier: "fst.paths.instrument"
        ).firstMatch
        XCTAssertTrue(pathInstrument.waitForExistence(timeout: 10))
        pathInstrument.tap()
        XCTAssertFalse(app.buttons["Bass"].exists, "Settings-hidden Bass is still a path choice")
        XCTAssertTrue(app.buttons["Lead"].exists)
        app.buttons["Lead"].tap()
        app.buttons["fst.paths.close"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).firstMatch.waitForExistence(timeout: 10))
        let preview = try await latestFixtureScoreQuery()
        XCTAssertEqual(preview.top, 10)
        XCTAssertNotNil(preview.leeway, "Preview ignored the enabled score filter")
        leadChart.tap()
        let next = app.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        let enabled = try await latestFixtureScoreQuery()
        XCTAssertEqual(enabled.offset, 0)
        XCTAssertNotNil(enabled.leeway, "Enabled score filtering omitted its wire tolerance")

        rootControl("Settings", app: app).tap()
        reveal(bass, in: app, scrollingUp: true)
        setSwitch(bass, to: originalBass)
        reveal(filter, in: app, scrollingUp: false)
        setSwitch(filter, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                identifier: "fst.song-leaderboard.row.fixture-player-26"
            ).firstMatch.waitForExistence(timeout: 10),
            "Page two never displayed its offset-25 fixture score"
        )
        let disabled = try await latestFixtureScoreQuery(fullOnly: true)
        XCTAssertEqual(disabled.top, 25)
        XCTAssertEqual(disabled.offset, 25)
        XCTAssertNil(disabled.leeway, "Disabled filtering still sent leeway")
        rootControl("Settings", app: app).tap()
        reveal(filter, in: app, scrollingUp: false)
        setSwitch(filter, to: originalFilter)
    }

    /// Split navigation must retain a chart filter and clear it when hidden in Settings.
    ///
    /// - Throws: Lost tab-owned state, a hidden chart still selected or an absent notice.
    @MainActor
    func testSectionSwitchKeepsAndSanitizesInstrument() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let menu = app.buttons["fst.songs.instrument-filter"]
        menu.tap()
        let leadItem = app.collectionViews.buttons["Lead"].firstMatch
        if leadItem.exists {
            leadItem.tap()
        } else {
            app.buttons["Lead"].firstMatch.tap()
        }
        XCTAssertTrue(menu.label.contains("Lead"))
        rootControl("Settings", app: app).tap()
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(menu.label.contains("Lead"), "The selected chart was lost on tab switch")
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].exists)

        rootControl("Settings", app: app).tap()
        let lead = app.switches["fst.settings.instrument.Solo_Guitar"]
        reveal(lead, in: app, scrollingUp: true)
        let original = try XCTUnwrap(lead.value as? String)
        setSwitch(lead, to: "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(menu.label.contains("All instruments"))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Lead was hidden")
            ).firstMatch.waitForExistence(timeout: 10)
        )

        rootControl("Settings", app: app).tap()
        reveal(lead, in: app, scrollingUp: true)
        setSwitch(lead, to: original)

        rootControl("Songs", app: app).tap()
        menu.tap()
        let absent = app.collectionViews.buttons["Pro Drums + Cymbals"].firstMatch
        if absent.exists {
            absent.tap()
        } else {
            app.buttons["Pro Drums + Cymbals"].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["No songs match your filters."].waitForExistence(timeout: 10))
    }

    /// A confirmed app-settings reset must not erase the current Songs query.
    ///
    /// - Throws: Missing reset confirmation, lost route state or wrong defaults.
    @MainActor
    func testAppOnlyResetPreservesSongsSearch() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let search = app.textFields["fst.songs.search"]
        search.tap()
        search.typeText("zzzz\n")
        let noMatches = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "No Results for")
        ).firstMatch
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10))
        rootControl("Settings", app: app).tap()

        let filter = app.switches["Filter Invalid Scores"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        setSwitch(filter, to: "1")
        let motion = app.switches["fst.settings.reduce-motion"]
        reveal(motion, in: app, scrollingUp: true)
        setSwitch(motion, to: "1")

        let publication = app.buttons["Check Publication"]
        reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "Publication 7")
        let reset = app.buttons["fst.settings.reset"]
        reveal(reset, in: app, scrollingUp: true)
        reset.tap()
        let confirmation = app.buttons.matching(
            NSPredicate(format: "label == %@", "Reset App Settings")
        ).allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(confirmation, "Reset confirmation was not presented")
        confirmation?.tap()

        reveal(filter, in: app, scrollingUp: false)
        XCTAssertEqual(filter.value as? String, "0")
        XCTAssertFalse(app.sliders["fst.settings.leeway"].exists)
        reveal(motion, in: app, scrollingUp: true)
        XCTAssertEqual(motion.value as? String, "0")
        rootControl("Songs", app: app).tap()
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10))
    }

    /// Explain why an unpinned generation change returns an old Detail route to Songs.
    ///
    /// - Throws: Missing unverified-data label, stale Detail route or absent notice.
    @MainActor
    func testHeaderlessRolloverExplainsRouteReset() async throws {
        continueAfterFailure = false
        let app = fixtureApp()
        let port = UIDevice.current.userInterfaceIdiom == .pad ? 8768 : 8767
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:\(port)"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        let appeared = song.waitForExistence(timeout: 15)
        if !appeared {
            record(app, name: "songs-unpinned-rollover-initial-failure")
        }
        XCTAssertTrue(
            appeared, "Unpinned Songs initial state: \(app.debugDescription.prefix(1_800))"
        )
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label == %@",
                "Showing live songs without publication verification"
            )
        ).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Publication changed - updating songs")
        ).firstMatch.exists)
        song.tap()
        XCTAssertTrue(app.staticTexts["Intensity"].waitForExistence(timeout: 10))

        let advance = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(port)/__fixture__/advance-publication")
        )
        let (data, response) = try await URLSession.shared.data(from: advance)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(
            try JSONDecoder().decode(FixturePublicationAdvance.self, from: data).publicationId, 8
        )

        rootControl("Settings", app: app).tap()
        let publication = app.buttons["Check Publication"]
        reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "Publication 8; songs live (publication unverified)")

        rootControl("Songs", app: app).tap()
        let notice = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Published scores changed.")
        ).firstMatch
        let noticeAppeared = notice.waitForExistence(timeout: 10)
        if !noticeAppeared {
            record(app, name: "songs-unpinned-rollover-missing-notice")
        }
        XCTAssertTrue(
            noticeAppeared, "Unpinned rollover return: \(app.debugDescription.prefix(2_400))"
        )
        XCTAssertFalse(app.staticTexts["Intensity"].exists)
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        record(app, name: "songs-unpinned-rollover-notice")
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
        let search = app.textFields["fst.profile.search"]
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
        app.buttons["fst.profile.open"].tap()
        let deselect = app.buttons["fst.profile.deselect"]
        XCTAssertTrue(deselect.waitForExistence(timeout: 10))
        deselect.tap()
        let confirmed = try XCTUnwrap(
            app.buttons.matching(identifier: "Deselect Profile")
                .allElementsBoundByIndex.first(where: \.isHittable)
        )
        confirmed.tap()
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

    /// Scroll the modal Form until Reset is above the always-visible action footer.
    ///
    /// - Parameter app: Foreground Songs Sort sheet on phone or tablet.
    /// - Returns: Hittable Reset button within the visible scroll viewport.
    @MainActor
    private func revealSortReset(in app: XCUIApplication) -> XCUIElement {
        let reset = app.buttons["fst.songs.sort.reset"]
        let table = app.tables.containing(.button, identifier: "fst.songs.sort.reset")
            .firstMatch
        let list = table.exists ? table : app.collectionViews.containing(
            .button, identifier: "fst.songs.sort.reset"
        ).firstMatch
        let footer = app.buttons["fst.songs.sort.cancel"]
        XCTAssertTrue(list.exists && footer.exists)
        for _ in 0..<8 {
            if reset.isHittable && reset.frame.maxY <= footer.frame.minY { break }
            list.swipeUp()
        }
        XCTAssertTrue(
            reset.isHittable && reset.frame.maxY <= footer.frame.minY,
            "Reset is hidden by the Sort action footer"
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
        let footer = app.buttons["fst.songs.sort.cancel"]
        XCTAssertTrue(form.exists && footer.exists)
        for _ in 0..<8 {
            if choice.isHittable && choice.frame.maxY <= footer.frame.minY { break }
            form.swipeUp()
        }
        XCTAssertTrue(
            choice.isHittable && choice.frame.maxY <= footer.frame.minY,
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
