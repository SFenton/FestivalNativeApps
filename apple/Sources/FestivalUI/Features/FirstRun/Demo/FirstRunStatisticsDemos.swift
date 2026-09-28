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
        .foregroundStyle(BrandTokens.textPrimary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(BrandTokens.accentPurple.opacity(0.8), in: Capsule())
        .firstRunPulse(BrandTokens.accentPurple)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Stat card primitive (shared by drill-down / overview / instrument breakdown)

private struct FirstRunStatCard: View {
    let label: String
    let value: String
    var tint: Color = BrandTokens.textPrimary
    var chevron = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(BrandTokens.textSecondary)
                Spacer(minLength: 0)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrandTokens.textMuted)
                }
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 78)
        .festivalGlass(.card, cornerRadius: 12)
    }
}

private let twoColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

// MARK: - statistics-drill-down

/// Ported from `pages/player/firstRun/demo/DrillDownDemo.tsx`: a 2-column stat grid where the
/// drillable cards (Songs Played, Full Combos) pulse to hint they're tappable.
struct FirstRunStatsDrillDownDemo: View {
    var body: some View {
        LazyVGrid(columns: twoColumns, spacing: 10) {
            FirstRunStatCard(label: "Songs Played", value: "142", chevron: true)
                .firstRunPulse(BrandTokens.accentBlue)
            FirstRunStatCard(label: "Gold Stars", value: "12", tint: BrandTokens.gold)
            FirstRunStatCard(label: "Avg Accuracy", value: "96.2%")
            FirstRunStatCard(label: "Full Combos", value: "38 (26.8%)", chevron: true)
                .firstRunPulse(BrandTokens.accentBlue)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - statistics-overview

/// Ported from `pages/player/firstRun/demo/OverviewDemo.tsx`: the global summary stat grid.
struct FirstRunStatsOverviewDemo: View {
    var body: some View {
        LazyVGrid(columns: twoColumns, spacing: 10) {
            FirstRunStatCard(label: "Songs Played", value: "142 / 206", chevron: true)
            FirstRunStatCard(label: "Full Combos", value: "38 (26.8%)", chevron: true)
            FirstRunStatCard(label: "Gold Stars", value: "12", tint: BrandTokens.gold)
            FirstRunStatCard(label: "Avg Accuracy", value: "96.2%")
            FirstRunStatCard(label: "Best Rank", value: "#4", chevron: true)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - statistics-instrument-breakdown

/// Ported from `pages/player/firstRun/demo/InstrumentBreakdownDemo.tsx`: one instrument's stat
/// cards, headed by its instrument icon.
struct FirstRunStatsInstrumentBreakdownDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FirstRunInstrumentHeader(instrument: .lead)
            LazyVGrid(columns: twoColumns, spacing: 10) {
                FirstRunStatCard(label: "Played", value: "98 / 206", chevron: true)
                FirstRunStatCard(label: "Full Combos", value: "24 (24.5%)", chevron: true)
                FirstRunStatCard(label: "Gold Stars", value: "8", tint: BrandTokens.gold)
                FirstRunStatCard(label: "Avg Accuracy", value: "94.4%")
            }
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
            .foregroundStyle(BrandTokens.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            ForEach(Array(FirstRunDemoPool.percentileBuckets.enumerated()), id: \.element.id) { index, bucket in
                HStack {
                    Text("Top \(bucket.percent)%")
                        .font(.subheadline)
                        .foregroundStyle(BrandTokens.textPrimary)
                    Spacer()
                    Text("\(bucket.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(BrandTokens.textPrimary)
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

/// Ported from `pages/player/firstRun/demo/TopSongsDemo.tsx`: a player's highest-percentile
/// songs, using `FirstRunAlbumArtPlaceholder` in place of network album art.
struct FirstRunStatsTopSongsDemo: View {
    private let percentiles = [1.2, 3.5, 7.8, 14.2]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(FirstRunDemoPool.songs.prefix(4).enumerated()), id: \.element.id) { index, song in
                HStack(spacing: 12) {
                    FirstRunAlbumArtPlaceholder()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrandTokens.textPrimary)
                        Text(song.artist).font(.caption)
                            .foregroundStyle(BrandTokens.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text("Top \(percentiles[index], specifier: "%.1f")%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrandTokens.gold)
                }
                .padding(10)
                .festivalGlass(.card, cornerRadius: 12)
                .firstRunStagger(index)
            }
        }
        .accessibilityHidden(true)
    }
}
