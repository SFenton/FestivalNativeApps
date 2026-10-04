import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Category card

/// One `SuggestionCategory` as a Liquid Glass group, ported card by card from the web
/// `CategoryCard` (`pages/suggestions/components/CategoryCard.tsx`).
///
/// The title, description and (for single-instrument categories) the category's
/// instrument icon sit **above** the card (operator rule, 2026-09-28: headers never
/// inside containers); the song rows are flat inside one material card
/// (`.agents/design/apple/liquid-glass.md`). Each row's right-hand metadata follows the
/// web's per-category `getRowLayout` (`SuggestionRowLayout` in FestivalCore).
struct SuggestionCategoryCardView: View {
    let category: SuggestionCategory
    let session: FestivalSession
    /// Effective current season, which season pills highlight (web `SeasonPill`).
    var currentSeason: Int?
    /// Settings-visible charts for the instrument status chips.
    var visibleInstruments: Set<Instrument> = Set(Instrument.allCases)

    var body: some View {
        let categoryInstrument = SuggestionRowLayout.categoryInstrument(category.key)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                FestivalSectionHeader(category.title, subtitle: category.description)
                if let categoryInstrument {
                    InstrumentIcon(categoryInstrument, size: 36)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 4)
            FestivalGlassSection {
                ForEach(category.songs) { item in
                    NavigationLink(value: AppRoute.songDetail(item.song)) {
                        SuggestionSongRowView(
                            item: item, session: session, categoryKey: category.key,
                            categoryInstrument: categoryInstrument, currentSeason: currentSeason,
                            visibleInstruments: visibleInstruments
                        )
                    }
                    .festivalRowButtonStyle(cornerRadius: 8)
                    .accessibilityIdentifier("fst.suggestions.row.\(item.id)")
                }
            }
        }
        .accessibilityIdentifier("fst.suggestions.category.\(category.key)")
    }
}

// MARK: - Song row

/// One flat row inside a category's material card (web `CategoryCard` `SongRow`): album art,
/// title and "artist · year" (web `SongInfo`), then the category's metadata. On a compact
/// width the metadata wraps to a right-aligned second line unless it is only an icon or
/// pill (web `twoRow` / `iconOnly`).
struct SuggestionSongRowView: View {
    let item: SuggestionSongItem
    let session: FestivalSession
    var categoryKey = ""
    /// The category's own instrument; rows fall back to it like the web, whose items
    /// carry the instrument key for single-instrument categories.
    var categoryInstrument: Instrument?
    var currentSeason: Int?
    var visibleInstruments: Set<Instrument> = Set(Instrument.allCases)
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Web `CategoryCard.showStars`: star-progress categories only.
    ///
    /// - Parameter categoryKey: `SuggestionCategory.key`.
    /// - Returns: Whether rows in that category show stars.
    nonisolated static func showsStars(categoryKey: String) -> Bool {
        SuggestionRowLayout.showsStars(categoryKey: categoryKey)
    }

    private var layout: SuggestionRowLayout { SuggestionRowLayout.forCategory(categoryKey) }
    private var showsStars: Bool { Self.showsStars(categoryKey: categoryKey) && (item.stars ?? 0) > 0 }
    private var rowInstrument: Instrument? { item.instrument ?? categoryInstrument }

    /// Web `SongInfo` subtitle: artist, then the release year when known.
    private var subtitle: String {
        [item.song.artist, item.song.year.map(String.init)].compactMap { $0 }
            .joined(separator: " \u{00B7} ")
    }

    private var twoRow: Bool {
        sizeClass != .regular && layout != .hidden && !layout.isCompact(showsStars: showsStars)
    }

