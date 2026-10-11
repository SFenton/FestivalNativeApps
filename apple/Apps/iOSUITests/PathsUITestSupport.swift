import XCTest

// MARK: - Paths journey helpers

/// Shared steps for the Paths sheet journeys that run against the large-catalogue fixture
/// (`PathsSwitchAccessibilityJourneyTests`, #430; `PathsDismissAccessibilityJourneyTests`,
/// #445): open `fixture-pulse`'s Paths from Songs, find elements by identifier, pick a
/// menu option and audit with one retry of XCTest's own deadline.
enum PathsUITestSupport {
    /// Filter Songs to `fixture-pulse` (the large catalogue lists it under F), open it, then
    /// its Paths sheet from the page tools, dismissing the Karaoke notice.
    ///
    /// - Parameter app: The launched app on Songs.
    @MainActor
    static func openPaths(in app: XCUIApplication) {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(20)), "No Songs rows")
        let field = SongsUITestSupport.songsSearchField(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: FestivalApp.budget(5)), "No Filter Songs field")
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        // The live filter can drop a keystroke while it re-renders, so retype once.
        for _ in 0..<2 where !song.exists {
            field.tap()
            if let typed = field.value as? String, !typed.isEmpty, typed != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count))
            }
            field.typeText("Pulse")
            _ = song.waitForExistence(timeout: FestivalApp.budget(5))
        }
        XCTAssertTrue(song.exists, "No fixture-pulse row")
        for _ in 0..<20 where !song.isHittable {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        song.tap()
        openPathsFromSongDetail(in: app)
    }

    /// Tap Song Detail's Paths button and wait for the sheet, past the Karaoke notice.
    ///
    /// - Parameter app: The running app on `fixture-pulse`'s Song Detail.
    @MainActor
    static func openPathsFromSongDetail(in app: XCUIApplication) {
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: FestivalApp.budget(20)), "No Paths button")
        open.tap()
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: FestivalApp.budget(3)) { warning.buttons["OK"].tap() }
        XCTAssertTrue(element("fst.paths.display", in: app).waitForExistence(timeout: FestivalApp.budget(10)),
                      "No Paths sheet")
    }

    /// The first element with an identifier, of any type.
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier.
    ///   - app: The running app.
    /// - Returns: The element query's first match.
    @MainActor
    static func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Open a menu picker and pick an option.
    ///
    /// - Parameters:
    ///   - option: The option's label.
    ///   - menu: The menu button.
    ///   - app: The running app.
    @MainActor
    static func choose(_ option: String, in menu: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(menu.waitForExistence(timeout: FestivalApp.budget(10)))
        menu.tap()
        let item = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", option, menu.identifier)
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: FestivalApp.budget(5)), "Menu option \(option) missing")
        item.tap()
        XCTAssertTrue(item.waitForNonExistence(timeout: FestivalApp.budget(5)), "Menu \(option) did not close")
    }
}
