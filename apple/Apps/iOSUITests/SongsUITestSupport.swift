import UIKit
import XCTest

/// Shared XCUITest helpers for the Songs, Song Detail, Item Shop and CHOpt Paths journeys.
///
/// Extracted from the legacy `FestivalMobileUITests` monolith (Wave 3 UX-test triage) so
/// `SongsJourneyTests`, `SongDetailJourneyTests` and `ShopJourneyTests` can share one copy of
/// fixture launch, native Settings/Filter/Sort scrolling and pixel-based accessibility helpers
/// without depending on another lane's test file. Namespaced under an `enum` (rather than an
/// `extension XCTestCase`) so it cannot collide with another lane's identically named helper
/// when both are extracted from the same monolith in parallel.
enum SongsUITestSupport {
    /// Start each fixture journey without a previously selected app profile.
    ///
    /// - Returns: Native app launcher that clears only the Debug selected-identity key.
    @MainActor
    static func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
    }
    /// Choose the source's icons-off variant for tests of numeric score metadata.
    ///
    /// - Parameter app: Launched fixture app before selecting an account.
    @MainActor
    static func showSelectedScoreMetadata(in app: XCUIApplication) {
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
    static func chipEntries(for songId: String, in app: XCUIApplication) -> [String] {
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
    static func metadataElement(
        _ key: String, songId: String = "fixture-pulse", in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any).matching(
            identifier: "fst.songs.metadata.\(key).\(songId)"
        ).firstMatch
    }

    /// Reach one synthetic player from a fresh profile sheet without selecting it.
    ///
    /// A search result dismisses the sheet and pushes the real `AppRoute.player`
    /// destination onto the presenting tab (`ProfileSelectionSheet.swift`'s
    /// dismiss-then-push flow), so this waits for `fst.player.name` on that pushed
    /// page and requires it to name `accountId`'s fixture player (the wrong-account
    /// bug pushed every result, leaving the last on top). Pair with
    /// ``selectViewedPlayer(in:)`` to select and return to the presenting tab.
    ///
    /// - Parameters:
    ///   - accountId: Fixture search result key.
    ///   - query: Source-like player name or state to type.
    ///   - app: Already launched native fixture app on Songs.
    @MainActor
    static func viewFixturePlayer(
        _ accountId: String, query: String, in app: XCUIApplication
    ) {
        let action = app.buttons["fst.shell.profile"]
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
        let viewed = app.staticTexts["fst.player.name"]
        XCTAssertTrue(
            viewed.waitForExistence(timeout: 10),
            "Pushed player page never replaced search results: "
                + "\(app.staticTexts.allElementsBoundByIndex.prefix(14).map(\.label))"
        )
        let expectedName = NSPredicate(
            format: "label == %@", fixtureDisplayNames[accountId] ?? accountId
        )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: expectedName, object: viewed)],
                timeout: 10
            ),
            .completed, "Viewed \(viewed.label) instead of \(accountId)"
        )
    }

    /// Display names `tools/mock_service.py` returns for its search fixtures.
    private static let fixtureDisplayNames = [
        "fixture-player-1": "Fixture Player 1",
        "fixture-player-2": "Fixture Player 2",
        "fixture-edge": "Fixture Edge Player",  // contracts/fixtures/metadata-edge.json
    ]

    /// Select (or switch to) the player page ``viewFixturePlayer(_:query:in:)`` just
    /// pushed, then return to the presenting tab root. The sheet was already
    /// dismissed before the push (dismiss-then-push), so there is no sheet to close.
    ///
    /// - Parameter app: Foreground fixture app on the pushed Player Profile page.
    @MainActor
    static func selectViewedPlayer(in app: XCUIApplication) {
        let select = app.buttons["fst.player.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        let switchConfirm = app.buttons["Switch Profile"]
        if switchConfirm.waitForExistence(timeout: 2) {
            switchConfirm.tap()
        }
        // A selection change pops the Songs stack by itself ("Selected profile
        // changed. Returned to Songs…"); only other tabs need a manual Back.
        let viewed = app.staticTexts["fst.player.name"]
        if !viewed.waitForNonExistence(timeout: 5) {
            let back = app.navigationBars.buttons["BackButton"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
        }
        XCTAssertTrue(app.buttons["fst.shell.profile"].waitForExistence(timeout: 10))
    }

    /// Remove only the app's selected identity through its own confirmation action.
    ///
    /// Deselect lives in the hamburger drawer (the player page has no Deselect button
    /// since operator batch 7): open the drawer from the Songs root, tap Deselect and
    /// confirm.
    ///
    /// - Parameter app: Foreground app with a selected player.
    /// - Throws: Missing accessible confirmation or stale selection.
    @MainActor
    static func deselectFixturePlayer(in app: XCUIApplication) throws {
        let songs = rootControl("Songs", app: app)
        if songs.waitForExistence(timeout: 5) { songs.tap() }
        let drawerOpen = app.buttons["fst.shell.drawer.open"]
        XCTAssertTrue(drawerOpen.waitForExistence(timeout: 10))
        drawerOpen.tap()
        let deselect = app.buttons["fst.shell.drawer.deselect-profile"]
        XCTAssertTrue(deselect.waitForExistence(timeout: 10))
        deselect.tap()
        let confirmed = try XCTUnwrap(
            app.buttons.matching(identifier: "Deselect Profile")
                .allElementsBoundByIndex.first(where: \.isHittable)
        )
        confirmed.tap()
        if songs.waitForExistence(timeout: 5), songs.isHittable { songs.tap() }
    }

    /// Open Shop from the leading hamburger drawer.
    ///
    /// The standalone Songs toolbar Shop button (`fst.songs.shop`) was removed when
    /// Item Shop moved into the shared drawer (`.agents/pages/shop/ios.md`: "Entry:
    /// the leading drawer"); this opens `fst.shell.drawer.open` and taps the drawer's
    /// `fst.shell.drawer.shop` row instead.
    ///
    /// - Parameter app: Fixture app on any root destination with the shared drawer.
    @MainActor
    static func openItemShop(in app: XCUIApplication) {
        let drawerOpen = app.buttons["fst.shell.drawer.open"]
        XCTAssertTrue(drawerOpen.waitForExistence(timeout: 10))
        drawerOpen.tap()
        let shop = app.buttons["fst.shell.drawer.shop"]
        XCTAssertTrue(
            shop.waitForExistence(timeout: 10),
            "Shop drawer row missing; visible buttons: "
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
    static func showFixtureShop(in app: XCUIApplication) throws -> String {
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
    static func restoreFixtureShopVisibility(
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
    static func openFilterSheet(in app: XCUIApplication) -> XCUIElement {
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
    static func openSongsFilter(in app: XCUIApplication) {
        _ = openFilterSheet(in: app)
        _ = revealFilterOption(app.switches["fst.songs.filter.in-shop"], in: app)
    }

    /// The Filter sheet's scrolling Form.
    ///
    /// Found by its content rather than its own `fst.songs.filter.form` identifier, which
    /// iOS 26 no longer reports on the Form's collection view.
    ///
    /// - Parameter app: App presenting the Filter sheet.
    /// - Returns: The collection view holding the Filter controls.
    @MainActor
    static func filterForm(in app: XCUIApplication) -> XCUIElement {
        let byID = app.collectionViews["fst.songs.filter.form"]
        if byID.exists { return byID }
        return app.collectionViews.containing(NSPredicate(
            format: "identifier BEGINSWITH 'fst.songs.filter.'"
        )).firstMatch
    }

    /// Scroll the native Filter Form until a score control clears its pinned actions.
    ///
    /// - Parameters:
    ///   - element: Named global switch, chart disclosure or chart switch.
    ///   - app: Active fixture app with the full-height native Filter Form.
    /// - Returns: A visibly hittable control above the Cancel/Apply footer.
    @MainActor
    static func revealFilterOption(
        _ element: XCUIElement, in app: XCUIApplication
    ) -> XCUIElement {
        let form = filterForm(in: app)
        let footer = app.buttons["fst.songs.filter.done"]
        XCTAssertTrue(
            form.exists && footer.exists,
            "Missing Filter Form or pinned actions: "
                + "\(app.collectionViews.allElementsBoundByIndex.prefix(4).map(\.identifier))"
        )
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.maxY <= sheetVisibleBottom(in: app) { break }
            form.swipeUp()
        }
        XCTAssertTrue(
            element.exists && element.isHittable && element.frame.maxY <= sheetVisibleBottom(in: app),
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
    static func revealSongsControlAboveTab(
        _ element: XCUIElement, in list: XCUIElement,
        app: XCUIApplication, failureName: String,
        bottomMargin: CGFloat = 8
    ) {
        let tabs = app.tabBars.firstMatch
        let visibleBottom = (tabs.exists
            ? tabs.frame.minY : app.windows.firstMatch.frame.maxY) - bottomMargin
        for _ in 0..<12 {
            if element.exists && element.isHittable && element.frame.maxY <= visibleBottom { break }
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
        if !element.exists || !element.isHittable || element.frame.maxY > visibleBottom {
            record(app, name: failureName)
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element.identifier) stayed outside Songs")
        XCTAssertLessThanOrEqual(element.frame.maxY, visibleBottom)
    }

    /// Bottom of the visible sheet content: the sheets have no pinned footer any more
    /// (immediate-apply sheets with a Done button in their navigation bar).
    ///
    /// - Parameter app: Foreground app presenting a Songs sheet.
    /// - Returns: The lowest y at which a control is fully visible.
    @MainActor
    static func sheetVisibleBottom(in app: XCUIApplication) -> CGFloat {
        app.windows.firstMatch.frame.maxY - 8
    }

    /// Scroll the modal Form until Reset is fully visible.
    ///
    /// - Parameter app: Foreground Songs Sort sheet on phone or tablet.
    /// - Returns: Hittable Reset button within the visible scroll viewport.
    @MainActor
    static func revealSortReset(in app: XCUIApplication) -> XCUIElement {
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
    static func revealFilterReset(in app: XCUIApplication) -> XCUIElement {
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
    static func revealSheetReset(
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
            if reset.exists && reset.isHittable && reset.frame.maxY <= sheetVisibleBottom(in: app) { break }
            list.swipeUp()
        }
        XCTAssertTrue(
            reset.exists && reset.isHittable && reset.frame.maxY <= sheetVisibleBottom(in: app),
            "Reset is hidden by the \(sheetName) action footer"
        )
        return reset
    }

    /// Move the public-Shop option above the sheet footer before selecting it.
    ///
    /// - Parameter app: Foreground native Songs Sort sheet.
    /// - Returns: A hittable, validated Item Shop sort row.
    @MainActor
    static func revealShopSort(in app: XCUIApplication) -> XCUIElement {
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
            if choice.exists && choice.isHittable && choice.frame.maxY <= sheetVisibleBottom(in: app) { break }
            form.swipeUp()
        }
        XCTAssertTrue(
            choice.exists && choice.isHittable && choice.frame.maxY <= sheetVisibleBottom(in: app),
            "Item Shop sort option is hidden by the sheet footer"
        )
        return choice
    }

    /// Expose the full detail pane before auditing iPad's split-view destination.
    ///
    /// - Parameter app: Foreground native Songs detail or leaderboard screen.
    @MainActor
    static func collapseSidebarOnPad(_ app: XCUIApplication) {
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
    static func revealSoloAccuracy(
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
    static func assertWholeSoloScore(
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
    static func rootControl(_ name: String, app: XCUIApplication) -> XCUIElement {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return app.descendants(matching: .any)
                .matching(identifier: "fst.nav.\(name.lowercased())").firstMatch
        }
        return app.tabBars.buttons[name]
    }

    /// The Songs list's inline filter field (`.searchable`, prompt "Filter Songs").
    ///
    /// Matched by its prompt so it is never confused with global search's field
    /// (the iOS 26 search tab), see `.agents/controls/global-search/ios.md`.
    ///
    /// - Parameter app: Foreground app on the Songs root.
    /// - Returns: The Songs filter search field.
    @MainActor
    static func songsSearchField(in app: XCUIApplication) -> XCUIElement {
        let field = app.searchFields.matching(
            NSPredicate(format: "placeholderValue == %@", "Filter Songs")
        ).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        return field
    }

    /// Scroll a large-type error until Retry is both tappable and above native navigation.
    ///
    /// - Parameter app: Foreground error scenario on a phone or tablet simulator.
    /// - Throws: Retry remains outside the usable viewport after eight deliberate swipes.
    @MainActor
    static func revealFailureAction(_ app: XCUIApplication) throws {
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

    /// Require a real gold FC outline or graded green fill in rendered score pixels.
    ///
    /// - Parameters:
    ///   - element: Fully visible, separately accessible native accuracy pill.
    ///   - fullCombo: Whether the validated score explicitly reports a full combo.
    /// - Throws: An absent or visually incorrect accent on the named badge.
    @MainActor
    static func assertScoreAccuracyAccent(
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
    static func assertAlignedScoreColumn(
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
    static func assertAlignedScoreEnds(_ first: XCUIElement, _ second: XCUIElement) {
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
    static func assertHeaderContrast(
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
    static func measuredTextContrast(
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
    static func bitmapPixels(_ image: CGImage) throws -> [UInt8] {
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
    static func brightGlyphHeight(in element: XCUIElement) throws -> Int {
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
    static func backgroundSignature(_ app: XCUIApplication) throws -> [UInt8] {
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

    /// Only an explicitly signaled local fixture may move publication seven to eight.
    struct FixturePublicationAdvance: Decodable {
        let publicationId: Int
    }

    /// Numeric-only diagnostic for a dedicated, locally owned rollover fixture.
    struct FixturePublicationJoinReads: Decodable {
        let shop: Int?
        let player: Int?
        let failedSongs: Int?
    }

    /// Advance only an exact fixture port after the native before-state is visible.
    ///
    /// - Parameter port: Runner-owned command-rollover listener on loopback.
    /// - Throws: Missing local endpoint, invalid publication or non-200 result.
    @MainActor
    static func advanceFixturePublication(port: Int) async throws {
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
    static func fixturePublicationJoinReads(
        port: Int
    ) async throws -> FixturePublicationJoinReads {
        let url = try XCTUnwrap(
            URL(string: "http://127.0.0.1:\(port)/__fixture__/publication-join-reads")
        )
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONDecoder().decode(FixturePublicationJoinReads.self, from: data)
    }

    /// Require visible neutral-white fixture pixels after native 0.7 dimming.
    ///
    /// - Parameter app: Foreground page with one fixture-white artwork path.
    /// - Throws: A screenshot without at least 32 uncovered white-art grid cells.
    @MainActor
    static func assertWhiteArtVisible(in app: XCUIApplication) async throws {
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
    static func pixelDistance(_ first: [UInt8], _ second: [UInt8]) -> Int {
        zip(first, second).reduce(0) { total, channels in
            total + abs(Int(channels.0) - Int(channels.1))
        }
    }

    /// Wait for an approved one-shot fixture to stop listening before offline actions.
    ///
    /// - Parameter port: Loopback one-shot fixture (8771-8775).
    /// - Throws: Unexpected transport failure or listener that never closes.
    @MainActor
    static func awaitClosedFixture(port: Int) async throws {
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

    struct FixtureScoreQuery: Decodable {
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
    static func latestFixtureScoreQuery(
        fullOnly: Bool = false
    ) async throws -> FixtureScoreQuery.Request {
        let name = fullOnly ? "last-full-score-query" : "last-score-query"
        let url = URL(string: "http://127.0.0.1:8765/__fixture__/\(name)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONDecoder().decode(FixtureScoreQuery.self, from: data).last)
    }

    /// Scroll the lazily created native Settings page to a visible control.
    ///
    /// Settings is a `LazyVStack`: an off-screen control does not exist until scrolled
    /// near, and `isHittable` on a missing element fails the test outright, so check
    /// `exists` first.
    ///
    /// - Parameters:
    ///   - element: Settings action to reveal before tapping or asserting.
    ///   - app: Fixture app with the Settings page visible.
    ///   - scrollingUp: Preferred direction, reversed if Settings retained its scroll position.
    @MainActor
    static func reveal(_ element: XCUIElement, in app: XCUIApplication, scrollingUp: Bool) {
        for direction in [scrollingUp, !scrollingUp] {
            for _ in 0..<10 {
                if element.exists && element.isHittable { return }
                if direction {
                    app.swipeUp()
                } else {
                    app.swipeDown()
                }
            }
        }
        XCTAssertTrue(
            element.exists && element.isHittable,
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
    static func setSwitch(_ element: XCUIElement, to value: String) {
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

    /// Run the full accessibility audit, allowing Dynamic Type findings only on
    /// navigation-bar buttons (the avatar monogram, a sheet's system Done): bar items
    /// keep their size at large text (HIG) and offer the Large Content Viewer instead.
    ///
    /// - Parameter app: Foreground app to audit.
    /// - Throws: The audit's own failure to run.
    @MainActor
    static func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit(for: .all) { issue in
            guard let element = issue.element else { return false }
            // The system search field's placeholder (a system control whose glyph
            // colour and clipping the app does not own).
            if element.elementType == .searchField
                && (issue.auditType == .textClipped || issue.auditType == .contrast) { return true }
            guard issue.auditType == .dynamicType else { return false }
            // Status bar + navigation bar region of every iPhone (and sheet headers).
            return element.frame.maxY <= 150
        }
    }

    /// Attach only the app's current display to the Xcode result bundle.
    ///
    /// - Parameters:
    ///   - app: Launched Festival fixture app.
    ///   - name: Named page/state/orientation for the evidence matrix.
    @MainActor
    static func record(_ app: XCUIApplication, name: String) {
        XCTContext.runActivity(named: name) { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }
}
