import SwiftUI
import FestivalCore
import FestivalDesign

/// Keep ordered metadata right-aligned without a fixed phone/tablet row count.
private struct SongMetadataFlow: Layout {
    struct Cache {
        var idealSizes: [CGSize]
    }

    let spacing: CGFloat

    /// Cache intrinsic pill sizes until content or text scaling changes.
    ///
    /// - Parameter subviews: At most seven independently visible score fields.
    /// - Returns: Measured native content dimensions.
    func makeCache(subviews: Subviews) -> Cache {
        Cache(idealSizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    /// Re-measure after Settings, profile or Dynamic Type replaces pill content.
    ///
    /// - Parameters:
    ///   - cache: Previously measured intrinsic sizes.
    ///   - subviews: Current independent metadata pills.
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.idealSizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    /// Grow vertically until all enabled fields fit instead of clipping a wide row.
    ///
    /// - Parameters:
    ///   - proposal: Actual compact or regular Songs-card content width.
    ///   - subviews: Ordered score-field views.
    ///   - cache: Their current intrinsic sizes.
    /// - Returns: Proposed content width and sum of measured row heights.
    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let intrinsic = rowWidth(cache.idealSizes.indices, sizes: cache.idealSizes)
        let available = boundedWidth(proposal.width ?? intrinsic, intrinsic: intrinsic)
        let sizes = constrainedSizes(subviews, ideal: cache.idealSizes, width: available)
        let groups = rows(sizes, width: available)
        let height = groups.reduce(CGFloat.zero) { partial, group in
            partial + group.reduce(CGFloat.zero) { max($0, sizes[$1].height) }
        } + CGFloat(max(0, groups.count - 1)) * spacing
        return CGSize(width: min(intrinsic, available), height: height)
    }

    /// Align each wrapped pill row to the score's trailing edge.
    ///
    /// - Parameters:
    ///   - bounds: Allocated full-width metadata strip.
    ///   - proposal: Parent SwiftUI proposal.
    ///   - subviews: Ordered field views, each placed exactly once.
    ///   - cache: Intrinsic measurements reused across layout passes.
    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout Cache
    ) {
        let available = boundedWidth(bounds.width, intrinsic:
            rowWidth(cache.idealSizes.indices, sizes: cache.idealSizes))
        let sizes = constrainedSizes(subviews, ideal: cache.idealSizes, width: available)
        var y = bounds.minY
        for group in rows(sizes, width: available) {
            var x = bounds.maxX - rowWidth(group, sizes: sizes)
            let height = group.reduce(CGFloat.zero) { max($0, sizes[$1].height) }
            for index in group {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + spacing
            }
            y += height + spacing
        }
    }

    /// Treat unspecified/infinite width as intrinsic size without Int overflow.
    ///
    /// - Parameters:
    ///   - width: Actual or unspecified parent width.
    ///   - intrinsic: Sum of all field widths and gaps.
    /// - Returns: Finite width no larger than the content's intrinsic bound.
    private func boundedWidth(_ width: CGFloat, intrinsic: CGFloat) -> CGFloat {
        width.isFinite ? min(max(1, width), max(1, intrinsic)) : max(1, intrinsic)
    }

    /// Let a single unusually long pill wrap in the available card width.
    ///
    /// - Parameters:
    ///   - subviews: Current pill content.
    ///   - ideal: Cached unconstrained measurements.
    ///   - width: Finite horizontal space.
    /// - Returns: Vertical growth for fields wider than the card.
    private func constrainedSizes(
        _ subviews: Subviews, ideal: [CGSize], width: CGFloat
    ) -> [CGSize] {
        ideal.enumerated().map { index, size in
            guard size.width > width else { return size }
            let fitted = subviews[index].sizeThatFits(
                ProposedViewSize(width: width, height: nil)
            )
            return CGSize(
                width: min(width, max(1, fitted.width)),
                height: max(size.height, fitted.height)
            )
        }
    }

