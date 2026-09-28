import Foundation
import Testing
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

/// Compete and Leaderboards share a slot; hidden profile tabs fall back to Songs.
@Test func resolveKeepsEquivalentSlot() {
    let anonymous = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let player = FestivalTabPolicy.sections(profile: .player, regularWidth: false)
    #expect(FestivalTabPolicy.resolve(.compete, in: anonymous) == .leaderboards)
    #expect(FestivalTabPolicy.resolve(.leaderboards, in: player) == .compete)
    #expect(FestivalTabPolicy.resolve(.rivals, in: player) == .compete)
    #expect(FestivalTabPolicy.resolve(.statistics, in: anonymous) == .songs)
    #expect(FestivalTabPolicy.resolve(.suggestions, in: anonymous) == .songs)
    #expect(FestivalTabPolicy.resolve(.settings, in: anonymous) == .settings)
    #expect(FestivalTabPolicy.resolve(.rivals, in: anonymous) == .songs)
}

/// Only Statistics forgets its nested route when left.
@Test func onlyStatisticsResetsOnLeave() {
    for section in FestivalSection.allCases {
        #expect(FestivalTabPolicy.resetsPathOnLeave(section) == (section == .statistics))
    }
}

// MARK: - Drawer menu

/// Anonymous drawer: Leaderboards is already a tab and Rivals needs a player.
@Test func anonymousDrawerBrowse() {
    let visible = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let ids = DrawerMenu.browse(profile: .none, visibleSections: visible, hideShop: false).map(\.id)
    #expect(ids == ["bands", "shop"])
}

/// Player drawer surfaces Leaderboards (replaced by Compete) and Rivals.
@Test func playerDrawerBrowse() {
    let visible = FestivalTabPolicy.sections(profile: .player, regularWidth: false)
    let items = DrawerMenu.browse(profile: .player, visibleSections: visible, hideShop: false)
    #expect(items.map(\.id) == ["leaderboards", "rivals", "bands", "shop"])
    #expect(items.first?.intent == .push(.leaderboards))
}

/// Settings › Hide Item Shop removes the drawer entry.
@Test func hiddenShopLeavesDrawer() {
    let items = DrawerMenu.browse(profile: .none, visibleSections: [.songs], hideShop: true)
    #expect(!items.contains { $0.id == "shop" })
}

/// Settings switches tabs; Manual and Licenses push onto the current stack.
@Test func drawerMoreIntents() {
    #expect(DrawerMenu.more.map(\.intent) == [
        .push(.manual), .select(.settings), .push(.licenses),
    ])
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
    }
    let debug = DebugLaunchRoute(environment: [
        "FST_DEBUG_DRAWER": "1", "FST_DEBUG_SHEET": "profile",
        "FST_DEBUG_PROFILE": "e408c4613c8f4da5907090b390bda80c:Some Name",
        "FST_DEBUG_ANONYMOUS": "1",
    ])
    #expect(debug.opensDrawer)
    #expect(debug.opensProfileSheet)
    #expect(debug.anonymous)
    #expect(debug.profile?.accountId == "e408c4613c8f4da5907090b390bda80c")
    #expect(debug.profile?.displayName == "Some Name")
}
#endif
