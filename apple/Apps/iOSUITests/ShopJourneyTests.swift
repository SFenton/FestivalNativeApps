import UIKit
import XCTest

/// Fixture-backed native journeys for the Item Shop: public offers, Song Detail hand-off, empty/error states and Settings hide/highlight propagation.
///
/// Migrated from the legacy `FestivalMobileUITests` monolith (Wave 3 UX-test triage). Shared
/// fixture-launch, Settings/Filter/Sort scrolling and pixel-accessibility helpers live in
/// ``SongsUITestSupport`` so this file, ``SongDetailJourneyTests`` and ``ShopJourneyTests`` can
/// each carry only their own journeys.
final class ShopJourneyTests: XCTestCase {
    /// A public Shop feed opens without adding a fourth compact tab.
    ///
    /// - Throws: Missing real fixture offers, unsafe outbound action or broken Song Detail.
    @MainActor
    func testPublicShopOffersAndSongDetailNavigation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        SongsUITestSupport.openItemShop(in: app)
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
            // The Shop opens inside Songs navigation, never as its own compact tab.
            let shopTab = app.tabBars.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Shop")
            )
            XCTAssertEqual(shopTab.count, 0)
            XCTAssertTrue(app.tabBars.buttons["Songs"].exists)
        }
        SongsUITestSupport.record(app, name: "shop-populated-offers")
        try app.performAccessibilityAudit(for: .all)
        let detail = app.buttons["fst.shop.song.fixture-pulse"]
        XCTAssertTrue(detail.waitForExistence(timeout: 10))
        detail.tap()
        XCTAssertTrue(app.staticTexts["Intensity"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["fst.song-detail.paths"].exists)
    }

    /// Issues #19, #376: the Filter sheet starts with every switch on, turning one off hides
    /// that group live, the sheet reopens with its saved state and Reset turns them back on.
    ///
    /// - Throws: A missing Filter action, switches that do not filter, lost state or a broken Reset.
    @MainActor
    func testShopFilterSheetNarrowsOffersAndResets() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        SongsUITestSupport.openItemShop(in: app)
        let pulse = app.buttons["fst.shop.song.fixture-pulse"]
        let orbit = app.buttons["fst.shop.song.fixture-orbit"]
        let filter = app.buttons["fst.shop.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 15))
        XCTAssertEqual(filter.label, "Filter Item Shop")

        filter.tap()
        let reset = app.buttons["fst.shop.filter.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        reset.tap()
        let new = app.switches["fst.shop.filter.new"]
        let available = app.switches["fst.shop.filter.available"]
        let leaving = app.switches["fst.shop.filter.leavingTomorrow"]
        XCTAssertEqual(new.label, "New")
        XCTAssertEqual(available.label, "Available")
        XCTAssertEqual(leaving.label, "Leaving Tomorrow")
        for toggle in [new, available, leaving] {
            XCTAssertEqual(toggle.value as? String, "1", "\(toggle.label) did not start on")
        }
        try app.performAccessibilityAudit(for: .all)
        SongsUITestSupport.setSwitch(leaving, to: "0")
        SongsUITestSupport.record(app, name: "shop-filter-sheet-hide-leaving")
        app.buttons["fst.shop.filter.done"].tap()

        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertFalse(orbit.exists, "Leaving Tomorrow switched off left its offer visible")
        XCTAssertEqual(filter.value as? String, "Hiding Leaving Tomorrow")

        filter.tap()
        XCTAssertTrue(leaving.waitForExistence(timeout: 10))
        XCTAssertEqual(leaving.value as? String, "0", "Reopened sheet lost the hidden group")
        XCTAssertEqual(new.value as? String, "1")
        SongsUITestSupport.setSwitch(new, to: "0")
        app.buttons["fst.shop.filter.done"].tap()
        // Shared centred empty state (issue #377): web-modelled copy, no Reset button.
        let empty = app.descendants(matching: .any)
            .matching(identifier: "fst.shop.filter-empty").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No Item Shop songs match your filters"].exists)
        XCTAssertFalse(app.buttons["Reset Filters"].exists)
        XCTAssertFalse(pulse.exists)
        XCTAssertFalse(orbit.exists)
        SongsUITestSupport.record(app, name: "shop-filter-no-matches")
        // The empty state is text on the page background (no card). The auditor flags its
        // wrapped white subtitle on the near-black gradient, so measure the composited
        // pixels for contrast issues instead, like Song Detail's band preview.
        try app.performAccessibilityAudit(for: .all) { issue in
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            try SongsUITestSupport.assertHeaderContrast(element, in: app)
            return true
        }

        // The way back is the Filter button's own sheet.
        filter.tap()
        let sheetReset = app.buttons["fst.shop.filter.reset"]
        XCTAssertTrue(sheetReset.waitForExistence(timeout: 10))
        sheetReset.tap()
        if app.buttons["fst.shop.filter.done"].exists { app.buttons["fst.shop.filter.done"].tap() }
        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertTrue(orbit.exists)
        XCTAssertEqual(filter.value as? String, "No filters")
    }

    /// Issue #379: the Shop's Sort sheet offers Songs' Title, Artist, Year and Duration
    /// modes with a direction, reorders the offers live, survives a relaunch and resets.
    ///
    /// - Throws: Missing modes, an order that ignores the sort, a lost choice or a broken Reset.
    @MainActor
    func testShopSortReordersOffersAndPersists() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        SongsUITestSupport.openItemShop(in: app)
        let pulse = app.buttons["fst.shop.song.fixture-pulse"]
        let orbit = app.buttons["fst.shop.song.fixture-orbit"]
        let sort = app.buttons["fst.shop.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))
        XCTAssertEqual(sort.label, "Sort Item Shop")

        sort.tap()
        let reset = SongsUITestSupport.revealSheetReset(
            "fst.shop.sort.reset", cancelId: "fst.shop.sort.done", sheetName: "Shop Sort", in: app
        )
        reset.tap()
        let modes = app.buttons.matching(identifier: "fst.shop.sort.mode")
        let labels = modes.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels, ["Title", "Artist", "Year", "Duration"])
        try app.performAccessibilityAudit(for: .all)
        app.buttons["fst.shop.sort.direction.descending"].tap()
        SongsUITestSupport.record(app, name: "shop-sort-sheet-title-descending")
        app.buttons["fst.shop.sort.done"].tap()

        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertEqual(sort.value as? String, "Title, descending")
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY, "Title Z–A left Orbit first")

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "FST_UI_TEST_RESET_SONG_CARDS")
        app.launch()
        SongsUITestSupport.openItemShop(in: app)
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))
        XCTAssertEqual(sort.value as? String, "Title, descending", "Relaunch lost the Shop sort")
        XCTAssertLessThan(pulse.frame.minY, orbit.frame.minY)

        sort.tap()
        SongsUITestSupport.revealSheetReset(
            "fst.shop.sort.reset", cancelId: "fst.shop.sort.done", sheetName: "Shop Sort", in: app
        ).tap()
        app.buttons["fst.shop.sort.done"].tap()
        XCTAssertTrue(orbit.waitForExistence(timeout: 10))
        XCTAssertEqual(sort.value as? String, "Title, ascending")
        XCTAssertLessThan(orbit.frame.minY, pulse.frame.minY, "Reset left Title Z–A")
    }

    /// PWA parity (gap #17): compact two-line rows with the bag before the chevron,
    /// as sibling actions of one row.
    ///
    /// - Throws: A tall row, a bag after the chevron slot or a nested action.
    @MainActor
    func testShopRowsAreCompactWithBagBeforeChevron() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        SongsUITestSupport.openItemShop(in: app)
        let row = app.buttons["fst.shop.song.fixture-pulse"]
        let bag = app.buttons["fst.shop.external.fixture-pulse"]
        let badge = app.descendants(matching: .any)
            .matching(identifier: "fst.shop.badge.new.fixture-pulse").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(bag.exists && bag.isHittable)
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        XCTAssertLessThanOrEqual(row.frame.height, 72, "Shop row is not compact")
        XCTAssertGreaterThanOrEqual(bag.frame.width, 44)
        XCTAssertGreaterThanOrEqual(bag.frame.height, 44)
        XCTAssertGreaterThan(bag.frame.minX, badge.frame.maxX - 1, "Badge must precede the bag")
        XCTAssertGreaterThan(
            row.frame.maxX - bag.frame.maxX, 16,
            "No chevron slot after the bag"
        )
        XCTAssertFalse(
            bag.label.contains("Synthetic Quartet"),
            "Bag must be its own action, not part of the Detail row"
        )
        SongsUITestSupport.record(app, name: "shop-compact-rows")
    }

    /// Empty Shop and a real service failure must never look like the same state.
    ///
    /// - Throws: Hidden empty text, silent HTTP error or unreadable Retry action.
    @MainActor
    func testPublicShopEmptyAndErrorStayDistinct() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "empty"
        app.launch()
        SongsUITestSupport.openItemShop(in: app)
        XCTAssertTrue(app.staticTexts["No songs in the Item Shop"]
            .waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Item Shop unavailable"].exists)
        SongsUITestSupport.record(app, name: "shop-genuinely-empty")
        try app.performAccessibilityAudit(for: .all)

        app.terminate()
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "error"
        app.launch()
        SongsUITestSupport.openItemShop(in: app)
        XCTAssertTrue(app.staticTexts["Item Shop unavailable"]
            .waitForExistence(timeout: 15))
        let retry = app.buttons["Retry"]
        XCTAssertTrue(retry.isHittable)
        SongsUITestSupport.record(app, name: "shop-service-error")
        try app.performAccessibilityAudit(for: .all)
    }

    /// Settings hide/highlight switches change Shop controls without losing saved values.
    ///
    /// - Throws: Badges ignoring the setting, a hidden Shop action or lost preference.
    @MainActor
    func testPublicShopSettingsHideAndHighlightPropagation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        let originalHidden = try XCTUnwrap(hidden.value as? String)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        let highlights = app.switches["fst.settings.shop-highlights"]
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        let originalHighlights = try XCTUnwrap(highlights.value as? String)
        SongsUITestSupport.setSwitch(highlights, to: "1")

        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
        SongsUITestSupport.openItemShop(in: app)
        let fresh = app.descendants(matching: .any).matching(
            identifier: "fst.shop.badge.new.fixture-pulse"
        ).firstMatch
        XCTAssertTrue(fresh.waitForExistence(timeout: 15))
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(highlights, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            identifier: "fst.shop.external.fixture-pulse"
        ).firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(fresh.exists, "Disabled highlighting left a New badge visible")

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: "1")
        XCTAssertFalse(highlights.isEnabled)
        SongsUITestSupport.rootControl("Songs", app: app).tap()
        XCTAssertTrue(app.staticTexts[
            "Item Shop was hidden. Returned to Songs."
        ].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["fst.songs.shop"].exists)
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(highlights, to: originalHighlights)
        SongsUITestSupport.setSwitch(hidden, to: originalHidden)
    }

    /// Valid Shop offers change anonymous Songs cards and their Detail action.
    ///
    /// - Throws: Missing Shop badges, stale disabled state or an unsafe external action.
    @MainActor
    func testPublicShopMembershipDecoratesSongsAndDetail() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let hidden = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hidden, in: app, scrollingUp: true)
        let originalHidden = try XCTUnwrap(hidden.value as? String)
        SongsUITestSupport.setSwitch(hidden, to: "0")
        let highlights = app.switches["fst.settings.shop-highlights"]
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        let originalHighlights = try XCTUnwrap(highlights.value as? String)
        SongsUITestSupport.setSwitch(highlights, to: "1")

        SongsUITestSupport.rootControl("Songs", app: app).tap()
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
        SongsUITestSupport.record(app, name: "songs-public-shop-membership")
        try app.performAccessibilityAudit(for: .all)
        row.tap()
        let official = app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.shop"
        ).firstMatch
        XCTAssertTrue(official.waitForExistence(timeout: 10))
        XCTAssertTrue(official.label.contains("Item Shop"))

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(highlights, to: "0")
        SongsUITestSupport.rootControl("Songs", app: app).tap()
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

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        SongsUITestSupport.reveal(highlights, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(highlights, to: originalHighlights)
        SongsUITestSupport.setSwitch(hidden, to: originalHidden)
    }

    /// Shop 503 is disclosed on Songs/Detail, never treated as an empty membership set.
    ///
    /// - Throws: A missing error/retry, invented Shop action or false empty-feed state.
    @MainActor
    func testShopFeedFailureAndEmptyStaySeparateFromSongs() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launch()
        let originallyHidden = try SongsUITestSupport.showFixtureShop(in: app)
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let unavailable = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.shop-error").firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["fst.songs.shop-retry"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.songs.shop-badge.fixture-pulse"
        ).firstMatch.exists)
        SongsUITestSupport.record(app, name: "songs-shop-service-unavailable")
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
        SongsUITestSupport.openItemShop(in: app)
        XCTAssertTrue(app.staticTexts["No songs in the Item Shop"]
            .waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "songs-populated-shop-genuinely-empty")
        SongsUITestSupport.restoreFixtureShopVisibility(originallyHidden, in: app)
    }

    /// Prove the Songs Shop Retry text actually scales on a real iPhone.
    ///
    /// - Throws: Missing 503 action, clipped large text or unreadable rendered glyphs.
    @MainActor
    func testSongsShopRetryScalesAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let originallyHidden = try SongsUITestSupport.showFixtureShop(in: app)
        let retry = app.buttons["fst.songs.shop-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 15))
        let normalGlyphHeight = try SongsUITestSupport.brightGlyphHeight(in: retry)
        try SongsUITestSupport.assertHeaderContrast(retry, in: app, leadingTextWidth: 220)
        SongsUITestSupport.record(app, name: "songs-shop-retry-normal-text")

        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let list = app.collectionViews["fst.songs.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "songs-shop-retry-ax5-before-scroll")
        SongsUITestSupport.revealSongsControlAboveTab(
            retry, in: list, app: app,
            failureName: "songs-shop-retry-ax5-unreachable"
        )
        let largeGlyphHeight = try SongsUITestSupport.brightGlyphHeight(in: retry)
        XCTAssertGreaterThan(
            Double(largeGlyphHeight), Double(normalGlyphHeight) * 1.35,
            "Shop Retry rendered glyphs did not grow with Dynamic Type"
        )
        try SongsUITestSupport.assertHeaderContrast(retry, in: app, leadingTextWidth: 220)
        SongsUITestSupport.record(app, name: "songs-shop-retry-accessibility-xxxlarge")
        SongsUITestSupport.restoreFixtureShopVisibility(originallyHidden, in: app)
    }

}
