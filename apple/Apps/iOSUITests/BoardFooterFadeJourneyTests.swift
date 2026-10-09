import UIKit
import XCTest

/// Accessibility at the largest text size for the board footer fade (issue #473, for
/// #329): every paginated board fades its rows over 40 pt above its pinned pager
/// (`bottomChromeFade`, pattern `scroll-edge` R3/R9). macOS has no Dynamic Type, so the
/// hosted `bandBoardFooterFadeKeepsRowsAndPagerAccessible` cannot show AX5; this journey
/// does, on Player Bands (a board the CI fixture pages: `fixture-player-1`'s 30-band
/// "All" group, 25 a page) with no selected player.
///
/// Runs against `tools/mock_service.py` on `:8765` (the `apple-ci` simulator step's
/// `--large-catalogue` fixture); set `FST_BOARD_FADE_FIXTURE_URL` (as
/// `TEST_RUNNER_FST_BOARD_FADE_FIXTURE_URL`) to use another port. Skips when the board
/// never loads.
final class BoardFooterFadeJourneyTests: XCTestCase {
    /// Identifier prefix of Player Bands' rows.
    private static let rowPrefix = "fst.player-bands.row."
    /// The pager's controls, in reading order, with the words their names carry.
    private static let pagerControls = [
        ("fst.player-bands.page-first", "First"),
        ("fst.player-bands.page-previous", "Previous"),
        ("fst.player-bands.page-info", "Page"),
        ("fst.player-bands.page-next", "Next"),
        ("fst.player-bands.page-last", "Last"),
    ]
    /// `ScrollEdgeFade.distance`: the board footer ramp (#329).
    private static let fadeDistance: CGFloat = 40
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    private static let minimumTarget: CGFloat = 44

    /// At AX5 the board's rows grow and the 40 pt fade above the pager stays drawing
    /// only: rows in it are still named and reachable, the pager's controls keep their
    /// names, reading order and 44 pt targets on screen, and at the end of
    /// the page the last row rests whole above the pager. The system audit (Dynamic
    /// Type, clipped text, descriptions, hit regions) covers the board's rows and pager.
    @MainActor
    func testBoardFooterFadeAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let base = ProcessInfo.processInfo.environment["FST_BOARD_FADE_FIXTURE_URL"] ?? "http://127.0.0.1:8765"
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": base,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_ROUTE": "playerBands:fixture-player-1",
        ])
        let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", ax5.rawValue]
        app.launch()

        let pageInfo = app.descendants(matching: .any)["fst.player-bands.page-info"]
        guard pageInfo.waitForExistence(timeout: 20) else {
            throw XCTSkip("Player Bands never loaded; run tools/mock_service.py on \(base).")
        }
        let window = app.windows.firstMatch.frame
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", Self.rowPrefix))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No band rows")

        // Pager: named, 44 pt, on screen and operable at AX5.
        var pagerTop = CGFloat.greatestFiniteMagnitude
        var previousMaxX = -CGFloat.greatestFiniteMagnitude
        for (identifier, word) in Self.pagerControls {
            let control = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(control.exists, "\(identifier) missing")
            XCTAssertTrue(control.label.localizedCaseInsensitiveContains(word), "\(identifier) reads \(control.label)")
            let frame = control.frame
            XCTAssertGreaterThanOrEqual(frame.width, Self.minimumTarget - 0.5, "\(identifier) target \(frame)")
            XCTAssertGreaterThanOrEqual(frame.height, Self.minimumTarget - 0.5, "\(identifier) target \(frame)")
            XCTAssertTrue(window.contains(frame), "\(identifier) off screen: \(frame)")
            XCTAssertGreaterThan(frame.minX, previousMaxX - 0.5, "\(identifier) out of reading order")
            previousMaxX = frame.maxX
            pagerTop = min(pagerTop, frame.minY)
        }
        XCTAssertTrue(app.buttons["fst.player-bands.page-next"].isHittable, "Next page is not reachable")
        XCTAssertTrue(app.buttons["fst.player-bands.page-next"].isEnabled)
        XCTAssertFalse(app.buttons["fst.player-bands.page-previous"].isEnabled, "Page 1 has no previous page")

        // Rows grew to AX5: at least one body line per card.
        let bodyLine = UIFont.preferredFont(
            forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: ax5)
        ).lineHeight
        XCTAssertGreaterThanOrEqual(rows.firstMatch.frame.height, bodyLine, "Row not at AX5: \(rows.firstMatch.frame)")

        // Rows inside the fade band stay named elements, reachable while their middle is
        // above the pager (the mask is drawing only, scroll-edge R7 keeps the cut below).
        var crossed = false
        for step in 0..<4 {
            let fadeBand = CGRect(
                x: window.minX, y: pagerTop - 8 - Self.fadeDistance, width: window.width, height: Self.fadeDistance
            )
            for row in rows.allElementsBoundByIndex where row.frame.intersects(fadeBand) {
                crossed = true
                XCTAssertFalse(row.label.isEmpty, "\(row.identifier) has no name in the fade")
                if row.frame.midY < fadeBand.maxY {
                    XCTAssertTrue(row.isHittable, "\(row.identifier) in the fade is not reachable: \(row.frame)")
                }
            }
            if step < 3 {
                let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)))
            }
        }
        XCTAssertTrue(crossed, "No row crossed the 40 pt fade above the pager")

        // The system audit at AX5, for the board's rows and pager only (the shell has its own).
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .sufficientElementDescription, .hitRegion]
        ) { issue in
            !(issue.element?.identifier.hasPrefix("fst.player-bands.") ?? false)
        }

        // End of the page: the last row rests whole above the pager (the fade has shrunk
        // to nothing), reachable and fully on screen.
        var lastFrame = CGRect.null
        for _ in 0..<40 {
            app.swipeUp(velocity: .fast)
            let bottom = rows.allElementsBoundByIndex.map(\.frame).filter { window.intersects($0) }
                .max { $0.maxY < $1.maxY } ?? .null
            if bottom == lastFrame { break }
            lastFrame = bottom
        }
        let last = try XCTUnwrap(rows.allElementsBoundByIndex.filter { window.intersects($0.frame) }
            .max { $0.frame.maxY < $1.frame.maxY })
        XCTAssertLessThanOrEqual(last.frame.maxY, pagerTop + 0.5, "Last row under the pager: \(last.frame) vs \(pagerTop)")
        XCTAssertGreaterThanOrEqual(last.frame.maxY, pagerTop - 8 - 12, "Last row does not rest at the pager: \(last.frame)")
        XCTAssertTrue(last.isHittable, "Last row is not reachable: \(last.frame)")
        XCTAssertFalse(last.label.isEmpty)
        XCTAssertTrue(app.buttons["fst.player-bands.page-next"].isHittable, "Pager lost at the end of the page")
    }
}
