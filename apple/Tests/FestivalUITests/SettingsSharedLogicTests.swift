import Foundation
import Testing
import FestivalCore
@testable import FestivalUI

// MARK: - Settings copy

/// The Settings strings and state mappings the SwiftUI page and the UIKit port both read.
@Test func metadataSubtitleFollowsPlayerAndIcons() {
    #expect(SettingsCopy.metadataSubtitle(hasPlayer: false, showInstrumentIcons: true)
        == "Select a player to customize score metadata.")
    #expect(SettingsCopy.metadataSubtitle(hasPlayer: true, showInstrumentIcons: true).hasPrefix("With icons and All instruments"))
    #expect(SettingsCopy.metadataSubtitle(hasPlayer: true, showInstrumentIcons: false).hasPrefix("Visible score fields"))
}

@Test func metadataHintsMatchTheSelectedPlayer() {
    #expect(SettingsCopy.metadataHint(for: .intensity, hasPlayer: false).hasPrefix("Controls song Intensity"))
    #expect(SettingsCopy.metadataHint(for: .lastPlayed, hasPlayer: false) == "Select a player to show the saved date")
    #expect(SettingsCopy.metadataHint(for: .score, hasPlayer: true).hasPrefix("Updates Songs score fields"))
    #expect(SettingsCopy.metadataSwitchDisabled(.score, hasPlayer: false))
    #expect(!SettingsCopy.metadataSwitchDisabled(.intensity, hasPlayer: false))
}

@Test func lastVisibleInstrumentStaysOn() {
    #expect(SettingsCopy.instrumentSwitchDisabled(isShown: true, visibleCount: 1))
    #expect(!SettingsCopy.instrumentSwitchDisabled(isShown: false, visibleCount: 1))
    #expect(!SettingsCopy.instrumentSwitchDisabled(isShown: true, visibleCount: 2))
}

@Test func serviceVersionTextShowsLoadingThenResult() {
    #expect(SettingsCopy.serviceVersionText(version: nil, failed: false) == "Loading")
    #expect(SettingsCopy.serviceVersionText(version: nil, failed: true) == "Unavailable")
    #expect(SettingsCopy.serviceVersionText(version: "2610.01.01", failed: true) == "2610.01.01")
}

@Test func resetAllRestoresEveryRegisteredDefault() throws {
    let suite = "fst.test.settings-reset"
    let store = try #require(UserDefaults(suiteName: suite))
    defer { store.removePersistentDomain(forName: suite) }
    for (key, value) in SettingsRegistry.defaults {
        switch value {
        case .bool(let flag): store.set(!flag, forKey: key)
        case .double(let number): store.set(number + 2, forKey: key)
        case .string: store.set("changed", forKey: key)
        case .data: store.set(Data([1]), forKey: key)
        }
    }
    SettingsRegistry.resetAll(in: store)
    for (key, value) in SettingsRegistry.defaults {
        #expect(SettingsRegistry.value(for: key, in: store) == value, "\(key)")
    }
}

// MARK: - First run policy

@Test func routesNameTheirFirstRunPage() {
    #expect(AppRoute.leaderboards.firstRunPage == .leaderboards)
    #expect(AppRoute.shop.firstRunPage == .shop)
    #expect(AppRoute.licenses.firstRunPage == nil)
}

@Test func firstRunGateContextFollowsShopSettings() {
    let on = FirstRunPresentationPolicy.gateContext(
        hasPlayer: true, hideShop: false, disableShopHighlighting: false, experimentalRanks: true, alwaysShow: false
    )
    #expect(on.shopHighlightEnabled && on.experimentalRanksEnabled && on.hasPlayer && on.ready)
    let hidden = FirstRunPresentationPolicy.gateContext(
        hasPlayer: false, hideShop: true, disableShopHighlighting: false, experimentalRanks: false, alwaysShow: true
    )
    #expect(!hidden.shopHighlightEnabled && hidden.alwaysShow)
}

@Test func firstRunShowsNothingWhenDebugModeIsOff() {
    let context = FirstRunPresentationPolicy.gateContext(
        hasPlayer: true, hideShop: false, disableShopHighlighting: false, experimentalRanks: true, alwaysShow: false
    )
    let seen = FirstRunSeenStorage()
    #expect(FirstRunPresentationPolicy.slides(for: .songs, debugMode: .off, context: context, seen: seen).isEmpty)
    #expect(!FirstRunPresentationPolicy.slides(for: .songs, debugMode: .normal, context: context, seen: seen).isEmpty)
}

// MARK: - Notification flag colours

@Test func flagChipHexMatchesTheWebFlagColors() {
    #expect(NotificationFlagChip.hex(.improvement) == 0x4B5563)
    #expect(NotificationFlagChip.hex(.progress) == 0x4338CA)
    #expect(Set(NotificationFlagKind.allCases.map(NotificationFlagChip.hex)).count == NotificationFlagKind.allCases.count)
}
