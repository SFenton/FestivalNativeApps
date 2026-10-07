import UIKit
import XCTest

/// Issue #351: the Player page's Select and Switch actions are the same accent-blue
/// prominent (`.borderedProminent`) item in every placement, and the drawer's Deselect
/// stays red.
///
/// On the iPhone Duo vertical bar (folded, or inner landscape) the page mirrors its
/// identity action into the rail as `fst.player.select.rail` (`VerticalBarActionItem`);
/// it must stay visible ahead of other rail items (not overflow into "…") and be filled
/// blue. Elsewhere (iPhone, Duo inner portrait's horizontal bar) the header button
/// `fst.player.select` is measured instead. Before #351 the rail drew a white glyph on
/// grey glass (0 % blue); the filled item measures ~80 % of its frame blue, a blue-tinted
/// glyph (the selected tab) ~13 %.
///
/// Run the rail on the Duo with `python3 tools/ios_sim.py uitest --device duo --pose
/// folded --only PlayerIdentityRailJourneyTests`; the default iPhone run covers the
/// header button. Runs against the loopback fixture (`tools/mock_service.py`;
/// `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL` or `127.0.0.1:8765`) on a flat backdrop,
/// so no artwork shows through the bars.
final class PlayerIdentityRailJourneyTests: XCTestCase {
    /// Smallest share of the action's frame painted accent blue: a filled item, not a
    /// blue-tinted glyph (~13 %).
    private static let minimumProminentBlue = 0.5
    /// Largest share of the Deselect button painted accent blue.
    private static let maximumDeselectBlue = 0.02
    /// Smallest share of the Deselect button painted red: its system-red title on the
    /// dark red-tinted bordered capsule measures ~9 % on the folded Duo.
    private static let minimumDeselectRed = 0.05

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// Launch the fixture app on the Settings tab, optionally on a player route.
    ///
    /// - Parameters:
    ///   - selected: The selected player as `accountId:displayName`, or nil for none.
    ///   - route: `FST_DEBUG_ROUTE`, or nil for the tab root.
    /// - Returns: The launched app.
    @MainActor
    private func launch(selected: String?, route: String?) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FLAT_BACKDROP": "1",
            "FST_DEBUG_TAB": "settings",
        ]
        if let selected { env["FST_DEBUG_PROFILE"] = selected }
        if let route { env["FST_DEBUG_ROUTE"] = route }
        return FestivalApp.launch(env)
    }

    // MARK: - Journeys

    /// Anonymous on Fixture Player 1: Select Profile is the blue prominent item.
    @MainActor
    func testSelectIsProminentBlue() throws {
        let app = launch(selected: nil, route: "player:fixture-player-1")
        try assertProminentBlue(in: app, label: "Select Profile")
    }

    /// Fixture Player 2 selected, viewing Fixture Player 1: Switch To This Profile is the
    /// same blue prominent item.
    @MainActor
    func testSwitchIsProminentBlue() throws {
        let app = launch(selected: "fixture-player-2:Fixture Player 2", route: "player:fixture-player-1")
        try assertProminentBlue(in: app, label: "Switch To This Profile")
    }

    /// The drawer's Deselect (the only Deselect since operator batch 7) stays red.
    @MainActor
    func testDrawerDeselectStaysRed() throws {
        let app = launch(selected: "fixture-player-1:Fixture Player 1", route: nil)
        openDrawer(app)
        let deselect = app.buttons["fst.shell.drawer.deselect-profile"]
        XCTAssertTrue(deselect.waitForExistence(timeout: 10), "Drawer Deselect missing")
        settle()
        let pixels = try capture(app, "#351 drawer Deselect")
        let frame = deselect.frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        let red = try XCTUnwrap(pixels.fraction(in: frame, matching: ButtonFillPixels.destructiveRed))
        let blue = try XCTUnwrap(pixels.fraction(in: frame, matching: ButtonFillPixels.accentBlue))
        XCTAssertGreaterThanOrEqual(red, Self.minimumDeselectRed, "Deselect is not red (\(red) of \(frame))")
        XCTAssertLessThanOrEqual(blue, Self.maximumDeselectBlue, "Deselect turned blue (\(blue))")
    }

    // MARK: - Helpers

    /// Require the page's identity action to be a filled accent-blue item: the rail item
    /// on a vertical bar (visible, not in "…"), otherwise the header button.
    ///
    /// - Parameters:
    ///   - app: The app on a player page.
    ///   - label: The action's expected title.
    /// - Throws: A missing screenshot bitmap or frame.
    @MainActor
    private func assertProminentBlue(
        in app: XCUIApplication, label: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertTrue(
            app.descendants(matching: .any)["fst.player.available"].waitForExistence(timeout: 20),
            "The player page did not load", file: file, line: line
        )
        let rail = app.buttons["fst.player.select.rail"]
        let header = app.buttons["fst.player.select"]
        let verticalBar = isVerticalBar(app)
        let action = verticalBar ? rail : header
        XCTAssertTrue(
            action.waitForExistence(timeout: 10),
            "\(verticalBar ? "Rail" : "Header") identity action missing", file: file, line: line
        )
        XCTAssertEqual(action.label, label, file: file, line: line)
        // A vertical-bar action that overflowed into "…" is not hittable.
        XCTAssertTrue(action.isHittable, "\(label) is hidden (overflowed?)", file: file, line: line)
        settle()
        let place = verticalBar ? "rail" : "header"
        let pixels = try capture(app, "#351 \(label) – \(place)")
        let frame = action.frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        let blue = try XCTUnwrap(
            pixels.fraction(in: frame, matching: ButtonFillPixels.accentBlue), file: file, line: line
        )
        XCTAssertGreaterThanOrEqual(
            blue, Self.minimumProminentBlue,
            "\(label) (\(place)) is not filled accent blue: \(blue) of \(frame)", file: file, line: line
        )
    }

    /// Whether the system shows sections in the iPhone Duo vertical bar: the Songs and
    /// Settings section items are stacked in one column rather than side by side.
    ///
    /// - Parameter app: The running app.
    /// - Returns: True on a vertical bar.
    @MainActor
    private func isVerticalBar(_ app: XCUIApplication) -> Bool {
        // The tab view also exposes zero-size copies of its items; measure the drawn ones.
        func section(_ label: String) -> XCUIElement? {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
            _ = matches.firstMatch.waitForExistence(timeout: 10)
            return matches.allElementsBoundByIndex.first { $0.frame.width > 0 && $0.frame.height > 0 }
        }
        guard let songs = section("Songs"), let settings = section("Settings") else { return false }
        return abs(songs.frame.midX - settings.frame.midX) < 4
            && abs(songs.frame.midY - settings.frame.midY) > 20
    }

    /// Open the drawer from the bar, or from the vertical bar's "…" overflow menu.
    ///
    /// - Parameter app: The app on a tab root.
    @MainActor
    private func openDrawer(_ app: XCUIApplication) {
        let open = app.buttons["fst.shell.drawer.open"]
        if open.waitForExistence(timeout: 10), open.isHittable {
            open.tap()
            return
        }
        let more = app.buttons.matching(identifier: "BottomOverflowBarButtonItem").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "Drawer button missing and no overflow menu")
        more.tap()
        let entry = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR label == %@", "Menu", "Open Navigation")).firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Overflow menu has no drawer entry")
        entry.tap()
    }

    /// Let a launch, push or drawer finish animating before measuring.
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    }

    /// Screenshot the app, attach it and wrap it for measuring.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - name: Attachment name.
    /// - Returns: The screenshot's pixels, scaled to the app window's points.
    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) throws -> ButtonFillPixels {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(shot.image.cgImage)
        return try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: app.frame.width))
    }
}
