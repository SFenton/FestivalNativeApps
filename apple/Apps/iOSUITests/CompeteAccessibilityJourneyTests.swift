import UIKit
import XCTest

// MARK: - Compete at AX5 (issue #35, backfilled by #407)

/// Compete's loaded page at the default text size and at the largest accessibility size
/// (AX5) on iPhone, after the one page spinner #35 introduced (since #354 the shared
/// `FestivalReloadGate`, "Loading Compete") has left.
///
/// The app reads the loopback fixture (`tools/mock_service.py`) as `fixture-riv` with Lead and
/// Bass shown: the Lead + Bass combo board (#602), then the Lead and Bass boards, each listing
/// Fixture Player 1, Fixture Player 2 and Fixture Rank 3. Each launch waits for the spinner to
/// leave the tree, checks the reading order (the Leaderboards heading, each board's heading,
/// its rows, its "View Full Leaderboard, <board>" button, then the Rivals heading; headings
/// with the header trait), checks that the section's only buttons are those rows and View Full
/// Leaderboard buttons (no Leaderboards Overview, removed by #36, backfilled by #408), and
/// brings every one of
/// those elements wholly into view between the navigation bar and the bottom chrome (tab-bar
/// floating page tools and tab bar). At AX5 each one must read back whole from its own capture (no
/// ellipsis, no clipped word), render glyphs more than 1.35× taller than at the default size
/// (recognized line height), and every row and button must be hittable there, the buttons at
/// least 44 × 44 pt. A scoped audit covers Dynamic Type, clipped text, hit regions and
/// descriptions on Compete's own elements. A second journey goes Back from View Full
/// Leaderboard at AX5 and checks that the same page returns without its spinner (#39, #410).
/// A third launches as `fixture-riv-ranked` (45th of 60 on every board) and checks the
/// viewer's own "Your rank" row under each board's top rows (#370, backfilled by #493).
/// macOS hosting cannot scale text, so this journey is
/// the AX5 evidence; `FestivalUITests/CompeteLoadingAccessibilityTests` covers the spinner's
/// name, role and the VoiceOver tree in `apple-ci`.
///
/// Needs `tools/mock_service.py` (`apple-ci` serves it with `--large-catalogue` on the default
/// port 8765; `FST_COMPETE_FIXTURE_URL` points a local run at another port). `apple-ci` runs it
/// on its iPhone simulator (`testing/apple/xcuitest.md#ci-journeys`). Waits use
/// `FestivalApp.budget(_:)` for the runner.
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases"; HIG
/// Accessibility: "offer text enlargement of at least 200%" and a 44×44 pt default control
/// size.
final class CompeteAccessibilityJourneyTests: XCTestCase {
    private static let fixtureService = ProcessInfo.processInfo.environment["FST_COMPETE_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// Settings keys of every instrument; only Lead and Bass are shown.
    private static let instrumentKeys = [
        "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
        "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
        "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
    ]
    private static let shownKeys: Set<String> = ["fst.settings.showLead", "fst.settings.showBass"]

    /// One element VoiceOver reads on the page.
    private struct Item: CustomStringConvertible {
        /// `spotlight` is the selected player's own row under a board's top rows (#370).
        enum Kind { case heading, row, action, spotlight }
        let kind: Kind
        /// Its accessibility label (a row's starts with its rank, e.g. "#1").
        let label: String
        /// The text it draws, read back from its capture.
        let drawn: String
        /// Which match of `label` (a row's rank repeats on each board).
        let occurrence: Int
        /// More text it draws, each read back whole on its own (not ordered after `drawn`).
        var also: [String] = []
        /// Its accessibility identifier, when its label repeats on every board.
        var identifier: String? = nil

        var description: String { "\(label) [\(occurrence)]" }
    }

    /// The fixture's instrument board rows: rank, name, songs and score.
    private static let rows = [
        (rank: 1, name: "Fixture Player 1", songs: "39 / 50", score: "89,000,000"),
        (rank: 2, name: "Fixture Player 2", songs: "38 / 50", score: "88,000,000"),
        (rank: 3, name: "Fixture Rank 3", songs: "37 / 50", score: "87,000,000"),
    ]

    /// The Lead + Bass combo board's rows: rank, name and both instruments' scores summed.
    /// On a portrait iPhone the combo card drops songs played to keep names whole (#38),
    /// and text recognition reads its trailing score first, so the score is checked apart.
    private static let comboRows = [
        (rank: 1, name: "Fixture Player 1", score: "178,000,000"),
        (rank: 2, name: "Fixture Player 2", score: "176,000,000"),
        (rank: 3, name: "Fixture Rank 3", score: "174,000,000"),
    ]

    /// The Leaderboards section in reading order, then the Rivals heading.
    private static let readingOrder: [Item] = {
        var items = [Item(kind: .heading, label: "Leaderboards", drawn: "Leaderboards", occurrence: 0)]
        for (board, instrument) in ["Lead + Bass", "Lead", "Bass"].enumerated() {
            items.append(Item(kind: .heading, label: instrument, drawn: instrument, occurrence: 0))
            if board == 0 {
                for row in comboRows {
                    items.append(Item(
                        kind: .row, label: "#\(row.rank)", drawn: "#\(row.rank) \(row.name)", occurrence: board,
                        also: [row.score]
                    ))
                }
            } else {
                for row in rows {
                    items.append(Item(
                        kind: .row, label: "#\(row.rank)",
                        drawn: "#\(row.rank) \(row.name) \(row.songs) \(row.score)", occurrence: board
                    ))
                }
            }
            items.append(Item(
                kind: .action, label: "View Full Leaderboard, \(instrument)", drawn: "View Full Leaderboard", occurrence: 0
            ))
        }
        items.append(Item(kind: .heading, label: "Rivals", drawn: "Rivals", occurrence: 0))
        return items
    }()

    /// The viewer ranked 45th of 60 on every board, on none of their top rows
    /// (`tools/mock_service.py` `fixture-riv-ranked`, #493).
    private static let rankedViewer = "fixture-riv-ranked:Fixture Viewer"
    /// The viewer's row's name: its rank and where it goes (leaderboard-row R7, #370).
    private static let jumpLabel = "Your rank, 45th. Jump to your position."

    /// ``readingOrder`` for the ranked viewer: each board's top rows, then the viewer's own
    /// row (its rank, name and total score; the combo sums both instruments), then its
    /// View Full Leaderboard.
    private static let rankedReadingOrder: [Item] = {
        let boards = [
            "View Full Leaderboard, Lead + Bass": (id: "03", score: "90,000,000"),
            "View Full Leaderboard, Lead": (id: "Solo_Guitar", score: "45,000,000"),
            "View Full Leaderboard, Bass": (id: "Solo_Bass", score: "45,000,000"),
        ]
        var items: [Item] = []
        for item in readingOrder {
            if item.kind == .action, let board = boards[item.label] {
                items.append(Item(
                    kind: .spotlight, label: jumpLabel, drawn: "#45 Fixture Viewer", occurrence: 0,
                    also: [board.score], identifier: "fst.compete.leaderboard-card.\(board.id).spotlight"
                ))
            }
            items.append(item)
        }
        return items
    }()

    // MARK: - Journey

    /// Headings, rows and View Full Leaderboard buttons grow, stay whole, in order and
    /// reachable above the bottom chrome at AX5.
    @MainActor
    func testCompeteIsReadableAtAX5() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let standard = launch(contentSize: UIContentSizeCategory.large.rawValue)
        assertReadingOrder(standard, size: "default")
        var baseline: [CGFloat] = []
        for item in Self.readingOrder {
            let (element, frame) = reveal(item, in: standard)
            let reading = RecognizedText.recognize(element, label: item.drawn, frame: frame)
            XCTAssertTrue(RecognizedText.showsWhole(item.drawn, in: reading.text),
                          "\(item) reads back whole at the default size: '\(reading.text ?? "nil")'")
            for text in item.also {
                XCTAssertTrue(RecognizedText.showsWhole(text, in: reading.text),
                              "\(item) draws \(text) whole at the default size: '\(reading.text ?? "nil")'")
            }
            let height = try XCTUnwrap(reading.lineHeight, "\(item) recognized at the default size")
            XCTAssertGreaterThan(height, 4, "\(item) has a measurable line height")
            baseline.append(height)
        }
        record(standard, name: "compete-default")
        standard.terminate()

        let app = launch(contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        record(app, name: "compete-ax5")
        assertReadingOrder(app, size: "AX5")
        let window = app.windows.firstMatch.frame
        var growth: [String] = []
        for (index, item) in Self.readingOrder.enumerated() {
            let (element, frame) = reveal(item, in: app)
            let region = contentRegion(app)
            XCTAssertGreaterThanOrEqual(frame.minY, region.minY - 0.5, "\(item) under the navigation bar: \(frame) vs \(region)")
            XCTAssertLessThanOrEqual(frame.maxY, region.maxY + 0.5, "\(item) under the bottom chrome: \(frame) vs \(region)")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(item) cut off at the leading edge: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(item) cut off at the trailing edge: \(frame)")
            let reading = RecognizedText.recognize(element, label: item.drawn, frame: frame)
            XCTAssertTrue(RecognizedText.showsWhole(item.drawn, in: reading.text),
                          "\(item) reads back whole at AX5: '\(reading.text ?? "nil")'")
            for text in item.also {
                XCTAssertTrue(RecognizedText.showsWhole(text, in: reading.text),
                              "\(item) draws \(text) whole at AX5: '\(reading.text ?? "nil")'")
            }
            let height = try XCTUnwrap(reading.lineHeight, "\(item) recognized at AX5")
            let ratio = height / baseline[index]
            growth.append(String(format: "%@ %.2f", item.description, ratio))
            XCTAssertGreaterThan(ratio, RecognizedText.minimumGrowth,
                                 "\(item) glyphs grow at AX5: \(height) vs \(baseline[index]) pt")
            if item.kind != .heading {
                XCTAssertTrue(element.isHittable, "\(item) is reachable at AX5")
            }
            if item.kind == .action {
                XCTAssertGreaterThanOrEqual(frame.height, 44, "\(item) is at least 44 pt tall: \(frame)")
                XCTAssertGreaterThanOrEqual(frame.width, 44, "\(item) is at least 44 pt wide: \(frame)")
            }
        }
        attach("compete-ax5-growth", growth.joined(separator: "\n"))
        record(app, name: "compete-ax5-end")
        try auditCompete(app, size: "AX5")
    }

    // MARK: - Back from View Full Leaderboard (issue #39, backfilled by #410)

    /// How long Compete is watched after Back for a spinner or a moved button.
    private static let returnWatch: TimeInterval = 2
    /// How far, in points, the View Full Leaderboard button may sit from where it was.
    private static let returnTolerance: CGFloat = 1

    /// Back from a board's View Full Leaderboard (#39) returns to the same loaded Compete
    /// at AX5: the page spinner never comes back, the button the reader left from is where
    /// it was (no reload jitter), still a hittable button of at least 44 × 44 pt, the page
    /// reads in the same order with the same heading traits, and the scoped audit is clean.
    ///
    /// HIG VoiceOver: "be sure to keep labels current as interface and content change";
    /// HIG Progress indicators show only while an operation is ongoing.
    @MainActor
    func testBackFromFullLeaderboardKeepsCompeteReadableAtAX5() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        let app = launch(contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        guard let bass = Self.readingOrder.last(where: { $0.kind == .action }) else {
            return XCTFail("the reading order ends with a board's View Full Leaderboard")
        }
        let (button, before) = reveal(bass, in: app)
        XCTAssertTrue(button.isHittable, "\(bass) is reachable before leaving")
        assertReadingOrder(app, size: "AX5 before View Full Leaderboard")
        record(app, name: "compete-ax5-before-full-leaderboard")

        button.tap()
        XCTAssertTrue(app.navigationBars["Bass Rankings"].waitForExistence(timeout: FestivalApp.budget(15)),
                      "View Full Leaderboard, Bass pushes Bass Rankings")
        let back = app.buttons["BackButton"]
        (back.exists && back.isHittable ? back : app.navigationBars.buttons.firstMatch).tap()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: FestivalApp.budget(15)), "Back returns to Compete")
        XCTAssertTrue(app.navigationBars["Bass Rankings"].waitForNonExistence(timeout: FestivalApp.budget(5)),
                      "the full leaderboard has left")

