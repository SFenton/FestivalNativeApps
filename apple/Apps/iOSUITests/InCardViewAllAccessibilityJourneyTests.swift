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
        /// A Songs row to tap first, for a page only a pushed row reaches.
        var openRow: String?
        /// The Quick Links section that jumps near the button, and the element that shows
        /// the jump landed, where the page offers Quick Links.
        var quickLink: (section: String, label: String, landing: String)? = nil
        /// An element that exists once the page has loaded.
        let ready: String
        /// The button's identifier, or a prefix when `idSuffix` is set.
        let id: String
        /// The identifier's suffix when `id` is a prefix.
        var idSuffix: String?
        /// The accessible name: the visible label, then the card.
        let nameFormat: String
        /// Words of the visible label that must render whole.
        let words: [String]
        /// Elements the full list shows, any one of which proves it opened (a song board is
        /// titled by the song header on iPhone and by its chart beside Song Detail).
        let destination: [String]
    }

    private static let leaderboards = Card(
        name: "leaderboards", env: ["FST_DEBUG_ROUTE": "leaderboards"], openRow: nil, ready: "Leaderboards",
        id: "fst.leaderboards.card.", idSuffix: ".view-all",
        nameFormat: #"^View all rankings \([0-9,]+\), .+$"#, words: ["view", "all", "rankings"],
        destination: ["fst.full-rankings.title"]
    )
    private static let rivalDetail = Card(
        name: "rival-detail",
        env: [
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
            "FST_DEBUG_ROUTE": "rivalDetail:f1c749eb07c32578cfa3e59ec38c03a8:song:Solo_Guitar",
        ],
        openRow: nil, ready: "fst.rival-detail.title",
        id: "fst.rival-detail.category.closest_battles.view-all",
        nameFormat: #"^View All, Closest Battles$"#, words: ["view", "all"],
        destination: ["fst.rivalry.title"]
    )
    /// Song Detail through its Songs row, like `SongDetailJourneyTests`: `FST_DEBUG_SONG`'s
    /// screenshot push is not on the tab's navigation path, so a page pushed from it
    /// bounced straight back to Song Detail.
    private static let songDetail: [String: String] = [
        "FST_UI_TEST_RESET_SONG_CARDS": "1",
        "FST_DEBUG_PROFILE": "fixture-history-multi:Multi History",
    ]
    private static let songRow = "fst.songs.row.fixture-pulse"
    private static let songPreview = Card(
        name: "song-preview", env: songDetail, openRow: songRow, quickLink: ("instrument-Solo_Guitar", "Lead", "fst.song-detail.card-header.Solo_Guitar"),
        ready: "fst.song-detail.intensity",
        id: "fst.song-detail.leaderboard.Solo_Guitar",
        nameFormat: #"^View Full Leaderboard, Lead$"#, words: ["view", "full", "leaderboard"],
        destination: ["fst.song-leaderboard.header", "fst.song-leaderboard.board-title"]
    )
    private static let scoreHistory = Card(
        name: "score-history", env: songDetail, openRow: songRow, ready: "fst.song-detail.intensity",
        id: "fst.song-detail.history.view-all",
        nameFormat: #"^View All Scores, .+ Score History$"#, words: ["view", "all", "scores"],
        destination: ["fst.history"]
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
        // Full card width: 60% of a phone, or most of a 360 pt minimum grid column on iPad.
        XCTAssertGreaterThan(frame.width, min(window.width * 0.6, 300), "\(card.name): spans the card: \(frame)")
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
        // One snapshot per issue: resolving each attribute separately re-queries the app, and
        // on iPad at AX5 that pushed Rival Detail's audit past XCTest's deadline.
        let handler: (XCUIAccessibilityAuditIssue) throws -> Bool = { issue in
            guard let element = try? issue.element?.snapshot(), element.identifier == identifier else { return true }
            issues.append("\(element.identifier) '\(element.label)': \(issue.compactDescription)")
            return true
        }
        // A loaded host can exceed XCTest's audit deadline (#388): retry that once.
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, audit, name: card.name, reset: { issues.removeAll() }, handler
        )
        XCTAssertEqual(issues, [], "\(card.name): audit issues at AX5")

        // Operable: it opens the card's full list.
        let reopened = app.buttons[identifier]
        XCTAssertTrue(reopened.waitForExistence(timeout: FestivalApp.budget(10)))
        if !reopened.isHittable { _ = try reveal(card, in: app) }
        reopened.tap()
        let destination = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", card.destination)).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: FestivalApp.budget(20)), "\(card.name): opens its full list")
    }

    // MARK: - Launch and reveal

    /// Filter Songs to `Pulse` and open the row, as `PathsUITestSupport.openPaths` does:
    /// the large catalogue lists `fixture-pulse` under F, below the first screen.
    ///
    /// - Parameters:
    ///   - identifier: The Songs row to open.
    ///   - app: The launched app on Songs.
    ///   - card: The card under test, naming the skip screenshot.
    /// - Throws: A skip when Songs never loads (no fixture service).
    @MainActor
    private func open(_ identifier: String, in app: XCUIApplication, card: Card) throws {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        guard rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(60)) else {
            record(app, name: "\(card.name)-no-songs")
            throw XCTSkip("\(card.name): Songs never loaded; run tools/mock_service.py --large-catalogue on \(Self.origin).")
        }
        let field = SongsUITestSupport.songsSearchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: FestivalApp.budget(5)), "No Filter Songs field")
        let song = app.buttons[identifier]
        // The live filter can drop a keystroke while it re-renders, so retype once.
        for _ in 0..<2 where !song.exists {
            field.tap()
            if let typed = field.value as? String, !typed.isEmpty, typed != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count))
            }
            field.typeText("Pulse")
            _ = song.waitForExistence(timeout: FestivalApp.budget(5))
        }
        XCTAssertTrue(song.exists, "\(card.name): no \(identifier) row")
        for _ in 0..<20 where !song.isHittable {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        song.tap()
    }

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
        if let openRow = card.openRow {
            try open(openRow, in: app, card: card)
        }
        let ready = app.descendants(matching: .any).matching(identifier: card.ready).firstMatch
        guard ready.waitForExistence(timeout: FestivalApp.budget(60)) else {
            record(app, name: "\(card.name)-not-ready")
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

    /// Jump to the card's section through Quick Links, as a reader would and as
    /// `SongDetailBandColumnsJourneyTests` does, when the page offers them and the button
    /// is off screen: Lead's button sits several screens down Song Detail at AX5.
    ///
    /// - Parameters:
    ///   - card: The button under test.
    ///   - app: The app on the card's page.
    ///   - button: The button to bring near.
    /// - Returns: Whether the page jumped.
    @MainActor
    private func jump(to card: Card, in app: XCUIApplication, unless button: XCUIElement) -> Bool {
        guard let link = card.quickLink, !button.isHittable else { return false }
        let open = app.buttons["fst.quick-links.open"]
        guard open.waitForExistence(timeout: FestivalApp.budget(2)), open.isHittable else { return false }
        open.tap()
        let item = FestivalApp.quickLinkRow(link.section, label: link.label, in: app)
        guard item.waitForExistence(timeout: FestivalApp.budget(10)) else {
            XCTFail("\(card.name): Quick Links has no \(link.section)")
            return false
        }
        item.tap()
        let landing = app.descendants(matching: .any).matching(identifier: link.landing).firstMatch
        let shown = NSPredicate(format: "exists == true AND isHittable == true")
        let landed = XCTNSPredicateExpectation(predicate: shown, object: landing)
        XCTAssertEqual(
            XCTWaiter().wait(for: [landed], timeout: FestivalApp.budget(15)), .completed,
            "\(card.name): Quick Links did not bring \(link.landing) into view"
        )
        return true
    }

    /// Drag the button into the middle of the screen, clear of the scroll-edge fades and
    /// the bottom chrome, from the leading margin (a drag on Score History's chart selects
    /// a bar). Never from the trailing edge: a held drag there grabs the scroll indicator
    /// and scrubs the page back towards the top. A drag that barely moves the button moves
    /// the next one to the middle. After a Quick Links jump it pages with system swipes.
    ///
    /// - Parameters:
    ///   - card: The button under test.
    ///   - app: The app on the card's page.
    /// - Returns: The button, on screen.
    @MainActor
    private func reveal(_ card: Card, in app: XCUIApplication) throws -> XCUIElement {
        let button = button(card, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: FestivalApp.budget(20)), "\(card.name): the page shows its button")
        let jumped = jump(to: card, in: app, unless: button)
        let window = app.windows.firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let lanes = [12, window.width * 0.5]
        var lane = 0
        for _ in 0..<20 {
            let frame = button.frame
            if button.isHittable, frame.minY >= window.height * 0.2, frame.maxY <= window.height * 0.7 { break }
            // Move the button's centre towards the middle of the screen, at most 0.4 screens per drag.
            let offset = max(-window.height * 0.4, min(window.height * 0.4, window.height * 0.45 - frame.midY))
            if jumped {
                // From a Quick Links landing, page with the system swipe, as the precedent does.
                if offset < 0 { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
                continue
            }
            let start = origin.withOffset(CGVector(dx: lanes[lane], dy: window.height * 0.5))
            // A slow drag with a hold, as `DriverTests`' `drag:`, scrolls without a fling.
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            if abs(button.frame.midY - frame.midY) < abs(offset) / 4 { lane = (lane + 1) % lanes.count }
        }
        // Let the drag's deceleration and the card's fade-in finish before reading pixels.
        sleep(UInt32(FestivalApp.budget(1)))
        if !button.isHittable { record(app, name: "\(card.name)-not-revealed") }
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

    /// Keep a capture of the element (or the whole app) with the test result.
    @MainActor
    private func record(_ element: XCUIScreenshotProviding, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
