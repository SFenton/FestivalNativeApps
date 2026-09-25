import Foundation
import Testing
import SwiftUI
@testable import FestivalCore
@testable import FestivalUI

private struct PublicationFixture: HTTPTransport {
    let ready: Bool
    let status: Int

    /// Return a fixture publication without contacting any live service.
    ///
    /// - Parameter request: Local API request sent by the view.
    /// - Returns: A synthetic publication, or the requested error status.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.url?.path == "/api/publication" else {
            return HTTPResult(status: 404, data: Data())
        }
        let bytes = Data("""
        {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
        "readyForPinning":\(ready),"pinningEnabled":\(ready),"unreadySurfaces":[]}
        """.utf8)
        return HTTPResult(status: status, data: bytes)
    }
}

/// The last chart cannot disappear, while a hidden chart may always return.
@Test func settingsInstrumentMinimum() {
    #expect(!SettingsScreen.canToggleInstrument(activeCount: 1, currentlyShown: true))
    #expect(SettingsScreen.canToggleInstrument(activeCount: 2, currentlyShown: true))
    #expect(SettingsScreen.canToggleInstrument(activeCount: 0, currentlyShown: false))
}

/// Reset only native app preferences, leaving profile and tab state intact.
@MainActor
@Test func settingsResetDoesNotEraseProfileOrTabHistory() {
    let defaults = UserDefaults.standard
    let keys = [
        "fst.settings.showLead", "fst.settings.hideShop",
        "fst.accessibility.reduceMotion", "fst:selectedProfile", "fst:tabRoutes",
    ]
    let originals = keys.map { ($0, defaults.object(forKey: $0)) }
    defer {
        for (key, original) in originals {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
    defaults.set(false, forKey: "fst.settings.showLead")
    defaults.set(true, forKey: "fst.settings.hideShop")
    defaults.set(true, forKey: "fst.accessibility.reduceMotion")
    defaults.set("kept-profile", forKey: "fst:selectedProfile")
    defaults.set("kept-tabs", forKey: "fst:tabRoutes")

    let view = SettingsScreen(session: FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }
    ))
    view.resetAppSettings()

    #expect(defaults.bool(forKey: "fst.settings.showLead"))
    #expect(!defaults.bool(forKey: "fst.settings.hideShop"))
    #expect(!defaults.bool(forKey: "fst.accessibility.reduceMotion"))
    #expect(defaults.string(forKey: "fst:selectedProfile") == "kept-profile")
    #expect(defaults.string(forKey: "fst:tabRoutes") == "kept-tabs")
}

/// Debug fixtures can only use loopback; invalid or production scenarios fail loudly.
@Test func rootConfigurationRejectsInvalidFixtureOrigins() throws {
    _ = try FestivalRootView.makeClient(environment: [
        "FST_API_BASE_URL": "http://127.0.0.1:8765",
        "FST_FIXTURE_SCENARIO": "empty",
    ])
    #expect(throws: FestivalAPIError.invalidResource) {
        try FestivalRootView.makeClient(environment: [
            "FST_FIXTURE_SCENARIO": "unknown",
        ])
    }
    #expect(throws: FestivalAPIError.invalidResource) {
        try FestivalRootView.makeClient(environment: [
            "FST_API_BASE_URL": "https://festivalscoretracker.com",
            "FST_FIXTURE_SCENARIO": "error",
        ])
    }
}

#if os(macOS)
/// Render the entire macOS navigation shell at each reachable root selection.
@MainActor
@Test(arguments: FestivalSection.allCases)
func rootSidebarDestinationsRender(_ destination: FestivalSection) throws {
    let content = FestivalRootView(initialSection: destination) {
        try FestivalAPI(transport: PublicationFixture(ready: true, status: 200))
    }
    let renderer = ImageRenderer(content: content.frame(width: 800, height: 600))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    #expect(image.width == 800)
    #expect(image.height == 600)
}
#endif
