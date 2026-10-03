import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - statistics-select-profile

/// Ported from `pages/player/firstRun/demo/SelectProfileDemo.tsx`: the pulsing "select this
/// player" pill from the page header.
struct FirstRunStatsSelectProfileDemo: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.checkmark")
            Text("Select This Player").font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(FestivalText.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(BrandTokens.accentPurple.opacity(0.8), in: Capsule())
        .firstRunPulse(BrandTokens.accentPurple, shape: .capsule)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Real stat tiles (operator batch 7)

/// The Statistics page's real `PlayerStatGrid` over sample tiles; a tile with a link shows
/// the in-tile chevron exactly as the page does. Taps are ignored (demos are inert).
private struct FirstRunStatTiles: View {
    let tiles: [StatTile]
    var pulsing: Set<String> = []

    @ViewBuilder var body: some View {
        let grid = PlayerStatGrid(tiles: tiles, scope: "first-run") { _ in }
            .allowsHitTesting(false)
        if pulsing.isEmpty {
            grid
        } else {
            // Every tile glows (the old shadow traced each tile of the grid).
            grid.environment(\.statTileGlow, BrandTokens.accentBlue)
        }
    }

    /// A drillable tile (chevron), like Songs Played / Full Combos / Best Rank.
    static func linked(_ id: String, _ label: String, _ value: String) -> StatTile {
        StatTile(id: id, label: label, value: value, link: .fullRankings(.lead, rankBy: "totalscore"))
    }
}

// MARK: - statistics-drill-down

/// Ported from `pages/player/firstRun/demo/DrillDownDemo.tsx`: the real stat grid where the
/// drillable tiles carry chevrons; the grid pulses to hint they're tappable.
struct FirstRunStatsDrillDownDemo: View {
    var body: some View {
        FirstRunStatTiles(tiles: [
            FirstRunStatTiles.linked("played", "Songs Played", "142"),
            StatTile(id: "gold", label: "Gold Stars", value: "12", tint: BrandTokens.gold),
            StatTile(id: "accuracy", label: "Avg Accuracy", value: "96.2%"),
            FirstRunStatTiles.linked("fc", "Full Combos", "38 (26.8%)"),
        ], pulsing: ["played", "fc"])
        .accessibilityHidden(true)
    }
}

// MARK: - statistics-overview

/// Ported from `pages/player/firstRun/demo/OverviewDemo.tsx`: the global summary stat grid.
struct FirstRunStatsOverviewDemo: View {
    var body: some View {
        FirstRunStatTiles(tiles: [
            FirstRunStatTiles.linked("played", "Songs Played", "142 / 206"),
            FirstRunStatTiles.linked("fc", "Full Combos", "38 (26.8%)"),
            StatTile(id: "gold", label: "Gold Stars", value: "12", tint: BrandTokens.gold),
            StatTile(id: "accuracy", label: "Avg Accuracy", value: "96.2%"),
            FirstRunStatTiles.linked("best", "Best Rank", "#4"),
            StatTile(id: "avg-stars", label: "Avg Stars", value: "5.2"),
        ])
        .accessibilityHidden(true)
    }
}

// MARK: - statistics-instrument-breakdown

/// Ported from `pages/player/firstRun/demo/InstrumentBreakdownDemo.tsx`: one instrument's real
/// stat tiles under its header.
struct FirstRunStatsInstrumentBreakdownDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FirstRunInstrumentHeader(instrument: .lead)
            FirstRunStatTiles(tiles: [
                FirstRunStatTiles.linked("played", "Played", "98 / 206"),
                FirstRunStatTiles.linked("fc", "Full Combos", "24 (24.5%)"),
                StatTile(id: "gold", label: "Gold Stars", value: "8", tint: BrandTokens.gold),
                StatTile(id: "accuracy", label: "Avg Accuracy", value: "94.4%"),
            ])
        }
        .accessibilityHidden(true)
    }
}

// MARK: - statistics-percentiles

/// Ported from `pages/player/firstRun/demo/PercentileDemo.tsx`: the percentile distribution
/// table, echoing `PlayerPercentileHeader`/`Row`'s two-column layout.
struct FirstRunStatsPercentilesDemo: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Percentile").font(.caption.weight(.semibold))
                Spacer()
                Text("Songs").font(.caption.weight(.semibold))
            }
            .foregroundStyle(FestivalText.primary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            ForEach(Array(FirstRunDemoPool.percentileBuckets.enumerated()), id: \.element.id) { index, bucket in
                HStack {
                    Text("Top \(bucket.percent)%")
                        .font(.subheadline)
                        .foregroundStyle(FestivalText.primary)
                    Spacer()
                    Text("\(bucket.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(FestivalText.primary)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .firstRunStagger(index)
                Divider().overlay(BrandTokens.borderSubtle)
            }
        }
        .festivalGlass(.card, cornerRadius: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - statistics-top-songs

/// Ported from `pages/player/firstRun/demo/TopSongsDemo.tsx`: real catalogue songs (with their
/// artwork) assigned the web's static demo percentiles; redacted placeholders until the
/// catalogue answers. Two rows swap songs every 5 s, as the web's `useDemoSongs` does.
struct FirstRunStatsTopSongsDemo: View {
    /// The web's `DEMO_PERCENTILES`.
    private static let percentiles = [1.2, 3.5, 7.8, 14.2, 22.6, 35.1, 48.9]

    var body: some View {
        FirstRunCatalogueSongs(count: 4, rotates: true) { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    HStack(spacing: 12) {
                        FirstRunSongArt(song: song, session: session)
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(song.title).font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            MarqueeText(Self.subtitle(song)).font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(FestivalText.primary)
                        .firstRunRedacted(song)
                        Spacer(minLength: 0)
                        Text("Top \(Self.percentiles[index % Self.percentiles.count], specifier: "%.1f")%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandTokens.gold)
                    }
                    .padding(10)
                    .festivalGlass(.card, cornerRadius: 12)
                    .firstRunStagger(index)
                    .firstRunSwapRow(index, key: song.id)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// "Artist · Year", like the web's `PlayerSongRow`.
    private static func subtitle(_ song: Song) -> String {
        [song.artist, song.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }
}
