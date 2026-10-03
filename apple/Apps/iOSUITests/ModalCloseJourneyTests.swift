import XCTest

/// Issue #23: every modal is built on the shared `FestivalModal`, so each one dismisses with
/// the system Close (`Button(role: .close)`, the ✕ glyph on iOS 26) in its own navigation
/// bar, labelled "Close" for VoiceOver — never a hand-drawn ✕, a text "Done" or a bottom
/// Close. Each test opens a group of modals and closes every one through that button.
///
/// Needs `tools/mock_service.py --port 18823` (a dedicated port, so another lane's fixture
/// service on 8765 is never assumed).
final class ModalCloseJourneyTests: XCTestCase {
    /// Loopback fixture origin for this class.
    private static let fixtureOrigin = "http://127.0.0.1:18823"

    /// The fixture app, first-run guides off unless a test asks for them.
    ///
    /// - Parameter extra: Additional launch environment.
    /// - Returns: An unlaunched app.
    @MainActor
    private func fixtureApp(_ extra: [String: String] = [:]) -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": Self.fixtureOrigin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": "off",
        ]
        environment.merge(extra) { _, new in new }
        return FestivalApp.makeApp(environment)
    }

    /// Assert the modal's Close is the navigation-bar system Close, then close with it.
    ///
    /// - Parameters:
    ///   - identifier: The Close button's accessibility identifier.
    ///   - app: The running application.
    ///   - shot: Optional screenshot name recorded before closing.
    @MainActor
    private func closeWithSystemClose(
        _ identifier: String, in app: XCUIApplication, shot: String? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let close = app.navigationBars.buttons[identifier]
        XCTAssertTrue(
            close.waitForExistence(timeout: 15),
            "\(identifier) is not a navigation-bar button", file: file, line: line
        )
        XCTAssertEqual(close.label, "Close", file: file, line: line)
        XCTAssertTrue(close.isHittable, "\(identifier) is not hittable", file: file, line: line)
        if let shot { SongsUITestSupport.record(app, name: shot) }
        close.tap()
        XCTAssertTrue(
            app.buttons[identifier].waitForNonExistence(timeout: 10),
            "\(identifier) did not dismiss its modal", file: file, line: line
        )
    }

    /// Tap a control once it exists.
    @MainActor
    private func tap(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.buttons[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(identifier)", file: file, line: line)
        element.tap()
    }

    /// Songs: Sort, Profiles, and Song Detail's Paths.
    @MainActor
    func testSongsModalsCloseWithSystemClose() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_TAB": "songs"])
        app.launch()
        tap("fst.songs.sort", in: app)
        closeWithSystemClose("fst.songs.sort.done", in: app)
        tap("fst.shell.profile", in: app)
        closeWithSystemClose("fst.profile.close", in: app, shot: "modal-close-profiles")
        tap("fst.songs.row.fixture-pulse", in: app)
        tap("fst.song-detail.paths", in: app)
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: 3) { warning.buttons["OK"].tap() }
        XCTAssertTrue(app.navigationBars.buttons["fst.paths.zoom-in"].waitForExistence(timeout: 15))
        closeWithSystemClose("fst.paths.close", in: app, shot: "modal-close-paths")
    }

    /// Settings: What's New (a full-screen cover on iPhone) and a first-run guide replay.
    @MainActor
    func testSettingsModalsCloseWithSystemClose() throws {
        continueAfterFailure = false
        let app = fixtureApp(["FST_DEBUG_TAB": "settings"])
        app.launch()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        let whatsNew = app.buttons["fst.settings.whats-new"]
        SongsUITestSupport.reveal(whatsNew, in: app, scrollingUp: true)
        whatsNew.tap()
        closeWithSystemClose("fst.whats-new.close", in: app, shot: "modal-close-whats-new")
        let replay = app.buttons["fst.settings.first-run.songs"]
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        replay.tap()
        closeWithSystemClose("fst.first-run.close", in: app, shot: "modal-close-first-run")
    }

    /// The Suggestions filter, which used a text "Done" before issue #23.
    @MainActor
    func testSuggestionsFilterClosesWithSystemClose() throws {
        continueAfterFailure = false
        let app = fixtureApp([
            "FST_DEBUG_TAB": "suggestions",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
        ])
        app.launch()
        tap("fst.suggestions.filter-button", in: app)
        XCTAssertTrue(app.navigationBars["Filter Suggestions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Done"].exists, "Filter Suggestions still has a text Done")
        closeWithSystemClose("fst.suggestions.filter.done", in: app, shot: "modal-close-suggestions-filter")
    }

    /// Rivals: Find Rival.
    @MainActor
    func testFindRivalClosesWithSystemClose() throws {
        continueAfterFailure = false
        let app = fixtureApp([
            "FST_DEBUG_ROUTE": "rivals",
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
        ])
        app.launch()
        tap("fst.rivals.findRival", in: app)
        closeWithSystemClose("fst.rivals.findRival.close", in: app)
    }

    /// Notifications (the bell shows only with a selected profile). `fixture-riv` has an
    /// empty feed, so closing it records no seen-state `NotificationsJourneyTests` relies on.
    @MainActor
    func testNotificationsClosesWithSystemClose() throws {
        continueAfterFailure = false
        let app = fixtureApp([
            "FST_DEBUG_TAB": "songs",
            "FST_DEBUG_PROFILE": "fixture-riv:Fixture Riv",
        ])
        app.launch()
        tap("fst.shell.notifications", in: app)
        closeWithSystemClose("fst.notifications.close", in: app)
    }
}
