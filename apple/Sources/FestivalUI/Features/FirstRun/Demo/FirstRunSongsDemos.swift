import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Shared demo data
//
// A small, fully static pool of representative songs, matching the spirit of the web's
// hardcoded first-run demo data (`useDemoSongs`) — first-run demos never touch the live
// catalogue or network.

/// One row of demo content, independent of any live `Song`/`FestivalSession` so it never
/// touches the network or artwork cache while a carousel is showing.
private struct FirstRunDemoSong: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let year: Int
}

private enum FirstRunDemoData {
    static let songs: [FirstRunDemoSong] = [
        FirstRunDemoSong(title: "Neon Skyline", artist: "The Voltage", year: 2023),
        FirstRunDemoSong(title: "Midnight Runners", artist: "Echo Parade", year: 2021),
        FirstRunDemoSong(title: "Static Bloom", artist: "Halcyon Drift", year: 2024),
    ]
}

/// A stand-in album art tile — real demos never load network artwork.
private struct FirstRunDemoArt: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(BrandTokens.surfaceMuted)
            .overlay(
                Image(systemName: "music.note")
                    .foregroundStyle(BrandTokens.textSecondary)
            )
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }
}

// MARK: - songs-song-list

/// Ported from `pages/songs/firstRun/demo/SongRowDemo.tsx`: a handful of song rows on glass
/// cards, matching the real Songs list row layout.
struct FirstRunSongListDemo: View {
    var body: some View {
        VStack(spacing: 8) {
            ForEach(FirstRunDemoData.songs) { song in
                HStack(spacing: 12) {
                    FirstRunDemoArt()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.headline).foregroundStyle(BrandTokens.textPrimary)
                        Text("\(song.artist) · \(song.year)")
                            .font(.subheadline).foregroundStyle(BrandTokens.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .festivalGlass(.card, cornerRadius: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - songs-sort

/// Ported from `pages/songs/firstRun/demo/SortDemo.tsx`: a sort-mode picker with a direction
/// toggle.
struct FirstRunSortDemo: View {
    private let modes = ["Title", "Artist", "Year", "Has FC"]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sort By").font(.caption.weight(.semibold))
                .foregroundStyle(BrandTokens.textSecondary)
            ForEach(modes, id: \.self) { mode in
                HStack {
                    Image(systemName: mode == modes.first ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(
                            mode == modes.first ? BrandTokens.accentBlue : BrandTokens.textMuted
                        )
                    Text(mode).foregroundStyle(BrandTokens.textPrimary)
                    Spacer(minLength: 0)
                }
            }
            HStack {
                Image(systemName: "arrow.up").foregroundStyle(BrandTokens.accentBlue)
                Text("Ascending").foregroundStyle(BrandTokens.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.down").foregroundStyle(BrandTokens.textMuted)
                Text("Descending").foregroundStyle(BrandTokens.textSecondary)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - songs-navigation

/// Ported from `pages/songs/firstRun/demo/NavigationDemo.tsx`: a compact replica of the
/// bottom tab bar.
struct FirstRunNavigationDemo: View {
    private let tabs: [(String, String)] = [
        ("Songs", "music.note.list"), ("Suggestions", "sparkles"),
        ("Statistics", "chart.bar.fill"), ("Settings", "gearshape.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                VStack(spacing: 4) {
                    Image(systemName: tab.1)
                        .font(.title3)
                    Text(tab.0).font(.caption2)
                }
                .foregroundStyle(index == 0 ? BrandTokens.accentBlue : BrandTokens.textMuted)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .festivalGlass(.control, cornerRadius: 18)
        .accessibilityHidden(true)
    }
}

// MARK: - songs-filter

/// Ported from `pages/songs/firstRun/demo/FilterDemo.tsx`: an instrument selector plus a couple
/// of score/FC toggle rows.
struct FirstRunFilterDemo: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach([Instrument.lead, .bass, .drums, .vocals], id: \.self) { instrument in
                    InstrumentIcon(instrument, size: 30)
                        .padding(6)
                        .background(
                            instrument == .lead
                                ? BrandTokens.accentBlue.opacity(0.3) : .clear,
                            in: Circle()
                        )
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                filterRow("Has Score", on: true)
                filterRow("Full Combo", on: false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }

    private func filterRow(_ label: String, on: Bool) -> some View {
        HStack {
            Text(label).foregroundStyle(BrandTokens.textPrimary)
            Spacer(minLength: 0)
            Capsule()
                .fill(on ? BrandTokens.accentBlue : BrandTokens.surfaceMuted)
                .frame(width: 40, height: 24)
                .overlay(
                    Circle().fill(.white).frame(width: 20, height: 20)
                        .offset(x: on ? 8 : -8)
                )
        }
    }
}

// MARK: - songs-icons

/// Ported from `pages/songs/firstRun/demo/SongIconsDemo.tsx`: the instrument status glyphs
/// (full combo, played, unplayed, not charted, inconsistent).
struct FirstRunSongIconsDemo: View {
    private let entries: [(Instrument, String, Color)] = [
        (.lead, "star.fill", BrandTokens.gold),
        (.bass, "checkmark", BrandTokens.statusGreen),
        (.drums, "minus", BrandTokens.textMuted),
        (.vocals, "slash.circle", BrandTokens.textDisabled),
    ]

    var body: some View {
        HStack(spacing: 18) {
            ForEach(entries, id: \.0) { instrument, badge, tint in
                ZStack(alignment: .bottomTrailing) {
                    InstrumentIcon(instrument, size: 40)
                    Image(systemName: badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(tint, in: Circle())
                        .offset(x: 4, y: 4)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - songs-metadata

/// Ported from `pages/songs/firstRun/demo/MetadataDemo.tsx`: the metadata pill row shown when a
/// single instrument is filtered.
struct FirstRunMetadataDemo: View {
    private let pills = ["98.4%", "Top 3%", "Season 5", "★★★★★"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                FirstRunDemoArt()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Neon Skyline").font(.headline).foregroundStyle(BrandTokens.textPrimary)
                    Text("2,481,920").font(.subheadline)
                        .foregroundStyle(BrandTokens.textSecondary)
                }
            }
            HStack(spacing: 8) {
                ForEach(pills, id: \.self) { pill in
                    Text(pill)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTokens.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(BrandTokens.surfaceMuted, in: Capsule())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .festivalGlass(.card, cornerRadius: 16)
        .accessibilityHidden(true)
    }
}

// MARK: - Item Shop badges (songs-shop-highlight / songs-new-in-shop / songs-leaving-tomorrow)

/// The three Item Shop pulse states shown on a Songs card, ported from
/// `ShopHighlightDemo.tsx`, `NewInShopDemo.tsx` and `LeavingTomorrowDemo.tsx`.
struct FirstRunShopBadgeDemo: View {
    enum Kind { case highlight, new, leaving }
    let kind: Kind

    private var tint: Color {
        switch kind {
        case .highlight: BrandTokens.gold
        case .new: BrandTokens.gold
        case .leaving: BrandTokens.statusRed
        }
    }

    private var symbol: String { kind == .leaving ? "clock.fill" : "sparkles" }

    var body: some View {
        HStack(spacing: 12) {
            FirstRunDemoArt()
            VStack(alignment: .leading, spacing: 2) {
                Text("Neon Skyline").font(.headline).foregroundStyle(BrandTokens.textPrimary)
                Text("The Voltage · 2023").font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(kind == .leaving ? BrandTokens.textPrimary : tint)
                .frame(width: 30, height: 30)
                .background(kind == .leaving ? BrandTokens.statusRed : BrandTokens.appBackground, in: Circle())
        }
        .padding(10)
        .festivalGlass(.card, cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint, lineWidth: 2)
        )
        .accessibilityHidden(true)
    }
}
