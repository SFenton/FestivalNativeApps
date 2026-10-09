import XCTest

/// Shared steps for the Report an Issue / Request a Feature journeys
/// (`FeedbackMediaJourneyTests`, `FeedbackSentJourneyTests`).
@MainActor
enum FeedbackJourney {
    /// The fixture app on the Settings tab.
    ///
    /// - Parameters:
    ///   - origin: Loopback fixture service.
    ///   - extra: More launch environment.
    /// - Returns: The configured, not-yet-launched app.
    static func fixtureApp(origin: String, _ extra: [String: String] = [:]) -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "settings",
        ].merging(extra) { _, new in new })
    }

    /// Whether the fixture service answers its features read.
    ///
    /// - Parameter origin: Loopback fixture service.
    /// - Returns: True when `GET /api/features` answers 200 within 5 s.
    static func fixtureReachable(origin: String) -> Bool {
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var reachable = false
        URLSession.shared.dataTask(with: URL(string: "\(origin)/api/features")!) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return reachable
    }

    /// The Settings row that opens a form.
    ///
    /// - Parameters:
    ///   - kind: `bug` (Report an Issue) or `feature` (Request a Feature).
    ///   - app: The app on Settings.
    static func row(_ kind: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["fst.settings.feedback.\(kind)"]
    }

    /// Scroll Settings to a feedback row and open its form.
    ///
    /// - Parameters:
    ///   - kind: `bug` or `feature`.
    ///   - app: The fixture app on Settings.
    static func openForm(_ kind: String = "bug", in app: XCUIApplication) {
        let row = row(kind, in: app)
        XCTAssertTrue(scrollTo(row, in: app), "The \(kind) feedback row is missing from Settings")
        row.tap()
        XCTAssertTrue(app.textFields["fst.settings.feedback.field.title"].waitForExistence(timeout: FestivalApp.budget(10)),
                      "The \(kind) feedback form did not open")
    }

    /// Cancel the form, confirm the discard when asked, and require it closed.
    ///
    /// - Parameter app: The app with the form open.
    static func cancelAndDiscard(in app: XCUIApplication) {
        let close = app.buttons["fst.settings.feedback.close"]
        XCTAssertTrue(close.waitForExistence(timeout: FestivalApp.budget(5)))
        close.tap()
        let discard = app.buttons["fst.settings.feedback.discard.confirm"]
        if discard.waitForExistence(timeout: FestivalApp.budget(5)) { discard.firstMatch.tap() }
        XCTAssertTrue(waitUntil { !app.textFields["fst.settings.feedback.field.title"].exists },
                      "Cancel did not close the form")
    }

    /// Swipe up on the app's window until the element is hittable. Never `app.swipeUp()`:
    /// in Split View the app element spans the screen, and its centre is the divider.
    ///
    /// - Returns: Whether it became hittable within 15 swipes.
    static func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        _ = element.waitForExistence(timeout: FestivalApp.budget(15))
        let page = app.windows.firstMatch
        var attempts = 0
        while !(element.exists && element.isHittable) && attempts < 12 {
            page.swipeUp()
            attempts += 1
        }
        // A compact window's tab bar covers the bottom of the page: bring the row above it.
        while element.exists && element.frame.maxY > page.frame.maxY - 140 && attempts < 15 {
            page.swipeUp()
            attempts += 1
        }
        return element.exists && element.isHittable
    }

    /// Poll a condition for up to `timeout` seconds (default: a VM-scaled 10 s).
    static func waitUntil(timeout: TimeInterval? = nil, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout ?? FestivalApp.budget(10))
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }
}
