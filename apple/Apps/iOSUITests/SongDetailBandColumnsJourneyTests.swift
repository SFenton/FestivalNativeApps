import UIKit
import XCTest

/// Accessibility of Song Detail's band previews in columns at the largest text size
/// (issue #491, for #366). #366 put the Duos, Trios and Quads previews in the same adaptive
/// card grid as the instrument cards (pattern `hinge-columns` R9), so on a wide window
/// Duos and Trios sit side by side. macOS has no Dynamic Type, so the hosted
/// `SongDetailBandColumnsAccessibilityTests` check the structure on the Mac (and the Duo
/// book pose); this journey opens `fixture-pulse` in iPad landscape at AX5 with
/// `fixture-player-1` selected, reaches Duos through Quick Links and checks that Duos and
/// Trios still pair, each heading is a header, every band button is a named, reachable
/// 44 pt target whose text grew and that sits wholly on screen, VoiceOver reads each card's
/// heading before its rows and Duos before Trios before Quads, and the system audit passes
/// for the band cards.
///
/// Runs against `tools/mock_service.py --large-catalogue` on `:8765` (the `apple-ci` iPad
/// step's fixture: two Duos rows plus the selected player's rank-29 band, empty Trios and
/// Quads); set `FST_FIXTURE_URL` (as `TEST_RUNNER_FST_FIXTURE_URL`) to use another port.
/// Skips when Song Detail never loads, and on iPhone, which runs portrait only (one column).
final class SongDetailBandColumnsJourneyTests: XCTestCase {
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44
    private static let prefix = "fst.song-detail."
    /// Duos' buttons in reading order: two ranked rows, the appended band, View Full.
    private static let duosButtons = [
        "band-row.Band_Duets.0", "band-row.Band_Duets.1", "band-selected.Band_Duets", "band-leaderboard.Band_Duets",
    ].map { prefix + $0 }

    // MARK: - Journey

