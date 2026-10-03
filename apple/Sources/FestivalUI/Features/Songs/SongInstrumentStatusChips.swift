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

    /// No explicit horizontal guide: the chips are icons, so the edges serve.
    ///
    /// The protocol's default merges every chip's guides, measuring all nine chips
    /// again whenever a parent stack aligns the row; on the Mac that was the
    /// heaviest app frame of the Songs scroll-stress profile.
    ///
    /// - Returns: Nil, so the parent uses the default guide value.
    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Cache
    ) -> CGFloat? {
        nil
    }

    /// No explicit vertical guide (no text baselines among the chips).
    ///
    /// - Returns: Nil, so the parent uses the default guide value.
    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Cache
    ) -> CGFloat? {
        nil
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
    @Environment(\.displayScale) private var displayScale
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
    /// filling most of the circle (web: 24pt icon in a 34pt chip, ~71%). Color alone
    /// now conveys status — no star/minus/check/exclamation corner badge — but the
    /// combined chip-group announcement (`badges.map(\.announcement)` above) still
    /// speaks every chart's status in words, so the status remains fully accessible
    /// without relying on color or a glyph.
    ///
    /// - Parameter badge: Source-ordered, verified per-song instrument state.
    /// - Returns: A bounded circular native status with a contrast-safe stroke.
    private func chip(_ badge: SongInstrumentBadge) -> some View {
        let keyboard = keyboard && (badge.instrument == .lead || badge.instrument == .proLead)
        return Group {
            if let image = SongStatusChipImages.image(
                instrument: badge.instrument, keyboard: keyboard, status: badge.status,
                side: side, scale: displayScale
            ) {
                // One pre-drawn bitmap per chip (the stroke's outer half overhangs the
                // frame, as before); unclipped frame keeps the layout size.
                Image(decorative: image, scale: displayScale)
                    .frame(width: side, height: side)
            } else {
                Self.drawnChip(badge.instrument, keyboard: keyboard, status: badge.status, side: side)
            }
        }
        .accessibilityHidden(true)
    }

    /// The chip as SwiftUI views; also what ``SongStatusChipImages`` draws once.
    ///
    /// - Parameters:
    ///   - instrument: Chart.
    ///   - keyboard: Keys variant for Lead/Pro Lead.
    ///   - status: Score status (fill and stroke colours).
    ///   - side: Chip diameter.
    /// - Returns: Icon in a filled, stroked circle.
    static func drawnChip(
        _ instrument: Instrument, keyboard: Bool, status: SongInstrumentStatus, side: CGFloat
    ) -> some View {
        InstrumentIcon(instrument, keyboard: keyboard, size: side * 0.7)
            .accessibilityHidden(true)
            .frame(width: side, height: side)
            .background(status.fillColor, in: Circle())
            .overlay {
                Circle().stroke(status.strokeColor, lineWidth: 2)
            }
    }
}

// MARK: - Pre-drawn chips

/// Bitmaps of every chip variant in use, drawn once per size and scale.
///
/// A Songs row shows up to nine chips; as views each was an image, a filled circle
/// and a stroked circle, which made chips about half of the row-building cost in the
/// Mac Songs scroll-stress profile. There are at most 9 instruments × 2 icon
/// variants × 5 statuses per size, so the cache stays small.
@MainActor
enum SongStatusChipImages {
    private struct Key: Hashable {
        let instrument: Instrument
        let keyboard: Bool
        let status: SongInstrumentStatus
        let side: CGFloat
        let scale: CGFloat
    }

    private static var images: [Key: CGImage] = [:]
    /// Stroke overhang outside the chip frame on each side (half the 2 pt line).
    static let overhang: CGFloat = 1

    /// The chip bitmap, drawn on first use.
    ///
    /// - Parameters:
    ///   - instrument: Chart.
    ///   - keyboard: Keys variant for Lead/Pro Lead.
    ///   - status: Score status.
    ///   - side: Chip diameter in points.
    ///   - scale: Display scale.
    /// - Returns: A `(side + 2) × (side + 2)` point bitmap, or nil if drawing failed.
    static func image(
        instrument: Instrument, keyboard: Bool, status: SongInstrumentStatus,
        side: CGFloat, scale: CGFloat
    ) -> CGImage? {
        let key = Key(instrument: instrument, keyboard: keyboard, status: status, side: side, scale: scale)
        if let cached = images[key] { return cached }
        let renderer = ImageRenderer(content:
            SongInstrumentStatusChips.drawnChip(instrument, keyboard: keyboard, status: status, side: side)
                .padding(overhang)
        )
        renderer.scale = scale
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return nil }
        images[key] = image
        return image
    }
}

extension SongInstrumentStatus {
    /// One distinct color per status: with the corner mark removed, color is the
    /// *only* visual cue, so `inconsistentFullCombo` can no longer share red with
    /// `noScore` — it now gets its own amber (`BrandTokens.statusAmber`), a native
    /// safety deviation on top of the existing web-vs-native color deviation.
    var fillColor: Color {
        switch self {
        case .fullCombo: BrandTokens.gold
        case .scored: BrandTokens.statusGreen
        case .noScore: BrandTokens.statusRed
        case .inconsistentFullCombo: BrandTokens.statusAmber
        case .unavailable: BrandTokens.surfaceMuted
        }
    }

    var strokeColor: Color {
        switch self {
        case .fullCombo: BrandTokens.goldStroke
        case .scored: BrandTokens.statusGreenStroke
        case .noScore: BrandTokens.statusRedStroke
        case .inconsistentFullCombo: BrandTokens.statusAmberStroke
        case .unavailable: BrandTokens.textDisabled
        }
    }
}
