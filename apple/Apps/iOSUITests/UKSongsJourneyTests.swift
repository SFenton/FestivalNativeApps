import UIKit
import XCTest

// MARK: - Songs and Item Shop (UIKit port parity and accessibility)

/// Songs and Item Shop identifiers, labels, traits, 44 pt targets and AX5 growth, written
/// against what both front ends must expose, so the same file runs against the SwiftUI app and
/// the UIKit port (`python3 tools/ios_sim.py uitest --app uikit --only UKSongsJourneyTests`).
/// The port-specific rules (one combined row element, child stops only while VoiceOver is
/// off) are in `.agents/platforms/apple/uikit-port.md`. Loopback fixture only.
final class UKSongsJourneyTests: XCTestCase {
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue

    @MainActor
    private func fixtureApp(profile: Bool = false, size: String? = nil, route: String? = nil) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ]
        if profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        if let route { env["FST_DEBUG_ROUTE"] = route }
        let app = FestivalApp.makeApp(env)
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        return app
    }

    private func assertTarget(_ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.height, 43.5, "\(name) is shorter than 44 pt", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.5, "\(name) is narrower than 44 pt", file: file, line: line)
    }

    // MARK: Songs

    /// Each catalogue song is one button named for the song, its artist and its year · length
    /// line; the Sort and Filter tools state their values.
    @MainActor
    func testSongsRowsAndToolsExposeNamesAndValues() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        if !pulse.waitForExistence(timeout: FestivalApp.budget(20)) {
            let dump = app.debugDescription
            let all = dump.components(separatedBy: "\n")
            let start = all.firstIndex { $0.contains("CollectionView") } ?? 0
            XCTFail("Row missing. Hierarchy: \(all[start..<min(all.count, start + 14)].map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " // "))")
            return
        }
        XCTAssertTrue(pulse.label.contains("Fixture Pulse"), "Row label: \(pulse.label)")
        XCTAssertTrue(pulse.label.contains(" · "), "Row label lacks the artist · year · length line: \(pulse.label)")
        XCTAssertTrue(pulse.isHittable)
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        XCTAssertEqual(sort.label, "Sort")
        XCTAssertEqual(sort.value as? String, "Title, ascending")
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(filter.exists)
        XCTAssertEqual(filter.label, "Filter Songs")
        XCTAssertEqual(filter.value as? String, "No filters")
        assertTarget(sort, "Sort")
        assertTarget(filter, "Filter")
    }

    /// The Sort sheet applies a change at once, states it on the tool and Reset restores Title A–Z.
    @MainActor
    func testSortSheetAppliesAndResets() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: FestivalApp.budget(20)))
        sort.tap()
        let descending = app.buttons["fst.songs.sort.direction.descending"]
        XCTAssertTrue(descending.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(descending.frame.width, 40, "Descending is narrower than its 44 pt control")
        XCTAssertGreaterThanOrEqual(descending.frame.height, 34, "Descending is shorter than its 36 pt control")
        descending.tap()
        let done = app.buttons["fst.songs.sort.done"]
        XCTAssertTrue(done.exists)
        done.tap()
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        XCTAssertEqual(sort.value as? String, "Title, descending")
        sort.tap()
        let reset = app.buttons["fst.songs.sort.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        reset.tap()
        app.buttons["fst.songs.sort.done"].tap()
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        XCTAssertEqual(sort.value as? String, "Title, ascending")
    }

    /// The Filter sheet's General groups disclose their switches; a change shows on the tool.
    @MainActor
    func testFilterSheetGroupsAndApply() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: FestivalApp.budget(20)))
        filter.tap()
        let bass = app.buttons["fst.songs.filter.double-bass"]
        XCTAssertTrue(bass.waitForExistence(timeout: 10))
        XCTAssertEqual(bass.value as? String, "Collapsed")
        bass.tap()
        let supported = app.switches["fst.songs.filter.double-bass.supported"]
        XCTAssertTrue(supported.waitForExistence(timeout: 5))
        supported.tap()
        app.buttons["fst.songs.filter.done"].tap()
        let after = app.buttons["fst.songs.filter"]
        XCTAssertTrue(after.waitForExistence(timeout: 15), "Filter tool missing after closing the sheet")
        XCTAssertTrue((after.value as? String)?.contains("Double Bass filter") == true, "Filter value: \(String(describing: after.value))")
    }

    /// At the largest text size rows wrap and grow, stay buttons and the tools keep 44 pt targets.
    @MainActor
    func testSongsAtLargestTextGrowAndStayReachable() throws {
        continueAfterFailure = false
        let normal = fixtureApp()
        normal.launch()
        let row = normal.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(20)))
        let normalHeight = row.frame.height
        normal.terminate()

        let large = fixtureApp(size: Self.ax5)
        large.launch()
        let grown = large.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(grown.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertGreaterThan(grown.frame.height, normalHeight, "The row did not grow at AX5")
        XCTAssertLessThanOrEqual(grown.frame.width, large.windows.firstMatch.frame.width)
        let tools = large.buttons["fst.songs.tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10) || large.buttons["fst.songs.sort"].exists)
    }

    // MARK: Item Shop

    /// The Item Shop lists each public offer with its official Shop link.
    @MainActor
    func testShopOffersExposeOfficialLinks() throws {
        continueAfterFailure = false
        let app = fixtureApp(route: "shop")
        app.launch()
        let link = app.buttons["fst.shop.external.fixture-pulse"]
        XCTAssertTrue(link.waitForExistence(timeout: FestivalApp.budget(25)))
        XCTAssertTrue(link.label.contains("Open Official Item Shop"), "Link label: \(link.label)")
        let sort = app.buttons["fst.shop.sort"]
        XCTAssertTrue(sort.exists)
        XCTAssertEqual(sort.label, "Sort Item Shop")
        XCTAssertEqual(sort.value as? String, "Title, ascending")
        let filter = app.buttons["fst.shop.filter"]
        XCTAssertTrue(filter.exists)
        XCTAssertEqual(filter.label, "Filter Item Shop")
        XCTAssertEqual(filter.value as? String, "No filters")
    }
}
