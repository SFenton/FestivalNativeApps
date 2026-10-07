import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Wide-row profile panel

/// The right half of a wide Songs row (pattern `songs-profile-panel`): one flat card per
/// scored chart of the selected player, or the selected band's one card (an icon, then
/// its score pills on one line), laid out in equal-width columns
/// (``SongProfilePanelPolicy/arrangement(width:tiles:overview:scale:)``). Only a single
/// filtered chart's card may wrap its pills.
///
/// Cards are flat fills inside the row's one card surface (surface-materials R6) and
/// reuse the Songs score pills (``SongMetadataFieldView``). Each card is one
/// VoiceOver stop naming its chart (or band) and every field, including stars a
/// compact arrangement leaves out visually.
struct SongProfilePanel: View {
    let songId: String
    let tiles: [SongProfilePanelTile]
    /// Columns and whether stars are left out.
    let arrangement: SongProfilePanelPolicy.Arrangement
    /// This song's `sig == "Keyboard"`; swaps the Lead/Pro Lead icon variant.
    let keyboard: Bool
    let highContrast: Bool

    var body: some View {
        let columns = arrangement.columns
        VStack(alignment: .leading, spacing: SongProfilePanelPolicy.tileSpacing) {
            ForEach(SongGridPolicy.rows(tiles, columns: columns), id: \.first!.id) { line in
                HStack(alignment: .top, spacing: SongProfilePanelPolicy.tileSpacing) {
                    ForEach(line) { tile in
                        card(tile)
                    }
                    ForEach(line.count..<columns, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
                // Cards on one line share the tallest card's height.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fst.songs.profile-panel.\(songId)")
    }

    /// The card's leading glyph: the chart icon (as on the status chips), or a people
    /// symbol sized to the band.
    ///
    /// - Parameter tile: The card.
    /// - Returns: A 28 pt decorative glyph.
    @ViewBuilder private func icon(_ tile: SongProfilePanelTile) -> some View {
        switch tile.subject {
        case let .chart(chart):
            InstrumentIcon(
                chart, keyboard: keyboard && (chart == .lead || chart == .proLead), size: 24
            )
        case let .band(type, _):
            Image(systemName: type.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FestivalText.primary)
        }
    }

    /// One card: its icon, then its pills.
    ///
    /// - Parameter tile: The chart (or band) and its ordered fields.
    /// - Returns: A flat-filled card that reads as one element.
    private func card(_ tile: SongProfilePanelTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let fields = arrangement.dropsStars ? tile.fields.filter { $0.id != .stars } : tile.fields
        return HStack(alignment: .top, spacing: 8) {
            icon(tile)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            if !fields.isEmpty {
                SongProfileMetadataPills(fields: fields, songId: songId, leading: true)
            } else {
                Text(tile.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .frame(minHeight: 28)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BrandTokens.surfaceMuted.opacity(0.35), in: shape)
        .overlay {
            if highContrast {
                shape.stroke(FestivalText.primary, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.announcement)
        .accessibilityIdentifier("fst.songs.profile-panel.\(songId).\(tile.id)")
    }
}
