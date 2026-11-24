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
        .firstRunDecorative()
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
            .firstRunDecorative()
        if pulsing.isEmpty {
            grid
        } else {
            // Every tile glows (the old shadow traced each tile of the grid).
            grid.environment(\.statTileGlow, BrandTokens.accentBlue)
        }
    }
}

/// Illustrative Statistics data shared by the native guide renderers, independent of the player.
enum FirstRunStatisticsSamples {
    /// Global Statistics tiles, including which examples show drill-down chevrons.
    static var overview: [StatTile] {
        [
            linked("played", "Songs Played", "142 / 206"),
            linked("fc", "Full Combos", "38 (26.8%)"),
            StatTile(id: "gold", label: "Gold Stars", value: "12", tint: BrandTokens.gold),
            StatTile(id: "accuracy", label: "Avg Accuracy", value: "96.2%"),
            linked("best", "Best Rank", "#4"),
            StatTile(id: "avg-stars", label: "Avg Stars", value: "5.2"),
        ]
    }

    /// Lead's per-instrument sample tiles in reading order.
    static var instrument: [StatTile] {
        [
            linked("played", "Played", "98 / 206"),
            linked("fc", "Full Combos", "24 (24.5%)"),
            StatTile(id: "gold", label: "Gold Stars", value: "8", tint: BrandTokens.gold),
            StatTile(id: "accuracy", label: "Avg Accuracy", value: "94.4%"),
        ]
    }

    /// The chevrons in the drill-down illustration mark only the linked sample tiles.
    static var drillDown: [StatTile] {
        [
            linked("played", "Songs Played", "142"),
            StatTile(id: "gold", label: "Gold Stars", value: "12", tint: BrandTokens.gold),
            StatTile(id: "accuracy", label: "Avg Accuracy", value: "96.2%"),
            linked("fc", "Full Combos", "38 (26.8%)"),
        ]
    }

    /// Illustrative top percentages in slot order, unchanged when a song rotates out.
    static let topSongPercentiles = [1.2, 3.5, 7.8, 14.2]

    /// The artist and optional release year for a ranked catalogue example.
    static func topSongSubtitle(_ song: Song) -> String {
        [song.artist, song.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }

    /// A drillable sample tile displays the production chevron.
    static func linked(_ id: String, _ label: String, _ value: String) -> StatTile {
        StatTile(id: id, label: label, value: value, link: .fullRankings(.lead, rankBy: "totalscore"))
    }
}

// MARK: - statistics-drill-down

/// Ported from `pages/player/firstRun/demo/DrillDownDemo.tsx`: the real stat grid where the
/// drillable tiles carry chevrons; the grid pulses to hint they're tappable.
struct FirstRunStatsDrillDownDemo: View {
    var body: some View {
        FirstRunStatTiles(tiles: FirstRunStatisticsSamples.drillDown, pulsing: ["played", "fc"])
            .accessibilityHidden(true)
    }
}

// MARK: - statistics-overview

/// Ported from `pages/player/firstRun/demo/OverviewDemo.tsx`: the global summary stat grid.
struct FirstRunStatsOverviewDemo: View {
    var body: some View {
        FirstRunStatTiles(tiles: FirstRunStatisticsSamples.overview)
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
            FirstRunStatTiles(tiles: FirstRunStatisticsSamples.instrument)
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
        .firstRunDecorative()
    }
}

// MARK: - statistics-top-songs

/// Ported from `pages/player/firstRun/demo/TopSongsDemo.tsx`: real catalogue songs (with their
/// artwork) assigned the web's static demo percentiles; redacted placeholders until the
/// catalogue answers. Two rows swap songs every 5 s, as the web's `useDemoSongs` does.
struct FirstRunStatsTopSongsDemo: View {
    var body: some View {
        let percentiles = FirstRunStatisticsSamples.topSongPercentiles
        FirstRunCatalogueSongs(count: percentiles.count, rotates: true) { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    HStack(spacing: 12) {
                        FirstRunSongArt(song: song, session: session)
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(song.title).font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            MarqueeText(FirstRunStatisticsSamples.topSongSubtitle(song)).font(.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(FestivalText.primary)
                        .firstRunRedacted(song)
                        Spacer(minLength: 0)
                        Text("Top \(percentiles[index], specifier: "%.1f")%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandTokens.gold)
                    }
                    .padding(10)
                    .festivalCard(cornerRadius: 12)
                    .firstRunStagger(index + 1)
                    .firstRunSwapRow(index)
                }
            }
        }
        .firstRunDecorative()
    }
}
