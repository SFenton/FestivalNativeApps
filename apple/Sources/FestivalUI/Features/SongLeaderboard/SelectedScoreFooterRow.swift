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
    /// Draw the stars right after the score when the columns show stars: the band
    /// footer (issue #306, web `starsAfterScore`); the Solo footer never draws stars.
    var starsAfterScore = false

    var body: some View {
        SongLeaderboardRowCard(
            entry: entry, isPlayer: true, currentSeason: currentSeason,
            starsAfterScore: starsAfterScore
        )
        .modifier(PinnedFooterBacking())
        .contentShape(Rectangle())
    }
}

// MARK: - Row card

/// One song-board row as its own card: the ``SongLeaderboardEntryRow`` columns, the
/// in-card disclosure chevron, the 48-unit minimum and the row surface (the selected
/// player's purple). The one card for the Solo board's rows, both boards' pinned
/// footers and the section's width probe (``SongLeaderboardNameFit``).
///
/// The chevron is centred on the whole card, so it stays centred when a crowded
/// trailing-pane board stacks its rows into multi-row cards (#364; HIG Lists and
/// tables: "for drill-down, use a disclosure indicator").
struct SongLeaderboardRowCard: View {
    let entry: LeaderboardEntry
    /// The selected player's own row: bold rank and name on the purple surface.
    var isPlayer = false
    let currentSeason: Int?
    /// Draw the stars after the score (the band footer, issue #306).
    var starsAfterScore = false
    /// Width probe only: see ``SongLeaderboardEntryRow/probeNames``. A probe draws no
    /// surface.
    var probeNames: [RankingRowName]? = nil

    var body: some View {
        let card = HStack(spacing: 8) {
            SongLeaderboardEntryRow(
                entry: entry, isPlayer: isPlayer, currentSeason: currentSeason,
                starsAfterScore: starsAfterScore, probeNames: probeNames
            )
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(FestivalText.deemphasized)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: LeaderboardRowMetrics.minHeight)
        if probeNames == nil {
            card.modifier(RankingRowSurface(isSelected: isPlayer))
        } else {
            card
        }
    }
}

// MARK: - Pinned footer backing

/// The opaque backing of a board's pinned selected row (song boards and Full
/// Rankings, issue #318). The footer floats over artwork with no band behind it
/// (issue #93): with Reduce Transparency or Increase Contrast its translucent purple
/// gets an opaque backing, as the pager's plates already have.
struct PinnedFooterBacking: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency || contrast == .increased {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BrandTokens.appBackground)
            }
        }
    }
}
