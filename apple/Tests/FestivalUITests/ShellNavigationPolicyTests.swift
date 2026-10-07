import Foundation
import Testing
import FestivalCore
@testable import FestivalUI

// MARK: - Tab policy

/// Anonymous phones show the web's three-tab bar.
@Test func anonymousPhoneTabs() {
    #expect(FestivalTabPolicy.sections(profile: .none, regularWidth: false)
        == [.songs, .leaderboards, .settings])
}

/// A selected player on a phone gets Suggestions, Compete and Statistics.
@Test func playerPhoneTabs() {
    #expect(FestivalTabPolicy.sections(profile: .player, regularWidth: false)
        == [.songs, .suggestions, .compete, .statistics, .settings])
}

/// Wide layouts split Compete into Leaderboards and Rivals (web ≥ 600 px).
@Test func playerWideSections() {
    #expect(FestivalTabPolicy.sections(profile: .player, regularWidth: true)
        == [.songs, .suggestions, .leaderboards, .rivals, .statistics, .settings])
}

/// Bands get Suggestions and Statistics but keep Leaderboards (no Compete/Rivals).
@Test(arguments: [false, true])
func bandSections(regularWidth: Bool) {
    #expect(FestivalTabPolicy.sections(profile: .band, regularWidth: regularWidth)
        == [.songs, .suggestions, .leaderboards, .statistics, .settings])
}

/// Compete and Leaderboards share a slot; other hidden tabs fall back to the nearest
/// visible tab before them.
@Test func resolveKeepsEquivalentSlot() {
    let anonymous = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let player = FestivalTabPolicy.sections(profile: .player, regularWidth: false)
    #expect(FestivalTabPolicy.resolve(.compete, in: anonymous) == .leaderboards)
    #expect(FestivalTabPolicy.resolve(.leaderboards, in: player) == .compete)
    #expect(FestivalTabPolicy.resolve(.rivals, in: player) == .compete)
    #expect(FestivalTabPolicy.resolve(.statistics, in: anonymous) == .leaderboards)
    #expect(FestivalTabPolicy.resolve(.suggestions, in: anonymous) == .songs)
    #expect(FestivalTabPolicy.resolve(.settings, in: anonymous) == .settings)
    #expect(FestivalTabPolicy.resolve(.rivals, in: anonymous) == .leaderboards)
    #expect(FestivalTabPolicy.resolve(.songs, in: [.settings]) == .settings)
}

// MARK: - Selection never navigates away (operator, 2026-09-28)

/// Selecting or deselecting a profile keeps the active tab and every path when the
/// active tab stays visible (Songs and Settings exist for every profile).
@Test(arguments: [FestivalSection.songs, .settings])
func selectionKeepsVisibleTabAndPaths(selected: FestivalSection) {
    let paths: [FestivalSection: [AppRoute]] = [
        selected: [.shop, .licenses], .statistics: [.bands], .compete: [.rivals],
    ]
    // Selecting (→ player) and deselecting (→ none) both keep everything.
    for profile in [FestivalProfileKind.player, .none] {
        let visible = FestivalTabPolicy.sections(profile: profile, regularWidth: false)
        let adapted = FestivalTabPolicy.adapt(selected: selected, paths: paths, to: visible)
        #expect(adapted.selected == selected)
        #expect(adapted.paths == paths)
    }
}

/// Selecting a player from Leaderboards › Player swaps the tab to Compete (same slot)
/// and carries the path, so the user stays on that player's page.
@Test func selectingFromLeaderboardsPlayerStaysOnThePage() {
    let player = AppRoute.player(accountId: "fixture-1", displayName: "Fixture")
    let paths: [FestivalSection: [AppRoute]] = [.leaderboards: [.leaderboards, player]]
    let visible = FestivalTabPolicy.sections(profile: .player, regularWidth: false)
    let adapted = FestivalTabPolicy.adapt(selected: .leaderboards, paths: paths, to: visible)
    #expect(adapted.selected == .compete)
    #expect(adapted.paths[.compete] == [.leaderboards, player])
    #expect(adapted.paths[.leaderboards] == [])

    // Deselecting there swaps back, still on the same page.
    let anonymous = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let back = FestivalTabPolicy.adapt(selected: .compete, paths: adapted.paths, to: anonymous)
    #expect(back.selected == .leaderboards)
    #expect(back.paths[.leaderboards] == [.leaderboards, player])
}