    /// Wrap source-order fields greedily, preserving one nonempty field per row.
    ///
    /// - Parameters:
    ///   - sizes: Intrinsic or width-constrained pill sizes.
    ///   - width: Available card content width.
    /// - Returns: Ordered pill index ranges.
    private func rows(_ sizes: [CGSize], width: CGFloat) -> [Range<Int>] {
        guard !sizes.isEmpty else { return [] }
        var groups: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0
        for index in sizes.indices {
            let required = sizes[index].width + (index == start ? 0 : spacing)
            if index > start && used + required > width {
                groups.append(start..<index)
                start = index
                used = sizes[index].width
            } else {
                used += required
            }
        }
        groups.append(start..<sizes.count)
        guard groups.count > 1 else { return groups }
        let base = sizes.count / groups.count
        let extra = sizes.count % groups.count
        var first = 0
        let balanced = (0..<groups.count).map { row in
            let end = first + base + (row < extra ? 1 : 0)
            defer { first = end }
            return first..<end
        }
        return balanced.allSatisfy { rowWidth($0, sizes: sizes) <= width }
            ? balanced : groups
    }

    /// Sum one row's content and inter-pill gaps.
    ///
    /// - Parameters:
    ///   - indices: Contiguous source-ordered field positions.
    ///   - sizes: Current fitted dimensions.
    /// - Returns: Intrinsic horizontal extent.
    private func rowWidth<C: Collection>(
        _ indices: C, sizes: [CGSize]
    ) -> CGFloat where C.Element == Int {
        indices.reduce(CGFloat.zero) { $0 + sizes[$1].width }
            + CGFloat(max(0, indices.count - 1)) * spacing
    }
}

/// One compact Fluent-informed field with explicit, independently spoken meaning.
struct SongMetadataFieldView: View {
    let field: SongMetadataField
    let songId: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var horizontalInset: CGFloat = 4

    private var badgeHeight: CGFloat {
        max(minHeight, dynamicTypeSize.isAccessibilitySize ? 44 : 28)
    }

    var body: some View {
        fieldContent
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(field.announcement)
            .accessibilityIdentifier("fst.songs.metadata.\(field.id.rawValue).\(songId)")
    }