    /// iPad landscape at AX5: Duos and Trios pair; headings, names, targets, reading order
    /// and the system audit hold for the band cards.
    ///
    /// - Throws: A skip on iPhone or when Song Detail never loads, or a failed requirement.
    @MainActor
    func testBandPreviewColumnsAreAccessibleAtLargestText() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone, "iPhone runs portrait only (one column)")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = try launch()
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "Not landscape: \(window)")
        try openDuos(in: app)

        // Two columns are in effect: the Duos and Trios cards share a row, Duos leading.
        let duos = any("band-header.Band_Duets", in: app)
        let trios = any("band-header.Band_Trios", in: app)
        XCTAssertTrue(trios.waitForExistence(timeout: FestivalApp.budget(10)), "No Trios heading")
        let duosFrame = duos.frame, triosFrame = trios.frame
        XCTAssertGreaterThan(triosFrame.minX, duosFrame.maxX, "Trios is not beside Duos: \(duosFrame) \(triosFrame)")
        XCTAssertLessThan(triosFrame.minY, duosFrame.maxY, "Trios is not on Duos' row: \(duosFrame) \(triosFrame)")
        XCTAssertLessThan(duosFrame.minY, triosFrame.maxY, "Trios is not on Duos' row: \(duosFrame) \(triosFrame)")

        // Headings: named for their band size (checked as headers in the reading order).
        for (heading, name) in [(duos, "Duos"), (trios, "Trios")] {
            XCTAssertTrue(heading.label.hasPrefix(name), "Heading reads \(heading.label)")
            XCTAssertFalse(heading.label.contains("fst."), "Heading reads its identifier: \(heading.label)")
        }

        // Text grew to AX5: a ranked row holds at least two body lines.
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
        ).lineHeight
        let firstRow = app.buttons[Self.duosButtons[0]]
        XCTAssertTrue(firstRow.waitForExistence(timeout: FestivalApp.budget(10)), "No Duos row button")
        XCTAssertGreaterThanOrEqual(firstRow.frame.height, bodyLine * 2, "Duos row not at AX5: \(firstRow.frame)")
        XCTAssertTrue(firstRow.label.hasPrefix("Rank 1, "), firstRow.label)

        // Every Duos button: named, a 44 pt target inside the Duos column and the window,
        // reachable once scrolled to.
        for id in Self.duosButtons {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists, "\(id) is not a button")
            for _ in 0..<6 where !button.isHittable { app.swipeUp() }
            let frame = button.frame
            XCTAssertTrue(button.isHittable, "\(id) is not reachable")
            XCTAssertFalse(button.label.isEmpty, "\(id) has no name")
            XCTAssertFalse(button.label.contains("fst."), "\(id) reads its identifier: \(button.label)")
            XCTAssertGreaterThanOrEqual(frame.width, Self.minimumTarget - 0.5, "\(id) target \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, Self.minimumTarget - 0.5, "\(id) target \(frame)")
            XCTAssertLessThan(frame.maxX, triosFrame.minX, "\(id) crosses into Trios: \(frame)")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(id) runs off screen: \(frame)")
        }
        XCTAssertTrue(app.buttons[Self.duosButtons[2]].label.hasPrefix("Your band, Rank 29, "))
        XCTAssertFalse(app.buttons[Self.prefix + "band-leaderboard.Band_Trios"].exists, "Empty Trios offers View Full")

        try assertReadingOrder(in: app)

        // The system audit at AX5, for the band cards only (the page and shell have their
        // own). Contrast is left to the hosted checks: cards under the fade dim by design.
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion]
        ) { issue in
            !(issue.element?.identifier ?? "").hasPrefix(Self.prefix + "band")
        }
    }

    // MARK: - Assertions

    /// VoiceOver reads the instrument cards first, then Duos (heading, rows, View Full),
    /// Trios (heading, empty state) and Quads (Quads may be outside the materialized tree);
    /// every band heading carries the header trait.
    ///
    /// - Parameter app: The running app.
    /// - Throws: An unavailable accessibility snapshot.
    @MainActor
    private func assertReadingOrder(in app: XCUIApplication) throws {
        var nodes: [XCUIElementSnapshot] = []
        func walk(_ element: XCUIElementSnapshot) {
            if !element.identifier.isEmpty { nodes.append(element) }
            element.children.forEach(walk)
        }
        walk(try app.snapshot())
        let identifiers = nodes.map(\.identifier)
        let expected = (["band-header.Band_Duets"] + Self.duosButtons.map { String($0.dropFirst(Self.prefix.count)) }
            + ["band-header.Band_Trios", "band-empty.Band_Trios", "band-header.Band_Quad", "band-empty.Band_Quad"])
            .map { Self.prefix + $0 }
        var read: [String] = []
        for id in identifiers where expected.contains(id) && !read.contains(id) { read.append(id) }
        XCTAssertEqual(Array(read.prefix(7)), Array(expected.prefix(7)), "Duos and Trios read out of order: \(read)")
        XCTAssertEqual(read, expected.filter(read.contains), "Band cards read out of order: \(read)")
        if let lastInstrument = identifiers.lastIndex(where: { $0.hasPrefix(Self.prefix + "card-header.") }),
           let firstBand = identifiers.firstIndex(where: { $0.hasPrefix(Self.prefix + "band") }) {
            XCTAssertLessThan(lastInstrument, firstBand, "An instrument card reads after the band cards")
        }
        for node in nodes where node.identifier.hasPrefix(Self.prefix + "band-header.") {
            let object = node as AnyObject
            guard object.responds(to: NSSelectorFromString("traits")),
                  let traits = (object.value(forKey: "traits") as? NSNumber)?.uint64Value else { continue }
            XCTAssertNotEqual(traits & UIAccessibilityTraits.header.rawValue, 0, "\(node.identifier) is not a header")
        }
    }

    // MARK: - Helpers

    /// The element carrying a Song Detail identifier.
    private func any(_ suffix: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: Self.prefix + suffix).firstMatch
    }

    /// Launch `fixture-pulse`'s Song Detail at AX5 with `fixture-player-1` selected.
    ///
    /// - Returns: The running app.
    /// - Throws: A skip when Song Detail never loads.
    @MainActor
    private func launch() throws -> XCUIApplication {
        let base = ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_SONG": "fixture-pulse",
        ])
        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", ax5.rawValue]
        app.launch()
        guard any("intensity", in: app).waitForExistence(timeout: FestivalApp.budget(30)),
              app.buttons["fst.quick-links.open"].waitForExistence(timeout: FestivalApp.budget(15)) else {
            throw XCTSkip("Song Detail never loaded; run tools/mock_service.py --large-catalogue on \(base).")
        }
        return app
    }

    /// Bring the Duos card into view through Quick Links (never repeated drags, which can
    /// trip Song Detail's known render loop).
    ///
    /// - Parameter app: The running app.
    /// - Throws: A missing Quick Links entry or heading.
    @MainActor
    private func openDuos(in app: XCUIApplication) throws {
        app.buttons["fst.quick-links.open"].tap()
        let item = FestivalApp.quickLinkRow("band-Band_Duets", label: "Duos", in: app)
        XCTAssertTrue(item.waitForExistence(timeout: FestivalApp.budget(10)), "Quick Links has no Duos section")
        item.tap()
        let heading = any("band-header.Band_Duets", in: app)
        let shown = NSPredicate(format: "exists == true AND isHittable == true")
        expectation(for: shown, evaluatedWith: heading)
        waitForExpectations(timeout: FestivalApp.budget(15)) { error in
            if error != nil { XCTFail("Quick Links did not bring the Duos heading into view") }
        }
    }
}
