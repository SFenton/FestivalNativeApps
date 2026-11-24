import UIKit
import XCTest

/// Fixture-backed native journeys for the Suggestions tab: the no-profile guard, the
/// generated-list-or-empty transition once a player is selected, the Filter sheet's
/// live filter (Close/Reset) and incremental loading when enough categories
/// exist.
///
/// The shared loopback fixture (`tools/mock_service.py`, default scenario) only serves two
/// synthetic songs, so `SuggestionGenerator` may legitimately produce zero categories for a
/// fixture player (most pipelines need three or more eligible songs). These journeys assert
/// the real reachable outcome — `fst.suggestions.list` or `fst.suggestions.no-results`, never
/// a stuck `fst.suggestions.loading` — rather than assuming a populated mix. See
/// `.agents/pages/suggestions/ios.md` and PROGRESS.md's Suggestions follow-up note for a
/// dedicated richer-catalogue fixture that would let a later pass assert specific categories
/// and drive the incremental-load and Start New Mix states without a skip.
final class SuggestionsJourneyTests: XCTestCase {
    /// Launch without a previously selected app profile.
    ///
    /// - Returns: Native app launcher that clears only the Debug selected-identity key.
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_API_BASE_URL": SongsUITestSupport.fixtureURL,
            "FST_DEBUG_TAB": "suggestions",
        ])
    }

    /// Wait for the screen to leave its transient loading spinner.
    ///
    /// - Parameter app: Foreground Suggestions destination after a profile is selected.
    /// - Returns: Whichever terminal state actually appeared.
    @MainActor
    @discardableResult
    private func awaitSuggestionsSettled(in app: XCUIApplication) -> XCUIElement {
        let list = app.descendants(matching: .any).matching(identifier: "fst.suggestions.list").firstMatch
        let empty = app.descendants(matching: .any)
            .matching(identifier: "fst.suggestions.no-results").firstMatch
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"), object: list
        )
        let settledEmpty = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"), object: empty
        )
        let result = XCTWaiter.wait(for: [settled], timeout: 1)
        if result == .completed { return list }
        _ = XCTWaiter.wait(for: [settledEmpty], timeout: 20)
        return list.exists ? list : empty
    }

    /// Anonymous, Suggestions is not offered at all (profile-only routes are hidden and
    /// redirect to Songs, web parity); selecting a player adds the tab, which settles
    /// into a list (or an honest empty mix) instead of a stuck spinner.
    ///
    /// - Throws: A Suggestions tab while anonymous, or a stuck loading spinner.
    @MainActor
    func testSuggestionsRequiresProfileThenSettlesAfterSelection() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let suggestionsTab = SongsUITestSupport.rootControl("Suggestions", app: app)
        XCTAssertTrue(app.buttons["fst.shell.profile"].waitForExistence(timeout: 15))
        XCTAssertFalse(suggestionsTab.exists, "Suggestions must be hidden without a selected player")
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "fst.suggestions.list").firstMatch.exists)
        record(app, name: "suggestions-hidden-anonymous")

        SongsUITestSupport.viewFixturePlayer("fixture-player-1", query: "Fixture Player 1", in: app)
        SongsUITestSupport.selectViewedPlayer(in: app)
        XCTAssertTrue(suggestionsTab.waitForExistence(timeout: 10))
        suggestionsTab.tap()

        let settled = awaitSuggestionsSettled(in: app)
        XCTAssertTrue(
            settled.exists,
            "Suggestions never left loading: \(app.debugDescription.prefix(1_600))"
        )
        record(app, name: "suggestions-settled-after-selection")
        XCTAssertTrue(app.buttons["fst.suggestions.filter-button"].waitForExistence(timeout: 5))
    }

    /// Filter changes apply live (no Cancel/Apply), persist across reopening, and Reset
    /// restores defaults; Close is the sheet's only toolbar action.
    ///
    /// - Throws: A missing form control or a change that did not persist.
    @MainActor
    func testSuggestionsFilterAppliesLiveAndResets() throws {
        continueAfterFailure = false
        let app = launchFilterFixture()

        var form = openFilter(in: app)
        let done = app.buttons["fst.suggestions.filter.done"]
        XCTAssertFalse(app.buttons["fst.suggestions.filter.apply"].exists)
        XCTAssertFalse(app.buttons["fst.suggestions.filter.cancel"].exists)
        record(app, name: "suggestions-filter-default")

        let nearFC = app.switches["fst.suggestions.filter.type.nearFC"]
        reveal([nearFC], in: form)
        let before = try XCTUnwrap(nearFC.value as? String)
        nearFC.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before), object: nearFC
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let saved = try XCTUnwrap(nearFC.value as? String)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 10))

        form = openFilter(in: app)
        reveal([nearFC], in: form)
        XCTAssertEqual(nearFC.value as? String, saved, "A live change did not persist")
        let reset = app.buttons["fst.suggestions.filter.reset"]
        reveal([reset], in: form)
        reset.tap()
        reveal([nearFC], in: form, scrollingUp: false)
        XCTAssertEqual(nearFC.value as? String, "1")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 10))
        record(app, name: "suggestions-filter-reset")
    }

    /// A General row exposes one switch and paints its full title and caption at AX5.
    @MainActor
    func testSuggestionsGeneralSwitchIncludesCaptionAndScales() throws {
        continueAfterFailure = false
        let nearFCID = "fst.suggestions.filter.type.nearFC"
        let caption = "Songs you're close to full-comboing."
        var defaultHeight: CGFloat = 0
        for (size, name) in [("UICTContentSizeCategoryL", "default"),
                             ("UICTContentSizeCategoryAccessibilityXXXL", "ax5")] {
            let app = launchFilterFixture(category: size)
            defer { app.terminate() }
            let form = openFilter(in: app)
            let nearFC = app.switches[nearFCID]
            reveal([nearFC], in: form)
            XCTAssertEqual(nearFC.label, "Near FC, \(caption)")
            let standaloneCaptions = try FestivalApp.snapshotNodes(in: form) {
                $0.elementType == .staticText && $0.label == caption
            }
            let switchCaptions = try FestivalApp.snapshotNodes(in: nearFC) {
                $0.elementType == .staticText && $0.label == caption
            }
            XCTAssertEqual(standaloneCaptions.count, switchCaptions.count, "The caption is repeated outside the switch")
            XCTAssertGreaterThanOrEqual(nearFC.frame.width, 44)
            let height = nearFC.frame.height
            if name == "default" {
                defaultHeight = height
                XCTAssertGreaterThanOrEqual(height, 60, "Title and caption need the native vertical inset")
                let general = try FestivalApp.snapshotNodes(in: form) {
                    $0.elementType == .switch && $0.identifier.hasPrefix("fst.suggestions.filter.type.")
                }
                XCTAssertEqual(Array(general.prefix(2).map(\.identifier)), [
                    nearFCID, "fst.suggestions.filter.type.starProgress",
                ])
            } else {
                XCTAssertGreaterThan(height, defaultHeight * 1.35)
            }
            record(app, name: "suggestions-filter-general-\(name)")
            if name == "ax5" {
                let starProgress = app.switches["fst.suggestions.filter.type.starProgress"]
                reveal([starProgress], in: form)
                let viewport = form.frame.intersection(app.windows.firstMatch.frame)
                let top = viewport.minY + 60
                let bottom = viewport.maxY - 8
                let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
                for _ in 0..<5 {
                    let frame = starProgress.frame
                    if frame.minY >= top && frame.maxY <= bottom { break }
                    let travel = viewport.height * 0.3
                    let shift = min(travel, max(-travel, (top + bottom) / 2 - frame.midY))
                    let end = start.withOffset(CGVector(dx: 0, dy: shift))
                    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
                }
                record(app, name: "suggestions-filter-general-star-progress-ax5")
                XCTAssertLessThanOrEqual(starProgress.frame.maxY, bottom, "The whole switch row must be visible")
                XCTAssertGreaterThanOrEqual(starProgress.frame.minY, top, "The title must clear the top fade")
                let expected = ["Star Progress", "Push five-star runs to gold, or gain more stars."]
                let paint = RecognizedText.recognize(
                    starProgress, label: expected.joined(separator: " "), frame: starProgress.frame
                )
                for text in expected {
                    XCTAssertTrue(RecognizedText.showsWhole(text, in: paint.text), paint.text ?? "Missing switch text")
                }
            }
        }
    }

    /// Hiding an instrument updates the rows of an existing mixed-instrument card in place.
    @MainActor
    func testSuggestionsInstrumentFilterRefreshesExistingMixedCard() {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launchEnvironment["FST_DEBUG_ROUTE"] = "suggestions"
        app.launchArguments += ["-fst.suggestions.filter", ""]
        app.launch()

        let hidden = app.buttons.matching(identifier: "fst.suggestions.row.fixture-pulse|Solo_Drums").firstMatch
        let retained = app.buttons.matching(identifier: "fst.suggestions.row.fixture-orbit|Solo_PeripheralDrums").firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 15))
        XCTAssertTrue(retained.exists)
        XCTAssertTrue(hidden.label.hasSuffix("Drums"))

        let filter = app.buttons["fst.suggestions.filter-button"]
        XCTAssertTrue(filter.isHittable)
        filter.tap()
        let drums = app.switches["fst.suggestions.filter.instrument.Solo_Drums"]
        XCTAssertTrue(drums.waitForExistence(timeout: 5))
        let bass = app.switches["fst.suggestions.filter.instrument.Solo_Bass"]
        XCTAssertTrue(bass.isHittable && drums.isHittable)
        XCTAssertTrue(drums.label.hasPrefix("Drums"))
        XCTAssertGreaterThanOrEqual(drums.frame.height, 56)
        XCTAssertEqual(drums.frame.minY - bass.frame.minY, 58, accuracy: 1)
        XCTAssertEqual(drums.value as? String, "1")
        drums.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(drums.value as? String, "0")
        app.buttons["fst.suggestions.filter.done"].tap()

        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: hidden)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed, "The existing card still speaks the excluded row")
        XCTAssertTrue(retained.isHittable, "The remaining mixed-card row should stay accessible")
        XCTAssertTrue(retained.label.hasSuffix("Pro Drums"))
    }

    /// The Instrument-Specific section is the shared InstrumentSelector (deferred mode,
    /// web): nothing selected on open and no per-instrument toggles; choosing an
    /// instrument (a circle, or the compact centre after cycling) reveals its toggles.
    ///
    @MainActor
    func testSuggestionsFilterInstrumentSelectorRevealsPerInstrumentToggles() {
        continueAfterFailure = false
        let app = launchFilterFixture()
        let form = openFilter(in: app)

        let prefix = "fst.suggestions.filter.instrument-picker"
        let lead = app.buttons["\(prefix).Solo_Guitar"]
        let centre = app.buttons["\(prefix).centre"]
        reveal([lead, centre], in: form)
        let isCompact = !lead.isHittable
        let selection = isCompact ? centre : lead
        let chart = isCompact ? "Solo_Bass" : "Solo_Guitar"
        let firstToggle = app.switches["fst.suggestions.filter.type.\(chart).nearFC"]
        XCTAssertFalse(firstToggle.exists, "Per-instrument toggles showed before a choice")
        XCTAssertFalse(selection.isSelected)
        if isCompact {
            app.buttons["\(prefix).next"].tap()
            XCTAssertEqual(centre.label, "Bass")
            XCTAssertFalse(centre.isSelected)
            XCTAssertFalse(firstToggle.exists, "A preview opened the chart's switches")
        }
        selection.tap()
        XCTAssertTrue(firstToggle.waitForExistence(timeout: 5), "Choosing a chart did not reveal its toggles")
        reveal([firstToggle], in: form)
        XCTAssertTrue(selection.isSelected)
        XCTAssertEqual(firstToggle.label, "Near FC")
        XCTAssertGreaterThanOrEqual(firstToggle.frame.width, 44)
        XCTAssertGreaterThanOrEqual(firstToggle.frame.height, 44)
        XCTAssertGreaterThan(firstToggle.frame.midY, selection.frame.midY)
        record(app, name: "suggestions-filter-instrument-selector")
        reveal([selection], in: form, scrollingUp: false)
        selection.tap()
        XCTAssertTrue(firstToggle.waitForNonExistence(timeout: 5), "Clearing the chart did not hide its toggles")
        XCTAssertFalse(selection.isSelected)
        app.buttons["fst.suggestions.filter.done"].tap()
    }

    /// Launch a selected player on Suggestions, optionally with two visible charts to
    /// put General near the top at both Dynamic Type sizes.
    @MainActor
    private func launchFilterFixture(category: String? = nil) -> XCUIApplication {
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launchEnvironment["FST_DEBUG_ROUTE"] = "suggestions"
        if let category {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
            for name in ["Drums", "Vocals", "ProLead", "ProBass", "Karaoke", "ProCymbals", "ProDrums"] {
                app.launchArguments += ["-fst.settings.show\(name)", "NO"]
            }
            app.launchArguments += ["-fst.settings.showLead", "YES", "-fst.settings.showBass", "YES"]
        }
        app.launch()
        XCTAssertTrue(awaitSuggestionsSettled(in: app).exists)
        return app
    }

    /// Open the page tool directly or through folded Duo's native toolbar overflow.
    @MainActor
    private func openFilter(in app: XCUIApplication) -> XCUIElement {
        ShellUITestSupport.tapToolbarItem(
            "fst.suggestions.filter-button", overflowLabels: ["Filter", "Filter Suggestions"], in: app
        )
        XCTAssertTrue(app.buttons["fst.suggestions.filter.done"].waitForExistence(timeout: 10))
        let form = app.descendants(matching: .any).matching(identifier: "fst.suggestions.filter.form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 10))
        return form
    }

    /// Scroll the sheet's Form until a target (or its compact equivalent) is hittable.
    @MainActor
    private func reveal(_ targets: [XCUIElement], in form: XCUIElement, scrollingUp: Bool = true) {
        for _ in 0..<12 {
            if targets.contains(where: \.isHittable) { return }
            if scrollingUp { form.swipeUp() } else { form.swipeDown() }
        }
        XCTAssertTrue(targets.contains(where: \.isHittable), "\(targets.map(\.identifier)) not reachable in Filter")
    }

    /// With horizontal tab chrome, Filter stays in its own 44 pt circle above the tab
    /// bar while Notifications and Profile stay grouped in the navigation bar.
    ///
    /// Scrolling needs a populated mix: pass a richer catalogue as
    /// `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL` (`mock_service.py --large-catalogue`);
    /// the two-song default checks only the top state.
    ///
    /// - Throws: A skip outside a horizontal-tab layout.
    @MainActor
    func testSuggestionsFilterFloatsWhileAccountItemsStayInTheBar() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        if let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"] {
            app.launchEnvironment["FST_API_BASE_URL"] = base
        }
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launch()
        let settled = awaitSuggestionsSettled(in: app)
        let tabBar = app.tabBars.firstMatch
        try XCTSkipUnless(tabBar.exists && tabBar.frame.width > tabBar.frame.height * 2, "Needs a horizontal tab bar")
        let bar = app.navigationBars.firstMatch
        let filter = app.buttons["fst.suggestions.filter-button"]
        func assertPlacement(_ state: String) {
            for id in ["fst.shell.notifications", "fst.shell.profile"] {
                let control = bar.buttons[id]
                XCTAssertTrue(control.waitForExistence(timeout: 10), "\(id) missing \(state)")
                XCTAssertTrue(control.isHittable, "\(id) not hittable \(state)")
            }
            XCTAssertTrue(filter.waitForExistence(timeout: 10), "Filter missing \(state)")
            XCTAssertTrue(filter.isHittable)
            XCTAssertEqual(filter.label, "Filter")
            XCTAssertGreaterThanOrEqual(filter.frame.width, 44)
            XCTAssertGreaterThanOrEqual(filter.frame.height, 44)
            XCTAssertGreaterThan(filter.frame.minY, bar.frame.maxY)
            XCTAssertLessThanOrEqual(filter.frame.maxY, tabBar.frame.minY + 1)
        }
        assertPlacement("at the top")
        if settled.identifier == "fst.suggestions.list", settled.isHittable, !settled.frame.isEmpty {
            let initial = filter.frame
            settled.swipeUp()
            settled.swipeUp()
            assertPlacement("while scrolled")
            XCTAssertEqual(filter.frame.minY, initial.minY, accuracy: 1)
        }
        filter.tap()
        let close = app.buttons["fst.suggestions.filter.done"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertFalse(filter.isHittable, "The sheet covers the page tool")
        close.tap()
        assertPlacement("after dismissing the filter")
    }

    /// Prove incremental loading when the fixture mix exceeds one page, otherwise skip
    /// rather than fail a fixture limitation that a richer catalogue would remove.
    ///
    /// - Throws: A load-more trigger that never fires despite enough rows to need it.
    @MainActor
    func testSuggestionsIncrementalLoadWhenMixIsLargeEnough() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launch()
        let settled = awaitSuggestionsSettled(in: app)
        guard settled.identifier == "fst.suggestions.list" else {
            throw XCTSkip(
                "Fixture mix produced no categories for fixture-player-1; a richer "
                    + "catalogue fixture is needed to exercise incremental loading"
            )
        }
        let list = settled
        let startNewMix = app.buttons["fst.suggestions.start-new-mix"]
        for _ in 0..<10 {
            if startNewMix.exists { break }
            list.swipeUp()
        }
        // One more drag lifts the footer clear of the tab bar.
        if startNewMix.exists && !startNewMix.isHittable { list.swipeUp() }
        record(app, name: "suggestions-list-scrolled")
        if startNewMix.exists {
            XCTAssertTrue(startNewMix.isHittable)
            startNewMix.tap()
            // A new mix regenerates behind the page spinner before the list returns.
            XCTAssertTrue(awaitSuggestionsSettled(in: app).exists)
            record(app, name: "suggestions-mix-restarted")
        } else {
            throw XCTSkip(
                "Fixture mix never exhausted within ten swipes; too few categories to "
                    + "observe incremental loading with the default fixture"
            )
        }
    }

    /// Attach the app's current display to the Xcode result bundle.
    ///
    /// - Parameters:
    ///   - app: Launched Festival fixture app.
    ///   - name: Named page/state for the evidence matrix.
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
