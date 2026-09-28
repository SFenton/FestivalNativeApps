import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Category card

/// One `SuggestionCategory` as a Liquid Glass group (web `CategoryCard` + `SectionHeader`):
/// a single glass card per category, with flat rows inside (`.agents/design/apple/liquid-glass.md`
/// — "Settings, Profile, Statistics, Suggestions, Rivals, Leaderboard groups").
struct SuggestionCategoryCardView: View {
    let category: SuggestionCategory
    let session: FestivalSession

    var body: some View {
        FestivalGlassSection(category.title, subtitle: category.description) {
            ForEach(category.songs) { item in
                NavigationLink(value: AppRoute.songDetail(item.song)) {
                    SuggestionSongRowView(item: item, session: session)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fst.suggestions.row.\(item.id)")
            }
        }
        .accessibilityIdentifier("fst.suggestions.category.\(category.key)")
    }
}

// MARK: - Song row

/// One flat row inside a category's glass card (web `SongCard` used by `CategoryCard`).
struct SuggestionSongRowView: View {
    let item: SuggestionSongItem
    let session: FestivalSession

    private var subtitle: String {
        var parts = [item.song.artist]
        if let instrument = item.instrument { parts.append(instrument.label) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkTile(raw: item.song.albumArt, session: session, size: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(item.song.title, font: .subheadline.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                MarqueeText(subtitle, font: .caption)
                    .foregroundStyle(BrandTokens.textSecondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var trailing: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let rivalName = item.rivalName {
                rivalBadge(rivalName, delta: item.rivalRankDelta ?? 0)
            }
            if let stars = item.stars, stars > 0 {
                starRow(stars)
            }
            HStack(spacing: 6) {
                if item.fullCombo == true {
                    Text("FC")
                        .font(.caption2.bold())
                        .foregroundStyle(BrandTokens.statusGreen)
                        .accessibilityHidden(true)
                }
                if let percent = item.percent {
                    Text(percent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                        .font(.caption2)
                        .foregroundStyle(BrandTokens.textSecondary)
                }
            }
            if let percentileDisplay = item.percentileDisplay {
                Text(percentileDisplay)
                    .font(.caption2)
                    .foregroundStyle(BrandTokens.textMuted)
            }
        }
        .accessibilityHidden(true)
    }

    /// A `song_rival_*` category's rival annotation (web `CategoryCard`'s `layout: 'rival'`
    /// `RightContent`): the rival's name in a tinted capsule plus a colored signed rank delta.
    /// Always the "song rival" color (blue) here — every rival family this app ports comes
    /// from `/rivals/all`'s per-song data; there is no leaderboard-rival source yet to need
    /// the web's second (gold) color.
    private func rivalBadge(_ name: String, delta: Int) -> some View {
        HStack(spacing: 6) {
            Text(name.count > 12 ? "\(name.prefix(11))\u{2026}" : name)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(BrandTokens.accentBlue.opacity(0.2)))
                .foregroundStyle(BrandTokens.accentBlue)
            if delta != 0 {
                Text(delta > 0 ? "+\(delta)" : "\(delta)")
                    .font(.caption2.bold())
                    .foregroundStyle(delta > 0 ? BrandTokens.statusGreen : BrandTokens.statusRed)
            }
        }
    }

    /// The web's star PNG row (`CategoryCard.RightContent`): that many white stars, or
    /// five gold stars for a six-star score.
    ///
    /// - Parameter stars: Raw service star count (1...6).
    /// - Returns: The bundled-artwork star row.
    private func starRow(_ stars: Int) -> some View {
        StarRating(stars: stars, size: 20)
    }
}
