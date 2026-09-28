import XCTest

/// Shared entry point for every `XCUIApplication` launch in this test target.
///
/// Every journey file used to construct `XCUIApplication()` directly and hand-roll
/// its own `launchEnvironment` dictionary. More than one forgot
/// `FST_DEBUG_STILL_BACKGROUND=1`: `SongsUITestSupport.fixtureApp()` (shared by
/// `SongsJourneyTests`/`SongDetailJourneyTests`/`ShopJourneyTests`) and
/// `FestivalMobileUITests.fixtureApp()` never set it at all. XCUITest waits for
/// the app to go idle before every synthetic action; the shared artwork
/// background carousel (and, since 2026-09-28, any overflowing `MarqueeText`
/// row) never idles without this flag, so a forgotten flag silently turns
/// every step of a journey into a multi-second-or-worse wait, and a long
/// enough journey exhausts the shared simulator's lock-hold budget entirely
/// (`.agents/workflow/simulator-driver.md`'s "Simulator queue stall").
///
/// Routing every launch through ``makeApp(_:)``/``launch(_:)`` makes that flag
/// structurally impossible to forget again: `tools/tests/test_launch_helper.py`
/// fails the build if any file under this directory other than this one
/// constructs `XCUIApplication()`.
enum FestivalApp {
    /// Launch environment every journey gets unless it explicitly overrides a key.
    ///
    /// - `FST_DEBUG_STILL_BACKGROUND`: freezes the shared artwork background and
    ///   any scrolling `MarqueeText` row so XCUITest's app-idle wait can settle.
    ///   `tools/ios_sim.py drive` sets this by default too (`--animate` opts out);
    ///   `DriverTests` reads it back out of its own passed-through environment
    ///   rather than through this helper, so that opt-out keeps working.
    private static let defaultEnvironment: [String: String] = [
        "FST_DEBUG_STILL_BACKGROUND": "1",
    ]

    /// Build a configured, not-yet-launched app.
    ///
    /// - Parameter env: Environment entries beyond the shared defaults; a key
    ///   repeated here overrides that default (e.g. to explicitly re-enable
    ///   animation for a test that needs it).
    /// - Returns: An `XCUIApplication` with `launchEnvironment` populated,
    ///   `launch()` not yet called.
    @MainActor
    static func makeApp(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        for (key, value) in defaultEnvironment {
            app.launchEnvironment[key] = value
        }
        for (key, value) in env {
            app.launchEnvironment[key] = value
        }
        return app
    }

    /// Build and immediately launch an app.
    ///
    /// - Parameter env: Environment entries beyond the shared defaults.
    /// - Returns: The launched `XCUIApplication`.
    @MainActor
    @discardableResult
    static func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = makeApp(env)
        app.launch()
        return app
    }
}
