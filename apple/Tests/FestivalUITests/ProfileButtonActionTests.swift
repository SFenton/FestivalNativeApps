import Testing
import FestivalCore
@testable import FestivalUI

// MARK: - Profile button routing (issue #290)

/// Pins where the profile button (avatar) goes: profile search without a selection,
/// the selected player's own Statistics page with one (web `getProfileClickDestination`).
@Suite("Profile button action")
struct ProfileButtonActionTests {
    private static let player = try! SelectedPlayerIdentity(
        searchResult: PlayerSearchResult(accountId: "fixture-player-1", displayName: "Fixture Player 1")
    )

    private static func resolve(
        player: SelectedPlayerIdentity? = Self.player,
        statisticsVisible: Bool = false,
        selected: FestivalSection = .songs,
        searchActive: Bool = false,
        topRoute: AppRoute? = nil
    ) -> ProfileButtonAction {
        ProfileButtonAction.resolve(
            selectedPlayer: player, statisticsVisible: statisticsVisible,
            selected: selected, searchActive: searchActive, topRoute: topRoute
        )
    }

    @Test("Without a selected player the button opens profile search")
    func anonymousChoosesProfile() {
        #expect(Self.resolve(player: nil) == .chooseProfile)
        #expect(Self.resolve(player: nil, statisticsVisible: true) == .chooseProfile)
        #expect(Self.resolve(player: nil, searchActive: true) == .chooseProfile)
    }

    @Test("A selected player's button selects the visible Statistics section")
    func selectsVisibleStatistics() {
        #expect(Self.resolve(statisticsVisible: true) == .navigate(.select(.statistics)))
        #expect(Self.resolve(statisticsVisible: true, searchActive: true) == .navigate(.select(.statistics)))
        #expect(Self.resolve(statisticsVisible: true, selected: .statistics) == .navigate(.select(.statistics)))
    }

    @Test("Without a Statistics tab the button pushes Statistics on the current stack")
    func pushesStatisticsWhenNotATab() {
        #expect(Self.resolve() == .navigate(.push(.statistics)))
        #expect(Self.resolve(selected: .settings, topRoute: .leaderboards) == .navigate(.push(.statistics)))
        let other = AppRoute.player(accountId: "fixture-player-2", displayName: "Fixture Player 2")
        #expect(Self.resolve(topRoute: other) == .navigate(.push(.statistics)))
    }

    @Test("The selected player's own page on top pushes nothing more")
    func ownProfileOnTopDoesNothing() {
        let own = AppRoute.player(accountId: "fixture-player-1", displayName: nil)
        #expect(Self.resolve(topRoute: .statistics) == .navigate(.none))
        #expect(Self.resolve(topRoute: own) == .navigate(.none))
    }

    @Test("From Search the button leaves Search and pushes Statistics")
    func searchPushes() {
        #expect(Self.resolve(searchActive: true, topRoute: .statistics) == .navigate(.push(.statistics)))
    }

    @Test("Handlers compare equal only for the same Statistics visibility")
    func handlerEquality() {
        let visible = ProfileButtonHandler(statisticsVisible: true) {}
        #expect(visible == ProfileButtonHandler(statisticsVisible: true) {})
        #expect(visible != ProfileButtonHandler(statisticsVisible: false) {})
    }

    @Test("The VoiceOver hint names the destination")
    func accessibilityHint() {
        #expect(RootProfileButton.accessibilityHint(hasPlayer: false) == "Opens profile selection")
        #expect(RootProfileButton.accessibilityHint(hasPlayer: true) == "Opens your statistics")
    }

    @MainActor
    @Test("macOS: the toolbar button selects Statistics with a player, else opens the sheet")
    func macToolbarButton() {
        let withPlayer = MacNavigationModel(
            storage: nil, visible: MacSidebarPolicy.destinations(hasPlayer: true, hideShop: false)
        )
        withPlayer.pressProfileButton(hasPlayer: true)
        #expect(withPlayer.selected == .statistics)
        #expect(!withPlayer.profilePresented)

        let anonymous = MacNavigationModel(
            storage: nil, visible: MacSidebarPolicy.destinations(hasPlayer: false, hideShop: false)
        )
        anonymous.pressProfileButton(hasPlayer: false)
        #expect(anonymous.selected == .songs)
        #expect(anonymous.profilePresented)

        // A selection whose Statistics row has not appeared yet falls back to the sheet.
        let pending = MacNavigationModel(
            storage: nil, visible: MacSidebarPolicy.destinations(hasPlayer: false, hideShop: false)
        )
        pending.pressProfileButton(hasPlayer: true)
        #expect(pending.profilePresented)
    }
}
