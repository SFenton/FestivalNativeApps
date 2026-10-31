import UIKit
import XCTest

// MARK: - UIKit design gallery

/// The UIKit port's design primitives (`UKDesignGalleryViewController`, opened with
/// `FST_UIKIT_GALLERY=design`): identifiers, labels, selected state, 44 pt targets and
/// AX5 text scaling for the section header, star rating, difficulty meter, instrument
/// icons and selector, marquee, accordion, disclosure group, empty and service states,
/// carousel and sheet chrome.
///
/// The SwiftUI app has no gallery: it ignores the variable, the gallery's scroll view
/// never appears and every test skips, so this file is safe in the SwiftUI app's UI-test
/// target. Run it against the port with
/// `python3 tools/ios_sim.py uitest --app uikit --only UKDesignGalleryJourneyTests`.
///
/// HIG Accessibility: "Strive for the platform's recommended minimum control size" (iOS
/// 44x44 pt); HIG Typography: "Keep text truncation to a minimum as font size increases".
final class UKDesignGalleryJourneyTests: XCTestCase {
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Helpers

    /// Launches the gallery and skips when this build has none.
    @MainActor
    private func openGallery(_ sections: String, size: String? = nil) throws -> XCUIApplication {
        let app = FestivalApp.makeApp(["FST_UIKIT_GALLERY": "design:\(sections)"])
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        let scroll = app.scrollViews["fst.uikit.gallery.design.scroll"]
        if !scroll.waitForExistence(timeout: FestivalApp.budget(8)) {
            throw XCTSkip("No UIKit design gallery in this build (SwiftUI app)")
        }
        return app
    }