        let spinner = app.descendants(matching: .any)["fst.compete.loading"]
        let deadline = Date().addingTimeInterval(FestivalApp.budget(Self.returnWatch))
        var samples: [String] = []
        repeat {
            XCTAssertFalse(spinner.exists, "Compete does not show its spinner again after Back")
            XCTAssertTrue(button.exists, "\(bass) stays on the page after Back")
            samples.append("\(button.frame)")
        } while Date() < deadline
        attach("compete-ax5-return-frames", samples.joined(separator: "\n"))

        let after = button.frame
        XCTAssertEqual(after.minY, before.minY, accuracy: Self.returnTolerance, "\(bass) keeps its place: \(after) vs \(before)")
        XCTAssertEqual(after.minX, before.minX, accuracy: Self.returnTolerance, "\(bass) keeps its place: \(after) vs \(before)")
        XCTAssertEqual(after.height, before.height, accuracy: Self.returnTolerance, "\(bass) keeps its size: \(after) vs \(before)")
        XCTAssertTrue(button.isHittable, "\(bass) is reachable after Back")
        XCTAssertGreaterThanOrEqual(after.height, 44, "\(bass) is at least 44 pt tall after Back: \(after)")
        XCTAssertGreaterThanOrEqual(after.width, 44, "\(bass) is at least 44 pt wide after Back: \(after)")
        assertReadingOrder(app, size: "AX5 after Back")
        record(app, name: "compete-ax5-after-back")
        try auditCompete(app, size: "AX5 after Back")
    }

    // MARK: - Your rank row (issue #370, backfilled by #493)

    /// A viewer ranked outside a board's top rows gets their own row under them (#370):
    /// one button named "Your rank, 45th. Jump to your position.", read after the top rows
    /// and before View Full Leaderboard on every board, at the default size and at AX5. At AX5
    /// it draws its rank, name and score whole with glyphs grown like the rest of the page,
    /// fits between the bars, stays hittable, at least 44 pt tall and as wide as the rows
    /// above it, and the scoped audit is clean. Pressing it opens that board's full
    /// leaderboard (the Lead board here).
    ///
    /// HIG Accessibility: "offer text enlargement of at least 200%" and a 44×44 pt default
    /// control size; HIG VoiceOver: labels describe what an element does.
    @MainActor
    func testYourRankRowIsAccessibleAtAX5() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let items = Self.rankedReadingOrder
        let spotlights = items.filter { $0.kind == .spotlight }
        XCTAssertEqual(spotlights.count, 3, "one row per board")

        let standard = launch(contentSize: UIContentSizeCategory.large.rawValue, profile: Self.rankedViewer)
        assertReadingOrder(standard, size: "default", items: items)
        var baseline: [CGFloat] = []
        for item in spotlights {
            let (element, frame) = reveal(item, in: standard)
            XCTAssertEqual(element.label, Self.jumpLabel, "\(item) says where it goes")
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(item) is at least 44 pt tall: \(frame)")
            let reading = RecognizedText.recognize(element, label: item.drawn, frame: frame)
            for text in [item.drawn] + item.also {
                XCTAssertTrue(RecognizedText.showsWhole(text, in: reading.text),
                              "\(item) draws \(text) whole at the default size: '\(reading.text ?? "nil")'")
            }
            baseline.append(try XCTUnwrap(reading.lineHeight, "\(item) recognized at the default size"))
        }
        record(standard, name: "compete-your-rank-default")
        standard.terminate()

        let app = launch(
            contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue, profile: Self.rankedViewer
        )
        assertReadingOrder(app, size: "AX5", items: items)
        let window = app.windows.firstMatch.frame
        var growth: [String] = []
        for (index, item) in spotlights.enumerated() {
            let (element, frame) = reveal(item, in: app)
            let region = contentRegion(app)
            XCTAssertGreaterThanOrEqual(frame.minY, region.minY - 0.5, "\(item) under the navigation bar: \(frame) vs \(region)")
            XCTAssertLessThanOrEqual(frame.maxY, region.maxY + 0.5, "\(item) under the bottom chrome: \(frame) vs \(region)")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(item) cut off at the leading edge: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(item) cut off at the trailing edge: \(frame)")
            XCTAssertTrue(element.isHittable, "\(item) is reachable at AX5")
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(item) is at least 44 pt tall at AX5: \(frame)")
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "#3")).element(boundBy: index).frame
            XCTAssertEqual(frame.width, row.width, accuracy: 1, "\(item) is as wide as the rows above it: \(frame) vs \(row)")
            let reading = RecognizedText.recognize(element, label: item.drawn, frame: frame)
            for text in [item.drawn] + item.also {
                XCTAssertTrue(RecognizedText.showsWhole(text, in: reading.text),
                              "\(item) draws \(text) whole at AX5: '\(reading.text ?? "nil")'")
            }
            let height = try XCTUnwrap(reading.lineHeight, "\(item) recognized at AX5")
            let ratio = height / baseline[index]
            growth.append(String(format: "%@ %.2f", item.description, ratio))
            XCTAssertGreaterThan(ratio, RecognizedText.minimumGrowth,
                                 "\(item) glyphs grow at AX5: \(height) vs \(baseline[index]) pt")
        }
        attach("compete-your-rank-ax5-growth", growth.joined(separator: "\n"))
        record(app, name: "compete-your-rank-ax5")
        try auditCompete(app, size: "AX5 (ranked viewer)", items: items)

        let lead = try XCTUnwrap(spotlights.first { $0.identifier?.contains("Solo_Guitar") == true })
        let (button, _) = reveal(lead, in: app)
        button.tap()
        XCTAssertTrue(app.navigationBars["Lead Rankings"].waitForExistence(timeout: FestivalApp.budget(15)),
                      "\(lead) opens the Lead full leaderboard")
        record(app, name: "compete-your-rank-ax5-full-leaderboard")
    }

    // MARK: - Audit

    /// Run the scoped audit (Dynamic Type, clipped text, hit regions, descriptions) and fail on
    /// any issue in Compete's own elements.
    ///
    /// - Parameters:
    ///   - app: The launched, loaded app showing Compete.
    ///   - size: Label for failure messages.
    ///   - items: The page's expected reading order.
    @MainActor
    private func auditCompete(_ app: XCUIApplication, size: String, items: [Item] = readingOrder) throws {
        var issues: [String] = []
        let labels = Set(items.filter { $0.kind != .row }.map(\.label))
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        ) { issue in
            let id = issue.element?.identifier ?? ""
            let label = issue.element?.label ?? ""
            let ours = id.hasPrefix("fst.compete.") || id.hasPrefix("fst.rankings.row.")
                || labels.contains(label) || label.hasPrefix("#")
            guard ours else { return true }
            issues.append("\(id) '\(label)': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Compete audit issues at \(size)")
    }

    // MARK: - Reading order

    /// The page's headings, rows and buttons read in ``readingOrder``, each heading with the
    /// header trait, and the loading spinner is gone.
    ///
    /// - Parameters:
    ///   - app: The launched, loaded app.
    ///   - size: Label for failure messages.
    ///   - items: The expected reading order (``rankedReadingOrder`` for the ranked viewer).
    @MainActor
    private func assertReadingOrder(_ app: XCUIApplication, size: String, items: [Item] = readingOrder) {
        guard let snapshot = try? app.snapshot() else {
            XCTFail("app snapshot (\(size))")
            return
        }
        let wanted = Set(items.map(\.label))
        var read: [XCUIElementSnapshot] = []
        Self.walk(snapshot) { node in
            if wanted.contains(Self.key(node.label)), [.staticText, .button].contains(node.elementType) {
                read.append(node)
            }
        }
        let order = read.map { Self.key($0.label) }
        XCTAssertEqual(order, items.map(\.label), "reading order at \(size): \(read.map { "\($0.elementType.rawValue) \($0.identifier) \($0.label) \($0.frame)" })")
        for node in read where items.contains(where: { $0.kind == .heading && $0.label == node.label }) {
            if let traits = Self.traits(node) {
                XCTAssertNotEqual(traits & UIAccessibilityTraits.header.rawValue, 0, "'\(node.label)' is a heading at \(size)")
            }
        }
        for node in read where node.label.hasPrefix("View Full Leaderboard") || node.label == Self.jumpLabel {
            XCTAssertEqual(node.elementType, .button, "'\(node.label)' is a button at \(size)")
        }
        assertOnlyBoardButtons(snapshot, size: size, allowing: items.contains { $0.kind == .spotlight } ? [Self.jumpLabel] : [])
    }

    /// Between the Leaderboards and Rivals headings the only buttons are ranking rows and
    /// each board's View Full Leaderboard (and, for a viewer outside the top rows, their own
    /// row): the Leaderboards Overview #36 removed (web parity) must not come back, and
    /// nothing reads as an overview.
    ///
    /// - Parameters:
    ///   - snapshot: The app's snapshot.
    ///   - size: Label for failure messages.
    ///   - allowing: Other button labels the section may hold.
    @MainActor
    private func assertOnlyBoardButtons(_ snapshot: XCUIElementSnapshot, size: String, allowing: Set<String> = []) {
        var inSection = false
        var strays: [String] = []
        var overview: [String] = []
        Self.walk(snapshot) { node in
            if node.label.localizedCaseInsensitiveContains("overview")
                || node.identifier.localizedCaseInsensitiveContains("overview") {
                overview.append("\(node.elementType.rawValue) \(node.identifier) '\(node.label)'")
            }
            guard [.staticText, .button].contains(node.elementType) else { return }
            if node.elementType == .staticText, node.label == "Leaderboards" { inSection = true }
            if node.elementType == .staticText, node.label == "Rivals" { inSection = false }
            if inSection, node.elementType == .button, !node.label.hasPrefix("#"),
               !node.label.hasPrefix("View Full Leaderboard, "), !allowing.contains(node.label) {
                strays.append("\(node.identifier) '\(node.label)'")
            }
        }
        XCTAssertEqual(strays, [], "only rows and View Full Leaderboard act in Leaderboards at \(size)")
        XCTAssertEqual(overview, [], "no Leaderboards Overview at \(size)")
    }

    /// The reading-order key for a label: a row's rank (its label starts "#1, …"), else the label.
    private static func key(_ label: String) -> String {
        guard label.hasPrefix("#"), let rank = label.split(whereSeparator: { $0 == "," || $0 == " " }).first
        else { return label }
        return String(rank)
    }

    // MARK: - Launch and scrolling

    /// Launch Compete for `fixture-riv` (Lead and Bass) at `contentSize` and wait until the
    /// page spinner has left and the last board's button is in the tree.
    ///
    /// - Parameters:
    ///   - contentSize: `UIContentSizeCategory` raw value.
    ///   - profile: The selected player, `accountId:displayName`.
    /// - Returns: The loaded app.
    @MainActor
    private func launch(contentSize: String, profile: String = "fixture-riv:Fixture Riv") -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixtureService,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": profile,
            "FST_DEBUG_TAB": "compete",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        for key in Self.instrumentKeys {
            app.launchArguments += ["-\(key)", Self.shownKeys.contains(key) ? "YES" : "NO"]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Compete"].waitForExistence(timeout: FestivalApp.budget(30)), "Compete opened")
        let last = app.buttons["View Full Leaderboard, Bass"]
        XCTAssertTrue(last.waitForExistence(timeout: FestivalApp.budget(30)),
                      "Compete loaded from \(Self.fixtureService)")
        let spinner = app.descendants(matching: .any)["fst.compete.loading"]
        XCTAssertTrue(spinner.waitForNonExistence(timeout: FestivalApp.budget(10)), "the page spinner leaves the tree")
        return app
    }

    /// The element for `item`.
    @MainActor
    private func element(_ item: Item, in app: XCUIApplication) -> XCUIElement {
        switch item.kind {
        case .row:
            return app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", item.label))
                .element(boundBy: item.occurrence)
        case .action:
            return app.buttons[item.label]
        case .spotlight:
            return app.buttons[item.identifier ?? item.label]
        case .heading:
            return app.staticTexts.matching(NSPredicate(format: "label == %@", item.label)).element(boundBy: item.occurrence)
        }
    }

    /// The scrolling page's visible region now: below the navigation bar, above the tab-bar
    /// floating page tools and the tab bar (the tab bar minimizes as the page scrolls, issue #92).
    @MainActor
    private func contentRegion(_ app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let top = app.navigationBars["Compete"].frame.maxY
        var bottom = window.maxY
        let accessory = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        if accessory.exists, !accessory.frame.isEmpty { bottom = min(bottom, accessory.frame.minY) }
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists, !tabBar.frame.isEmpty { bottom = min(bottom, tabBar.frame.minY) }
        return CGRect(x: window.minX, y: top, width: window.width, height: bottom - top)
    }

    /// Scroll `item` wholly into the content region with slow, held drags (no fling).
    ///
    /// - Parameters:
    ///   - item: An entry of ``readingOrder``.
    ///   - app: The launched app.
    /// - Returns: The element and its frame once revealed (or after the last drag).
    @MainActor
    private func reveal(_ item: Item, in app: XCUIApplication) -> (XCUIElement, CGRect) {
        let element = element(item, in: app)
        XCTAssertTrue(element.exists, "\(item) is on the page")
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        var frame = element.frame
        var region = contentRegion(app)
        for _ in 0..<16 {
            if frame.minY >= region.minY - 0.5, frame.maxY <= region.maxY + 0.5 { break }
            let step = region.height * 0.6
            let delta = frame.maxY > region.maxY
                ? -min(frame.maxY - region.maxY + 16, step)
                : min(region.minY - frame.minY + 16, step)
            let startY = delta < 0 ? region.maxY - 16 : region.minY + 16
            // Drag at the leading margin, beside the cards' rows and buttons.
            let start = origin.withOffset(CGVector(dx: region.minX + 8, dy: startY))
            let end = origin.withOffset(CGVector(dx: region.minX + 8, dy: startY + delta))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: FestivalApp.budget(0.3))
            frame = element.frame
            region = contentRegion(app)
        }
        return (element, frame)
    }

    // MARK: - Snapshot helpers

    /// Visit `root` and its descendants in tree (reading) order. A button is one element to
    /// VoiceOver, so the texts XCUITest lists inside it are not visited.
    @MainActor
    private static func walk(_ root: XCUIElementSnapshot, _ visit: (XCUIElementSnapshot) -> Void) {
        visit(root)
        guard root.elementType != .button else { return }
        for child in root.children { walk(child, visit) }
    }

    /// The snapshot's accessibility traits, when readable.
    @MainActor
    private static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
    }

    // MARK: - Evidence

    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
