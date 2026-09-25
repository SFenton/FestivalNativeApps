import XCTest

/// Exercise actual AppKit-hosted SwiftUI screens without a browser or live API.
final class FestivalDesktopUITests: XCTestCase {
    // MARK: - Window and navigation

    /// Open the fixture catalogue, then switch to native sidebar Settings.
    ///
    /// - Throws: A missing page control or failed app launch.
    @MainActor
    func testSongsAndSettingsSidebar() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.row.fixture-pulse").firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        capture(app, name: "macos-songs")

        let settings = app.descendants(matching: .any)
            .matching(identifier: "fst.nav.settings").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.click()
        XCTAssertTrue(app.staticTexts["App Settings"].waitForExistence(timeout: 10))
        capture(app, name: "macos-settings")
    }

    /// Inspect native row hit target, destination and score pagination.
    ///
    /// - Throws: A missing Detail, leaderboard or page-two control.
    @MainActor
    func testSongDetailAndLeaderboard() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:8765"
        app.launch()
        let song = app.descendants(matching: .any)
            .matching(identifier: "fst.songs.row.fixture-pulse").firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.click()
        XCTAssertTrue(app.staticTexts["Intensity"].waitForExistence(timeout: 10))
        capture(app, name: "macos-song-detail")

        let chart = app.descendants(matching: .any)
            .matching(identifier: "fst.song-detail.leaderboard.Solo_Guitar").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        chart.click()
        let next = app.buttons["fst.song-leaderboard.page-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.click()
        XCTAssertTrue(app.staticTexts["2 / 2"].waitForExistence(timeout: 10))
        capture(app, name: "macos-score-page2")
    }

    // MARK: - Evidence

    /// Retain only our native app's window in the Xcode result bundle.
    ///
    /// - Parameters:
    ///   - app: Launched Festival desktop app.
    ///   - name: Page/state identifier for the visual matrix.
    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        XCTContext.runActivity(named: name) { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }
}