    /// Scrolls the gallery until `element` is hittable.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews["fst.uikit.gallery.design.scroll"]
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < 24 {
            scroll.swipeUp(velocity: .fast)
            swipes += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) never became visible", file: file, line: line)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertTarget(_ element: XCUIElement, minimum: CGFloat = 44, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.height, minimum - 0.5, "\(name) is shorter than \(minimum) pt", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, minimum - 0.5, "\(name) is narrower than \(minimum) pt", file: file, line: line)
    }

    // MARK: Tests

    /// Text, section header, surfaces and the group card exist with their copy.
    @MainActor
    func testSurfacesAndGroupSection() throws {
        let app = try openGallery("section-header,surfaces,group")
        XCTAssertTrue(app.staticTexts["Find a Profile"].exists, "section header title")
        XCTAssertTrue(app.staticTexts["Search by username."].exists, "section header subtitle")
        for role in ["card", "control", "overlay"] {
            reveal(element("fst.uikit.gallery.glass.\(role)", in: app), in: app)
        }
        reveal(app.staticTexts["Padded row 3"], in: app)
        let viewAll = app.buttons["fst.uikit.gallery.view-all"]
        reveal(viewAll, in: app)
        XCTAssertEqual(viewAll.label, "View All Item Shop")
        assertTarget(viewAll, "View All")
    }

    /// Stars and the difficulty meter speak the same labels as the SwiftUI views.
    @MainActor
    func testStarsAndDifficultyLabels() throws {
        let app = try openGallery("stars,difficulty")
        let three = app.images["3 stars"]
        reveal(three, in: app)
        XCTAssertTrue(app.images["5 gold stars"].exists)
        XCTAssertTrue(app.images["4 stars"].exists)
        let meter = app.descendants(matching: .any).matching(identifier: "fst.songs.difficulty-meter")
        XCTAssertTrue(meter.matching(NSPredicate(format: "label == %@", "Difficulty 4 of 7")).firstMatch.exists)
        XCTAssertTrue(meter.matching(NSPredicate(format: "label == %@", "Difficulty 3 of 7")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["fst.songs.difficulty-unavailable"].exists)
        XCTAssertEqual(app.staticTexts["fst.songs.difficulty-unavailable"].label, "Difficulty unavailable")
    }

    /// The instrument selector toggles, marks the chosen instrument selected, keeps 64 pt
    /// targets and lays out as arrows when compact.
    @MainActor
    func testInstrumentSelector() throws {
        let app = try openGallery("selector")
        let lead = app.buttons["fst.uikit.gallery.selector.full.lead"]
        reveal(lead, in: app)
        XCTAssertEqual(lead.label, "Lead")
        XCTAssertTrue(lead.isSelected, "initial choice is selected")
        let bass = app.buttons["fst.uikit.gallery.selector.full.bass"]
        assertTarget(bass, minimum: 64, "instrument circle")
        bass.tap()
        XCTAssertTrue(bass.isSelected)
        XCTAssertFalse(lead.isSelected)
        XCTAssertTrue(app.staticTexts["Selected: Bass"].waitForExistence(timeout: 2))
        let next = app.buttons["fst.uikit.gallery.selector.compact.next"]
        reveal(next, in: app)
        XCTAssertEqual(next.label, "Next Instrument")
        assertTarget(next, "compact next arrow")
        XCTAssertTrue(app.buttons["fst.uikit.gallery.selector.compact.centre"].exists)
        let muted = app.buttons["fst.uikit.gallery.selector.states.bass"]
        reveal(muted, in: app)
        XCTAssertEqual(muted.value as? String ?? "", "")
        XCTAssertFalse(app.buttons["fst.uikit.gallery.selector.states.vocals"].isEnabled, "disabled instrument")
    }

    /// The accordion opens its content and the disclosure group announces its state.
    @MainActor
    func testAccordionAndDisclosure() throws {
        let app = try openGallery("accordion")
        let toggle = app.buttons["fst.uikit.gallery.accordion.toggle"]
        reveal(toggle, in: app)
        XCTAssertFalse(app.staticTexts["fst.uikit.gallery.accordion.content"].exists)
        toggle.tap()
        XCTAssertTrue(app.staticTexts["fst.uikit.gallery.accordion.content"].waitForExistence(timeout: 2))
        let disclosure = app.buttons["fst.uikit.gallery.disclosure"]
        reveal(disclosure, in: app)
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        assertTarget(disclosure, minimum: 44, "disclosure header")
        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Disclosed body text."].waitForExistence(timeout: 2))
    }

    /// Empty, loading and service states carry their identifiers, labels and 44 pt retry.
    @MainActor
    func testCommonStates() throws {
        let app = try openGallery("states")
        reveal(app.staticTexts["No Songs"], in: app)
        XCTAssertTrue(app.staticTexts["Try a different filter."].exists)
        let combined = app.staticTexts["fst.uikit.gallery.empty.combined"]
        reveal(combined, in: app)
        XCTAssertEqual(combined.label, "No Results. Search for a song, artist or player.")
        reveal(app.staticTexts["Loading songs"], in: app)
        let retry = app.buttons.matching(identifier: "fst.service-status.retry").firstMatch
        reveal(retry, in: app)
        assertTarget(retry, "Retry")
        let title = app.staticTexts["fst.service-status.title"]
        reveal(title, in: app)
        let countdown = app.staticTexts["fst.service-status.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 4), "scrape freeze counts down")
        XCTAssertTrue(countdown.label.hasPrefix("Trying again automatically in "), countdown.label)
        reveal(app.otherElements["fst.service-status.inline"], in: app)
        XCTAssertTrue(app.staticTexts["Update failed: The network connection was lost."].exists || app.staticTexts.matching(identifier: "fst.songs.refresh-error").firstMatch.exists)
    }

    /// Marquee text is one static text with its full string, even while it overflows.
    @MainActor
    func testMarqueeIsSpokenInFull() throws {
        let app = try openGallery("marquee")
        let marquee = app.staticTexts["fst.uikit.gallery.marquee.long"]
        reveal(marquee, in: app)
        XCTAssertEqual(marquee.label, "A very long song title that does not fit on one line at all, so it scrolls")
    }

    /// Page titles combine title and subtitle into one element.
    @MainActor
    func testInstrumentPageTitles() throws {
        let app = try openGallery("titles")
        let header = app.descendants(matching: .any).matching(identifier: "fst.uikit.gallery.title.header").firstMatch
        reveal(header, in: app)
        XCTAssertEqual(header.label, "Lead Guitar, Rank 12")
        let pinned = element("fst.uikit.gallery.title.pinned", in: app)
        XCTAssertEqual(pinned.label, "Bass Leaderboard, Top 100")
    }

    /// The carousel exposes one adjustable page indicator that pages the cards.
    @MainActor
    func testCarouselIndicator() throws {
        let app = try openGallery("carousel")
        let indicator = element("fst.carousel.indicator", in: app)
        reveal(indicator, in: app)
        XCTAssertEqual(indicator.label, "Gallery Cards")
        XCTAssertTrue((indicator.value as? String ?? "").hasPrefix("Page 1 of 5"), "\(String(describing: indicator.value))")
        indicator.adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue((indicator.value as? String ?? "").hasPrefix("Page 2 of 5"), "\(String(describing: indicator.value))")
    }

    /// The sheet opens with its title and a 44 pt Close button, and closes.
    @MainActor
    func testSheetChrome() throws {
        let app = try openGallery("sheet")
        let open = app.buttons["fst.uikit.gallery.sheet.open"]
        reveal(open, in: app)
        open.tap()
        let close = app.buttons["fst.uikit.gallery.sheet.close"]
        XCTAssertTrue(close.waitForExistence(timeout: FestivalApp.budget(5)))
        XCTAssertEqual(close.label, "Close")
        assertTarget(close, "sheet Close")
        XCTAssertTrue(app.staticTexts["Sheet row 1"].exists)
        close.tap()
        XCTAssertTrue(app.buttons["fst.uikit.gallery.sheet.open"].waitForExistence(timeout: FestivalApp.budget(5)))
    }

    /// At AX5 text grows and wraps, targets stay 44 pt and nothing clips.
    @MainActor
    func testAccessibilityTextScaling() throws {
        let normal = try openGallery("text,group,accordion")
        let body = normal.staticTexts["Body text wraps at every Dynamic Type size up to AX5 and stays white."]
        XCTAssertTrue(body.exists)
        let normalHeight = body.frame.height
        normal.terminate()

        let large = try openGallery("text,group,accordion", size: Self.ax5)
        let big = large.staticTexts["Body text wraps at every Dynamic Type size up to AX5 and stays white."]
        XCTAssertTrue(big.waitForExistence(timeout: 4))
        XCTAssertGreaterThan(big.frame.height, normalHeight * 1.35, "body text grows with Dynamic Type")
        XCTAssertLessThanOrEqual(big.frame.width, large.frame.width, "body text wraps within the screen")
        let viewAll = large.buttons["fst.uikit.gallery.view-all"]
        reveal(viewAll, in: large)
        assertTarget(viewAll, "View All at AX5")
        let toggle = large.buttons["fst.uikit.gallery.accordion.toggle"]
        reveal(toggle, in: large)
        assertTarget(toggle, "accordion toggle at AX5")
        try large.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
            // The marquee rows scroll instead of wrapping, by design (MarqueeText).
            issue.element?.identifier.contains("marquee") == true
        }
    }
}
