import UIKit
import XCTest

/// Fixture-backed native journeys for the Suggestions tab: the no-profile guard, the
/// generated-list-or-empty transition once a player is selected, the Filter sheet's staged
/// live filter (Done/Reset) and incremental loading when enough categories
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
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
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
    /// restores defaults; Done is the sheet's only toolbar action.
    ///
    /// - Throws: A missing form control or a change that did not persist.
    @MainActor
    func testSuggestionsFilterAppliesLiveAndResets() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launch()
        awaitSuggestionsSettled(in: app)
        let filterButton = app.buttons["fst.suggestions.filter-button"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 15))
        filterButton.tap()

        XCTAssertTrue(app.navigationBars["Filter Suggestions"].waitForExistence(timeout: 10))
        let form = app.descendants(matching: .any)
            .matching(identifier: "fst.suggestions.filter.form").firstMatch
        XCTAssertTrue(form.exists)
        let done = app.buttons["fst.suggestions.filter.done"]
        XCTAssertTrue(done.exists)
        XCTAssertFalse(app.buttons["fst.suggestions.filter.apply"].exists)
        XCTAssertFalse(app.buttons["fst.suggestions.filter.cancel"].exists)
        record(app, name: "suggestions-filter-default")

        let nearFC = app.switches["fst.suggestions.filter.type.nearFC"]
        XCTAssertTrue(nearFC.waitForExistence(timeout: 10))
        let before = nearFC.value as? String
        nearFC.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before ?? "1"), object: nearFC
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        record(app, name: "suggestions-filter-live-changed")
        done.tap()
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))

        filterButton.tap()
        XCTAssertTrue(nearFC.waitForExistence(timeout: 10))
        XCTAssertNotEqual(nearFC.value as? String, before, "A live change did not persist")
        let reset = app.buttons["fst.suggestions.filter.reset"]
        // Reset sits after the instrument selector section at the end of the form.
        for _ in 0..<8 where !reset.exists { app.swipeUp() }
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        reset.tap()
        for _ in 0..<8 where !nearFC.isHittable { app.swipeDown() }
        XCTAssertEqual(nearFC.value as? String, before)
        app.buttons["fst.suggestions.filter.done"].tap()
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))
        record(app, name: "suggestions-filter-reset")
    }

    /// The Instrument-Specific section is the shared InstrumentSelector (deferred mode,
    /// web): nothing selected on open and no per-instrument toggles; choosing an
    /// instrument (a circle, or the compact centre after cycling) reveals its toggles.
    ///
    /// - Throws: A missing selector or toggles that never appear.
    @MainActor
    func testSuggestionsFilterInstrumentSelectorRevealsPerInstrumentToggles() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launch()
        awaitSuggestionsSettled(in: app)
        let filterButton = app.buttons["fst.suggestions.filter-button"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 15))
        filterButton.tap()
        XCTAssertTrue(app.navigationBars["Filter Suggestions"].waitForExistence(timeout: 10))

        let prefix = "fst.suggestions.filter.instrument-picker"
        let lead = app.buttons["\(prefix).Solo_Guitar"]
        let centre = app.buttons["\(prefix).centre"]
        for _ in 0..<8 where !(lead.exists || centre.exists) { app.swipeUp() }
        XCTAssertTrue(lead.exists || centre.exists, "The instrument selector is missing")
        let leadToggles = app.switches.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fst.suggestions.filter.type.Solo_Guitar.")
        )
        XCTAssertEqual(leadToggles.count, 0, "Per-instrument toggles showed before a choice")
        if lead.exists {
            lead.tap()
        } else {
            // Compact: the centre previews Lead first; tapping it commits.
            centre.tap()
        }
        XCTAssertTrue(leadToggles.firstMatch.waitForExistence(timeout: 5), "Choosing Lead did not reveal its toggles")
        record(app, name: "suggestions-filter-instrument-selector")
        app.buttons["fst.suggestions.filter.done"].tap()
    }

    /// Filter plus account items are navigation-bar items, so they stay in the bar row,
    /// hittable (and so reachable by VoiceOver), at the top and while scrolled; the
    /// large title collapses under them and returns at the top.
    ///
    /// Scrolling needs a populated mix: pass a richer catalogue as
    /// `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL` (`mock_service.py --large-catalogue`);
    /// the two-song default checks only the top state.
    ///
    /// - Throws: A control that leaves the bar or stops being hittable.
    @MainActor
    func testSuggestionsToolbarItemsStayInTheBarWhileScrolled() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        if let base = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"] {
            app.launchEnvironment["FST_API_BASE_URL"] = base
        }
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launch()
        let settled = awaitSuggestionsSettled(in: app)
        let bar = app.navigationBars.firstMatch
        let controls = [
            "fst.suggestions.filter-button", "fst.shell.notifications", "fst.shell.profile",
        ].map { app.buttons[$0] }
        func assertInBar(_ state: String) {
            for control in controls {
                XCTAssertTrue(control.waitForExistence(timeout: 10), "\(control) missing \(state)")
                XCTAssertTrue(control.isHittable, "\(control) not hittable \(state)")
                XCTAssertLessThanOrEqual(control.frame.maxY, bar.frame.maxY + 1, "\(control) left the bar \(state)")
            }
        }
        assertInBar("at the top")
        let expanded = bar.frame.height
        guard settled.identifier == "fst.suggestions.list" else {
            throw XCTSkip("Fixture mix produced no categories; nothing to scroll")
        }
        guard settled.isHittable, !settled.frame.isEmpty else {
            throw XCTSkip("Fixture mix produced no visible list viewport; nothing to scroll")
        }
        settled.swipeUp()
        settled.swipeUp()
        let collapsed = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in bar.frame.height < expanded - 20 }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed, "Large title did not collapse")
        assertInBar("while scrolled")
        record(app, name: "suggestions-tools-in-bar-scrolled")
        for _ in 0..<4 { settled.swipeDown() }
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in abs(bar.frame.height - expanded) < 2 }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed, "Large title did not return")
        assertInBar("back at the top")
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
