import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - statistics-select-profile

/// Ported from `pages/player/firstRun/demo/SelectProfileDemo.tsx`: the player page's header
/// with its real **Select** button (``ProfileIdentityButton``), ringed by the web's 2 s
/// accent `pulseWrap` hint.
struct FirstRunStatsSelectProfileDemo: View {
    var body: some View {
        HStack(spacing: 12) {
            Text(FirstRunDemoPool.rankings[0].name)
                .font(.title2.weight(.bold))
                .foregroundStyle(FestivalText.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            ProfileIdentityButton(action: .select) { _ in }
                .firstRunPulse(BrandTokens.accentBlue, shape: .capsule)
                .firstRunInert()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .festivalCard(cornerRadius: 16)
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
            // The Statistics page's real instrument header (`PlayerProfileContent`).
            InstrumentSectionHeader(.lead, size: .medium)
                .firstRunStagger(0)
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

/// Ported from `pages/player/firstRun/demo/PercentileDemo.tsx`: the Statistics page's real
/// percentile table (``PlayerPercentileTableCard``, percentile pills and Songs chevrons).
struct FirstRunStatsPercentilesDemo: View {
    var body: some View {
        PlayerPercentileTableCard(
            buckets: FirstRunDemoPool.percentileBuckets.map {
                PlayerPercentileBucket(topPercent: $0.percent, count: $0.count)
            },
            instrument: .lead, linkFilter: { $0 }, onSelect: { _ in }
        )
        .firstRunStagger(0)
        .firstRunInert()
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
                    .festivalCard(cornerRadius: 12)
                    .firstRunStagger(index + 1)
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