    var body: some View {
        Group {
            if twoRow {
                VStack(alignment: .trailing, spacing: 6) {
                    songInfo
                    metadata
                }
            } else {
                HStack(spacing: 12) {
                    songInfo
                    metadata
                }
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var songInfo: some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: item.song.albumArt, session: session, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(item.song.title, font: .subheadline.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                MarqueeText(subtitle, font: .caption)
                    .foregroundStyle(FestivalText.primary)
            }
            .marqueeSync()
            Spacer(minLength: 0)
        }
    }

    // MARK: Metadata by layout

    @ViewBuilder private var metadata: some View {
        switch layout {
        case .hidden:
            EmptyView()
        case .rival:
            let showsRivalName = SuggestionRowLayout.showsRivalName(categoryKey: categoryKey)
            HStack(spacing: 8) {
                if showsRivalName, let rivalName = item.rivalName { rivalBadge(rivalName) }
                if let delta = item.rivalRankDelta, delta != 0 {
                    Text(delta > 0 ? "+\(delta)" : "\(delta)")
                        .font(.footnote.bold().monospacedDigit())
                        .foregroundStyle(delta > 0 ? BrandTokens.statusGreen : BrandTokens.statusRed)
                        .accessibilityLabel(SuggestionRowLayout.rivalDeltaAccessibilityLabel(
                            delta: delta, rivalName: showsRivalName ? nil : item.rivalName
                        ))
                }
                instrumentIcon
            }
        case .unfcAccuracy:
            if let accuracy = SuggestionRowLayout.unfcAccuracy(percent: item.percent) {
                SongMetadataFieldView(
                    field: .accuracy(
                        accuracy, fullCombo: false, percentageVisible: true,
                        tint: try? ScoreFormatting.accuracyTint(accuracy)
                    ),
                    songId: item.song.songId
                )
            }
        case .season:
            if let season = seasonAchieved, season > 0 {
                SongMetadataFieldView(
                    field: .season(season, current: season == currentSeason), songId: item.song.songId
                )
            }
        case .percentile:
            HStack(spacing: 8) {
                if let display = item.percentileDisplay {
                    SongMetadataFieldView(
                        field: .percentile(display, tier: Self.tier(display)), songId: item.song.songId
                    )
                }
                instrumentIcon
            }
        case .singleInstrument:
            HStack(spacing: 8) {
                if showsStars, let stars = item.stars {
                    StarRating(stars: stars, size: 18)
                        .accessibilityLabel(stars >= 6 ? "5 gold stars" : "\(stars) stars")
                }
                instrumentIcon
            }
        case .instrumentChips:
            SongInstrumentStatusChips(
                songId: item.song.songId,
                badges: SongInstrumentStatusPolicy.badges(
                    for: item.song, visibleInstruments: visibleInstruments,
                    scores: session.selectedPlayerScores[item.song.songId] ?? [:]
                ),
                keyboard: item.song.usesKeyboardIcon
            )
            .fixedSize()
        }
    }

    @ViewBuilder private var instrumentIcon: some View {
        if let rowInstrument {
            InstrumentIcon(rowInstrument, size: 28)
                .accessibilityLabel(rowInstrument.label)
        }
    }

    /// Season the selected player's current score was set in: this row's chart, or the
    /// latest across charts for an instrument-agnostic row (web `layout: 'season'`).
    private var seasonAchieved: Int? {
        let scores = session.selectedPlayerScores[item.song.songId] ?? [:]
        if let rowInstrument { return scores[rowInstrument]?.season }
        return scores.values.compactMap(\.season).max()
    }

    /// Web `PercentilePill` auto tier: gold italic for Top 1%, gold for Top 5%.
    ///
    /// - Parameter display: "Top N%" label.
    /// - Returns: The pill tier.
    static func tier(_ display: String) -> SongPercentileTier {
        let digits = display.filter { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { return .ordinary }
        return value <= 1 ? .topOne : value <= 5 ? .topFive : .ordinary
    }

    /// A rival category's badge (web `rivalBadge`): the name, truncated past 12
    /// characters, in a tinted capsule. Song rivals are blue; there is no
    /// leaderboard-rival source yet to need the web's gold variant.
    private func rivalBadge(_ name: String) -> some View {
        Text(name.count > 12 ? "\(name.prefix(11))\u{2026}" : name)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Self.songRivalBlue.opacity(0.2)))
            .foregroundStyle(Self.songRivalBlue)
    }

    /// Web song-rival badge colour `#4285F4`.
    private static let songRivalBlue = Color(.sRGB, red: 66 / 255, green: 133 / 255, blue: 244 / 255)
}
