import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Leaderboards dual-source region

/// The Leaderboards overview's bottom region on the iPhone Duo inner display in
/// portrait: the selected player's 30-day rank history, one card per Settings-visible
/// instrument (`.agents/design/apple/duo.md`, "Dual-source half-fold layouts").
///
/// Reuses the player-profile graph card (`PlayerRankHistoryPage`, the pure
/// `GET /api/rankings/{instrument}/{accountId}/history` read). View All opens the
/// player's own profile, where every graph lives.
struct LeaderboardsRankHistoryPane: View {
    let session: FestivalSession

    @Environment(\.openProfile) private var openProfile
    private var visible = VisibleInstrumentsReader()

    /// Create the pane.
    ///
    /// - Parameter session: Shared app session (selected player).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        let player = session.selectedPlayer
        DualSourcePane(
            "Your Rank History", systemImage: "chart.line.uptrend.xyaxis",
            seeAll: player.map { .player(accountId: $0.accountId, displayName: $0.displayName) },
            identifier: "leaderboards.rank-history"
        ) {
            if let player {
                if visible.instruments.isEmpty {
                    FestivalEmptyState(
                        "No Instruments", systemImage: "slider.horizontal.3",
                        subtitle: "Enable at least one instrument in Settings to see rank history."
                    )
                } else {
                    HorizontalCarousel("Your Rank History", items: visible.instruments, minimumCardWidth: 300) { instrument in
                        PlayerRankHistoryPage(session: session, accountId: player.accountId, instrument: instrument)
                    }
                    .id(player.accountId)
                }
            } else {
                FestivalEmptyState(
                    "No Profile Selected", systemImage: "chart.line.uptrend.xyaxis",
                    subtitle: "Select a player to follow their rank on every leaderboard here."
                ) {
                    Button("Choose Profile") { openProfile() }
                        .festivalProminentButton()
                        .accessibilityIdentifier("fst.dual.leaderboards.choose-profile")
                }
            }
        }
    }
}
