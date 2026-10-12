import UIKit
import Vision
import XCTest

// MARK: - In-card View All at AX5 (issue #382, backfilled by #500)

/// The purple "View All" buttons #382 moved inside their group cards, on a real iPhone or
/// iPad navigation stack with real Dynamic Type: Leaderboards' "View all rankings (N)",
/// Rival Detail's category "View All", and Song Detail's "View Full Leaderboard" and
/// "View All Scores". macOS has no Dynamic Type, so
/// `FestivalUITests/InCardViewAllAccessibilityTests` covers their name, role, reading order,
/// target and AXPress in `apple-ci`, and this journey is the iOS and iPadOS large-text
/// evidence. (Rivals' View All Rivals and Compete's View Full Leaderboard have their own
/// journeys: `RivalsViewAllAccessibilityJourneyTests`, `CompeteAccessibilityJourneyTests`.)
///
/// At AX5 each button must:
/// - read as one button named label first, then its card ("View All, Closest Battles");
/// - grow its label (> 1.35× the default size's glyph height) and render every word of
///   it, wrapping instead of clipping or truncating;
/// - stay a full-width, hittable target at least 44 pt tall;
/// - pass a scoped audit (Dynamic Type, clipped text, hit region, description, contrast);
/// - open its card's full list when tapped.
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765; set
/// `TEST_RUNNER_FST_FIXTURE_URL` for another mock). `apple-ci` runs it on its iPhone and
/// iPad simulators (`testing/apple/xcuitest.md#ci-journeys`).
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases"; HIG
/// Accessibility: "Strive for the platform's recommended minimum control size" (iOS 44×44 pt).
final class InCardViewAllAccessibilityJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue

    /// One in-card button and how to reach it.
    private struct Card {
        /// Failure and attachment label.
        let name: String
        /// Launch environment (route, profile, song).
        let env: [String: String]
        /// An element that exists once the page has loaded.
        let ready: String
        /// The button's identifier, or a prefix when `idSuffix` is set.
        let id: String
        /// The identifier's suffix when `id` is a prefix.
        var idSuffix: String?
        /// Quick Links entry that jumps to the card, if any.
        var quickLink: String?
        /// The accessible name: the visible label, then the card.
        let nameFormat: String
        /// Words of the visible label that must render whole.
        let words: [String]
        /// An element the full list shows.
        let destination: String
    }

    private static let leaderboards = Card(
        name: "leaderboards", env: ["FST_DEBUG_ROUTE": "leaderboards"], ready: "Leaderboards",
        id: "fst.leaderboards.card.", idSuffix: ".view-all",
        nameFormat: #"^View all rankings \([0-9,]+\), .+$"#, words: ["view", "all", "rankings"],
        destination: "fst.full-rankings.title"
    )
    private static let rivalDetail = Card(
        name: "rival-detail",
        env: [
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
            "FST_DEBUG_ROUTE": "rivalDetail:f1c749eb07c32578cfa3e59ec38c03a8:song:Solo_Guitar",
        ],
        ready: "fst.rival-detail.title",
        id: "fst.rival-detail.category.closest_battles.view-all",
        nameFormat: #"^View All, Closest Battles$"#, words: ["view", "all"],
        destination: "fst.rivalry.title"
    )
    private static let songDetail: [String: String] = [
        "FST_UI_TEST_RESET_SONG_CARDS": "1",
        "FST_DEBUG_PROFILE": "fixture-history-multi:Multi History",
        "FST_DEBUG_SONG": "fixture-pulse",
    ]
    private static let songPreview = Card(
        name: "song-preview", env: songDetail, ready: "fst.quick-links.open",
        id: "fst.song-detail.leaderboard.Solo_Guitar", quickLink: "instrument-Solo_Guitar",
        nameFormat: #"^View Full Leaderboard, Lead$"#, words: ["view", "full", "leaderboard"],
        destination: "fst.song-leaderboard.board-title"
    )
    private static let scoreHistory = Card(
        name: "score-history", env: songDetail, ready: "fst.quick-links.open",
        id: "fst.song-detail.history.view-all", quickLink: "score-history",
        nameFormat: #"^View All Scores, .+ Score History$"#, words: ["view", "all", "scores"],
        destination: "fst.history.row.0"
    )

    // MARK: - Journeys

    /// Leaderboards' first "View all rankings (N)" at AX5.
    @MainActor
    func testLeaderboardsViewAllRankingsIsReadableAtAX5() throws {
        try check(Self.leaderboards)
    }

    /// Rival Detail's Closest Battles "View All" at AX5.
    @MainActor
    func testRivalDetailCategoryViewAllIsReadableAtAX5() throws {
        try check(Self.rivalDetail)
    }

    /// Song Detail's Lead preview "View Full Leaderboard" at AX5.
    @MainActor
    func testSongPreviewViewFullLeaderboardIsReadableAtAX5() throws {
        try check(Self.songPreview)
    }

    /// Song Detail's Score History "View All Scores" at AX5.
    @MainActor
    func testScoreHistoryViewAllScoresIsReadableAtAX5() throws {
        try check(Self.scoreHistory)
    }

    // MARK: - Checks

    /// Measure the button at the default size, then check it at AX5 and open its list.
    ///
    /// - Parameter card: The button under test.
    @MainActor
    private func check(_ card: Card) throws {
        continueAfterFailure = false
        let standard = try launch(card, size: nil)
        let standardButton = try reveal(card, in: standard)
        let standardGlyphs = try SongsUITestSupport.brightGlyphHeight(in: standardButton)
        standard.terminate()

        let app = try launch(card, size: Self.ax5)
        let button = try reveal(card, in: app)
        let window = app.windows.firstMatch.frame
        let frame = button.frame
        record(button, name: "\(card.name)-view-all-ax5")

        // Name, role and state.
        XCTAssertNotNil(button.label.range(of: card.nameFormat, options: .regularExpression),
                        "\(card.name): label first, then the card: '\(button.label)'")
        XCTAssertEqual(button.elementType, .button, card.name)
        XCTAssertFalse(button.isSelected, "\(card.name): a push button has no selected state")

        // Target size.
        XCTAssertTrue(button.isHittable, "\(card.name): reachable at AX5")
        XCTAssertGreaterThanOrEqual(frame.height, 44 - 1, "\(card.name): at least 44 pt tall: \(frame)")
        XCTAssertGreaterThan(frame.width, min(window.width, 700) * 0.6, "\(card.name): spans the card: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(card.name): starts on screen: \(frame)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(card.name): ends on screen: \(frame)")

        // Text scaling: the label grows and every word renders whole.
        let glyphs = try SongsUITestSupport.brightGlyphHeight(in: button)
        XCTAssertGreaterThan(Double(glyphs), Double(standardGlyphs) * 1.35,
                             "\(card.name): the label grows at AX5: \(glyphs) px vs \(standardGlyphs) px")
        let lines = try Self.recognizeLines(button)
        XCTContext.runActivity(named: "\(card.name) recognized: \(lines)") { _ in }
        let words = Set(lines.flatMap { $0.lowercased().split { !$0.isLetter }.map(String.init) })
        for word in card.words {
            XCTAssertTrue(words.contains(word), "\(card.name): '\(word)' renders whole: \(lines)")
        }
        XCTAssertFalse(lines.contains { $0.contains("…") || $0.contains("...") }, "\(card.name): no truncation: \(lines)")

        // Audit the button only: the rows and chrome have their own journeys.
        let identifier = button.identifier
        var issues: [String] = []
        let audit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription, .contrast]
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            guard let element = issue.element, element.identifier == identifier else { return true }
            issues.append("\(element.identifier) '\(element.label)': \(issue.compactDescription)")
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
        XCTAssertEqual(issues, [], "\(card.name): audit issues at AX5")

        // Operable: it opens the card's full list.
        let reopened = app.buttons[identifier]
        XCTAssertTrue(reopened.waitForExistence(timeout: FestivalApp.budget(10)))
        if !reopened.isHittable { _ = try reveal(card, in: app, jump: false) }
        reopened.tap()
        let destination = app.descendants(matching: .any).matching(identifier: card.destination).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: FestivalApp.budget(20)), "\(card.name): opens its full list")
    }

    // MARK: - Launch and reveal

    /// Open the card's page at a text size.
    ///
    /// - Parameters:
    ///   - card: The button under test.
    ///   - size: A `UIContentSizeCategory` raw value; nil keeps the default.
    /// - Returns: The launched app on the page.
    /// - Throws: A skip when the page never loads (no fixture service).
    @MainActor
    private func launch(_ card: Card, size: String?) throws -> XCUIApplication {
        let app = FestivalApp.makeApp(card.env.merging([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]) { mine, _ in mine })
        if let size {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        let ready = app.descendants(matching: .any).matching(identifier: card.ready).firstMatch
        guard ready.waitForExistence(timeout: FestivalApp.budget(30)) else {
            throw XCTSkip("\(card.name) never loaded; run tools/mock_service.py --large-catalogue on \(Self.origin).")
        }
        return app
    }

    /// The card's button.
    @MainActor
    private func button(_ card: Card, in app: XCUIApplication) -> XCUIElement {
        guard let suffix = card.idSuffix else { return app.buttons[card.id] }
        return app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", card.id, suffix
        )).firstMatch
    }

    /// Jump to the card through Quick Links when it has one (Song Detail: never long runs
    /// of drags, which can trip its known render loop), then drag the button into the
    /// middle of the screen, clear of the scroll-edge fades and the bottom chrome, from the
    /// trailing margin (a drag on Score History's chart selects a bar).
    ///
    /// - Parameters:
    ///   - card: The button under test.
    ///   - app: The app on the card's page.
    ///   - jump: Use the card's Quick Links entry first.
    /// - Returns: The button, on screen.
    @MainActor
    private func reveal(_ card: Card, in app: XCUIApplication, jump: Bool = true) throws -> XCUIElement {
        if jump, let link = card.quickLink {
            let open = app.buttons["fst.quick-links.open"]
            XCTAssertTrue(open.waitForExistence(timeout: FestivalApp.budget(15)), "\(card.name): Quick Links")
            open.tap()
            let item = app.buttons["fst.quick-links.item.\(link)"]
            XCTAssertTrue(item.waitForExistence(timeout: FestivalApp.budget(10)), "\(card.name): Quick Links has \(link)")
            item.tap()
            sleep(UInt32(FestivalApp.budget(1)))
        }
        let button = button(card, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: FestivalApp.budget(20)), "\(card.name): the page shows its button")
        let window = app.windows.firstMatch.frame
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: window.width - 12, dy: window.height * 0.5))
        for _ in 0..<20 {
            let frame = button.frame
            if button.isHittable, frame.minY >= window.height * 0.2, frame.maxY <= window.height * 0.7 { break }
            // Move the button's centre towards the middle of the screen, at most 0.4 screens per drag.
            let offset = max(-window.height * 0.4, min(window.height * 0.4, window.height * 0.45 - frame.midY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)))
        }
        // Let the drag's deceleration and the card's fade-in finish before reading pixels.
        sleep(UInt32(FestivalApp.budget(1)))
        XCTAssertTrue(button.isHittable, "\(card.name): scrolls on screen: \(button.frame)")
        return button
    }

    // MARK: - Rendered text

    /// Recognize the button's rendered lines, top to bottom.
    ///
    /// - Parameter element: The button on screen.
    /// - Returns: Each recognized line.
    /// - Throws: An unavailable capture.
    @MainActor
    private static func recognizeLines(_ element: XCUIElement) throws -> [String] {
        let image = try XCTUnwrap(element.screenshot().image.cgImage, "button capture")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        return (request.results ?? [])
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    /// Keep a capture of the element with the test result.
    @MainActor
    private func record(_ element: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