    @ViewBuilder private var fieldContent: some View {
        switch field {
        case let .score(value):
            Text(value.formatted())
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(FestivalText.primary)
                .fixedSize(horizontal: false, vertical: true)
        case let .accuracy(value, combo, percentageVisible, tint):
            let label = accuracyLabel(
                value: value, fullCombo: combo,
                percentageVisible: percentageVisible, tint: tint
            )
            let text: Text = combo ? Text(label).italic() : Text(label)
            text
                .font(.callout.bold())
                .foregroundStyle(combo ? BrandTokens.gold : FestivalText.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, horizontalInset)
                .frame(
                    minWidth: combo ? max(82, badgeHeight * 2.8)
                        : max(64, badgeHeight * 2.1),
                    minHeight: badgeHeight
                )
                .background(
                    accuracyBackground(combo: combo, tint: tint),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(
                        combo ? BrandTokens.goldStroke : Color.clear, lineWidth: 2
                    )
                }
        case let .percentile(label, tier):
            let highlighted = tier != .ordinary
            let text: Text = tier == .topOne
                ? Text(label).italic() : Text(label)
            text
                .font(.callout.bold())
                .foregroundStyle(
                    highlighted ? BrandTokens.gold : FestivalText.primary
                )
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, horizontalInset)
                .frame(minWidth: 80, minHeight: badgeHeight)
                .background(
                    highlighted ? BrandTokens.cardBackground : BrandTokens.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(
                        highlighted ? BrandTokens.goldStroke : Color.clear,
                        lineWidth: 2
                    )
                }
        case let .stars(count, gold):
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 4) {
                    // One web star image (white or gold) beside the spelled-out count.
                    Image(StarRating.assetName(gold: gold), bundle: .module)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(gold ? "\(count) gold stars" : "\(count) stars")
                        .font(.callout.bold())
                        .foregroundStyle(gold ? BrandTokens.gold : FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, horizontalInset)
                .frame(minHeight: badgeHeight)
            } else {
                // The web's star images (`GoldStars`), not SF Symbols.
                StarRating(stars: count, gold: gold, size: 16)
                    .accessibilityHidden(true)
                    .frame(minHeight: badgeHeight)
            }
        case let .season(number, current):
            Text("S\(number)")
                .font(.callout.bold())
                .foregroundStyle(
                    current ? BrandTokens.surfaceSubtle : FestivalText.primary
                )
                .padding(.horizontal, horizontalInset)
                .frame(minWidth: 42, minHeight: badgeHeight)
                .background(
                    current ? BrandTokens.textSecondary : BrandTokens.surfaceSubtle, // chip fill, not text
                    in: RoundedRectangle(cornerRadius: 6)
                )
        case let .intensity(raw):
            DifficultyMeter(level: raw, raw: true)
        case let .difficulty(number):
            Text(difficultyInitial(number))
                .font(.callout.bold())
                .foregroundStyle(difficultyForeground(number))
                .padding(.horizontal, horizontalInset)
                .frame(minWidth: 32, minHeight: badgeHeight)
                .background(
                    difficultyBackground(number), in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6).stroke(
                        BrandTokens.borderSubtle, lineWidth: 1
                    )
                }
        case let .lastPlayed(value):
            Text(value)
                .font(.footnote)
                .foregroundStyle(FestivalText.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, horizontalInset)
                .frame(minWidth: 108, minHeight: badgeHeight)
                .background(BrandTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Blend a validated non-FC accuracy over the opaque card without faking a zero.
    ///
    /// - Parameters:
    ///   - combo: Explicit FC uses its own gold outlined surface.
    ///   - tint: Source-graded RGB components validated by the shared Core formatter.
    /// - Returns: Real tint, opaque content surface, or a visibly invalid-data accent.
    private func accuracyBackground(combo: Bool, tint: ScoreAccuracyTint?) -> Color {
        if combo { return BrandTokens.cardBackground }
        guard let tint else { return BrandTokens.statusRed }
        return Color(
            .sRGB, red: Double(tint.red) / 255,
            green: Double(tint.green) / 255,
            blue: Double(tint.blue) / 255,
            opacity: 0.25
        )
    }

    /// Do not make an invalid non-FC tint look like a correctly graded score.
    ///
    /// - Parameters:
    ///   - value: Optional validated expanded accuracy.
    ///   - fullCombo: Independent full-combo flag.
    ///   - percentageVisible: Saved score-field preference.
    ///   - tint: Successfully validated non-FC source color.
    /// - Returns: Exact percentage, truthful FC-only cue or an explicit unavailable label.
    private func accuracyLabel(
        value: Double?, fullCombo: Bool,
        percentageVisible: Bool, tint: ScoreAccuracyTint?
    ) -> String {
        if !fullCombo && value != nil && tint == nil {
            return "Accuracy display unavailable"
        }
        if percentageVisible, let value {
            return "\(fullCombo ? "FC " : "")\(ScoreFormatting.accuracy(value))%"
        }
        return fullCombo ? "FC" : "Accuracy unavailable"
    }

    /// Give each game difficulty an explicit legible initial.
    ///
    /// - Parameter number: Validated source game tier zero through three.
    /// - Returns: E, M, H or X, with an invalid marker if a caller bypasses policy.
    private func difficultyInitial(_ number: Int) -> String {
        switch number {
        case 0: "E"
        case 1: "M"
        case 2: "H"
        case 3: "X"
        default: "?"
        }
    }

    /// Avoid the source's low-contrast white text on Easy and Hard backgrounds.
    ///
    /// - Parameter number: Validated source game tier.
    /// - Returns: Dark on green/blue or white on red/purple.
    private func difficultyForeground(_ number: Int) -> Color {
        switch number {
        case 0, 2: BrandTokens.cardBackground
        case 1, 3: FestivalText.primary
        default: BrandTokens.gold
        }
    }

    /// Keep native game colours source-backed without using licensed artwork.
    ///
    /// - Parameter number: Validated game difficulty tier.
    /// - Returns: One opaque background, or an explicitly abnormal status color.
    private func difficultyBackground(_ number: Int) -> Color {
        switch number {
        case 0: BrandTokens.diffPillEasy
        case 1: BrandTokens.diffPillMedium
        case 2: BrandTokens.diffPillHard
        case 3: BrandTokens.diffPillExpert
        default: BrandTokens.statusRed
        }
    }
}

/// Ordered source-style secondary values that never overflow a narrow Song card.
struct SongProfileMetadataPills: View {
    let fields: [SongMetadataField]
    let songId: String

    var body: some View {
        SongMetadataFlow(spacing: 10) {
            ForEach(fields) { field in
                SongMetadataFieldView(field: field, songId: songId)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
