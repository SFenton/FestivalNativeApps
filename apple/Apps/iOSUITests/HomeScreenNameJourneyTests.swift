import XCTest

/// The Home Screen label under the app icon (issue #79).
///
/// `CFBundleDisplayName` in `apple/project.yml` is the short name "FST" for the iPhone
/// (also iPhone Duo) and iPad apps, matching the web app's manifest `short_name`; the full
/// "Festival Score Tracker" truncates under the icon. The macOS app keeps the full name.
///
/// The check reads the app element's own label, which the system derives from the installed
/// bundle's display name. Springboard icons carry no bundle identity, and the shared
/// simulators also hold the installed-PWA reference web clip (also "FST") and other jobs'
/// copies of the app, so a Springboard lookup cannot tell this build's icon apart (and on
/// iPhone Duo it does not reliably list icons right after leaving the app).
///
/// Run with `python3 tools/ios_sim.py uitest --only HomeScreenNameJourneyTests`
/// (add `--device ipad` for the iPad app, `--device duo` for iPhone Duo).
final class HomeScreenNameJourneyTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The installed app's Home Screen name is "FST", never the full, truncating name.
    @MainActor
    func testHomeScreenLabelIsShortName() throws {
        let app = FestivalApp.launch([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertEqual(app.label, "FST", "the app's Home Screen name")
    }
}
