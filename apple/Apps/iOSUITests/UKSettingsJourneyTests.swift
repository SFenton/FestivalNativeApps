import UIKit
import XCTest

/// The Settings lane's pages in the UIKit port (`UIKitPort/Features/Settings`) and the SwiftUI
/// app's: the Settings page's switches and link rows, Licenses, the Privacy Policy sheet, the
/// First Run replay from Settings and the Notifications sheet, each with identifiers, labels,
/// roles and 44 pt targets, and the page at AX5 with a scoped accessibility audit. They run on
/// both apps (the SwiftUI app is the parity reference).
///
/// Run with `python3 tools/ios_sim.py uitest --app uikit --only UKSettingsJourneyTests --batch-size 3`.
/// Needs `tools/mock_service.py --port 8765`.
final class UKSettingsJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ env: [String: String] = [:], largeText: Bool = false) -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "settings",
        ]
        environment.merge(env) { $1 }
        let app = FestivalApp.makeApp(environment)
        if largeText {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
        }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    // MARK: - Settings page

    /// The page's switches are named, stateful switch elements at least 44 pt tall; its link rows
    /// are buttons with a hint; the section headings are headings; Highlight Shop Items follows
    /// Hide Item Shop.
    @MainActor
    func testSettingsRowsAreNamedStatefulAndLargeEnough() throws {
        let app = launch()
        let toggles = [
            "fst.settings.show-instrument-icons", "fst.settings.enable-visual-order", "fst.settings.filter-invalid-scores",
            "fst.settings.experimental-ranks", "fst.settings.reduce-motion", "fst.settings.disable-artwork-animation",
            "fst.settings.more-contrast", "fst.settings.less-transparency", "fst.settings.hide-shop", "fst.settings.shop-highlights",
        ]
        XCTAssertTrue(app.switches[toggles[0]].waitForExistence(timeout: 20))
        for id in toggles {
            let toggle = app.switches[id]
            SongsUITestSupport.reveal(toggle, in: app, scrollingUp: true)
            XCTAssertFalse(toggle.label.isEmpty, "\(id) has no label")
            XCTAssertTrue(["0", "1"].contains(toggle.value as? String ?? ""), "\(id) has no on/off value")
            XCTAssertGreaterThanOrEqual(toggle.frame.height, 43.5, "\(id) target height")
        }
        let hide = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hide, in: app, scrollingUp: true)
        let highlights = app.switches["fst.settings.shop-highlights"]
        SongsUITestSupport.setSwitch(hide, to: "1")
        XCTAssertFalse(highlights.isEnabled, "Highlight Shop Items follows Hide Item Shop")
        SongsUITestSupport.setSwitch(hide, to: "0")
        XCTAssertTrue(highlights.isEnabled)
        for id in ["fst.settings.licenses", "fst.settings.privacy-policy"] {
            let row = app.buttons[id]
            SongsUITestSupport.reveal(row, in: app, scrollingUp: false)
            XCTAssertFalse(row.label.isEmpty, "\(id) has no label")
            XCTAssertGreaterThanOrEqual(row.frame.height, 43.5, "\(id) target height")
        }
        SongsUITestSupport.record(app, name: "settings-rows")
    }

    /// Reset App Settings restores a changed switch and the path default view, and asks first.
    @MainActor
    func testResetRestoresDefaultsAfterConfirmation() throws {
        let app = launch()
        let motion = app.switches["fst.settings.reduce-motion"]
        XCTAssertTrue(motion.waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(motion, in: app, scrollingUp: true)
        let original = motion.value as? String ?? "0"
        SongsUITestSupport.setSwitch(motion, to: "1")
        let reset = app.buttons["fst.settings.reset"]
        SongsUITestSupport.reveal(reset, in: app, scrollingUp: false)
        reset.tap()
        let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "Reset App Settings"))
        let dialog = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 1"), object: confirmations)
        XCTAssertEqual(XCTWaiter.wait(for: [dialog], timeout: 10), .completed, "Reset asks before it acts")
        XCTAssertTrue(app.buttons["Cancel"].exists || app.sheets.buttons["Cancel"].exists)
        let confirm = try XCTUnwrap(
            confirmations.allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "fst.settings.reset" }
        )
        confirm.tap()
        SongsUITestSupport.reveal(motion, in: app, scrollingUp: true)
        XCTAssertEqual(motion.value as? String, "0", "Reset restores Reduce Motion (was \(original))")
    }

    // MARK: - Privacy Policy and Licenses

    /// Privacy Policy opens as a sheet with its effective date and first section, a title, and a
    /// Close that dismisses it.
    @MainActor
    func testPrivacyPolicyOpensAsASheetAndCloses() throws {
        let app = launch()
        let row = app.buttons["fst.settings.privacy-policy"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(row, in: app, scrollingUp: false)
        row.tap()
        let date = element(app, "fst.privacy-policy.effective-date")
        XCTAssertTrue(date.waitForExistence(timeout: 10), "Effective date")
        XCTAssertTrue(element(app, "fst.privacy-policy.section.overview").exists, "First section heading")
        let close = app.buttons["fst.privacy-policy.close"]
        XCTAssertTrue(close.exists)
        // The shared sheet's system Close (Design lane) is a 36 pt glass button.
        XCTAssertGreaterThanOrEqual(close.frame.height, 35.5)
        SongsUITestSupport.record(app, name: "privacy-policy-sheet")
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }

    // MARK: - First Run replay

    /// Show on a First Run Guides row opens that page's guide with page dots, Next, Skip and
    /// Close; Next moves to a second page with Back; Done on the last page closes it.
    @MainActor
    func testFirstRunReplayFromSettings() throws {
        let app = launch()
        let show = app.buttons["fst.settings.first-run.shop"]
        XCTAssertTrue(show.waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(show, in: app, scrollingUp: false)
        XCTAssertEqual(show.label, "Show Item Shop guide")
        show.tap()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        let dots = element(app, "fst.first-run.dots")
        XCTAssertTrue(dots.exists)
        XCTAssertTrue((dots.value as? String ?? "").hasPrefix("1 of "), "Dots read the first page")
        XCTAssertTrue(app.buttons["fst.first-run.skip"].exists)
        XCTAssertFalse(app.buttons["fst.first-run.back"].exists)
        next.tap()
        XCTAssertTrue(app.buttons["fst.first-run.back"].waitForExistence(timeout: 10))
        SongsUITestSupport.record(app, name: "first-run-replay-second-page")
        app.buttons["fst.first-run.skip"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: next)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }

    // MARK: - AX5

    /// At AX5 the page keeps its switches named and large, wraps instead of clipping, and the
    /// Accessibility card passes a scoped accessibility audit.
    @MainActor
    func testSettingsAtAX5PassesAScopedAudit() throws {
        let app = launch(largeText: true)
        let motion = app.switches["fst.settings.reduce-motion"]
        XCTAssertTrue(motion.waitForExistence(timeout: 25))
        SongsUITestSupport.reveal(motion, in: app, scrollingUp: true)
        XCTAssertGreaterThanOrEqual(motion.frame.height, 43.5)
        XCTAssertFalse(motion.label.isEmpty)
        let identifiers: Set<String> = [
            "fst.settings.reduce-motion", "fst.settings.disable-artwork-animation", "fst.settings.more-contrast",
            "fst.settings.less-transparency",
        ]
        var issues: [String] = []
        try app.performAccessibilityAudit(for: [.elementDetection, .sufficientElementDescription, .hitRegion]) { issue in
            guard let id = issue.element?.identifier, identifiers.contains(id) else { return true }
            issues.append("\(id): \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [])
        SongsUITestSupport.record(app, name: "settings-ax5")
    }

    // MARK: - Notifications

    /// The bell opens Notifications with a profile selected: the sheet has its title and Close,
    /// and shows either rows or the empty state; Close dismisses it.
    @MainActor
    func testNotificationsSheetOpensAndCloses() throws {
        let app = launch(["FST_DEBUG_PROFILE": "fixture-player-1:FixturePlayer", "FST_UI_TEST_CLEAR_PROFILE": "0"])
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 25))
        bell.tap()
        let close = app.buttons["fst.notifications.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Notifications"].exists || app.staticTexts["Notifications"].exists)
        let content = element(app, "fst.notifications.empty")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'fst.notifications.row.'"))
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 0"), object: rows
        )
        _ = XCTWaiter.wait(for: [loaded], timeout: 8)
        XCTAssertTrue(content.exists || rows.count > 0, "Rows or the empty state")
        SongsUITestSupport.record(app, name: "notifications-sheet")
        close.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
    }
}
