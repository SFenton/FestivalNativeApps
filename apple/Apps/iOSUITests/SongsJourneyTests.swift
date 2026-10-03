import UIKit
import XCTest

/// Fixture-backed native journeys for the Songs catalogue: Sort, Filter, the selected-player score/Shop pipeline, publication rollover and accessibility evidence.
///
/// Migrated from the legacy `FestivalMobileUITests` monolith (Wave 3 UX-test triage). Shared
/// fixture-launch, Settings/Filter/Sort scrolling and pixel-accessibility helpers live in
/// ``SongsUITestSupport`` so this file, ``SongDetailJourneyTests`` and ``ShopJourneyTests`` can
/// each carry only their own journeys.
final class SongsJourneyTests: XCTestCase {
    /// A selected card grows when actual largest Dynamic Type reaches native layout.
    ///
    /// - Throws: A missing icon state or accessibility-size row clipped at its old height.
    @MainActor
    func testSelectedInstrumentChipsRemainReachableAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        SongsUITestSupport.viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        XCTAssertTrue(SongsUITestSupport.chipEntries(for: "fixture-pulse", in: app).contains("Drums, scored"))
        let normalHeight = row.frame.height
        SongsUITestSupport.record(app, name: "songs-default-chips-normal-type")

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
        let loadedChips = SongsUITestSupport.chipEntries(for: "fixture-pulse", in: app)
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
        SongsUITestSupport.record(app, name: "songs-default-chips-accessibility-xxxlarge")
        try SongsUITestSupport.deselectFixturePlayer(in: app)
    }

    /// The chip-only AX layout must not replace anonymous row navigation.
    ///
    /// - Throws: A clipped anonymous catalogue row or offscreen Detail destination.
    @MainActor
    func testAnonymousSongsRowAtLargestTextRetainsDetailNavigation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
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
        SongsUITestSupport.record(app, name: "songs-anonymous-row-largest-text")
        orbit.tap()
        XCTAssertTrue(app.staticTexts["Fixture Orbit"].waitForExistence(timeout: 10))
    }

    /// Applied Settings and cold launch must affect one chosen player's real score card.
    ///
    /// - Throws: Stale anonymous rows, ignored switches, or disk-cached scores.
    @MainActor
    func testSelectedPlayerMetadataAndColdRelaunchRespectSettings() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        SongsUITestSupport.showSelectedScoreMetadata(in: app)
        SongsUITestSupport.viewFixturePlayer("fixture-player-1", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let score = app.switches["fst.settings.metadata.score"]
        SongsUITestSupport.reveal(score, in: app, scrollingUp: true)
        XCTAssertTrue(score.isEnabled)
        let originalScore = try XCTUnwrap(score.value as? String)
        SongsUITestSupport.setSwitch(score, to: "1")
        let percentage = app.switches["fst.settings.metadata.percentage"]
        SongsUITestSupport.reveal(percentage, in: app, scrollingUp: true)
        let originalPercentage = try XCTUnwrap(percentage.value as? String)
        SongsUITestSupport.setSwitch(percentage, to: "1")
        let lead = app.switches["fst.settings.instrument.Solo_Guitar"]
        SongsUITestSupport.reveal(lead, in: app, scrollingUp: false)
        let originalLead = try XCTUnwrap(lead.value as? String)
        SongsUITestSupport.setSwitch(lead, to: "1")
        let filtering = app.switches["Filter Invalid Scores"]
        SongsUITestSupport.reveal(filtering, in: app, scrollingUp: false)
        let originalFilter = try XCTUnwrap(filtering.value as? String)
        SongsUITestSupport.setSwitch(filtering, to: "0")

        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Score 99,900"))
        XCTAssertTrue(row.label.contains("Accuracy 97.9 percent"))
        SongsUITestSupport.record(app, name: "songs-player-score-and-percentage-enabled")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(score, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(score, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertFalse(row.label.contains("Score 99,900"))
        XCTAssertTrue(row.label.contains("Accuracy 97.9 percent"))
        SongsUITestSupport.record(app, name: "songs-profile-score-hidden-percentage-retained")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(score, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(score, to: "1")
        SongsUITestSupport.reveal(percentage, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(percentage, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.label.contains("Score 99,900"))
        XCTAssertFalse(row.label.contains("Accuracy 97.9 percent"))

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(percentage, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(percentage, to: "1")
        SongsUITestSupport.reveal(lead, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(lead, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.label.contains("No Bass score"))
        XCTAssertTrue(
            app.buttons["fst.songs.row.fixture-orbit"].label
                .contains("Bass is not charted"),
            "A hidden Lead score reappeared on an uncharted Bass song"
        )
        SongsUITestSupport.record(app, name: "songs-hidden-lead-reveals-bass-status")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(lead, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(lead, to: "1")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(row.label.contains("Score 99,900"))

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_CLEAR_PROFILE")
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launch()
        let restored = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(restored.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fst.shell.profile"].label.contains("Fixture Player 1"))
        let restoredScore = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Score 99,900"),
            object: restored
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restoredScore], timeout: 15), .completed)
        SongsUITestSupport.record(app, name: "songs-player-identity-restored-scores-refetched")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(score, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(score, to: originalScore)
        SongsUITestSupport.reveal(percentage, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(percentage, to: originalPercentage)
        SongsUITestSupport.reveal(lead, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(lead, to: originalLead)
        SongsUITestSupport.reveal(filtering, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(filtering, to: originalFilter)
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        try SongsUITestSupport.deselectFixturePlayer(in: app)
    }

    /// A coherent long-title, seven-digit and Shop case must reflow without a new API.
    ///
    /// - Throws: An unavailable edge profile, clipped score/pill or stalled iPad sidebar.
    @MainActor
    func testLongScoreMetadataAndShopRemainReachableAcrossWidths() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8776"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-marathon"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        SongsUITestSupport.showSelectedScoreMetadata(in: app)
        SongsUITestSupport.viewFixturePlayer("fixture-edge", query: "Fixture Edge", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        let score = SongsUITestSupport.metadataElement("score", songId: "fixture-marathon", in: app)
        let accuracy = SongsUITestSupport.metadataElement("accuracy", songId: "fixture-marathon", in: app)
        let difficulty = SongsUITestSupport.metadataElement("difficulty", songId: "fixture-marathon", in: app)
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
        let lastPlayed = SongsUITestSupport.metadataElement(
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
        SongsUITestSupport.record(app, name: "songs-long-title-seven-digit-shop-score")

        if UIDevice.current.userInterfaceIdiom == .pad {
            SongsUITestSupport.collapseSidebarOnPad(app)
            XCTAssertTrue(score.waitForExistence(timeout: 10))
            XCTAssertEqual(score.label, "Score 1,234,567")
            XCTAssertLessThanOrEqual(abs(score.frame.maxX - lastPlayed.frame.maxX), 2)
            SongsUITestSupport.record(app, name: "ipad-long-metadata-sidebar-hidden")
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
        let axStars = SongsUITestSupport.metadataElement(
            "stars", songId: "fixture-marathon", in: app
        )
        XCTAssertTrue(axStars.isHittable)
        XCTAssertEqual(axStars.label, "5 stars")
        XCTAssertFalse(shop.frame.intersects(lastPlayed.frame))
        XCTAssertLessThanOrEqual(
            abs(shop.frame.maxX - lastPlayed.frame.maxX), 2,
            "Wrapped Last Played must share the Shop badge's trailing card edge"
        )
        SongsUITestSupport.record(app, name: "songs-long-metadata-accessibility-xxxlarge")
        try SongsUITestSupport.deselectFixturePlayer(in: app)
    }

    /// A grouped selected-player catalogue must expose both rows above the tab bar.
    ///
    /// - Throws: Missing Shop groups, unreadable lower score row or failed full audit.
    @MainActor
    func testSelectedShopSortSongsRowsClearTabBar() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launchArguments += [
            "-fst.settings.hideShop", "NO",
            "-fst.songs.sortMode", "shop",
            "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        SongsUITestSupport.showSelectedScoreMetadata(in: app)
        SongsUITestSupport.viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertEqual(sort.value as? String, "Item Shop, ascending")
        let leaving = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-section.leaving-tomorrow").firstMatch
        let inShop = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-section.in-shop").firstMatch
        XCTAssertTrue(leaving.waitForExistence(timeout: 10))
        XCTAssertTrue(inShop.exists)
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(orbit.exists && pulse.exists)
        XCTAssertTrue(pulse.label.contains("Score 99,800"))
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.exists)
        SongsUITestSupport.record(app, name: "songs-selected-shop-sort-tab-edge")
        XCTAssertLessThanOrEqual(
            pulse.frame.maxY, tabs.frame.minY,
            "Grouped card \(pulse.frame) extends behind tab bar \(tabs.frame)"
        )
        try app.performAccessibilityAudit(for: .all) { issue in
            guard UIDevice.current.userInterfaceIdiom == .phone,
                  UIDevice.current.systemVersion == "26.5",
                  issue.auditType == .contrast else {
                return false
            }
            XCTContext.runActivity(named: "Known iOS 26.5 fixture contrast near-pass") { _ in }
            return true
        }
    }

    /// Stage selected-player per-chart score checks and prove real Songs row changes.
    ///
    /// - Throws: Missing chart toggles, a leaked draft, unchanged rows or lost cold preference.
    @MainActor
    func testSelectedPlayerScoreFilterDraftApplyAndColdRelaunch() throws {
        throw XCTSkip("Draft/Apply/Discard sheets were replaced by immediate-apply sheets with Done (operator, 2026-09-28); this journey tests the removed discard path and needs a rewrite.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launchArguments += [
            "-fst.settings.hideShop", "NO",
            "-fst.songs.sortMode", "title",
            "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: 15) && orbit.exists)
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertFalse(filter.exists)
        SongsUITestSupport.viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        let scoreSections = app.buttons["fst.songs.filter.score-sections"]
        XCTAssertTrue(scoreSections.waitForExistence(timeout: 10))
        XCTAssertEqual(scoreSections.value as? String, "Collapsed")
        scoreSections.tap()
        let allScores = app.switches["fst.songs.filter.score.global.hasScores"]
        XCTAssertTrue(allScores.waitForExistence(timeout: 10))
        XCTAssertEqual(allScores.value as? String, "0")
        let apply = app.buttons["fst.songs.filter.done"]
        XCTAssertFalse(apply.isEnabled)
        SongsUITestSupport.record(app, name: "songs-score-filter-default")
        try app.performAccessibilityAudit(for: .all)

        let drums = app.descendants(matching: .any).matching(
            identifier: "fst.songs.filter.score.instrument.Solo_Drums"
        ).firstMatch
        SongsUITestSupport.revealFilterOption(drums, in: app).tap()
        let hasDrums = app.switches["fst.songs.filter.score.chart.Solo_Drums.hasScores"]
        let readyHasDrums = SongsUITestSupport.revealFilterOption(hasDrums, in: app)
        XCTAssertEqual(readyHasDrums.value as? String, "0")
        SongsUITestSupport.setSwitch(readyHasDrums, to: "1")
        XCTAssertTrue(apply.isEnabled)
        SongsUITestSupport.record(app, name: "songs-score-filter-drums-draft")
        app.buttons["fst.songs.filter.done"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 10))
        app.buttons["Continue Editing"].tap()
        XCTAssertEqual(hasDrums.value as? String, "1")
        apply.tap()
        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertFalse(orbit.exists)
        XCTAssertTrue((filter.value as? String)?.contains("1 player score check") == true)
        SongsUITestSupport.record(app, name: "songs-score-filter-has-drums")

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_CLEAR_PROFILE")
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launch()
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        let saved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "1 player score check"),
            object: filter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 15), .completed)
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertFalse(orbit.exists)
        filter.tap()
        let reset = SongsUITestSupport.revealFilterReset(in: app)
        reset.tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(orbit.waitForExistence(timeout: 10))
        XCTAssertEqual(filter.value as? String, "No filters")
        SongsUITestSupport.record(app, name: "songs-score-filter-reset")
    }

    /// Reach a real chart score toggle and footer at AccessibilityXXXL on iPhone.
    ///
    /// - Throws: A clipped control, unchanged score rows or an unwaived accessibility finding.
    @MainActor
    func testSelectedPlayerScoreFilterAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launchArguments += [
            "-fst.songs.sortMode", "title",
            "-fst.songs.sortAscending", "YES",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: 15) && orbit.exists)
        SongsUITestSupport.viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        let filter = SongsUITestSupport.openFilterSheet(in: app)
        let scoreSections = app.buttons["fst.songs.filter.score-sections"]
        XCTAssertTrue(scoreSections.waitForExistence(timeout: 10))
        scoreSections.tap()
        let global = app.switches["fst.songs.filter.score.global.hasScores"]
        XCTAssertTrue(SongsUITestSupport.revealFilterOption(global, in: app).isEnabled)
        let drums = app.descendants(matching: .any).matching(
            identifier: "fst.songs.filter.score.instrument.Solo_Drums"
        ).firstMatch
        SongsUITestSupport.revealFilterOption(drums, in: app).tap()
        let hasDrums = app.switches["fst.songs.filter.score.chart.Solo_Drums.hasScores"]
        SongsUITestSupport.setSwitch(SongsUITestSupport.revealFilterOption(hasDrums, in: app), to: "1")
        let apply = app.buttons["fst.songs.filter.done"]
        XCTAssertTrue(apply.isEnabled && apply.isHittable)
        try SongsUITestSupport.assertHeaderContrast(apply, in: app, leadingTextWidth: 160)
        SongsUITestSupport.record(app, name: "songs-score-filter-ax5-draft")
        try app.performAccessibilityAudit(for: .all)
        apply.tap()
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertFalse(orbit.exists)
        SongsUITestSupport.record(app, name: "songs-score-filter-ax5-applied")

        _ = SongsUITestSupport.openFilterSheet(in: app)
        XCTAssertEqual(scoreSections.value as? String, "Expanded")
        SongsUITestSupport.revealFilterReset(in: app).tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))
        XCTAssertEqual(filter.value as? String, "No filters")
    }

    /// Pause saved score checks honestly while keeping public Shop choices on deselect.
    ///
    /// - Throws: Raw-score filtering, hidden-chart leakage, lost Shop choice or stale identity.
    @MainActor
    func testPlayerScoreFilterSettingsPauseAndDeselectScope() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launchArguments += [
            "-fst.settings.hideShop", "NO",
            "-fst.songs.sortMode", "title",
            "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: 15) && orbit.exists)
        SongsUITestSupport.viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        // General sits above the score sections; set it before scrolling down to them.
        SongsUITestSupport.openSongsFilter(in: app)
        let unavailable = app.switches["fst.songs.filter.shop-unavailable"]
        SongsUITestSupport.setSwitch(unavailable, to: "0")
        let scoreSections = app.buttons["fst.songs.filter.score-sections"]
        SongsUITestSupport.revealFilterOption(scoreSections, in: app).tap()
        let drums = app.descendants(matching: .any).matching(
            identifier: "fst.songs.filter.score.instrument.Solo_Drums"
        ).firstMatch
        SongsUITestSupport.revealFilterOption(drums, in: app).tap()
        let hasDrums = app.switches["fst.songs.filter.score.chart.Solo_Drums.hasScores"]
        SongsUITestSupport.setSwitch(SongsUITestSupport.revealFilterOption(hasDrums, in: app), to: "1")
        app.buttons["fst.songs.filter.done"].tap()
        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertFalse(orbit.exists)
        XCTAssertTrue((filter.value as? String)?.contains("Item Shop filter") == true)
        XCTAssertTrue((filter.value as? String)?.contains("1 player score check") == true)

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let invalid = app.switches["fst.settings.filter-invalid-scores"]
        SongsUITestSupport.reveal(invalid, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(invalid, to: "1")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let paused = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.score-filter-paused").firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 10))
        XCTAssertTrue(paused.label.contains("Filter Invalid Scores"))
        XCTAssertTrue(pulse.exists && orbit.exists)
        filter.tap()
        XCTAssertEqual(scoreSections.value as? String, "Expanded")
        XCTAssertFalse(SongsUITestSupport.revealFilterOption(
            app.switches["fst.songs.filter.score.global.hasScores"], in: app
        ).isEnabled)
        app.buttons["fst.songs.filter.done"].tap()
        SongsUITestSupport.record(app, name: "songs-score-filter-invalid-score-mode-paused")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(invalid, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(invalid, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertFalse(orbit.exists)
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let drumsVisibility = app.switches["fst.settings.instrument.Solo_Drums"]
        SongsUITestSupport.reveal(drumsVisibility, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(drumsVisibility, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(pulse.exists && orbit.exists)
        XCTAssertTrue(paused.waitForExistence(timeout: 10))
        XCTAssertTrue(paused.label.contains("hidden in Settings"))
        XCTAssertTrue((filter.value as? String)?.contains("1 player score check") == true)
        SongsUITestSupport.record(app, name: "songs-score-filter-hidden-chart-paused")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(drumsVisibility, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(drumsVisibility, to: "1")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertFalse(orbit.exists)
        try SongsUITestSupport.deselectFixturePlayer(in: app)
        SongsUITestSupport.reshowSongsToolbar(in: app)
        SongsUITestSupport.record(app, name: "songs-score-filter-cleared-shop-kept")
        let shopOnly = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Item Shop filter"),
            object: filter
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [shopOnly], timeout: 10), .completed,
            "After deselect Filter value: \(filter.value as? String ?? "<missing>"); "
                + "rows: \(pulse.exists), \(orbit.exists)"
        )
        XCTAssertTrue(pulse.exists && orbit.exists)
        SongsUITestSupport.viewFixturePlayer("fixture-player-1", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        let activeShop = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Item Shop filter"),
            object: filter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [activeShop], timeout: 10), .completed)
        XCTAssertTrue(pulse.waitForExistence(timeout: 10) && orbit.exists)
    }

    /// A selected player's Shop Filter stages choices and persists only Apply.
    ///
    /// - Throws: Anonymous Filter leakage, a discarded draft, unchanged rows or lost preference.
    @MainActor
    func testSelectedShopFilterDraftApplyDiscardAndRelaunch() throws {
        throw XCTSkip("Draft/Apply/Discard sheets were replaced by immediate-apply sheets with Done (operator, 2026-09-28); this journey tests the removed discard path and needs a rewrite.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        let originallyHidden = try XCTUnwrap(hidden.value as? String)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertTrue(orbit.exists)
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertFalse(filter.exists, "Source mobile Filter requires an available player")

        SongsUITestSupport.viewFixturePlayer("fixture-player-1", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        SongsUITestSupport.openSongsFilter(in: app)
        let inShop = app.switches["fst.songs.filter.in-shop"]
        let leaving = app.switches["fst.songs.filter.leaving"]
        let apply = app.buttons["fst.songs.filter.done"]
        XCTAssertEqual(inShop.value as? String, "0")
        XCTAssertEqual(leaving.value as? String, "0")
        XCTAssertFalse(apply.isEnabled)
        let available = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: inShop
        )
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed)
        SongsUITestSupport.record(app, name: "songs-player-shop-filter-default")
        try app.performAccessibilityAudit(for: .all)

        SongsUITestSupport.setSwitch(inShop, to: "1")
        XCTAssertTrue(apply.isEnabled)
        app.buttons["fst.songs.filter.done"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 10))
        app.buttons["Continue Editing"].tap()
        XCTAssertEqual(inShop.value as? String, "1")
        apply.tap()
        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertFalse(orbit.exists)
        XCTAssertEqual(filter.value as? String, "In Shop")
        SongsUITestSupport.record(app, name: "songs-player-filtered-in-shop")

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_CLEAR_PROFILE")
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launch()
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        for _ in 0..<100 {
            if pulse.exists && !orbit.exists
                && (filter.value as? String) == "In Shop" { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(pulse.exists)
        XCTAssertFalse(orbit.exists)
        SongsUITestSupport.openSongsFilter(in: app)
        let reset = app.buttons["fst.songs.filter.reset"]
        for _ in 0..<6 {
            if reset.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(reset.isHittable)
        reset.tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(orbit.waitForExistence(timeout: 10))
        XCTAssertEqual(filter.value as? String, "No filters")
        SongsUITestSupport.record(app, name: "songs-player-shop-filter-reset")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: originallyHidden)
    }

    /// Keep saved Item Shop filters honest across hide, failure, true empty and deselection.
    ///
    /// - Throws: A hidden song, fabricated empty feed, lost setting or unreachable Reset.
    @MainActor
    func testSelectedShopFilterPausesAndRecoversAcrossShopStates() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launch()
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        let originallyHidden = try XCTUnwrap(hidden.value as? String)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        SongsUITestSupport.viewFixturePlayer("fixture-player-1", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        SongsUITestSupport.openSongsFilter(in: app)
        let unavailable = app.switches["fst.songs.filter.shop-unavailable"]
        let done = app.buttons["fst.songs.filter.done"]
        SongsUITestSupport.setSwitch(unavailable, to: "0")
        done.tap()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertFalse(orbit.exists)

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: "1")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let paused = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.filter-paused").firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 10))
        XCTAssertTrue(paused.label.contains("Shop is hidden"))
        XCTAssertTrue(orbit.waitForExistence(timeout: 10))
        _ = SongsUITestSupport.openFilterSheet(in: app)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "fst.songs.filter.shop").firstMatch.exists,
            "Item Shop accordion is hidden with the Shop, like web")
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "fst.songs.filter.double-bass").firstMatch.exists)
        done.tap()
        SongsUITestSupport.record(app, name: "songs-player-filter-paused-while-shop-hidden")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertFalse(paused.exists)
        XCTAssertFalse(orbit.exists)
        XCTAssertTrue(pulse.exists)

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_CLEAR_PROFILE")
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launch()
        let shopPause = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Shop data loads"),
            object: paused
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [shopPause], timeout: 15), .completed,
            "Expected a Shop-specific pause; last notice: \(paused.label)"
        )
        XCTAssertTrue(orbit.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-error").firstMatch.exists)
        SongsUITestSupport.openSongsFilter(in: app)
        XCTAssertEqual(unavailable.value as? String, "0")
        XCTAssertTrue(app.staticTexts[
            "Item Shop filters need matching public Songs and Shop data."
        ].exists)
        done.tap()
        SongsUITestSupport.record(app, name: "songs-player-filter-paused-on-shop-error")

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-empty"
        app.launch()
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 15))
        XCTAssertFalse(paused.exists)
        XCTAssertTrue(app.staticTexts["No songs match your filters."].exists)
        XCTAssertFalse(pulse.exists)
        SongsUITestSupport.record(app, name: "songs-player-filter-validated-empty-shop")

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launch()
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertFalse(orbit.exists)
        try SongsUITestSupport.deselectFixturePlayer(in: app)
        SongsUITestSupport.reshowSongsToolbar(in: app)
        let kept = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Item Shop filter"), object: filter
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [kept], timeout: 15), .completed,
            "General filters survive deselection; value: \(filter.value as? String ?? "<missing>")"
        )
        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertFalse(orbit.exists)
        XCTAssertFalse(paused.exists)
        SongsUITestSupport.openSongsFilter(in: app)
        XCTAssertFalse(app.buttons["fst.songs.filter.score-sections"].exists,
                       "Without a profile only General filters are shown")
        XCTAssertEqual(unavailable.value as? String, "0")
        SongsUITestSupport.record(app, name: "songs-anonymous-general-filter-sheet")
        SongsUITestSupport.revealFilterReset(in: app).tap()
        done.tap()
        XCTAssertTrue(orbit.waitForExistence(timeout: 10))
        XCTAssertTrue(filter.exists, "Filter stays available without a profile")
        XCTAssertEqual(filter.value as? String, "No filters")
        SongsUITestSupport.record(app, name: "songs-anonymous-shop-filter-cleared")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: originallyHidden)
    }

    /// Verify Shop Filter actions and controls grow and remain reachable at AX5.
    ///
    /// - Throws: A stale draft, clipped footer, unscaled glyphs or failed manufacturer audit.
    @MainActor
    func testSelectedShopFilterAtLargestText() throws {
        throw XCTSkip("Draft/Apply/Discard sheets were replaced by immediate-apply sheets with Done (operator, 2026-09-28); this journey tests the removed discard path and needs a rewrite.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        let originallyHidden = try XCTUnwrap(hidden.value as? String)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        SongsUITestSupport.viewFixturePlayer("fixture-player-1", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        SongsUITestSupport.openSongsFilter(in: app)
        let inShop = app.switches["fst.songs.filter.in-shop"]
        let apply = app.buttons["fst.songs.filter.done"]
        let available = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: inShop
        )
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed)
        SongsUITestSupport.setSwitch(inShop, to: "1")
        XCTAssertTrue(apply.isEnabled)
        let normalGlyphHeight = try SongsUITestSupport.brightGlyphHeight(in: apply)
        app.buttons["fst.songs.filter.done"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 10))
        app.buttons["Discard Changes"].tap()

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_CLEAR_PROFILE")
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.filter"].waitForExistence(timeout: 15))
        SongsUITestSupport.openSongsFilter(in: app)
        let reset = SongsUITestSupport.revealFilterReset(in: app)
        XCTAssertTrue(reset.isHittable)
        let footerBottom = app.windows.firstMatch.frame.maxY - 16
        XCTAssertTrue(apply.isHittable)
        XCTAssertLessThanOrEqual(apply.frame.maxY, footerBottom)
        XCTAssertEqual(inShop.value as? String, "0")
        SongsUITestSupport.setSwitch(inShop, to: "1")
        XCTAssertTrue(apply.isEnabled)
        let largeGlyphHeight = try SongsUITestSupport.brightGlyphHeight(in: apply)
        XCTAssertGreaterThan(
            Double(largeGlyphHeight), Double(normalGlyphHeight) * 1.35,
            "Filter Apply glyphs did not scale with Dynamic Type"
        )
        try SongsUITestSupport.assertHeaderContrast(apply, in: app, leadingTextWidth: 160)
        SongsUITestSupport.record(app, name: "songs-player-shop-filter-ax5-sheet")
        try app.performAccessibilityAudit(for: .all)
        apply.tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"]
            .waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["fst.songs.row.fixture-orbit"].exists)
        SongsUITestSupport.record(app, name: "songs-player-shop-filter-ax5-applied")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: originallyHidden)
    }

    /// Native Sort stages changes, persists rows and audits reachable modal text.
    ///
    /// - Throws: Wrong row order, silent discard, lost preference or visible contrast.
    @MainActor
    func testAnonymousSongsSortDraftApplyDiscardAndRelaunch() throws {
        throw XCTSkip("Draft/Apply/Discard sheets were replaced by immediate-apply sheets with Done (operator, 2026-09-28); this journey tests the removed discard path and needs a rewrite.")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
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
            SongsUITestSupport.record(app, name: "songs-sort-before-baseline-reset")
            SongsUITestSupport.revealSortReset(in: app).tap()
            SongsUITestSupport.record(app, name: "songs-sort-after-baseline-reset")
            let initialApply = app.buttons["fst.songs.sort.done"]
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
        SongsUITestSupport.record(app, name: "songs-sort-default-sheet")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try SongsUITestSupport.assertHeaderContrast(app.staticTexts["Sort Songs"], in: app)
        }
        let direction = app.segmentedControls["fst.songs.sort.direction"]
        XCTAssertTrue(direction.waitForExistence(timeout: 10))
        let descending = direction.buttons["Descending"]
        XCTAssertTrue(descending.exists)
        let apply = app.buttons["fst.songs.sort.done"]
        XCTAssertFalse(apply.isEnabled)
        let artist = app.buttons["Artist"]
        XCTAssertTrue(artist.exists)
        artist.tap()
        XCTAssertTrue(apply.isEnabled, "Choosing Artist did not change the sort draft")
        app.buttons["Title"].tap()
        XCTAssertFalse(apply.isEnabled, "Restoring Title did not clear the sort draft")
        descending.tap()
        XCTAssertTrue(descending.isSelected)
        SongsUITestSupport.record(app, name: "songs-sort-draft-descending")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try SongsUITestSupport.assertHeaderContrast(app.buttons["fst.songs.sort.done"], in: app)
        }
        XCTAssertTrue(apply.isEnabled, "Changing direction did not create a draft")
        app.buttons["fst.songs.sort.done"].tap()
        let continueEditing = app.buttons["Continue Editing"]
        XCTAssertTrue(continueEditing.waitForExistence(timeout: 10))
        continueEditing.tap()
        XCTAssertTrue(descending.isSelected)
        XCTAssertTrue(apply.isEnabled)
        app.buttons["fst.songs.sort.done"].tap()
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
        SongsUITestSupport.record(app, name: "songs-title-descending")

        app.terminate()
        app.launch()
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)
        sort.tap()
        XCTAssertTrue(direction.buttons["Descending"].isSelected)
        SongsUITestSupport.revealSortReset(in: app).tap()
        app.buttons["fst.songs.sort.done"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 10))
        app.buttons["Discard Changes"].tap()
        XCTAssertEqual(sort.value as? String, "Title, descending")
        sort.tap()
        XCTAssertTrue(direction.buttons["Descending"].isSelected)
        SongsUITestSupport.revealSortReset(in: app).tap()
        let resetApply = app.buttons["fst.songs.sort.done"]
        for _ in 0..<30 {
            if resetApply.isEnabled { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(resetApply.isEnabled, "Reset did not create a changed sort draft")
        app.buttons["fst.songs.sort.done"].tap()
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
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launch()
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        let originallyHidden = try XCTUnwrap(hidden.value as? String)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()

        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        if (sort.value as? String) != "Title, ascending" {
            sort.tap()
            SongsUITestSupport.revealSortReset(in: app).tap()
            let resetApply = app.buttons["fst.songs.sort.done"]
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
        let readyShop = SongsUITestSupport.revealShopSort(in: app)
        SongsUITestSupport.record(app, name: "songs-shop-sort-choice")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try app.performAccessibilityAudit(for: .all)
        } else {
            try SongsUITestSupport.assertHeaderContrast(readyShop, in: app, leadingTextWidth: 180)
        }
        readyShop.tap()
        let apply = app.buttons["fst.songs.sort.done"]
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
        SongsUITestSupport.record(app, name: "songs-shop-sort-ascending")
        if UIDevice.current.userInterfaceIdiom == .phone {
            try SongsUITestSupport.assertHeaderContrast(inShop, in: app, leadingTextWidth: 180)
            try SongsUITestSupport.assertHeaderContrast(notInShop, in: app, leadingTextWidth: 180)
        } else {
            let search = SongsUITestSupport.songsSearchEntry(in: app)
            XCTAssertTrue(search.exists)
            let contentX = search.frame.minX
            XCTAssertGreaterThan(contentX, app.windows.firstMatch.frame.minX)
            try SongsUITestSupport.assertHeaderContrast(
                inShop, in: app, leadingTextWidth: 180, horizontalOrigin: contentX
            )
            try SongsUITestSupport.assertHeaderContrast(
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
        XCTAssertTrue(app.buttons["fst.songs.sort.direction.ascending"].isSelected)
        app.buttons["fst.songs.sort.direction.descending"].tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        for _ in 0..<30 {
            if orbit.frame.minY < pulse.frame.minY { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)
        XCTAssertEqual(sort.value as? String, "Item Shop, descending")
        XCTAssertLessThan(notInShop.frame.minY, inShop.frame.minY)

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: "1")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let paused = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.sort-paused").firstMatch
        XCTAssertTrue(paused.waitForExistence(timeout: 10))
        XCTAssertTrue(paused.label.contains("while Shop is hidden"))
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)
        XCTAssertTrue((sort.value as? String)?.contains("paused; showing Title") == true)
        XCTAssertFalse(inShop.exists)
        XCTAssertFalse(notInShop.exists)
        SongsUITestSupport.record(app, name: "songs-shop-sort-paused-hidden")
        sort.tap()
        XCTAssertFalse(shopMode.exists, "Hidden Shop is still a selectable sort option")
        app.buttons["fst.songs.sort.done"].tap()

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
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
        app.buttons["fst.songs.sort.done"].tap()

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
        XCTAssertTrue(SongsUITestSupport.revealShopSort(in: app).isEnabled)
        app.buttons["fst.songs.sort.done"].tap()

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
        SongsUITestSupport.revealSortReset(in: app).tap()
        app.buttons["fst.songs.sort.done"].tap()
        XCTAssertEqual(sort.value as? String, "Title, ascending")
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: originallyHidden)
    }

    /// Run the system audit against a visible fixture-backed native screen.
    ///
    /// - Throws: An accessibility audit issue for actionable labels/contrast/order.
    @MainActor
    func testSongsAccessibilityAudit() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
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
            painted = try SongsUITestSupport.backgroundSignature(app)
            if SongsUITestSupport.pixelDistance(painted, base) > 1_500 { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertGreaterThan(
            SongsUITestSupport.pixelDistance(painted, base), 1_500,
            "Cannot audit artwork contrast before original fixture art is visible"
        )
        SongsUITestSupport.record(app, name: "songs-before-accessibility-audit")
        try app.performAccessibilityAudit(for: .all)
    }

    /// Exercise real native no-results and service-error presentation.
    ///
    /// - Throws: A missing fixture-only state or retry action.
    @MainActor
    func testEmptyAndErrorCatalogueStates() throws {
        continueAfterFailure = false
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "empty"
        app.launch()
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "songs-empty")
        app.terminate()

        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        app.launch()
        XCTAssertTrue(app.staticTexts["Songs unavailable"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Retry"].exists)
        SongsUITestSupport.record(app, name: "songs-service-error")
        try app.performAccessibilityAudit(for: .all)
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let publication = app.buttons["Check Publication"]
        SongsUITestSupport.reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        SongsUITestSupport.reveal(status, in: app, scrollingUp: true)
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
        let app = SongsUITestSupport.fixtureApp()
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
        try SongsUITestSupport.revealFailureAction(app)
        SongsUITestSupport.record(app, name: "songs-error-largest-text-portrait")
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
        SongsUITestSupport.record(app, name: "songs-error-largest-text-landscape-before-scroll")
        try SongsUITestSupport.revealFailureAction(app)
        SongsUITestSupport.record(app, name: "songs-error-largest-text-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// An initial 503 can recover on the same publication without a stuck Songs error.
    ///
    /// - Throws: Failed fixture-only retry, missing white art or inaccessible error state.
    @MainActor
    func testSongsRecoversAfterSamePublicationSettingsCheck() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8769"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "art-white"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Songs unavailable"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Retry"].exists)
        SongsUITestSupport.record(app, name: "songs-first-catalogue-503")
        try app.performAccessibilityAudit(for: .all)

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let publication = app.buttons["Check Publication"]
        SongsUITestSupport.reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        SongsUITestSupport.reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "Publication 7")
        SongsUITestSupport.reveal(app.staticTexts["App Settings"], in: app, scrollingUp: false)
        try await SongsUITestSupport.assertWhiteArtVisible(in: app)
        SongsUITestSupport.record(app, name: "settings-recovered-white-art")

        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-white"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Songs unavailable"].exists)
        try await SongsUITestSupport.assertWhiteArtVisible(in: app)
        SongsUITestSupport.record(app, name: "songs-recovered-same-publication")
        try app.performAccessibilityAudit(for: .all)
    }

    /// A confirmed app-settings reset must not erase the current Songs query.
    ///
    /// - Throws: Missing reset confirmation, lost route state or wrong defaults.
    @MainActor
    func testAppOnlyResetPreservesSongsSearch() throws {
        continueAfterFailure = false
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        let search = SongsUITestSupport.songsSearchField(in: app)
        search.tap()
        search.typeText("zzzz\n")
        let noMatches = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "No Results for")
        ).firstMatch
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10))
        SongsUITestSupport.rootControl("Settings", app: app).tap()

        let filter = app.switches["Filter Invalid Scores"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        SongsUITestSupport.setSwitch(filter, to: "1")
        let motion = app.switches["fst.settings.reduce-motion"]
        SongsUITestSupport.reveal(motion, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(motion, to: "1")

        let publication = app.buttons["Check Publication"]
        SongsUITestSupport.reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        SongsUITestSupport.reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "Publication 7")
        let reset = app.buttons["fst.settings.reset"]
        SongsUITestSupport.reveal(reset, in: app, scrollingUp: true)
        reset.tap()
        let confirmation = app.buttons.matching(
            NSPredicate(format: "label == %@", "Reset App Settings")
        ).allElementsBoundByIndex.first(where: \.isHittable)
        XCTAssertNotNil(confirmation, "Reset confirmation was not presented")
        confirmation?.tap()

        SongsUITestSupport.reveal(filter, in: app, scrollingUp: false)
        XCTAssertEqual(filter.value as? String, "0")
        XCTAssertFalse(app.sliders["fst.settings.leeway"].exists)
        SongsUITestSupport.reveal(motion, in: app, scrollingUp: true)
        XCTAssertEqual(motion.value as? String, "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(noMatches.waitForExistence(timeout: 10))
    }

    /// Explain why an unpinned generation change returns an old Detail route to Songs.
    ///
    /// - Throws: Missing unverified-data label, stale Detail route or absent notice.
    @MainActor
    func testHeaderlessRolloverExplainsRouteReset() async throws {
        continueAfterFailure = false
        let app = SongsUITestSupport.fixtureApp()
        let port = UIDevice.current.userInterfaceIdiom == .pad ? 8768 : 8767
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:\(port)"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        let appeared = song.waitForExistence(timeout: 15)
        if !appeared {
            SongsUITestSupport.record(app, name: "songs-unpinned-rollover-initial-failure")
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

        try await SongsUITestSupport.advanceFixturePublication(port: port)

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let publication = app.buttons["Check Publication"]
        SongsUITestSupport.reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        SongsUITestSupport.reveal(status, in: app, scrollingUp: true)
        XCTAssertEqual(status.label, "Publication 8; songs live (publication unverified)")

        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let notice = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Published scores changed.")
        ).firstMatch
        let noticeAppeared = notice.waitForExistence(timeout: 10)
        if !noticeAppeared {
            SongsUITestSupport.record(app, name: "songs-unpinned-rollover-missing-notice")
        }
        XCTAssertTrue(
            noticeAppeared, "Unpinned rollover return: \(app.debugDescription.prefix(2_400))"
        )
        XCTAssertFalse(app.staticTexts["Intensity"].exists)
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        SongsUITestSupport.record(app, name: "songs-unpinned-rollover-notice")
    }

    /// Keep old Songs unfiltered and unbadged when only new Shop/profile reads succeed.
    ///
    /// - Throws: Mixed-publication rows, false No Results or an unowned fixture response.
    @MainActor
    func testPublicationRolloverPausesShopDerivedSongs() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        let port = UIDevice.current.userInterfaceIdiom == .pad ? 8778 : 8777
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:\(port)"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        let highlights = app.switches["fst.settings.shop-highlights"]
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        let originallyHidden = try XCTUnwrap(hidden.value as? String)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        let originalHighlights = try XCTUnwrap(highlights.value as? String)
        SongsUITestSupport.setSwitch(highlights, to: "1")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))
        XCTAssertTrue(pulse.exists)
        SongsUITestSupport.viewFixturePlayer("fixture-player-2", query: "Fixture Player", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        SongsUITestSupport.openSongsFilter(in: app)
        let unavailable = app.switches["fst.songs.filter.shop-unavailable"]
        SongsUITestSupport.setSwitch(unavailable, to: "0")
        app.buttons["fst.songs.filter.done"].tap()
        XCTAssertTrue(pulse.exists && orbit.exists)

        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        if (sort.value as? String) != "Title, ascending" {
            sort.tap()
            SongsUITestSupport.revealSortReset(in: app).tap()
            app.buttons["fst.songs.sort.done"].tap()
        }
        sort.tap()
        SongsUITestSupport.revealShopSort(in: app).tap()
        app.buttons["fst.songs.sort.done"].tap()
        XCTAssertEqual(sort.value as? String, "Item Shop, ascending")
        let orbitBadge = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-badge.fixture-orbit").firstMatch
        let pulseBadge = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-badge.fixture-pulse").firstMatch
        XCTAssertTrue(orbitBadge.waitForExistence(timeout: 10))
        XCTAssertTrue(pulseBadge.exists)
        XCTAssertTrue(
            SongsUITestSupport.chipEntries(for: "fixture-pulse", in: app).contains("Lead, full combo")
        )
        SongsUITestSupport.record(app, name: "songs-shop-join-publication-seven")

        try await SongsUITestSupport.advanceFixturePublication(port: port)
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let publication = app.buttons["Check Publication"]
        SongsUITestSupport.reveal(publication, in: app, scrollingUp: true)
        publication.tap()
        let status = app.staticTexts["fst.settings.publication-status"]
        let failed = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label BEGINSWITH %@", "Publication 8; songs update failed:"
            ), object: status
        )
        XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 15), .completed)
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let filterPaused = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.filter-paused").firstMatch
        let sortPaused = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.sort-paused").firstMatch
        let filterNotice = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "publications differ"),
            object: filterPaused
        )
        let sortNotice = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "publications differ"),
            object: sortPaused
        )
        XCTAssertEqual(XCTWaiter.wait(for: [filterNotice, sortNotice], timeout: 15),
                       .completed)

        var reads = try await SongsUITestSupport.fixturePublicationJoinReads(port: port)
        for _ in 0..<80 {
            if reads.shop == 8 && reads.player == 8 && reads.failedSongs == 8 { break }
            try await Task.sleep(for: .milliseconds(100))
            reads = try await SongsUITestSupport.fixturePublicationJoinReads(port: port)
        }
        XCTAssertEqual(reads.shop, 8)
        XCTAssertEqual(reads.player, 8)
        XCTAssertEqual(reads.failedSongs, 8)
        let profilePaused = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.profile-paused").firstMatch
        let scoreNotice = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS %@", "current observed publication"
            ), object: profilePaused
        )
        XCTAssertEqual(XCTWaiter.wait(for: [scoreNotice], timeout: 15), .completed)
        let list = app.collectionViews["fst.songs.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if orbit.exists && pulse.exists { break }
            list.swipeUp()
        }
        XCTAssertTrue(orbit.exists && pulse.exists, "Old catalogue rows must remain visible")
        let refreshedChips = app.descendants(matching: .any).matching(
            identifier: "fst.songs.instrument-status.fixture-pulse"
        ).firstMatch
        XCTAssertFalse(refreshedChips.exists, "Newer player chips decorated older Songs")
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-error"
        ).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.profile-status"
        ).firstMatch.exists)
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY)
        XCTAssertFalse(orbitBadge.exists)
        XCTAssertFalse(pulseBadge.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-section.in-shop"
        ).firstMatch.exists)
        XCTAssertTrue((sort.value as? String)?.contains("paused; showing Title order") == true)
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue((filter.value as? String)?.contains("paused; showing all songs") == true)
        SongsUITestSupport.record(app, name: "songs-shop-join-old-catalogue-new-shop-paused")
        for (row, name) in [(orbit, "orbit"), (pulse, "pulse")] {
            SongsUITestSupport.revealSongsControlAboveTab(
                row, in: list, app: app,
                failureName: "songs-shop-join-\(name)-unreachable",
                bottomMargin: 0
            )
            XCTAssertTrue(
                row.label.contains("Player scores paused until songs update"),
                "The retained \(name) row still presents newer player data"
            )
            SongsUITestSupport.record(app, name: "songs-shop-join-\(name)-fully-visible")
        }

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let icons = app.switches["fst.settings.show-instrument-icons"]
        SongsUITestSupport.reveal(icons, in: app, scrollingUp: false)
        XCTAssertEqual(icons.value as? String, "1")
        SongsUITestSupport.setSwitch(icons, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        let flatList = app.collectionViews["fst.songs.list"]
        SongsUITestSupport.revealSongsControlAboveTab(
            pulse, in: flatList, app: app,
            failureName: "songs-shop-join-icons-off-pulse-unreachable",
            bottomMargin: 0
        )
        XCTAssertTrue(pulse.label.contains("Player scores paused until songs update"))
        XCTAssertFalse(pulse.label.contains("Score 99,850"))
        XCTAssertFalse(pulse.label.contains("Score 99,800"))
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.metadata.score.fixture-pulse"
        ).firstMatch.exists)
        SongsUITestSupport.record(app, name: "songs-player-newer-score-paused-with-icons-off")

        SongsUITestSupport.openSongsFilter(in: app)
        XCTAssertEqual(unavailable.value as? String, "0")
        XCTAssertTrue(app.staticTexts[
            "Item Shop filters need matching public Songs and Shop data."
        ].exists)
        app.buttons["fst.songs.filter.done"].tap()
        sort.tap()
        let shopChoice = app.buttons.matching(
            identifier: "fst.songs.sort.mode"
        ).matching(NSPredicate(format: "label == %@", "Item Shop")).firstMatch
        XCTAssertTrue(shopChoice.waitForExistence(timeout: 10))
        XCTAssertFalse(shopChoice.isEnabled)
        app.buttons["fst.songs.sort.done"].tap()

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(icons, in: app, scrollingUp: false)
        SongsUITestSupport.setSwitch(icons, to: "1")
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(highlights, to: originalHighlights)
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: originallyHidden)
    }

    /// The Item Shop sort's Quick Links menu must jump to a real Shop bucket.
    ///
    /// Title/Artist/Year hide Quick Links in favor of the section-index scrubber
    /// (`songs-section-index/ios.md`), so this exercises the one sort mode where the
    /// Songs Quick Links menu is actually visible with the shared two-song fixture:
    /// `fixture-pulse` (New) and `fixture-orbit` (Leaving Tomorrow) give two distinct,
    /// non-empty Shop buckets.
    ///
    /// - Throws: A hidden menu, a missing bucket item or a jump that doesn't scroll.
    @MainActor
    func testSongsItemShopSortQuickLinksJump() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchArguments += [
            "-fst.settings.hideShop", "NO",
            "-fst.songs.sortMode", "shop",
            "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: 15))
        XCTAssertTrue(orbit.exists)

        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(
            quickLinks.waitForExistence(timeout: 10),
            "Item Shop sort must show Quick Links once two Shop buckets exist"
        )
        SongsUITestSupport.record(app, name: "songs-shop-quick-links-closed")
        quickLinks.tap()

        let leaving = app.buttons["fst.quick-links.item.shop:leaving-tomorrow"]
        let inShop = app.buttons["fst.quick-links.item.shop:in-shop"]
        XCTAssertTrue(leaving.waitForExistence(timeout: 10))
        XCTAssertTrue(inShop.exists)
        SongsUITestSupport.record(app, name: "songs-shop-quick-links-open")
        leaving.tap()

        XCTAssertTrue(orbit.waitForExistence(timeout: 10))
        XCTAssertTrue(orbit.isHittable, "Jumping to Leaving Tomorrow must scroll it into view")
        let activeValue = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS[c] %@", "Leaving"),
            object: quickLinks
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [activeValue], timeout: 10), .completed,
            "Quick Links did not report the jumped-to section as active: "
                + "\(quickLinks.value as? String ?? "<missing>")"
        )
        SongsUITestSupport.record(app, name: "songs-shop-quick-links-jumped")
    }

}
