import FestivalCore

// MARK: - Profile button routing

/// What the shell's profile button (the top-bar avatar, `RootProfileButton`) does
/// when pressed (issue #290).
///
/// Mirrors the web's `getProfileClickDestination` (`FortniteFestivalWeb/src/utils/
/// profileNavigation.ts`): with no selection it opens profile search; with a selected
/// player it shows that player's own profile, the Statistics page, like the drawer
/// and sidebar footers. Explicit "Select/Switch Profile" commands and in-page "Choose
/// Profile" buttons keep opening the search sheet; only the avatar routes here.
/// Natives cannot select a band as the profile yet, so there is no band case.
enum ProfileButtonAction: Equatable {
    /// No profile is selected: present the profile search sheet.
    case chooseProfile
    /// A player is selected: carry out this navigation to their Statistics page
    /// (``RootTabTransition/none`` when it is already on screen).
    case navigate(RootTabTransition)

    /// Resolve the button press for the current shell state.
    ///
    /// - Parameters:
    ///   - selectedPlayer: The selected player, if any.
    ///   - statisticsVisible: Whether Statistics is a visible tab or sidebar row.
    ///   - selected: The selected section (underneath Search while it is open).
    ///   - searchActive: Whether the Search tab or sidebar row is showing.
    ///   - topRoute: The page on top of the selected section's stack, if any.
    /// - Returns: ``chooseProfile`` without a selection; otherwise a transition that
    ///   selects the Statistics section where it is visible, or pushes Statistics on the
    ///   current stack (as the drawer does when Statistics is not a tab), unless the
    ///   selected player's own page is already frontmost.
    static func resolve(
        selectedPlayer: SelectedPlayerIdentity?,
        statisticsVisible: Bool,
        selected: FestivalSection,
        searchActive: Bool,
        topRoute: AppRoute?
    ) -> ProfileButtonAction {
        guard let player = selectedPlayer else { return .chooseProfile }
        if statisticsVisible {
            return .navigate(.select(.statistics))
        }
        if !searchActive, isOwnProfile(topRoute, accountId: player.accountId) {
            return .navigate(.none)
        }
        return .navigate(.push(.statistics))
    }

    /// Whether `route` already shows the selected player's own profile.
    ///
    /// - Parameters:
    ///   - route: The frontmost pushed page, if any.
    ///   - accountId: The selected player's account ID.
    /// - Returns: True for the Statistics page or that player's profile page.
    private static func isOwnProfile(_ route: AppRoute?, accountId: String) -> Bool {
        switch route {
        case .statistics: true
        case let .player(id, _): id == accountId
        default: false
        }
    }
}

// MARK: - Environment handler

/// Environment handler for the profile button, installed by the root shells.
///
/// Equal whenever ``statisticsVisible`` matches, for the reason given on
/// `OpenProfileAction`: the root re-creates the closure on every body pass. That flag
/// is the only shell input the closure captures by value; the rest (selection, paths,
/// Search, the session) is read live when the button is pressed, so a size-class change
/// that moves Statistics in or out of the tab bar still reaches every reader.
struct ProfileButtonHandler: Equatable {
    /// Whether Statistics is a visible tab or sidebar row when the handler was made.
    let statisticsVisible: Bool
    let handler: @MainActor () -> Void

    /// Handle a profile-button press.
    @MainActor func callAsFunction() { handler() }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.statisticsVisible == rhs.statisticsVisible
    }
}
