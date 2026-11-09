import UIKit
import XCTest

/// Focused UIKit modal-shell regressions. These journeys intentionally exercise the
/// presentation path rather than asserting implementation details.
final class UKModalFoundationTests: XCTestCase {
    @MainActor
    private func app() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_MODAL_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
            "FST_DEBUG_TAB": "songs",
        ])
    }

    /// Keeps the final rendered state and accessibility hierarchy, including failed journeys.
    @MainActor
    private func capture(_ application: XCUIApplication, name: String) {
        SongsUITestSupport.record(application, name: name)
        let hierarchy = XCTAttachment(string: application.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    /// Closing a Profiles sheet while its UISearchController owns the responder chain must
    /// dismiss the sheet, not merely the search controller.
    @MainActor
    func testSearchActiveCloseDismissesTheOuterSheet() throws {
        let application = app()
        defer { capture(application, name: "profiles-search-close") }
        application.launch()
        let profile = application.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        profile.tap()

        let field = application.searchFields.matching(
            NSPredicate(format: "placeholderValue == %@", "Search players or bands")
        ).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("fixture")

        let close = application.buttons["fst.profile.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: application.buttons["fst.profile.close"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertTrue(profile.waitForExistence(timeout: 5), "The presenting shell did not return")
    }

    /// Compact sheet sizing keeps its primary action and native Close reachable.
    @MainActor
    func testCompactSongSheetKeepsItsActions() throws {
        let application = app()
        defer { capture(application, name: "compact-song-actions") }
        application.launch()
        let sort = application.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 20))
        sort.tap()

        let done = application.buttons["fst.songs.sort.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(done.isHittable, "The compact sheet hid its action")
        XCTAssertTrue(application.navigationBars["Sort By"].exists)
    }

    @MainActor
    func testProfilesCloseRemainsAccessibleAtAX5() throws {
        let application = app()
        defer { capture(application, name: "profiles-close-ax5") }
        application.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        application.launch()
        let profile = application.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        profile.tap()

        let close = application.buttons["fst.profile.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertEqual(close.label, "Close")
        XCTAssertTrue(close.isHittable)
        var issues: [String] = []
        try application.performAccessibilityAudit(
            for: [.elementDetection, .sufficientElementDescription, .hitRegion]
        ) { issue in
            guard issue.element?.identifier == "fst.profile.close" else { return true }
            issues.append(issue.compactDescription)
            return true
        }
        XCTAssertEqual(issues, [])
        SongsUITestSupport.record(application, name: "profiles-modal-ax5")
        // Stay one 2x-display pixel inside the target's exclusive maximum edges.
        let probes = [
            CGVector(dx: -21.5, dy: 0), CGVector(dx: 21.5, dy: 0),
            CGVector(dx: 0, dy: -21.5), CGVector(dx: 0, dy: 21.5),
        ]
        for (index, offset) in probes.enumerated() {
            if index > 0 {
                XCTAssertTrue(profile.waitForExistence(timeout: 5))
                profile.tap()
            }
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            let center = close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.withOffset(offset).tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed, "Close hit-region probe \(index)")
        }
    }

    @MainActor
    func testSongsDetailLeaderboardRetainsItsPagedRoute() throws {
        let application = app()
        defer { capture(application, name: "shared-navigation-song-page-two") }
        application.launch()
        let song = application.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 20))
        song.tap()
        let leaderboard = application.buttons["fst.song-detail.leaderboard.Solo_Guitar"]
        XCTAssertTrue(leaderboard.waitForExistence(timeout: 10))
        leaderboard.tap()

        let next = application.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(next.isHittable)
        next.tap()
        let pageInfo = application.descendants(matching: .any).matching(
            identifier: "fst.song-leaderboard.page-info"
        ).firstMatch
        let pageTwo = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "2 of 2"), object: pageInfo
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pageTwo], timeout: 10), .completed)
        XCTAssertTrue(
            application.descendants(matching: .any).matching(
                identifier: "fst.song-leaderboard.row.fixture-player-26"
            ).firstMatch.waitForExistence(timeout: 10))
        SongsUITestSupport.record(application, name: "shared-navigation-song-page-two")
    }
}
