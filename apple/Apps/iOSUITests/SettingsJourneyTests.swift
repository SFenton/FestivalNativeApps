import UIKit
import XCTest

/// Native journeys for Settings: a toggle survives a cold relaunch, the inline reorder
/// lists drag to reorder, View Licenses opens a third-party-only page, Privacy Policy opens
/// a dismissible sheet, and Reset App
/// Settings restores a changed toggle to its registered default
/// (`SettingsRegistry.defaults`). Needs `tools/mock_service.py --port 18790`.
///
/// **Re-investigated and un-skipped 2026-09-28 (Lane C):** all three methods
/// were previously skipped as "consistently hung the full 300s lock-hold
/// budget, inconclusive root cause." Ruled out a product bug on inspection:
/// unlike `Features/Songs` (see `Design/MarqueeText.swift`'s fix for
/// `FST_DEBUG_STILL_BACKGROUND` not stopping its `TimelineView`), nothing in
/// `Features/Settings/**` or `FirstRunSettingsSection.swift` uses
/// `TimelineView`/`repeatForever`/`Timer`, and a live `tools/ios_sim.py drive`
/// load-then-scroll-then-tap sequence against Settings completed in under 20s.
/// Re-run individually via `tools/ios_sim.py uitest` after this lane's
/// `FestivalApp` launch-helper fix (every journey now always gets
/// `FST_DEBUG_STILL_BACKGROUND=1`): all three passed alone —
/// `testSongRowOrderReorderSheetOpensAndCloses` in 267.8s (cold
/// build-for-testing), `testResetAppSettingsRestoresChangedToggle` in 68.2s,
/// `testAccessibilityToggleSurvivesRelaunch` (a full terminate+relaunch) in
/// 281.8s. Running two of them together in one 200s batch did time out once
/// during this investigation — consistent with the original finding being
/// shared-simulator contention (this Mac had 10+ other lanes' concurrent
/// `xcodebuild` processes at points during this session) rather than a
/// deterministic hang: batch multiple Settings tests with a generous
/// `--timeout` (300s+) or run them one at a time.
final class SettingsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_API_BASE_URL": "http://127.0.0.1:18790",
            "FST_DEBUG_TAB": "settings",
        ])
    }

    /// Toggling an accessibility override must still read back the same value after
    /// a full process relaunch (real `UserDefaults.standard`, not `FST_DEBUG_PROFILE`'s
    /// in-memory-only identity), then restore it so later tests see the default.
    @MainActor
    func testAccessibilityToggleSurvivesRelaunch() throws {
        continueAfterFailure = false
        let toggleId = "fst.settings.more-contrast"
        let firstLaunch = fixtureApp()
        firstLaunch.launch()
        let toggle = firstLaunch.switches[toggleId]
        SongsUITestSupport.reveal(toggle, in: firstLaunch, scrollingUp: true)
        let original = try XCTUnwrap(toggle.value as? String)
        let flipped = original == "1" ? "0" : "1"
        SongsUITestSupport.setSwitch(toggle, to: flipped)
        SongsUITestSupport.record(firstLaunch, name: "settings-toggle-before-relaunch")
        firstLaunch.terminate()

        let relaunched = fixtureApp()
        relaunched.launch()
        let restoredToggle = relaunched.switches[toggleId]
        SongsUITestSupport.reveal(restoredToggle, in: relaunched, scrollingUp: true)
        XCTAssertEqual(
            restoredToggle.value as? String, flipped,
            "Accessibility override did not survive a cold relaunch"
        )
        SongsUITestSupport.record(relaunched, name: "settings-toggle-after-relaunch")
        // Restore the original value so later tests/lanes see the registered default.
        SongsUITestSupport.setSwitch(restoredToggle, to: original)
    }

    /// Operator batch 6 (6.11): enabling Independent Song Row Visual Order shows its
    /// reorder list inline (no sheet), and CHOpt Text Path Column Order rows reorder by
    /// dragging their grip handle; Reset restores the default order.
    @MainActor
    func testInlineReorderListsDragToReorder() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let enable = app.switches["fst.settings.enable-visual-order"]
        SongsUITestSupport.reveal(enable, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(enable, to: "1")
        let visualScore = app.descendants(matching: .any)
            .matching(identifier: "fst.settings.song-row-order.score").firstMatch
        XCTAssertTrue(visualScore.waitForExistence(timeout: 10), "Visual order list is not inline")
        XCTAssertFalse(app.buttons["Done"].exists, "No reorder sheet")

        func row(_ key: String) -> XCUIElement {
            app.descendants(matching: .any)
                .matching(identifier: "fst.settings.path-column-order.\(key)").firstMatch
        }
        // Earlier runs may have left a custom order: find the current first and last rows.
        let keys = ["note", "beat", "time", "od", "score"]
        SongsUITestSupport.reveal(row("score"), in: app, scrollingUp: true)
        SongsUITestSupport.reveal(row("note"), in: app, scrollingUp: false)
        let first = try XCTUnwrap(keys.map(row).first { $0.value as? String == "1 of 5" })
        let last = try XCTUnwrap(keys.map(row).first { $0.value as? String == "5 of 5" })
        XCTAssertLessThan(first.frame.minY, last.frame.minY)
        SongsUITestSupport.record(app, name: "settings-path-columns-before-drag")

        // Drag the last row by its leading grip handle onto the first.
        last.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).press(
            forDuration: 0.3,
            thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.3))
        )
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1 of 5"), object: last
        )
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 10), .completed, "Row was not dragged to the top")
        XCTAssertEqual(first.value as? String, "2 of 5")
        SongsUITestSupport.record(app, name: "settings-path-columns-after-drag")
        let score = row("score")

        // A quick swipe that starts on the list still scrolls the page.
        let before = score.frame.minY
        app.swipeUp()
        XCTAssertNotEqual(score.frame.minY, before, "Swiping over a reorder list must scroll the page")

        let resetButton = app.buttons["fst.settings.reset"]
        SongsUITestSupport.reveal(resetButton, in: app, scrollingUp: true)
        resetButton.tap()
        // The page button shares the dialog button's label; tap the dialog's.
        let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "Reset App Settings"))
        let dialog = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 1"), object: confirmations
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dialog], timeout: 10), .completed)
        let confirm = try XCTUnwrap(
            confirmations.allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "fst.settings.reset" }
        )
        confirm.tap()
        SongsUITestSupport.reveal(score, in: app, scrollingUp: false)
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "5 of 5"), object: score
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
        XCTAssertFalse(visualScore.exists, "Reset turns the independent visual order off")
    }

    /// Operator batch 6 (6.17): View Licenses opens the Licenses page without a Bundled
    /// Assets section or iconography entry.
    @MainActor
    func testLicensesRowOpensThirdPartyOnlyPage() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let licenses = app.buttons["fst.settings.licenses"]
        SongsUITestSupport.reveal(licenses, in: app, scrollingUp: true)
        licenses.tap()
        XCTAssertTrue(app.staticTexts["Third-Party Software"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Bundled Assets"].exists)
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Iconography")).firstMatch.exists)
        SongsUITestSupport.record(app, name: "settings-licenses-page")
    }

    /// Issue #98: the Privacy Policy row opens the policy as a titled sheet whose text
    /// scrolls to its Contact section, and the system Close returns to Settings.
    @MainActor
    func testPrivacyPolicyRowOpensDismissibleSheet() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let row = app.buttons["fst.settings.privacy-policy"]
        SongsUITestSupport.reveal(row, in: app, scrollingUp: true)
        row.tap()

        XCTAssertTrue(app.navigationBars["Privacy Policy"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["fst.privacy-policy.effective-date"].exists)
        let firstHeading = app.staticTexts["fst.privacy-policy.section.information-collected"]
        XCTAssertTrue(firstHeading.exists)
        SongsUITestSupport.record(app, name: "settings-privacy-policy-top")

        let contact = app.staticTexts["fst.privacy-policy.section.contact"]
        let content = app.scrollViews["fst.privacy-policy.content"]
        for _ in 0..<12 where !contact.isHittable {
            content.swipeUp()
        }
        XCTAssertTrue(contact.isHittable, "The policy does not scroll to its Contact section")
        let contactText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "github.com/SFenton/FestivalNativeApps/issues")
        ).firstMatch
        XCTAssertTrue(contactText.exists, "Contact Us names the public issues page")
        SongsUITestSupport.record(app, name: "settings-privacy-policy-contact")

        let close = app.navigationBars.buttons["fst.privacy-policy.close"]
        XCTAssertEqual(close.label, "Close")
        close.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Privacy Policy"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
    }

    /// Reset App Settings restores a changed toggle to its registered default.
    @MainActor
    func testResetAppSettingsRestoresChangedToggle() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let hideShop = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(hideShop, in: app, scrollingUp: true)
        SongsUITestSupport.setSwitch(hideShop, to: "1")
        SongsUITestSupport.record(app, name: "settings-hide-shop-before-reset")

        let resetButton = app.buttons["fst.settings.reset"]
        SongsUITestSupport.reveal(resetButton, in: app, scrollingUp: false)
        resetButton.tap()
        let confirmations = app.buttons.matching(NSPredicate(format: "label == %@", "Reset App Settings"))
        let dialog = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > 1"), object: confirmations
        )
        XCTAssertEqual(XCTWaiter.wait(for: [dialog], timeout: 10), .completed)
        let confirm = try XCTUnwrap(
            confirmations.allElementsBoundByIndex.first { $0.isHittable && $0.identifier != "fst.settings.reset" }
        )
        confirm.tap()

        let restoredHideShop = app.switches["fst.settings.hide-shop"]
        SongsUITestSupport.reveal(restoredHideShop, in: app, scrollingUp: true)
        let settledOff = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "0"), object: restoredHideShop
        )
        XCTAssertEqual(XCTWaiter.wait(for: [settledOff], timeout: 10), .completed)
        SongsUITestSupport.record(app, name: "settings-hide-shop-after-reset")
    }

    /// **Removed (#374):** the Debug-only Diagnostics section (Tap Diagnostics, Tap
    /// Telemetry) must not render in this Debug build. Sweeps the whole page from the top
    /// to Reset App Settings so a lazily realized section cannot slip past offscreen.
    @MainActor
    func testDiagnosticsSectionIsAbsentInDebug() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.buttons["fst.quick-links.open"].waitForExistence(timeout: 15), "Settings did not load")
        let reset = app.buttons["fst.settings.reset"]
        // Positive control: the sweep must pass Accessibility, where Diagnostics used to sit.
        let accessibility = app.switches["fst.settings.more-contrast"]
        var sawAccessibility = false
        var reachedReset = false
        for _ in 0..<24 {
            XCTAssertFalse(app.switches["fst.settings.tap-diagnostics"].exists, "Tap Diagnostics is back")
            XCTAssertFalse(app.switches["fst.settings.tap-telemetry"].exists, "Tap Telemetry is back")
            XCTAssertFalse(app.staticTexts["Diagnostics"].exists, "The Diagnostics section header is back")
            XCTAssertFalse(app.staticTexts["Tap Diagnostics"].exists, "Tap Diagnostics copy is back")
            sawAccessibility = sawAccessibility || accessibility.exists
            if reset.exists && reset.isHittable {
                reachedReset = true
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(sawAccessibility, "The sweep never passed the Accessibility section")
        XCTAssertTrue(reachedReset, "Did not sweep Settings down to Reset App Settings")
        SongsUITestSupport.record(app, name: "settings-no-diagnostics")
    }

    /// **Fixed bug (#6):** the iPhone Quick Links menu must keep the page's section
    /// order instead of letting iOS reorder an `.automatic` menu. `QuickLinksMenu` now
    /// uses `.menuOrder(.fixed)`. Rows must stack top-to-bottom in page order, the active
    /// section stays checked, and choosing a row still jumps to it.
    @MainActor
    func testQuickLinksMenuListsSectionsInPageOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        quickLinks.tap()

        let pageOrder = [
            "app-settings", "accessibility", "item-shop", "show-instruments",
            "show-metadata", "version", "service-info", "first-run", "licenses", "privacy-policy",
            "reset",
        ]
        let rows = pageOrder.map { app.buttons["fst.quick-links.item.\($0)"] }
        XCTAssertTrue(rows[0].waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.buttons["fst.quick-links.item.diagnostics"].exists,
            "The removed Diagnostics section is offered as a Quick Link (#374)"
        )
        let tops = rows.map(\.frame.minY)
        XCTAssertEqual(tops, tops.sorted(), "Quick Links rows are not in page order: \(zip(pageOrder, tops).map { "\($0.0)@\(Int($0.1))" })")
        XCTAssertLessThan(tops[0], tops[tops.count - 1])
        XCTAssertTrue(rows[0].isSelected, "The active (first) section is not checked")
        SongsUITestSupport.record(app, name: "settings-quick-links-menu-order")

        let itemShop = app.buttons["fst.quick-links.item.item-shop"]
        itemShop.tap()
        let jumped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Item Shop"), object: quickLinks
        )
        XCTAssertEqual(XCTWaiter.wait(for: [jumped], timeout: 10), .completed)
    }

    /// **Fixed bug (#12):** a Quick Link landed its section flush with the navigation
    /// bar's bottom edge, inside iOS 26's scroll-edge effect, so the section title was
    /// blurred and dimmed. Each jump must now land the title about 32 pt below the bar
    /// (`QuickLinks.defaultActivationOffset`), clear of that effect but not far below.
    @MainActor
    func testQuickLinksLandSectionTitlesBelowTheNavigationBar() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))

        let targets = [
            ("accessibility", "Accessibility"), ("item-shop", "Item Shop"),
            ("service-info", "Service Info"), ("show-instruments", "Show Instruments"),
        ]
        for (id, title) in targets {
            quickLinks.tap()
            let row = app.buttons["fst.quick-links.item.\(id)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            let landed = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    MainActor.assumeIsolated {
                        Self.titleGap(title, in: app).map { (24...48).contains($0) } ?? false
                    }
                },
                object: nil
            )
            let outcome = XCTWaiter.wait(for: [landed], timeout: 8)
            let gap = Self.titleGap(title, in: app)
            XCTAssertEqual(
                outcome, .completed,
                "\(title) landed \(gap.map { "\(Int($0)) pt" } ?? "off screen") below the navigation bar; expected ~32 pt"
            )
        }
        SongsUITestSupport.record(app, name: "settings-quick-links-landing")
    }

    /// **Accessibility (#393, for #12):** at the largest accessibility text size the
    /// Quick Links control keeps its name and a 44×44 pt target (HIG Accessibility),
    /// each sheet row is named and at least 44 pt tall, and every jump leaves its section
    /// title whole and hittable below the navigation bar, clear of the scroll-edge blur,
    /// while the control's VoiceOver value names that section. Includes the last section,
    /// which cannot scroll up to the line and must still own the value.
    @MainActor
    func testQuickLinksLandingIsAccessibleAtLargestText() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        XCTAssertEqual(quickLinks.label, "Quick Links")
        XCTAssertTrue(quickLinks.isHittable)
        XCTAssertGreaterThanOrEqual(quickLinks.frame.width, 44, "Quick Links is narrower than 44 pt")
        XCTAssertGreaterThanOrEqual(quickLinks.frame.height, 44, "Quick Links is shorter than 44 pt")

        let targets = [
            ("item-shop", "Item Shop"), ("accessibility", "Accessibility"),
            ("service-info", "Service Info"), ("reset", "Reset Settings"),
        ]
        for (id, title) in targets {
            Self.assertQuickLinksJump(to: id, title: title, landing: id == "reset" ? .clampedEnd : .line, in: app)
        }
        SongsUITestSupport.record(app, name: "settings-quick-links-landing-ax5")
    }

    /// **Accessibility (#393, for #12; scroll-edge R7):** with Reduce Transparency the
    /// navigation bar's scroll edge is a hard edge (no blur or ramp to land clear of), and
    /// a Quick Links jump must still leave its title whole, hittable and below the bar,
    /// never under it, while the control's VoiceOver value names that section. Uses the
    /// app's Less Transparency (a launch argument, so nothing persists), which
    /// `ScrollEdgeHardEdge` treats exactly like the system setting; run it again with
    /// `ios_sim.py uitest --a11y reduce-transparency` for the system path. Covers ordinary
    /// targets down and back up, and both clamped ends: Reset Settings (cannot scroll up
    /// to the line) and App Settings (the top of the page).
    @MainActor
    func testQuickLinksLandingKeepsTitlesClearWithReduceTransparency() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launchArguments += ["-fst.accessibility.lessTransparency", "YES"]
        app.launch()
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: 15))
        XCTAssertEqual(quickLinks.label, "Quick Links")
        XCTAssertTrue(quickLinks.isHittable)
        XCTAssertGreaterThanOrEqual(quickLinks.frame.width, 44, "Quick Links is narrower than 44 pt")
        XCTAssertGreaterThanOrEqual(quickLinks.frame.height, 44, "Quick Links is shorter than 44 pt")

        let targets: [(String, String, QuickLinksLanding)] = [
            ("item-shop", "Item Shop", .line), ("accessibility", "Accessibility", .line),
            ("first-run", "First Run Guides", .line), ("reset", "Reset Settings", .clampedEnd),
            ("show-metadata", "Show Instrument Metadata", .line), ("app-settings", "App Settings", .clampedTop),
        ]
        for (id, title, landing) in targets {
            Self.assertQuickLinksJump(to: id, title: title, landing: landing, in: app)
            if id == "accessibility" {
                // The hard-edge state is really on: the section just landed shows it.
                let lessTransparency = app.switches["fst.settings.less-transparency"]
                XCTAssertTrue(lessTransparency.exists, "The Accessibility section has no Reduce Transparency switch")
                XCTAssertEqual(lessTransparency.value as? String, "1", "Reduce Transparency is not on for this journey")
            }
            SongsUITestSupport.record(app, name: "settings-quick-links-landing-reduce-transparency-\(id)")
        }
    }

    /// Where a Quick Links jump may leave its section title.
    enum QuickLinksLanding {
        /// On the landing line, about 32 pt below the navigation bar.
        case line
        /// The last section: it cannot scroll up to the line, so anywhere 24 pt or more
        /// below the bar while whole on screen.
        case clampedEnd
        /// The first section: the page rests at its top, so anywhere at or below the bar.
        case clampedTop
    }

    /// Open Quick Links, pick a section and check what an assistive-technology user
    /// gets (#393): a named sheet row at least 44 pt tall, then the section title whole,
    /// hittable and clear of the navigation bar, and a Quick Links VoiceOver value that
    /// names the section and keeps naming it after the jump settles.
    ///
    /// - Parameters:
    ///   - id: The section's Quick Links id (`fst.quick-links.item.<id>`).
    ///   - title: Its title, as the sheet row and the section heading read.
    ///   - landing: Where the title may land.
    ///   - app: Foreground app, on a page with Quick Links.
    @MainActor
    private static func assertQuickLinksJump(
        to id: String, title: String, landing: QuickLinksLanding, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let quickLinks = app.buttons["fst.quick-links.open"]
        quickLinks.tap()
        // At AX5 the Quick Links sheet scrolls; rows past its fold are absent until revealed.
        let menuRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.quick-links.item."))
        XCTAssertTrue(menuRows.firstMatch.waitForExistence(timeout: 10), file: file, line: line)
        let row = app.buttons["fst.quick-links.item.\(id)"]
        let window = app.windows.firstMatch
        for _ in 0..<8 where !(row.exists && row.isHittable && row.frame.maxY <= window.frame.maxY) {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            )
        }
        XCTAssertTrue(
            row.exists && row.isHittable,
            "The \(id) row cannot be reached in the Quick Links sheet: "
                + menuRows.allElementsBoundByIndex.map { "\($0.identifier)@\(Int($0.frame.minY))\($0.isHittable ? "" : "(hidden)")" }.joined(separator: ", "),
            file: file, line: line
        )
        XCTAssertTrue(row.label.contains(title), "The \(id) row reads \"\(row.label)\"", file: file, line: line)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, "The \(id) row is shorter than 44 pt", file: file, line: line)
        row.tap()
        let named = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", title), object: quickLinks
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [named], timeout: 10), .completed,
            "Quick Links reads \(String(describing: quickLinks.value))", file: file, line: line
        )
        let minimumGap: CGFloat = landing == .clampedTop ? 0 : 24
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                MainActor.assumeIsolated {
                    landedTitle(title, in: app).map { $0.gap >= minimumGap && $0.frame.maxY <= app.frame.maxY } ?? false
                }
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [visible], timeout: 8), .completed,
            "\(title) is under the bar or off screen (\(landedTitle(title, in: app).map { "\(Int($0.gap)) pt below the bar" } ?? "not found"))",
            file: file, line: line
        )
        if landing == .line {
            let gap = landedTitle(title, in: app)?.gap ?? .infinity
            XCTAssertLessThanOrEqual(
                gap, 48, "\(title) landed \(Int(gap)) pt below the navigation bar; expected ~32 pt", file: file, line: line
            )
        }
        // A clamped section must keep the value once the jump settles.
        let dropped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", title), object: quickLinks
        )
        dropped.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [dropped], timeout: 2), .completed,
            "Quick Links stopped naming \(title) after the jump settled", file: file, line: line
        )
    }

    /// The highest copy of a section title at or below the navigation bar, with its gap
    /// below the bar, once it is hittable.
    ///
    /// - Parameters:
    ///   - title: The section title's label.
    ///   - app: Foreground app.
    /// - Returns: The title's frame and gap, or `nil` when no hittable copy is near the top.
    @MainActor
    private static func landedTitle(_ title: String, in app: XCUIApplication) -> (frame: CGRect, gap: CGFloat)? {
        let barBottom = app.navigationBars.firstMatch.frame.maxY
        return app.staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
            .filter { $0.frame.minY >= barBottom - 8 && $0.isHittable }
            .min { $0.frame.minY < $1.frame.minY }
            .map { ($0.frame, $0.frame.minY - barBottom) }
    }

    /// Distance from the navigation bar's bottom to the highest on-screen copy of a
    /// section title at or below it (another row may reuse the same words further down).
    ///
    /// - Parameters:
    ///   - title: The section title's label.
    ///   - app: Foreground app.
    /// - Returns: The gap in points, or `nil` when no copy is near the top.
    @MainActor
    private static func titleGap(_ title: String, in app: XCUIApplication) -> CGFloat? {
        let barBottom = app.navigationBars.firstMatch.frame.maxY
        return app.staticTexts.matching(NSPredicate(format: "label == %@", title)).allElementsBoundByIndex
            .map(\.frame.minY)
            .filter { $0 >= barBottom - 8 }
            .min()
            .map { $0 - barBottom }
    }
}
