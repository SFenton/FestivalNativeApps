import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Selected score footer row

/// The pinned selected-profile row above a song board's pager: the selected player's
/// score on the Solo board, or their band's score on the band board (web
/// `FixedLeaderboardPlayerFooter` with `LeaderboardEntry isPlayer` on both pages).
///
/// Drawn exactly like a Solo list row (operator batch 7.3): the shared
/// ``SongLeaderboardEntryRow`` columns, the purple selected surface and the in-card
/// disclosure chevron. The caller wraps it in the button or link chosen by
/// ``SelectedRowAction/footer(rank:isVisible:pageSize:)`` (issue #307).
struct SelectedScoreFooterRow: View {
    let entry: LeaderboardEntry
    let currentSeason: Int?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            SongLeaderboardEntryRow(entry: entry, isPlayer: true, currentSeason: currentSeason)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FestivalText.deemphasized)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: LeaderboardRowMetrics.minHeight)
        .modifier(RankingRowSurface(isSelected: true))
        // The footer floats over artwork with no band behind it (issue #93): with
        // Reduce Transparency or Increase Contrast its translucent purple gets an
        // opaque backing, as the pager's plates already have.
        .background {
            if reduceTransparency || contrast == .increased {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BrandTokens.appBackground)
            }
        }
        .contentShape(Rectangle())
    }
}

extension LeaderboardEntry {
    /// A band board row as a pinned footer row: the band's members as the name, with
    /// its rank, team score, accuracy, stars and season (web `SongBandLeaderboardPage`
    /// footer `LeaderboardEntry` with `formatBandTeamName`).
    ///
    /// - Parameter band: The selected band's row.
    init(selectedBand band: SongBandLeaderboardEntry) {
        self.init(
            accountId: band.teamKey.isEmpty ? band.bandId : band.teamKey,
            displayName: band.membersLabel, score: band.score, rank: band.rank,
            accuracy: Double(band.accuracy), isFullCombo: band.isFullCombo,
            stars: band.stars, season: band.season, difficulty: Double(band.difficulty)
        )
    }
}
