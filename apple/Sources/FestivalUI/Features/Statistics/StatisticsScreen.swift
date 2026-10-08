import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - StatisticsScreen

/// `/statistics` — the selected player's own profile statistics hub.
///
/// The web renders this route by pointing `PlayerPage` at the tracked/selected
/// account (`App.tsx:95-105`); this tab is only reachable once a player is
/// selected (`FestivalTabPolicy.sections(profile:)`), so this screen reuses the
/// same `PlayerProfileContent` the pushed `/player/:accountId` route uses, always
/// in its selected (Deselect) state. The defensive empty state below only appears for the
/// brief moment between an explicit deselect and the tab bar hiding Statistics.
struct StatisticsScreen: View {
    let session: FestivalSession
    @Environment(\.openProfile) private var openProfile

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (API client, selected profile, caches).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        Group {
            if let selected = session.selectedPlayer {
                PlayerProfileContent(
                    session: session, accountId: selected.accountId,
                    routeDisplayName: selected.displayName, showsRootTrailingItems: true
                )
                // This tab root survives a profile switch, so key its per-account
                // state (phase, rank rows, pending dialogs) by the account itself.
                .id(selected.accountId)
            } else {
                FestivalEmptyState(
                    "No Profile Selected", systemImage: "chart.bar",
                    subtitle: "Select a player to see their statistics.",
                    accessibilityIdentifier: "fst.statistics.empty"
                ) {
                    Button("Choose Profile") { openProfile() }
                        .festivalProminentButton()
                        .accessibilityIdentifier("fst.statistics.choose-profile")
                }
                // Every root page keeps its title (issue #341); the profile sets its own.
                .festivalNavigationTitle("Statistics")
            }
        }
        .festivalBackground(.carousel, session: session)
    }
}
