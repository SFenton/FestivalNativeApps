import XCTest

// MARK: - Paths journey helpers

/// Shared steps for the Paths sheet journeys that run against the large-catalogue fixture
/// (`PathsSwitchAccessibilityJourneyTests`, #430; `PathsDismissAccessibilityJourneyTests`,
/// #445; `PathsKaraokeNoticeAccessibilityJourneyTests`, #649): open `fixture-pulse`'s Paths
/// from Songs, find elements by identifier, pick a menu option, check the Karaoke notice
/// against the chart behind it and hold Paths reads with the fixture's control.
enum PathsUITestSupport {
    /// Filter Songs to `fixture-pulse` (the large catalogue lists it under F), open it, then
    /// its Paths sheet from the page tools, dismissing the Karaoke notice.
    ///
    /// - Parameter app: The launched app on Songs.
    @MainActor
    static func openPaths(in app: XCUIApplication) {
        openSongDetail(in: app)
        openPathsFromSongDetail(in: app)
    }

    /// Filter Songs to `fixture-pulse` and open its Song Detail, leaving Paths closed.
    ///
    /// - Parameter app: The launched app on Songs.
    @MainActor
    static func openSongDetail(in app: XCUIApplication) {
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
        XCTAssertTrue(app.buttons["fst.song-detail.paths"].waitForExistence(timeout: FestivalApp.budget(20)),
                      "No Paths button")
    }

    /// Tap Song Detail's Paths button and wait for the sheet, past the Karaoke notice.
    ///
    /// - Parameter app: The running app on `fixture-pulse`'s Song Detail.
    @MainActor
    static func openPathsFromSongDetail(in app: XCUIApplication) {
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: FestivalApp.budget(20)), "No Paths button")
        open.tap()
        dismissKaraokeNotice(in: app)
        XCTAssertTrue(element("fst.paths.display", in: app).waitForExistence(timeout: FestivalApp.budget(10)),
                      "No Paths sheet")
    }

    // MARK: Karaoke notice (#649)

    /// The Paths sheet's first chart (image, table or error) once it replaces the spinner.
    ///
    /// - Parameter app: The running app.
    /// - Returns: The first loaded form.
    @MainActor
    static func loadedChart(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ OR identifier IN %@",
            "fst.paths.text.", ["fst.paths.image", "fst.paths.error"]
        )).firstMatch
    }

    /// Wait for the "Some Instruments Unavailable" notice, checking the sheet the moment it
    /// shows: the loaded chart behind it and no spinner (load-transition R1, issue #649).
    /// A notice raised over the spinner fails here even if the chart loads behind it later.
    ///
    /// - Parameter app: The running app, with the Paths sheet just opened.
    /// - Returns: True when the notice is showing.
    @MainActor
    @discardableResult
    static func waitForKaraokeNotice(in app: XCUIApplication) -> Bool {
        let warning = app.alerts["Some Instruments Unavailable"]
        let chart = loadedChart(in: app)
        let deadline = Date().addingTimeInterval(FestivalApp.budget(15))
        while Date() < deadline, !warning.exists, !chart.exists {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard warning.exists || warning.waitForExistence(timeout: FestivalApp.budget(3)) else { return false }
        assertKaraokeNoticeFollowsLoadedChart(in: app, "Paths notice")
        return true
    }

    /// Answer the Karaoke notice with OK once it follows the loaded chart, if it shows.
    ///
    /// - Parameter app: The running app, with the Paths sheet just opened.
    @MainActor
    static func dismissKaraokeNotice(in app: XCUIApplication) {
        let warning = app.alerts["Some Instruments Unavailable"]
        if waitForKaraokeNotice(in: app) {
            warning.buttons["OK"].tap()
            _ = warning.waitForNonExistence(timeout: FestivalApp.budget(5))
        }
    }

    /// Expect the showing Karaoke notice to have the loaded chart behind it and no
    /// "Loading … path" spinner (issue #649).
    ///
    /// - Parameters:
    ///   - app: The running app, showing the notice.
    ///   - context: Which opening, for the failure message.
    @MainActor
    static func assertKaraokeNoticeFollowsLoadedChart(in app: XCUIApplication, _ context: String) {
        XCTAssertTrue(loadedChart(in: app).exists, "\(context): notice showed before the path loaded")
        XCTAssertFalse(spinner(in: app).exists, "\(context): notice covers the loading spinner")
    }

    /// A Paths form's spinner ("Loading image path" / "Loading text path").
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - form: `image` or `text` for that form's spinner, nil for either.
    /// - Returns: The first matching spinner.
    @MainActor
    static func spinner(in app: XCUIApplication, form: String? = nil) -> XCUIElement {
        let predicate = form.map { NSPredicate(format: "label == %@", "Loading \($0) path") }
            ?? NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Loading ", " path")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    // MARK: Fixture hold control (#430, #649)

    /// Call the fixture's `/__fixture__/hold-paths` control.
    ///
    /// - Parameters:
    ///   - origin: The fixture listener, e.g. `http://127.0.0.1:8765`.
    ///   - query: `seconds=<n>` (with `&form=image|data` to hold one form), or nil for the status.
    /// - Returns: Whether reads are held and how many wait, or nil without the control.
    static func pathHold(origin: String, _ query: String?) -> (held: Bool, waiting: Int)? {
        guard let url = URL(string: "\(origin)/__fixture__/hold-paths" + (query.map { "?\($0)" } ?? "")) else {
            return nil
        }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var body: [String: Any]?
        URLSession.shared.dataTask(with: url) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data {
                body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + 5) == .success,
              let held = body?["held"] as? Bool, let waiting = body?["waiting"] as? Int else { return nil }
        return (held, waiting)
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
