import UIKit
import XCTest

// MARK: - Profile bands at AX5 (#312, backfilled by #463)

/// The Player Profile's inline "{name}'s Bands" section (#312) on a real iPhone
/// navigation stack with real Dynamic Type. macOS has no Dynamic Type, so the hosted
/// `FestivalUITests/ProfileBandsSectionAccessibilityTests` (title, section link, loading,
/// failure, empty, activation) and `ProfileBandsCardAccessibilityTests` (cards, rows,
/// View All Bands) pin names, roles, order and targets in `apple-ci`; this journey is
/// the iOS large-text evidence.
///
/// At AX5, after Quick Links › Bands:
/// - the section title is on screen below the navigation bar, grows (> 1.35× its
///   default line height, `RecognizedText`) and renders whole;
/// - the section's View All is a hittable button named "View All {name}'s Bands", at
///   least 44×44 pt;
/// - the Duos card's View All Bands reads "View All Bands (18), Duos", grows and renders
///   whole the same way, spans the card and stays at least 44 pt tall;
/// - a scoped audit (Dynamic Type, clipped text, hit region, description, contrast)
///   finds nothing in the section;
/// - View All Bands opens the player's band list.
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_PROFILE_BANDS_A11Y_FIXTURE_URL` for another mock) on Fixture
/// Player 1 (18 duos, 8 trios, 4 quads). `apple-ci` runs it on its iPhone simulator
/// (`testing/apple/xcuitest.md#ci-journeys`).
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases"; HIG
/// Accessibility: "Strive for the platform's recommended minimum control size" (iOS 44×44 pt).
final class ProfileBandsAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_PROFILE_BANDS_A11Y_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"
    private static let player = "Fixture Player 1"
    private static let title = "\(player)'s Bands"
    private static let viewAllID = "fst.player.bands.view-all.duos"
    /// Duos' View All Bands as drawn, and as spoken (label, then its group).
    private static let viewAllDrawn = "View All Bands (18)"
    private static let viewAllName = "View All Bands (18), Duos"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Journey

    /// At AX5 the section title, its View All and the Duos View All Bands are named,
    /// grow, render whole, keep their targets and open the band list.
    @MainActor
    func testProfileBandsSectionIsReadableAtAX5() throws {
        let standard = launchProfile(size: nil)
        jumpToBands(in: standard)
        let standardTitle = try read(standard.staticTexts[Self.title], drawn: Self.title, "title, default size")
        let standardButton = try reveal(Self.viewAllID, in: standard)
        XCTAssertEqual(standardButton.label, Self.viewAllName)
        let standardLabel = try read(standardButton, drawn: Self.viewAllDrawn, "View All Bands, default size")
        standard.terminate()

        let app = launchProfile(size: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        jumpToBands(in: app)
        let window = app.windows.firstMatch.frame

        // The Quick Link lands on the title, below the navigation bar; it grows and renders whole.
        let title = app.staticTexts[Self.title]
        XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(10)), "the section title shows")
        let bar = app.navigationBars.firstMatch.frame
        XCTAssertGreaterThanOrEqual(title.frame.minY, bar.maxY - 1, "title clears the navigation bar: \(title.frame) vs \(bar)")
        XCTAssertLessThan(title.frame.minY, window.maxY * 0.6, "Quick Links lands on the title: \(title.frame)")
        record(app, name: "profile-bands-title-ax5")
        let titleHeight = try read(title, drawn: Self.title, "title, AX5")
        XCTAssertGreaterThan(titleHeight / standardTitle, RecognizedText.minimumGrowth,
                             "the title grows at AX5: \(titleHeight) vs \(standardTitle) pt")

        // The section's View All: named for its list, a 44 pt target on screen.
        let link = app.buttons["fst.player.bands-link"]
        XCTAssertTrue(link.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertEqual(link.label, "View All \(Self.title)")
        XCTAssertTrue(link.isHittable, "the section's View All is reachable at AX5: \(link.frame)")
        XCTAssertGreaterThanOrEqual(link.frame.width, 44 - 1, "\(link.frame)")
        XCTAssertGreaterThanOrEqual(link.frame.height, 44 - 1, "\(link.frame)")
        XCTAssertLessThanOrEqual(link.frame.maxX, window.maxX + 0.5, "ends on screen: \(link.frame)")

        // The Duos card's View All Bands: named, a full-width 44 pt target that grows whole.
        let button = try reveal(Self.viewAllID, in: app)
        let frame = button.frame
        record(app, name: "profile-bands-view-all-ax5")
        XCTAssertEqual(button.label, Self.viewAllName, "label first, then its group")
        XCTAssertEqual(button.elementType, .button)
        XCTAssertGreaterThanOrEqual(frame.height, 44 - 1, "at least 44 pt tall: \(frame)")
        XCTAssertGreaterThan(frame.width, window.width * 0.75, "spans the card: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "starts on screen: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "ends on screen: \(frame)")
        let labelHeight = try read(button, drawn: Self.viewAllDrawn, "View All Bands, AX5")
        XCTAssertGreaterThan(labelHeight / standardLabel, RecognizedText.minimumGrowth,
                             "View All Bands grows at AX5: \(labelHeight) vs \(standardLabel) pt")

        // Audit the section only: the rest of the profile has its own journeys.
        try auditSection(in: app)

        // Operable: it opens the player's band list.
        if !button.isHittable { _ = try reveal(Self.viewAllID, in: app) }
        button.tap()
        let picker = app.descendants(matching: .any)["fst.player-bands.group-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: FestivalApp.budget(20)), "View All Bands opens the band list")
    }

    /// The failed section's inline Retry (#463): with every API path's first read
    /// answered by a synthetic scrape freeze (`FST_DEBUG_FORCE_FREEZE`, Debug only), the
    /// section shows its inline status, and its Retry is a named button with its own
    /// identifier and a 44×44 pt target that brings the bands back.
    @MainActor
    func testFailedBandsRetryIsANamed44PointTarget() throws {
        let app = launchProfile(size: nil, environment: ["FST_DEBUG_FORCE_FREEZE": "1"])
        // Jump rather than drag: the section is five screens down and auto-retries
        // when the 30 s Retry-After runs out.
        jumpToBands(in: app, once: "fst.player.bands.error")
        let error = app.descendants(matching: .any)["fst.player.bands.error"]
        XCTAssertTrue(error.exists, "the bands read fails once")
        let retry = error.buttons["fst.service-status.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: FestivalApp.budget(5)), "Retry keeps its own identifier")
        // The jump leaves the page's last card on screen; dragging only rubber-bands it.
        XCTAssertTrue(retry.isHittable, "Retry is on screen after the jump: \(retry.frame)")
        let accessory = app.buttons["fst.quick-links.open"].frame
        XCTAssertLessThanOrEqual(retry.frame.maxY, accessory.minY + 0.5, "Retry clears the bottom chrome: \(retry.frame)")
        record(app, name: "profile-bands-failed")
        XCTAssertTrue(retry.label.hasPrefix("Retry"), "'\(retry.label)'")
        let frame = retry.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44 - 0.5, "Retry is 44 pt wide: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 44 - 0.5, "Retry is 44 pt tall: \(frame)")
        retry.tap()
        let card = app.descendants(matching: .any)["fst.player.bands.card.duos"]
        XCTAssertTrue(card.waitForExistence(timeout: FestivalApp.budget(20)), "Retry brings the bands back")
    }

    /// Read an element's drawn text back with the shared `RecognizedText`.
    ///
    /// - Parameters:
    ///   - element: The element on screen.
    ///   - drawn: The text it should draw whole.
    ///   - context: Names the reading in failures.
    /// - Returns: Its recognized line height in points.
    @MainActor
    private func read(_ element: XCUIElement, drawn: String, _ context: String) throws -> CGFloat {
        XCTAssertTrue(element.waitForExistence(timeout: FestivalApp.budget(10)), "\(context): exists")
        let reading = RecognizedText.recognize(element, label: drawn, frame: element.frame)
        XCTAssertTrue(RecognizedText.showsWhole(drawn, in: reading.text),
                      "\(context): '\(drawn)' renders whole: '\(reading.text ?? "nil")'")
        let height = try XCTUnwrap(reading.lineHeight, "\(context): recognized")
        XCTAssertGreaterThan(height, 4, "\(context): a measurable line height")
        return height
    }

    // MARK: - Launch and reveal

    /// Open Fixture Player 1's profile at a text size.
    ///
    /// - Parameters:
    ///   - size: A `UIContentSizeCategory` raw value; nil keeps the default.
    ///   - environment: Extra launch environment.
    /// - Returns: The launched app on the loaded profile.
    @MainActor
    private func launchProfile(size: String?, environment: [String: String] = [:]) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_DEBUG_TAB": "settings",
            "FST_DEBUG_ROUTE": "player:fixture-player-1",
        ]
        env.merge(environment) { $1 }
        let app = FestivalApp.makeApp(env)
        if let size {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        // A forced freeze holds the profile's own read for its 30 s countdown first.
        XCTAssertTrue(SongsUITestSupport.playerPage(in: app).waitForExistence(timeout: FestivalApp.budget(60)),
                      "the profile loads")
        return app
    }

    /// Jump to the bands section with Quick Links, once it shows the given state.
    ///
    /// - Parameters:
    ///   - app: The app on the profile.
    ///   - state: Identifier the section shows before the jump (the Duos card by default).
    @MainActor
    private func jumpToBands(in app: XCUIApplication, once state: String = "fst.player.bands.card.duos") {
        let shown = app.descendants(matching: .any)[state]
        XCTAssertTrue(shown.waitForExistence(timeout: FestivalApp.budget(30)), "the bands section shows \(state)")
        let quickLinks = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(quickLinks.waitForExistence(timeout: FestivalApp.budget(15)), "Quick Links shows")
        quickLinks.tap()
        let first = FestivalApp.quickLinkRow("global", label: "Global Statistics", in: app)
        XCTAssertTrue(first.waitForExistence(timeout: FestivalApp.budget(10)), "Quick Links opens")
        // Bands is the last section; at AX5 the list scrolls (QuickLinksOrderJourneyTests).
        let item = FestivalApp.quickLinkRow("bands", label: "Bands", in: app)
        // Any row: the list is lazy, so the first one leaves the hierarchy as it scrolls.
        let list = app.collectionViews.containing(
            FestivalApp.quickLinkRowsPredicate([("global", "Global Statistics"), ("bands", "Bands")])
        ).firstMatch
        for _ in 0..<8 where !(item.exists && item.isHittable) {
            list.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(item.isHittable, "Quick Links lists Bands")
        item.tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: FestivalApp.budget(10)), "Quick Links closes")
        // Let the jump's scroll settle before reading frames or pixels.
        sleep(UInt32(FestivalApp.budget(1)))
    }

    /// Scroll a button into the middle of the screen, clear of the scroll-edge fades
    /// and the bottom chrome.
    ///
    /// - Parameters:
    ///   - identifier: The button's accessibility identifier.
    ///   - app: The app on the profile.
    /// - Returns: The button, hittable.
    @MainActor
    private func reveal(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let element = app.buttons[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: FestivalApp.budget(20)), "\(identifier) exists")
        reveal(element, in: app)
        return element
    }

    /// Scroll an existing element into the middle of the screen.
    ///
    /// - Parameters:
    ///   - element: The element.
    ///   - app: The app on the profile.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        for _ in 0..<30 {
            let frame = element.frame
            if element.isHittable, frame.minY >= window.height * 0.2, frame.maxY <= window.height * 0.7 { break }
            // Move the element's centre towards the middle, at most 0.4 screen per drag.
            let offset = max(-window.height * 0.4, min(window.height * 0.4, window.height * 0.45 - frame.midY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)))
        }
        sleep(UInt32(FestivalApp.budget(1)))
        XCTAssertTrue(element.isHittable, "\(element.identifier) scrolls on screen: \(element.frame)")
    }

    // MARK: - Audit

    /// Audit the screen and keep only issues in the bands section.
    ///
    /// - Parameter app: The app with the section on screen.
    @MainActor
    private func auditSection(in app: XCUIApplication) throws {
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription, .contrast]
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            guard let element = issue.element else { return true }
            let id = element.identifier
            guard id.hasPrefix("fst.player.bands") || id.hasPrefix("fst.player-bands.row.")
                || element.label == Self.title else { return true }
            issues.append("\(id) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        do {
            try app.performAccessibilityAudit(for: audit, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            // The CI runner can exceed XCTest's audit deadline (#388): retry once.
            issues.removeAll()
            try app.performAccessibilityAudit(for: audit, handler)
        }
        XCTAssertEqual(issues, [], "profile bands audit issues at AX5")
    }

    // MARK: - Evidence

    /// Keep a capture of the screen with the test result.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
