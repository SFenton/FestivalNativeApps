#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixture session
//
// `SettingsScreen`'s only reads (Service Info, Service Version) fail instantly on this
// throwing session, so every state here is driven purely by the
// `@AppStorage` values seeded into a private `UserDefaults` suite passed as
// `.defaultAppStorage`, matching `SettingsPersistenceTests.swift`'s own
// direct-`UserDefaults` approach for the same registry.

@MainActor
private func settingsSession(selected: Bool) -> FestivalSession {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    guard selected else { return session }
    let suite = "fst.tests.settings-session.\(UUID().uuidString)"
    let storage = UserDefaults(suiteName: suite)!
    let identity: [String: String] = ["accountId": "fixture-player-1", "displayName": "Fixture Player 1"]
    storage.set(try! JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    return FestivalSession(factory: { throw FestivalAPIError.invalidResource }, selectionStorage: storage)
}

@MainActor
private func settingsImage(
    session: FestivalSession, storage: UserDefaults, size: CGSize = CGSize(width: 402, height: 2200)
) throws -> CGImage {
    let host = nativeHostedView(
        NavigationStack { SettingsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    return try nativeHostedImage(host)
}

@MainActor
private func freshSuite() -> UserDefaults {
    let name = "fst.tests.settings.\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
}

// MARK: - Default states

@MainActor
@Test func settingsScreenRendersAnonymousDefaults() throws {
    let storage = freshSuite()
    let image = try settingsImage(session: settingsSession(selected: false), storage: storage)
    _ = try nativeHostedPNG(image, filename: "settings-anonymous.png", environment: "FST_SETTINGS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func settingsScreenRendersWithSelectedPlayerEnablesMetadataHints() throws {
    let storage = freshSuite()
    let image = try settingsImage(session: settingsSession(selected: true), storage: storage)
    _ = try nativeHostedPNG(image, filename: "settings-selected-player.png", environment: "FST_SETTINGS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - Expanded App Settings (leeway slider, visual order summary)

@MainActor
@Test func settingsScreenExpandsLeewaySliderAndVisualOrderRow() throws {
    let storage = freshSuite()
    storage.set(true, forKey: "fst.settings.filterInvalidScores")
    storage.set(true, forKey: "fst.settings.enableVisualOrder")
    storage.set(2.5, forKey: "fst.settings.leeway")
    let image = try settingsImage(session: settingsSession(selected: false), storage: storage)
    _ = try nativeHostedPNG(image, filename: "settings-expanded-app-settings.png", environment: "FST_SETTINGS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - Item Shop hidden disables highlight toggle

@MainActor
@Test func settingsScreenHidingShopDisablesHighlightToggle() throws {
    let storage = freshSuite()
    storage.set(true, forKey: "fst.settings.hideShop")
    let image = try settingsImage(session: settingsSession(selected: false), storage: storage)
    _ = try nativeHostedPNG(image, filename: "settings-shop-hidden.png", environment: "FST_SETTINGS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - Single visible instrument disables its own toggle

@MainActor
@Test func settingsScreenWithOneVisibleInstrumentDisablesItsToggle() throws {
    let storage = freshSuite()
    for key in [
        "fst.settings.showBass", "fst.settings.showDrums", "fst.settings.showVocals",
        "fst.settings.showProLead", "fst.settings.showProBass", "fst.settings.showKaraoke",
        "fst.settings.showProCymbals", "fst.settings.showProDrums",
    ] {
        storage.set(false, forKey: key)
    }
    let image = try settingsImage(session: settingsSession(selected: false), storage: storage)
    _ = try nativeHostedPNG(image, filename: "settings-one-instrument.png", environment: "FST_SETTINGS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - Accessibility overrides

@MainActor
@Test func settingsScreenRendersAccessibilityOverridesEnabled() throws {
    let storage = freshSuite()
    for key in [
        "fst.accessibility.reduceMotion", "fst.accessibility.disableAnimatedArtwork",
        "fst.accessibility.moreContrast", "fst.accessibility.lessTransparency",
    ] {
        storage.set(true, forKey: key)
    }
    let image = try settingsImage(session: settingsSession(selected: false), storage: storage)
    _ = try nativeHostedPNG(image, filename: "settings-accessibility-on.png", environment: "FST_SETTINGS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - Inline reorder lists (operator batch 6, item 6.11)

@MainActor
@Test func settingsExpandedAppSettingsShowInlineReorderListsWithoutPublicationCheck() async throws {
    let storage = freshSuite()
    storage.set(true, forKey: "fst.settings.enableVisualOrder")
    storage.set(true, forKey: "fst.settings.filterInvalidScores")
    let size = CGSize(width: 402, height: 2600)
    let host = nativeHostedView(
        NavigationStack { SettingsScreen(session: settingsSession(selected: true)) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = [
        "Enable Independent Song Row Visual Order", "Song Row Visual Order", "Song Intensity",
        "CHOpt Text Path Column Order", "OD", "Maximum Score Leeway: +1.0%", "Difficulty",
        "View Licenses",
        "Display instrument icons on each song row showing which parts have leaderboard scores or FCs.",
    ]
    let image = try await nativeHostedSettle(host, untilText: expected)
    _ = try nativeHostedPNG(image, filename: "settings-inline-reorder.png", environment: "FST_SETTINGS_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: expected,
        notContaining: ["Check Publication", "Game Difficulty", "Song Row Order", "Star: full combo"]
    )
}

/// In the list/detail Settings, turning Independent Visual Order off while Song Row
/// Visual Order is open on the right closes it to the placeholder (`split-panes` R6,
/// issue #372); the chevron row leaves the list.
@MainActor
@Test func settingsListClosesSongRowOrderWhenItsSwitchTurnsOff() async throws {
    let storage = freshSuite()
    storage.set(true, forKey: "fst.settings.enableVisualOrder")
    final class Recorder { var closed = 0 }
    let recorder = Recorder()
    let select = ListDetailSelectAction(section: .settings, page: .settings, close: { recorder.closed += 1 }) { _ in }
    let size = CGSize(width: 420, height: 1600)
    let host = nativeHostedView(
        NavigationStack { SettingsScreen(session: settingsSession(selected: false)) }
            .environment(\.listDetailSelect, select)
            .environment(\.listDetailSelection, .settingsTopic(.songRowOrder))
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let rowID = SettingsTopic.songRowOrder.accessibilityIdentifier
    _ = try await nativeHostedSettle(host) { nativeHostedAccessibility(host).identifiers.contains(rowID) }
    #expect(recorder.closed == 0)
    storage.set(false, forKey: "fst.settings.enableVisualOrder")
    _ = try await nativeHostedSettle(host) { recorder.closed > 0 }
    #expect(recorder.closed == 1)
    _ = try await nativeHostedSettle(host) { !nativeHostedAccessibility(host).identifiers.contains(rowID) }
    #expect(!nativeHostedAccessibility(host).identifiers.contains(rowID))
}

@MainActor
@Test func settingsReorderListRendersRowsAndMovesByAccessibilityAction() async throws {
    var order = PathColumnKey.allCases
    let size = CGSize(width: 402, height: 400)
    let host = nativeHostedView(
        SettingsReorderList(
            items: order, identifier: "fst.settings.path-column-order",
            label: \.label, key: \.rawValue
        ) { order = $0 }
        .padding(16)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(BrandTokens.cardBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["Note", "Beat", "Time", "OD", "Score"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    _ = try nativeHostedPNG(image, filename: "settings-reorder-list.png", environment: "FST_SETTINGS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: expected)
    #expect(order == PathColumnKey.allCases, "Rendering must not reorder")
}

// MARK: - SettingsServiceSummary (pure logic, exercised via the Service section's message builder)

@MainActor
@Test func settingsServiceSummaryDescribesEveryPublicationOutcome() {
    func payload(publicationId: Int?, isStale: Bool) -> CatalogPayload {
        CatalogPayload(
            catalog: SongsResponse(count: 0, currentSeason: nil, songs: []),
            publicationId: publicationId, observedPublicationId: 7, isStale: isStale
        )
    }
    #expect(SettingsServiceSummary.message(for: payload(publicationId: 7, isStale: false)) == "Publication 7")
    #expect(
        SettingsServiceSummary.message(for: payload(publicationId: nil, isStale: false))
            == "Publication 7; songs live (publication unverified)"
    )
    #expect(
        SettingsServiceSummary.message(for: payload(publicationId: 7, isStale: true))
            == "Publication 7; songs offline - showing verified cached data"
    )
    #expect(
        SettingsServiceSummary.message(for: payload(publicationId: nil, isStale: true))
            == "Publication 7; songs offline - last seen (publication unverified)"
    )
}
// MARK: - Fixture-only publication check and What's New pull-down (batch 6)

@Test func fixtureToolsOnlyRenderForLoopbackOriginsInDebug() {
    #expect(SettingsFixtureTools.isEnabled(environment: ["FST_API_BASE_URL": "http://127.0.0.1:8765"]))
    #expect(SettingsFixtureTools.isEnabled(environment: ["FST_API_BASE_URL": "http://localhost:8765"]))
    #expect(!SettingsFixtureTools.isEnabled(environment: [:]))
    #expect(!SettingsFixtureTools.isEnabled(
        environment: ["FST_API_BASE_URL": "https://festivalscoretracker.com"]
    ))
}

@Test func whatsNewPullDownDismissesOnlyPastThreshold() {
    #expect(!PullDownToDismiss.shouldDismiss(pull: 0))
    #expect(!PullDownToDismiss.shouldDismiss(pull: PullDownToDismiss.threshold - 1))
    #expect(PullDownToDismiss.shouldDismiss(pull: PullDownToDismiss.threshold))
}

#endif
