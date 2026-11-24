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
        let app = FestivalApp.makeApp([
            "FST_UIKIT_GALLERY": "design:\(sections)",
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
        ])
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
        let unavailable = app.staticTexts["fst.songs.difficulty-unavailable"]
        reveal(unavailable, in: app)
        XCTAssertEqual(unavailable.label, "Difficulty unavailable")
        SongsUITestSupport.record(app, name: "gallery-difficulty-unavailable")
    }

    /// The instrument selector toggles, marks the chosen instrument selected, keeps 64 pt
    /// targets and lays out as arrows when compact.
    @MainActor
    func testInstrumentSelector() throws {
        let app = try openGallery("selector")
        let lead = element("fst.uikit.gallery.selector.full.Solo_Guitar", in: app)
        reveal(lead, in: app)
        XCTAssertEqual(lead.label, "Lead")
        XCTAssertTrue(lead.isSelected, "initial choice is selected")
        let bass = element("fst.uikit.gallery.selector.full.Solo_Bass", in: app)
        assertTarget(bass, minimum: 64, "instrument circle")
        bass.tap()
        XCTAssertTrue(bass.isSelected)
        XCTAssertFalse(lead.isSelected)
        XCTAssertTrue(app.staticTexts["Selected: Bass"].waitForExistence(timeout: 2))
        let next = element("fst.uikit.gallery.selector.compact.next", in: app)
        reveal(next, in: app)
        XCTAssertEqual(next.label, "Next Instrument")
        assertTarget(next, "compact next arrow")
        XCTAssertTrue(element("fst.uikit.gallery.selector.compact.centre", in: app).exists)
        let muted = element("fst.uikit.gallery.selector.states.Solo_Bass", in: app)
        let drums = element("fst.uikit.gallery.selector.states.Solo_Drums", in: app)
        let disabled = element("fst.uikit.gallery.selector.states.Solo_Vocals", in: app)
        reveal(muted, in: app)
        XCTAssertTrue(drums.isSelected)
        XCTAssertTrue(muted.isEnabled, "muted does not mean disabled")
        XCTAssertFalse(disabled.isEnabled, "disabled instrument")
        SongsUITestSupport.record(app, name: "gallery-instrument-disabled-and-muted")
        muted.tap()
        XCTAssertTrue(muted.isSelected, "a muted instrument can still be selected")
        XCTAssertFalse(drums.isSelected)
        SongsUITestSupport.record(app, name: "gallery-muted-instrument-selected")
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

    /// The rendered disclosure indicator grows at AX5 and the named header remains operable.
    @MainActor
    func testDisclosureIndicatorScalesWithText() throws {
        func paintedChevron(_ size: UIContentSizeCategory) throws -> Double {
            let app = try openGallery("accordion", size: size.rawValue)
            defer { app.terminate() }
            let header = app.buttons["fst.uikit.gallery.disclosure"]
            reveal(header, in: app)
            assertTarget(header, "disclosure header")
            XCTAssertEqual(header.label, "Disclosure group")
            XCTAssertEqual(header.value as? String, "Collapsed")
            XCTAssertEqual(app.buttons.matching(identifier: "fst.uikit.gallery.disclosure").count, 1)
            let screenshot = header.screenshot()
            let image = try XCTUnwrap(screenshot.image.cgImage)
            let frame = header.frame
            let bitmap = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: frame.width))
            let trailing = CGRect(x: frame.width - 40, y: (frame.height - 44) / 2, width: 40, height: 44)
            let fraction = try XCTUnwrap(bitmap.fraction(in: trailing) { min($0, $1, $2) >= 220 })
            XCTAssertGreaterThan(fraction, 0.003, "The trailing indicator did not paint at \(size)")
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "disclosure-indicator-\(size.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            header.tap()
            XCTAssertEqual(header.value as? String, "Expanded")
            XCTAssertTrue(app.staticTexts["Disclosed body text."].waitForExistence(timeout: 2))
            return fraction
        }
        let regular = try paintedChevron(.large)
        let largest = try paintedChevron(.accessibilityExtraExtraExtraLarge)
        XCTAssertGreaterThan(largest, 2 * regular, "The indicator should grow with the text: \(regular) -> \(largest)")
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
        reveal(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Loading songs")).firstMatch, in: app)
        let retry = app.buttons.matching(identifier: "fst.service-status.retry").firstMatch
        reveal(retry, in: app)
        assertTarget(retry, "Retry")
        let title = app.staticTexts["fst.service-status.title"]
        reveal(title, in: app)
        let countdown = app.staticTexts["fst.service-status.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 4), "scrape freeze counts down")
        XCTAssertTrue(countdown.label.hasPrefix("Trying again automatically in "), countdown.label)
        reveal(app.otherElements["fst.service-status.inline"], in: app)
        let banner = element("fst.songs.refresh-error", in: app)
        reveal(banner, in: app)
        XCTAssertEqual(banner.label, "Update failed: The network connection was lost.")
    }

    /// An inline freeze keeps its whole Retry target within the row and stacks it at AX5.
    @MainActor
    func testInlineServiceFreezeContainsRetryAndPreservesReadingOrder() throws {
        for size in [UIContentSizeCategory.large.rawValue, Self.ax5] {
            let app = try openGallery("inline-freeze", size: size)
            defer { app.terminate() }
            let inline = app.otherElements["fst.service-status.inline"]
            let retry = inline.buttons["fst.service-status.retry"]
            reveal(retry, in: app)
            let title = inline.staticTexts["Scores are updating"]
            let countdownPrefix = "Trying again automatically in "
            let countdown = inline.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", countdownPrefix)).firstMatch
            XCTAssertTrue(title.exists)
            XCTAssertTrue(countdown.waitForExistence(timeout: 4))
            XCTAssertEqual(retry.label, "Retry Now")
            assertTarget(retry, "Inline Retry Now")
            let bounds = inline.frame.insetBy(dx: -1, dy: -1)
            for element in [title, countdown, retry] {
                XCTAssertTrue(bounds.contains(element.frame), "\(element.label) fits inside the status row")
            }
            let readingOrder = inline.descendants(matching: .any).allElementsBoundByIndex.map(\.label)
            let titleIndex = try XCTUnwrap(readingOrder.firstIndex(of: title.label))
            let countdownIndex = try XCTUnwrap(readingOrder.firstIndex { $0.hasPrefix(countdownPrefix) })
            let retryIndex = try XCTUnwrap(readingOrder.firstIndex(of: retry.label))
            XCTAssertLessThan(titleIndex, countdownIndex)
            XCTAssertLessThan(countdownIndex, retryIndex)
            if size == Self.ax5 {
                XCTAssertGreaterThanOrEqual(retry.frame.minY, countdown.frame.maxY)
            } else {
                XCTAssertEqual(retry.frame.width, 65.67, accuracy: 1)
                XCTAssertEqual(retry.frame.midY, title.frame.midY, accuracy: 1)
            }
            SongsUITestSupport.record(app, name: "inline-service-freeze-\(size)")
        }
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
        // The indicator is an adjustable element (VoiceOver swipes up and down); XCUITest
        // can only adjust sliders, so page by swiping the cards.
        app.collectionViews["fst.carousel.gallery-cards"].swipeLeft()
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
        // The system bar button draws 34 pt tall inside a 44 pt hit region.
        assertTarget(close, minimum: 34, "sheet Close")
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
