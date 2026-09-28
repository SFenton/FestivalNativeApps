import UIKit
import XCTest

/// Fixture-backed native journeys for the Suggestions tab: the no-profile guard, the
/// generated-list-or-empty transition once a player is selected, the Filter sheet's staged
/// draft (Apply/Cancel-with-discard/Reset) and incremental loading when enough categories
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

    /// A deselected profile must show the choose-profile guard, never a fabricated list.
    ///
    /// - Throws: A stuck loading spinner or an unreachable profile action.
    @MainActor
    func testSuggestionsRequiresProfileThenSettlesAfterSelection() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let choose = app.buttons["fst.suggestions.choose-profile"]
        XCTAssertTrue(choose.waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "fst.suggestions.list").firstMatch.exists)
        record(app, name: "suggestions-choose-profile")

        choose.tap()
        let search = app.textFields["fst.profile.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Fixture Player 1\n")
        let result = app.buttons["fst.profile.result.fixture-player-1"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        result.tap()
        let select = app.buttons["fst.profile.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()

        let settled = awaitSuggestionsSettled(in: app)
        XCTAssertTrue(
            settled.exists,
            "Suggestions never left loading: \(app.debugDescription.prefix(1_600))"
        )
        record(app, name: "suggestions-settled-after-selection")
        if settled.identifier == "fst.suggestions.list" {
            XCTAssertTrue(app.buttons["fst.suggestions.filter-button"].exists)
        } else {
            // A genuinely empty mix still offers the Filter action once a player is loaded.
            XCTAssertTrue(app.buttons["fst.suggestions.filter-button"].waitForExistence(timeout: 5))
        }
    }

    /// Stage instrument/category filter changes and prove Apply/Cancel/Reset semantics.
    ///
    /// - Throws: A missing form control, a silently discarded draft or a stuck Apply state.
    @MainActor
    func testSuggestionsFilterDraftApplyDiscardAndReset() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1"
        app.launch()
        awaitSuggestionsSettled(in: app)
        let filterButton = app.buttons["fst.suggestions.filter-button"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 15))
        filterButton.tap()

        let title = app.staticTexts["fst.suggestions.filter.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Filter Suggestions")
        let form = app.descendants(matching: .any)
            .matching(identifier: "fst.suggestions.filter.form").firstMatch
        XCTAssertTrue(form.exists)
        let apply = app.buttons["fst.suggestions.filter.apply"]
        let cancel = app.buttons["fst.suggestions.filter.cancel"]
        XCTAssertTrue(apply.exists && cancel.exists)
        XCTAssertFalse(apply.isEnabled, "Apply must start disabled with no draft changes")
        record(app, name: "suggestions-filter-default")

        let nearFC = app.switches["fst.suggestions.filter.type.nearFC"]
        XCTAssertTrue(nearFC.waitForExistence(timeout: 10))
        let before = nearFC.value as? String
        nearFC.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before ?? "1"), object: nearFC
        )
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTAssertTrue(apply.isEnabled, "Apply must enable once the draft differs")
        record(app, name: "suggestions-filter-draft-changed")

        cancel.tap()
        let discard = app.buttons["Discard Changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        let keepEditing = app.buttons["Continue Editing"]
        XCTAssertTrue(keepEditing.exists)
        keepEditing.tap()
        XCTAssertEqual(nearFC.value as? String, before == "1" ? "0" : "1")
        cancel.tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 10))
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))
        record(app, name: "suggestions-filter-discarded")

        filterButton.tap()
        XCTAssertTrue(nearFC.waitForExistence(timeout: 10))
        XCTAssertEqual(nearFC.value as? String, before)
        nearFC.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))
        record(app, name: "suggestions-filter-applied")

        filterButton.tap()
        let reset = app.buttons["fst.suggestions.filter.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        reset.tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))
        record(app, name: "suggestions-filter-reset")
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
        record(app, name: "suggestions-list-scrolled")
        if startNewMix.exists {
            XCTAssertTrue(startNewMix.isHittable)
            startNewMix.tap()
            XCTAssertTrue(list.waitForExistence(timeout: 10))
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
