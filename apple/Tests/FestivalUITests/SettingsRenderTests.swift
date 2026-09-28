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
// `SettingsScreen` never issues a network read on appear (only an explicit
// "Check Publication" tap does), so every state here is driven purely by the
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

// MARK: - Diagnostics (DEBUG-only section)

@MainActor
@Test func settingsScreenDiagnosticsToggleEnablesTelemetryRow() throws {
    let storage = freshSuite()
    storage.set(true, forKey: "fst.settings.tapDiagnostics")
    let image = try settingsImage(session: settingsSession(selected: false), storage: storage)
    _ = try nativeHostedPNG(image, filename: "settings-diagnostics-on.png", environment: "FST_SETTINGS_RENDER_OUT")
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

// MARK: - SettingsReorderSheet

@MainActor
@Test func settingsReorderSheetRendersMetadataFieldOrder() throws {
    let items = Binding<[MetadataField]>(
        get: { MetadataField.allCases }, set: { _ in }
    )
    let host = nativeHostedView(
        SettingsReorderSheet(
            title: "Song Row Order", subtitle: "Sets the order visible fields appear.",
            items: items, label: \.label
        )
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "settings-reorder-metadata.png", environment: "FST_SETTINGS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func settingsReorderSheetRendersPathColumnOrder() throws {
    let items = Binding<[PathColumnKey]>(
        get: { PathColumnKey.allCases }, set: { _ in }
    )
    let host = nativeHostedView(
        SettingsReorderSheet(
            title: "Path Column Order", subtitle: "Sets the CHOpt Paths column order.",
            items: items, label: \.label
        )
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "settings-reorder-path.png", environment: "FST_SETTINGS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
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
#endif
