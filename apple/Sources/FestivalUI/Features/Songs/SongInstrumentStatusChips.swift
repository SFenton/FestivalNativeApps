import SwiftUI
import FestivalCore
import FestivalDesign

/// Balanced, measured rows instead of a fixed phone/tablet chip breakpoint.
private struct SongChipRows: Layout {
    struct Cache {
        var sizes: [CGSize]
    }

    let spacing: CGFloat

    /// Measure each bounded child once until its text size or content changes.
    ///
    /// - Parameter subviews: At most nine semantic instrument chips.
    /// - Returns: Reusable child sizes for successive layout proposals.
    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    /// Refresh cached sizes when SwiftUI replaces children or Dynamic Type changes.
    ///
    /// - Parameters:
    ///   - cache: The previous measurements.
    ///   - subviews: Current semantic chips.
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    /// Let the card grow vertically rather than clipping chips at a narrow width.
    ///
    /// - Parameters:
    ///   - proposal: Actual width offered by Songs, including split-view changes.
    ///   - subviews: Measured chip views.
    ///   - cache: Current intrinsic child sizes.
    /// - Returns: Natural width and the height of evenly balanced rows.
    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
    ) -> CGSize {
        guard !cache.sizes.isEmpty else { return .zero }
        let ideal = rowWidth(cache.sizes.indices, sizes: cache.sizes)
        let proposed = proposal.width ?? ideal
        let width = proposed.isFinite ? max(0, proposed) : ideal
        let rows = balancedRows(cache.sizes, availableWidth: width)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.reduce(CGFloat.zero) { max($0, cache.sizes[$1].height) }
        } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: min(width, ideal), height: height)
    }

    /// Center each bounded status row in its actual available width.
    ///
    /// - Parameters:
    ///   - bounds: Allocated Songs-card content rectangle.
    ///   - proposal: SwiftUI's view-size proposal.
    ///   - subviews: One semantic chart view per enabled instrument.
    ///   - cache: Current intrinsic child sizes.
    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Cache
    ) {
        let rows = balancedRows(cache.sizes, availableWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            let width = rowWidth(row, sizes: cache.sizes)
            var x = bounds.minX + max(0, (bounds.width - width) / 2)
            let height = row.reduce(CGFloat.zero) { max($0, cache.sizes[$1].height) }
            for index in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(cache.sizes[index])
                )
                x += cache.sizes[index].width + spacing
            }
            y += height + spacing
        }
    }

    /// Split the bounded chart set evenly at a measured content width.
    ///
    /// - Parameters:
    ///   - sizes: One intrinsic width/height per enabled chart.
    ///   - availableWidth: Actual space, not the physical device's pixel width.
    /// - Returns: Nonempty, source-ordered row index ranges.
    private func balancedRows(
        _ sizes: [CGSize], availableWidth: CGFloat
    ) -> [Range<Int>] {
        guard !sizes.isEmpty else { return [] }
        let widest = sizes.map(\.width).max() ?? 0
        let ideal = rowWidth(sizes.indices, sizes: sizes)
        let measured = availableWidth.isFinite
            ? min(max(0, availableWidth), ideal) : ideal
        let fit = max(1, Int((measured + spacing) / (widest + spacing)))
        let rowCount = (sizes.count + fit - 1) / fit
        let base = sizes.count / rowCount
        let extra = sizes.count % rowCount
        var start = 0
        return (0..<rowCount).map { row in
            let end = start + base + (row < extra ? 1 : 0)
            defer { start = end }
            return start..<end
        }
    }

    /// Sum a single row's intrinsic widths and gaps.
    ///
    /// - Parameters:
    ///   - indices: Source-order chip positions within this row.
    ///   - sizes: Measured chip dimensions.
    /// - Returns: Required width for the row.
    private func rowWidth<C: Collection>(
        _ indices: C, sizes: [CGSize]
    ) -> CGFloat where C.Element == Int {
        indices.reduce(CGFloat.zero) { $0 + sizes[$1].width }
            + CGFloat(max(0, indices.count - 1)) * spacing
    }
}

/// Source statuses with native-drawn, distinguishable visual and spoken cues.
struct SongInstrumentStatusChips: View {
    let songId: String
    let badges: [SongInstrumentBadge]
    /// This song's `sig == "Keyboard"`; swaps the Lead/Pro Lead icon variant.
    var keyboard: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 34

    private var side: CGFloat {
        min(max(scaledSide, dynamicTypeSize.isAccessibilitySize ? 48 : 34), 64)
    }

    var body: some View {
        SongChipRows(spacing: 4) {
            ForEach(badges) { badge in
                chip(badge)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badges.map(\.announcement).joined(separator: "; "))
        .accessibilityIdentifier("fst.songs.instrument-status.\(songId)")
    }

    /// Match the web `InstrumentChip`'s colored ring/fill with the real chart icon
    /// inside, while keeping a second non-color status mark for accessibility.
    ///
    /// - Parameter badge: Source-ordered, verified per-song instrument state.
    /// - Returns: A bounded circular native status with contrast-safe glyphs.
    private func chip(_ badge: SongInstrumentBadge) -> some View {
        InstrumentIcon(
            badge.instrument,
            keyboard: keyboard && (badge.instrument == .lead || badge.instrument == .proLead),
            size: side * 0.56
        )
            .accessibilityHidden(true)
            .frame(width: side, height: side)
            .background(badge.status.fillColor, in: Circle())
            .overlay {
                Circle().stroke(badge.status.strokeColor, lineWidth: 2)
            }
            .overlay(alignment: .bottomTrailing) {
                statusMark(badge.status)
                    .frame(width: side * 0.42, height: side * 0.42)
                    .background(badge.status.glyphBackground, in: Circle())
                    .overlay { Circle().stroke(badge.status.strokeColor, lineWidth: 1) }
                    .offset(x: side * 0.08, y: side * 0.08)
            }
            .accessibilityHidden(true)
    }

    /// Draw the same non-color status distinction previously carried by the chip fill.
    ///
    /// - Parameter status: Verified per-chart score/FC state.
    /// - Returns: A small badge glyph, distinguishable without color.
    private func statusMark(_ status: SongInstrumentStatus) -> some View {
        Group {
            if let mark = status.mark {
                Image(systemName: mark)
                    .font(.system(size: side * 0.24, weight: .bold))
            } else {
                Text("/")
                    .font(.system(size: side * 0.24, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(status.glyphColor)
        .accessibilityHidden(true)
    }
}

private extension SongInstrumentStatus {
    var fillColor: Color {
        switch self {
        case .fullCombo: BrandTokens.gold
        case .scored: BrandTokens.statusGreen
        case .noScore, .inconsistentFullCombo: BrandTokens.statusRed
        case .unavailable: BrandTokens.surfaceMuted
        }
    }

    var strokeColor: Color {
        switch self {
        case .fullCombo: BrandTokens.goldStroke
        case .scored: BrandTokens.statusGreenStroke
        case .noScore, .inconsistentFullCombo: BrandTokens.statusRedStroke
        case .unavailable: BrandTokens.textDisabled
        }
    }

    var glyphColor: Color {
        switch self {
        case .fullCombo, .scored: BrandTokens.cardBackground
        case .noScore, .unavailable, .inconsistentFullCombo: BrandTokens.textPrimary
        }
    }

    /// Background of the small corner status badge, matching the ring's fill.
    var glyphBackground: Color { fillColor }

    var mark: String? {
        switch self {
        case .fullCombo: "star.fill"
        case .scored: "checkmark"
        case .noScore: "minus"
        case .unavailable: nil
        case .inconsistentFullCombo: "exclamationmark"
        }
    }
}