/// An iPad window crossing size classes on Compete keeps the nested page too (the Duo
/// keeps one phone set since #337).
@Test func sectionSetWidthChangeCarriesComparablePath() {
    let rival = AppRoute.rivalDetail(rivalId: "r1", name: nil, scope: nil)
    let wide = FestivalTabPolicy.sections(profile: .player, regularWidth: true)
    let unfolded = FestivalTabPolicy.adapt(selected: .compete, paths: [.compete: [rival]], to: wide)
    #expect(unfolded.selected == .leaderboards)
    #expect(unfolded.paths[.leaderboards] == [rival])
    let compact = FestivalTabPolicy.sections(profile: .player, regularWidth: false)
    let folded = FestivalTabPolicy.adapt(selected: .rivals, paths: [.rivals: [rival]], to: compact)
    #expect(folded.selected == .compete)
    #expect(folded.paths[.compete] == [rival])
}

/// Only when the active tab disappears (deselect on Statistics) does the selection move,
/// and even then no path is discarded.
@Test func disappearingTabMovesToNearestWithoutDroppingPaths() {
    let paths: [FestivalSection: [AppRoute]] = [.statistics: [.bands], .songs: [.shop]]
    let anonymous = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let adapted = FestivalTabPolicy.adapt(selected: .statistics, paths: paths, to: anonymous)
    #expect(adapted.selected == .leaderboards)
    #expect(adapted.paths == paths)
    let fromSuggestions = FestivalTabPolicy.adapt(selected: .suggestions, paths: paths, to: anonymous)
    #expect(fromSuggestions.selected == .songs)
    #expect(fromSuggestions.paths[.songs] == [.shop])
}

/// Only Statistics forgets its nested route when left.
@Test func onlyStatisticsResetsOnLeave() {
    for section in FestivalSection.allCases {
        #expect(FestivalTabPolicy.resetsPathOnLeave(section) == (section == .statistics))
    }
}

// MARK: - Drawer menu

/// Anonymous drawer mirrors the web sidebar: Songs, Leaderboards, Item Shop (no Bands,
/// no Licenses); tab destinations switch tabs, Item Shop pushes.
@Test func anonymousDrawerBrowse() {
    let visible = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let items = DrawerMenu.browse(profile: .none, visibleSections: visible, hideShop: false)
    #expect(items.map(\.id) == ["songs", "leaderboards", "shop"])
    #expect(items.map(\.intent) == [.select(.songs), .select(.leaderboards), .push(.shop)])
}

/// Player drawer adds Suggestions, Statistics and Rivals in web order; Leaderboards and
/// Rivals are not tabs on a compact iPhone (Compete is), so they push.
@Test func playerDrawerBrowse() {
    let visible = FestivalTabPolicy.sections(profile: .player, regularWidth: false)
    let items = DrawerMenu.browse(profile: .player, visibleSections: visible, hideShop: false)
    #expect(items.map(\.id) == ["songs", "suggestions", "statistics", "rivals", "leaderboards", "shop"])
    #expect(items[3].intent == .push(.rivals))
    #expect(items[4].intent == .push(.leaderboards))
    #expect(items[1].intent == .select(.suggestions))
}

/// The highlight names the section root on screen, or the pushed page a row opens.
@Test func drawerHighlightsCurrentDestination() {
    let visible = FestivalTabPolicy.sections(profile: .player, regularWidth: false)
    let items = DrawerMenu.browse(profile: .player, visibleSections: visible, hideShop: false)
    let songs = items[0]
    let leaderboards = items[4]
    #expect(DrawerMenu.isCurrent(songs, selected: .songs, topRoute: nil))
    #expect(!DrawerMenu.isCurrent(songs, selected: .songs, topRoute: .shop))
    #expect(DrawerMenu.isCurrent(leaderboards, selected: .compete, topRoute: .leaderboards))
    #expect(!DrawerMenu.isCurrent(leaderboards, selected: .compete, topRoute: nil))
}

/// Settings › Hide Item Shop removes the drawer entry.
@Test func hiddenShopLeavesDrawer() {
    let items = DrawerMenu.browse(profile: .none, visibleSections: [.songs], hideShop: true)
    #expect(!items.contains { $0.id == "shop" })
}

/// Settings is pinned at the bottom and switches tabs; Licenses lives in Settings.
@Test func drawerMoreIntents() {
    #expect(DrawerMenu.more.map(\.intent) == [.select(.settings)])
}

