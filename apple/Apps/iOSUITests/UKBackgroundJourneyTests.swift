import XCTest

/// The shared artwork background of the UIKit port (`UIKitPort/Background`).
///
/// The UIKit app hosts one backdrop at the window root and, under
/// `FST_DEBUG_BACKGROUND_PROBE=1` (Debug builds), publishes its state through one
/// accessibility element, `fst.debug.backgroundProbe`: `mode`, the song `cover`, the active
/// `slot`, the carousel's current `raw` cover, whether it is `moving`, `plays` (how often the
/// carousel loader was started) and `views` (how often the backdrop view was built). The
/// SwiftUI app has no probe, so every test here skips there.
///
/// Run with `python3 tools/ios_sim.py uitest --app uikit --only UKBackgroundJourneyTests`
/// (and without `--app` to see the skips on the SwiftUI app).
final class UKBackgroundJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    @MainActor
    private func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_BACKGROUND_PROBE": "1",
        ]
        environment.merge(env) { $1 }
        return FestivalApp.launch(environment)
    }

    @MainActor
    private func probe(in app: XCUIApplication) throws -> XCUIElement {
        let element = app.descendants(matching: .any)["fst.debug.backgroundProbe"]
        try XCTSkipUnless(
            element.waitForExistence(timeout: 20),
            "This app has no background probe (the SwiftUI app draws one backdrop per page)."
        )
        return element
    }

    /// The probe's `key=value;…` value as a dictionary.
    @MainActor
    private func state(_ probe: XCUIElement) -> [String: String] {
        let value = (probe.value as? String) ?? ""
        return Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        })
    }

    /// Waits until two reads half a second apart agree, so launch-time restarts (network path,
    /// catalogue arrival) are over before the test compares anything.
    @MainActor
    private func settled(_ probe: XCUIElement) -> [String: String] {
        var previous = state(probe)
        let deadline = Date().addingTimeInterval(FestivalApp.budget(15))
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 1)
            let next = state(probe)
            if next == previous, next["raw"] != nil, next["raw"] != "none" { return next }
            previous = next
        }
        return previous
    }

    // MARK: - Journeys

    /// The backdrop is decorative: no accessibility element covers the screen behind the pages.
    @MainActor
    func testBackgroundIsHiddenFromAccessibility() throws {
        let app = launch()
        let probe = try probe(in: app)
        _ = settled(probe)
        let screen = app.windows.firstMatch.frame
        let covering = try FestivalApp.snapshotNodes(in: app) { node in
            node.identifier != "fst.debug.backgroundProbe"
                && node.elementType == .image
                && node.frame.width >= screen.width * 0.9 && node.frame.height >= screen.height * 0.9
        }
        XCTAssertTrue(covering.isEmpty, "the artwork backdrop must not be an accessibility element")
        XCTAssertEqual(state(probe)["mode"], "carousel")
    }

    /// Switching tabs and back neither rebuilds the backdrop nor restarts the carousel.
    @MainActor
    func testBackgroundStaysPutAcrossTabSwitch() throws {
        let app = launch()
        let probe = try probe(in: app)
        let before = settled(probe)
        let settings = app.descendants(matching: .any).matching(identifier: "fst.nav.settings").firstMatch
        let songs = app.descendants(matching: .any).matching(identifier: "fst.nav.songs").firstMatch
        try XCTSkipUnless(settings.waitForExistence(timeout: 10) && songs.exists, "no tab bar in this layout")
        settings.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let away = state(probe)
        songs.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let back = state(probe)
        for key in ["plays", "views", "slot", "raw"] {
            XCTAssertEqual(away[key], before[key], "\(key) changed when leaving the tab")
            XCTAssertEqual(back[key], before[key], "\(key) changed when returning to the tab")
        }
        XCTAssertEqual(back["mode"], "carousel")
    }

    /// A song cover fades in over the carousel and back out, driven by the shared coordinator
    /// (`FST_DEBUG_BACKGROUND_CYCLE` alternates the two), with the carousel's loader untouched.
    @MainActor
    func testSongCoverTransitionLeavesTheCarouselRunning() throws {
        let app = launch(["FST_DEBUG_BACKGROUND_CYCLE": "3"])
        let probe = try probe(in: app)
        let deadline = Date().addingTimeInterval(FestivalApp.budget(20))
        var sawSong = false
        var playsAtSong = ""
        while Date() < deadline, !sawSong {
            let current = state(probe)
            if current["mode"] == "song" {
                sawSong = true
                playsAtSong = current["plays"] ?? ""
            } else {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        XCTAssertTrue(sawSong, "the backdrop never took a song cover")
        var sawCarousel = false
        while Date() < deadline, !sawCarousel {
            if state(probe)["mode"] == "carousel" { sawCarousel = true } else {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        XCTAssertTrue(sawCarousel, "the backdrop never returned to the carousel")
        // A cover pauses the carousel (its policy turns invisible), so plays may advance by
        // the pause and resume only; it must not run away.
        let finalPlays = Int(state(probe)["plays"] ?? "") ?? 0
        XCTAssertLessThanOrEqual(finalPlays - (Int(playsAtSong) ?? 0), 3)
    }
}
