import XCTest
import UIKit

/// Fixture-backed native flows, never production or privileged endpoints.
final class FestivalMobileUITests: XCTestCase {
    // MARK: - Navigation and orientation

    /// A public Shop feed opens without adding a fourth compact tab.
    ///
    /// - Throws: Missing real fixture offers, unsafe outbound action or broken Song Detail.
    @MainActor
    func testPublicShopOffersAndSongDetailNavigation() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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

    /// Native Sort stages changes, persists rows and audits reachable modal text.
    ///
    /// - Throws: Wrong row order, silent discard, lost preference or visible contrast.
    @MainActor
    func testAnonymousSongsSortDraftApplyDiscardAndRelaunch() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
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

    /// Public CHOpt paths switch image/text and difficulty without stale content.
    ///
    /// - Throws: Missing selectors, unsafe zoom, stale path, hidden error or unreachable close.
    @MainActor
    func testSongPathsImageTextSwitchAndMissingDifficulty() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        collapseSidebarOnPad(app)
        let first = app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-1"
        ).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Fixture Player 1"].exists)
        let previewQuery = try await latestFixtureScoreQuery()
        XCTAssertEqual(previewQuery.top, 10)
        XCTAssertEqual(previewQuery.offset, 0)
        XCTAssertNil(previewQuery.leeway)
        XCTAssertFalse(app.descendants(matching: .any).matching(
            identifier: "fst.song-detail.preview-row.Solo_Guitar.fixture-player-11"
        ).firstMatch.exists)
        record(app, name: "song-detail-real-top-scores")
        try assertHeaderContrast(app.staticTexts["Fixture Player 1"], in: app)

        let viewFull = app.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(viewFull.waitForExistence(timeout: 10))
        viewFull.tap()
        XCTAssertTrue(app.buttons["fst.song-leaderboard.page-next"].waitForExistence(timeout: 10))
        let fullQuery = try await latestFixtureScoreQuery()
        XCTAssertEqual(fullQuery.top, 25)
        XCTAssertEqual(fullQuery.offset, 0)
    }

    /// Traverse Songs, Detail and page two, then verify landscape layout survives.
    ///
    /// - Throws: An XCTest failure for missing accessible actions or screen state.
    @MainActor
    func testSongsDetailScoresInPortraitAndLandscape() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
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
        try app.performAccessibilityAudit(for: .all)
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
        let app = XCUIApplication()
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
        let lastAccuracy = revealSoloAccuracy("fixture-player-26", app: app)
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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

    /// Retain validated unpinned Songs across a warm resume, never a cold relaunch.
    ///
    /// - Throws: A fixture still online, missing offline disclosure or persisted cold bytes.
    @MainActor
    func testHeaderlessWarmOfflineSurvivesBackgroundButNotColdLaunch() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8771"
        app.launchEnvironment["FST_UI_TEST_RESET_VISUALS"] = "1"
        app.launch()
        let row = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
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
        record(app, name: "songs-headerless-warm-offline")
        try app.performAccessibilityAudit(for: .all)

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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
        let app = XCUIApplication()
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
    func testHeaderlessRolloverExplainsRouteReset() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let port = UIDevice.current.userInterfaceIdiom == .pad ? 8768 : 8767
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:\(port)"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
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
        XCTAssertTrue(notice.waitForExistence(timeout: 10))
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
        let app = XCUIApplication()
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
    ///   - app: Foreground chart at AccessibilityXXXL.
    /// - Returns: The visible, explicitly labeled accuracy element.
    @MainActor
    private func revealSoloAccuracy(
        _ accountID: String, app: XCUIApplication
    ) -> XCUIElement {
        let accuracy = app.staticTexts
            .matching(identifier: "fst.song-leaderboard.row.\(accountID)")
            .matching(NSPredicate(format: "label == %@", "Accuracy 98%"))
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
        let identifier = "fst.song-leaderboard.row.\(accountID)"
        let rankText = app.staticTexts.matching(identifier: identifier)
            .matching(NSPredicate(format: "label == %@", "#\(rank)")).firstMatch
        let scoreText = app.staticTexts.matching(identifier: identifier)
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

    /// Check the actual rendered foreground against its median art-colored surface.
    ///
    /// - Parameters:
    ///   - element: A completely visible Settings section header.
    ///   - app: Its foreground white-cover app, used for a composited screenshot.
    /// - Throws: A missing screenshot or insufficient 4.5:1 rendered contrast.
    @MainActor
    private func assertHeaderContrast(_ element: XCUIElement, in app: XCUIApplication) throws {
        XCTAssertTrue(element.isHittable)
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        let scaleX = Double(image.width) / window.width
        let scaleY = Double(image.height) / window.height
        let crop = try XCTUnwrap(image.cropping(to: CGRect(
            x: (frame.minX - window.minX) * scaleX,
            y: (frame.minY - window.minY) * scaleY,
            width: frame.width * scaleX, height: frame.height * scaleY
        ).integral))
        let bytes = try bitmapPixels(crop)
        let luminances = stride(from: 0, to: bytes.count, by: 4).map { offset in
            (0..<3).map { channel -> Double in
                let value = Double(bytes[offset + channel]) / 255
                return value <= 0.04045
                    ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
        }.map { channels in
            0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }.sorted()
        XCTAssertFalse(luminances.isEmpty)
        let background = luminances[luminances.count / 2]
        let text = luminances[luminances.count * 99 / 100]
        XCTAssertGreaterThan(
            luminances.filter { $0 > background * 3 }.count, 100,
            "\(element.label) has no readable text pixels in its rendered section"
        )
        XCTAssertGreaterThanOrEqual(
            (text + 0.05) / (background + 0.05), 4.5,
            "\(element.label) lacks readable contrast over pure-white fixture art "
                + "(background \(background), text \(text), "
                + "crop \(crop.width)x\(crop.height))"
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
    /// - Parameter port: Loopback Songs, solo or Shop one-shot fixture (8771-8773).
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
    ///   - scrollingUp: True for lower sections, false for the first section.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool) {
        for _ in 0..<8 {
            if element.isHittable { return }
            if scrollingUp {
                app.swipeUp()
            } else {
                app.swipeDown()
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
