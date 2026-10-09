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

// MARK: - Pinned footer control

extension View {
    /// The pinned selected-row footer's control on every board (pattern `leaderboard-row`
    /// R5): apply to the ``SelectedRowAction`` Jump button or Open link around the row.
    ///
    /// The whole-row button style (``festivalRowButtonStyle(cornerRadius:)``) gives the
    /// footer what every list row has on the Mac: the keyboard focus ring in the card's
    /// shape, Return as well as Space, and the hover tint (issue #461); iPhone and iPad
    /// keep the plain style. Then the page margins and one container identifier.
    ///
    /// - Parameter identifier: The footer container's identifier
    ///   (`fst.<board>.spotlight-footer`).
    /// - Returns: The styled footer.
    func pinnedFooterControl(identifier: String) -> some View {
        festivalRowButtonStyle()
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier)
    }
}

// MARK: - Row card

/// One song-board row: the ``SongLeaderboardEntryRow`` columns, the in-card disclosure
/// chevron, the 48-unit minimum and the row surface (the selected player's purple). The
/// one row for the Solo board, where it is a segment of the page's group card
/// (``FestivalGroupSegment``, owner #543), both boards' pinned footers, which stay
/// floating cards of their own, and the section's width probe (``SongLeaderboardNameFit``).
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

    /// The row's horizontal padding, also the group card's hairline inset.
    static let horizontalPadding: CGFloat = 14

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
        .padding(.horizontal, Self.horizontalPadding)
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
/// gets an opaque backing, as the pager's plates already have. The system settings and
/// the app's own toggles both count, as for every other surface (surface-materials
/// R4 through ``FestivalGlassSurface/resolve(reduceTransparency:systemContrast:lessTransparency:moreContrast:glassAvailable:)``;
/// issue #461: the app's toggles had left the row translucent over artwork beside an
/// opaque pager).
struct PinnedFooterBacking: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    /// Whether the pinned row needs its opaque backing.
    ///
    /// - Parameters:
    ///   - reduceTransparency: System Reduce Transparency.
    ///   - systemContrast: System Increase Contrast (`colorSchemeContrast`).
    ///   - lessTransparency: The app's Reduce Transparency toggle.
    ///   - moreContrast: The app's Increase Contrast toggle.
    /// - Returns: True whenever the shared surfaces turn opaque.
    static func isOpaque(
        reduceTransparency: Bool, systemContrast: ColorSchemeContrast,
        lessTransparency: Bool, moreContrast: Bool
    ) -> Bool {
        FestivalGlassSurface.resolve(
            reduceTransparency: reduceTransparency, systemContrast: systemContrast,
            lessTransparency: lessTransparency, moreContrast: moreContrast, glassAvailable: true
        ) == .opaque
    }

    func body(content: Content) -> some View {
        content.background {
            if Self.isOpaque(
                reduceTransparency: reduceTransparency, systemContrast: contrast,
                lessTransparency: lessTransparency, moreContrast: moreContrast
            ) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BrandTokens.appBackground)
            }
        }
    }
}