/// The player row draws only the name; VoiceOver still names it the selected player.
@Test func selectedPlayerRowAccessibilityLabel() {
    #expect(DrawerMenu.selectedPlayerAccessibilityLabel("Fixture Player") == "Fixture Player, Selected Player")
}

// MARK: - Avatar and debug routing

/// Monograms skip punctuation and upper-case the first letter or digit.
@Test func avatarInitials() {
    #expect(ProfileAvatar.initial(for: "debug-player") == "D")
    #expect(ProfileAvatar.initial(for: "_9lives") == "9")
    #expect(ProfileAvatar.initial(for: "--") == "?")
}

#if DEBUG
/// Every section is reachable from `FST_DEBUG_TAB`, plus the shell extras.
@Test func debugLaunchRouteParsesShellExtras() {
    for section in FestivalSection.allCases {
        #expect(DebugLaunchRoute(environment: ["FST_DEBUG_TAB": section.rawValue]).section == section)
        #expect(!DebugLaunchRoute(environment: ["FST_DEBUG_TAB": section.rawValue]).opensSearch)
    }
    // The Search tab is not a section (iPhone Duo audits open it this way, Lane A11Y4).
    let search = DebugLaunchRoute(environment: ["FST_DEBUG_TAB": "search"])
    #expect(search.opensSearch)
    #expect(search.section == nil)
    let debug = DebugLaunchRoute(environment: [
        "FST_DEBUG_DRAWER": "1", "FST_DEBUG_SHEET": "profile",
        "FST_DEBUG_PROFILE": "f1c7fea37bf9b1069250832ae4211461:Some Name",
        "FST_DEBUG_ANONYMOUS": "1",
    ])
    #expect(debug.opensDrawer)
    #expect(debug.opensProfileSheet)
    #expect(debug.anonymous)
    #expect(debug.profile?.accountId == "f1c7fea37bf9b1069250832ae4211461")
    #expect(debug.profile?.displayName == "Some Name")
}

/// `FST_DEBUG_PROFILE` selects a validated identity in memory only: building it, and
/// handing it to a session, must never write to any `UserDefaults` domain — the bug
/// this fixed let one lane's debug launch clobber another lane's real persisted
/// selection on the shared simulator.
@MainActor
@Test func debugProfileSelectsInMemoryWithoutTouchingUserDefaults() throws {
    let suiteName = "fst-debug-profile-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    let debug = DebugLaunchRoute(environment: [
        "FST_DEBUG_PROFILE": "f1c7fea37bf9b1069250832ae4211461:Some Name",
    ])
    let identity = try #require(debug.debugSelectedPlayer())
    #expect(identity.accountId == "f1c7fea37bf9b1069250832ae4211461")
    #expect(identity.displayName == "Some Name")
    #expect(storage.data(forKey: SelectedPlayerIdentity.storageKey) == nil)

    let session = FestivalSession(
        factory: { throw FestivalAPIError.invalidResource },
        selectionStorage: storage, debugSelectedPlayer: identity
    )
    #expect(session.selectedPlayer == identity)
    // Seeding the in-memory selection must not have persisted it either.
    #expect(storage.data(forKey: SelectedPlayerIdentity.storageKey) == nil)

    #expect(DebugLaunchRoute(environment: [:]).debugSelectedPlayer() == nil)
    let malformed = DebugLaunchRoute(environment: ["FST_DEBUG_PROFILE": "not-two-parts"])
    #expect(malformed.debugSelectedPlayer() == nil)
}
#endif

// MARK: - Profile-only routes

/// Without a player, Rivals/Statistics/Suggestions/Compete routes (and anything above
/// them) are dropped; with one, paths are untouched.
@Test func profileOnlyRoutesDropWithoutPlayer() {
    let path: [AppRoute] = [.shop, .rivals, .player(accountId: "a", displayName: nil)]
    #expect(ProfileRoutePolicy.resolve(path, hasPlayer: false) == [.shop])
    #expect(ProfileRoutePolicy.resolve(path, hasPlayer: true) == path)
    #expect(ProfileRoutePolicy.resolve([.leaderboards], hasPlayer: false) == [.leaderboards])
    #expect(ProfileRoutePolicy.requiresPlayer(.statistics))
    #expect(!ProfileRoutePolicy.requiresPlayer(.bands))
}
