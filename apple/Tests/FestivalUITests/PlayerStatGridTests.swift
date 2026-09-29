#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Grid layout

@Test func statTileGridSplitsTheCardIntoEqualColumns() {
    let layout = StatTileGridLayout(spacing: 8)
    // iPhone 17 Pro card content width: two 165 pt tiles.
    let phone = layout.metrics(for: 338)
    #expect(phone.columns == 2)
    #expect(phone.tileWidth == 165)
    // A regular-width card: four columns.
    let wide = layout.metrics(for: 640)
    #expect(wide.columns == 4)
    #expect(wide.tileWidth == 154)
    // No proposal: the two-column ideal.
    #expect(layout.metrics(for: nil).columns == 2)
}

@Test func statTileHintsNameTheirDestination() {
    #expect(PlayerStatTileView.hint(for: .songs(.instrument(.hasScores, .lead))) == "Shows these songs in Songs")
    #expect(PlayerStatTileView.hint(for: .songDetail(songId: "pulse", instrument: .lead)) == "Opens the song")
    #expect(PlayerStatTileView.hint(for: .fullRankings(.lead, rankBy: "totalscore")) == "Opens the full rankings")
}

// MARK: - Rank history sizing

@Test func rankHistoryChartWidthComesFromTheCardWidth() {
    #expect(RankHistoryCharts.chartWidth(forCardWidth: 0) == 0)
    #expect(RankHistoryCharts.chartWidth(forCardWidth: 40) == 0)
    // 370 pt card: minus row insets and axis titles.
    #expect(RankHistoryCharts.chartWidth(forCardWidth: 370) == 302)
}

// MARK: - Songs preset store

@MainActor
@Test func songsPresetStoreWritesTheSongsTabsSavedState() throws {
    let suite = "fst.tests.songs-preset.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(SongSortMode.shop.rawValue, forKey: SongsPresetStore.sortModeKey)
    defaults.set(false, forKey: SongsPresetStore.sortAscendingKey)
    defaults.set(true, forKey: SongsPresetStore.filterInShopKey)
    defaults.set(
        try SongPlayerScoreFilter(hasScores: [.bass]).encoded(), forKey: SongPlayerScoreFilter.storageKey
    )

    let saved = SongsPresetStore.apply(
        .instrument(.hasFCs, .lead), visibleInstruments: [.lead, .bass], instrument: nil, defaults: defaults
    )
    #expect(saved.instrument == .lead)
    let reloaded = SongsPresetStore.load(from: defaults, instrument: saved.instrument)
    #expect(reloaded == saved)
    #expect(reloaded.playerFilter == SongPlayerScoreFilter(hasScores: [.bass], hasFCs: [.lead]))
    #expect(reloaded.sortMode == .score && reloaded.sortAscending && reloaded.filterInShop)
}

@MainActor
@Test func songsPresetStoreReplacesACorruptSavedFilter() throws {
    let suite = "fst.tests.songs-preset.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(Data("not json".utf8), forKey: SongPlayerScoreFilter.storageKey)
    // Defaults read as the Songs tab's own defaults.
    #expect(SongsPresetStore.load(from: defaults, instrument: nil) == SongsSavedState())

    SongsPresetStore.apply(
        .overall(.hasScores, visible: [.lead]), visibleInstruments: [.lead], instrument: .drums, defaults: defaults
    )
    let data = try #require(defaults.data(forKey: SongPlayerScoreFilter.storageKey))
    #expect(try SongPlayerScoreFilter.decodeSaved(data) == SongPlayerScoreFilter(hasScores: [.lead]))
}

// MARK: - Hosted tiles

/// Overview-shaped grid: linked tiles (chevrons), plain tiles, gold stars and a
/// loading placeholder, at iPhone width.
@MainActor
@Test func statGridRendersLinkedPlainAndPlaceholderTiles() throws {
    let tiles = [
        StatTile(id: "songs-played", label: "Songs Played", value: "412",
                 link: .songs(.overall(.hasScores, visible: [.lead]))),
        StatTile(id: "full-combos", label: "Full Combos", value: "96 (23.3%)",
                 link: .songs(.overall(.hasFCs, visible: [.lead]))),
        StatTile(id: "gold-stars", label: "Gold Stars", value: "301", tint: BrandTokens.gold),
        StatTile(id: "avg-accuracy", label: "Avg Accuracy", value: "98.2%"),
        StatTile(id: "avg-stars", label: "Avg Stars", value: "6", goldStars: true),
        StatTile(id: "best-rank", label: "Best Rank", value: "#3",
                 link: .songDetail(songId: "pulse", instrument: .lead)),
        StatTile(id: "global-rank", label: "Global Rank", value: "#0,000", isPlaceholder: true),
    ]
    let host = nativeHostedView(
        PlayerStatGrid(tiles: tiles, scope: "overview", onSelect: { _ in })
        .padding(16)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 520)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 520))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "player-stat-grid.png", environment: "FST_PROFILE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}
#endif
