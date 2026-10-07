import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Wide-row profile panel

/// The right half of a wide Songs row: one flat card per scored chart (its icon, then
/// its score pills on one line where they fit), laid out in equal-width columns
/// (``SongProfilePanelPolicy/arrangement(width:tiles:overview:scale:)``).
///
/// Cards are flat fills inside the row's one card surface (surface-materials R6) and
/// reuse the Songs score pills (``SongMetadataFieldView``). Each card is one
/// VoiceOver stop naming its chart and every field, including stars a compact
/// arrangement leaves out visually.
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

    /// One chart's card: the chart icon (as on the status chips), then its pills.
    ///
    /// - Parameter tile: The chart and its ordered fields.
    /// - Returns: A flat-filled card that reads as one element.
    private func card(_ tile: SongProfilePanelTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let keys = keyboard && (tile.chart == .lead || tile.chart == .proLead)
        let fields = arrangement.dropsStars ? tile.fields.filter { $0.id != .stars } : tile.fields
        return HStack(alignment: .top, spacing: 8) {
            InstrumentIcon(tile.chart, keyboard: keys, size: 24)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            if !fields.isEmpty {
                SongProfileMetadataPills(fields: fields, songId: songId, leading: true)
            } else {
                Text(tile.chart.label)
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
        .accessibilityIdentifier("fst.songs.profile-panel.\(songId).\(tile.chart.rawValue)")
    }
}
