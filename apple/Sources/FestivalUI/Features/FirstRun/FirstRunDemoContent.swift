import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Demo routing

/// Maps a slide id to its native demo preview, mirroring the web's per-slide `render()`.
///
/// Every registered slide across all 9 first-run pages now gets a full live native mini-demo
/// built from real design primitives (`InstrumentIcon`, `festivalCard`, `BrandTokens`, Swift
/// Charts) with static, non-networked sample data — matching the web's own hardcoded first-run
/// demo pools. ``FirstRunStaticIllustration`` remains only as a safety-net fallback for an id
/// that somehow isn't in the catalog; ``hasLiveDemo(id:)`` is unit-tested to confirm every
/// catalog id actually reaches a live demo (see `.agents/controls/first-run/ios.md`).
struct FirstRunDemoContent: View {
    let page: FirstRunPageKey
    let slide: FirstRunSlide

    var body: some View {
        if Self.hasLiveDemo(id: slide.id) {
            liveDemo
        } else {
            FirstRunStaticIllustration(page: page)
        }
    }

    @ViewBuilder
    private var liveDemo: some View {
        switch slide.id {
        // Songs (9) — the app's real Songs UI (batch 7): rows, sheets, tab bar, chips.
        case "songs-song-list": FirstRunNativeSongListDemo()
        case "songs-sort": FirstRunNativeSortDemo()
        case "songs-navigation": FirstRunNativeNavigationDemo()
        case "songs-filter": FirstRunNativeFilterDemo()
        case "songs-icons": FirstRunNativeIconsDemo()
        case "songs-metadata": FirstRunNativeMetadataDemo()
        case "songs-shop-highlight": FirstRunNativeShopDemo(kind: .highlight)
        case "songs-new-in-shop": FirstRunNativeShopDemo(kind: .new)
        case "songs-leaving-tomorrow": FirstRunNativeShopDemo(kind: .leaving)

        // Song Info (8)
        case "songinfo-chart": FirstRunSongInfoChartDemo()
        case "songinfo-bar-select": FirstRunSongInfoBarSelectDemo()
        case "songinfo-view-all": FirstRunSongInfoViewAllDemo()
        case "songinfo-top-scores": FirstRunSongInfoTopScoresDemo()
        case "songinfo-paths": FirstRunSongInfoPathsDemo()
        case "songinfo-shop-button": FirstRunSongInfoShopPillDemo(tone: .shop)
        case "songinfo-new-in-shop": FirstRunSongInfoShopPillDemo(tone: .new)
        case "songinfo-leaving-tomorrow": FirstRunSongInfoShopPillDemo(tone: .leaving)

        // Player History (2)
        case "playerhistory-score-list": FirstRunPlayerHistoryScoreListDemo()
        case "playerhistory-sort": FirstRunPlayerHistorySortDemo()

        // Statistics (6)
        case "statistics-select-profile": FirstRunStatsSelectProfileDemo()
        case "statistics-drill-down": FirstRunStatsDrillDownDemo()
        case "statistics-overview": FirstRunStatsOverviewDemo()
        case "statistics-instrument-breakdown": FirstRunStatsInstrumentBreakdownDemo()
        case "statistics-percentiles": FirstRunStatsPercentilesDemo()
        case "statistics-top-songs": FirstRunStatsTopSongsDemo()

        // Suggestions (4)
        case "suggestions-category-card": FirstRunSuggestionsCategoryCardDemo()
        case "suggestions-global-filter": FirstRunSuggestionsGlobalFilterDemo()
        case "suggestions-instrument-filter": FirstRunSuggestionsInstrumentFilterDemo()
        case "suggestions-infinite-scroll": FirstRunSuggestionsInfiniteScrollDemo()

        // Leaderboards (3)
        case "leaderboards-overview": FirstRunLeaderboardsOverviewDemo()
        case "leaderboards-experimental-metrics": FirstRunLeaderboardsExperimentalMetricsDemo()
        case "leaderboards-your-rank": FirstRunLeaderboardsYourRankDemo()

        // Compete (3)
        case "compete-hub": FirstRunCompeteHubDemo()
        case "compete-leaderboards": FirstRunCompeteLeaderboardsDemo()
        case "compete-rivals": FirstRunCompeteRivalsDemo()

        // Rivals (3)
        case "rivals-overview": FirstRunRivalsOverviewDemo()
        case "rivals-instruments": FirstRunRivalsInstrumentsDemo()
        case "rivals-detail": FirstRunRivalsDetailDemo()

        // Item Shop (4; `shop-views` intentionally not in the catalog — see FirstRunCatalog.swift)
        case "shop-overview": FirstRunShopOverviewDemo()
        case "shop-highlighting": FirstRunShopHighlightingDemo()
        case "shop-new-items": FirstRunShopNewItemsDemo()
        case "shop-leaving-tomorrow": FirstRunShopLeavingTomorrowDemo()

        default: FirstRunStaticIllustration(page: page)
        }
    }

    /// Whether `id` has a live native demo (vs. the static SF Symbol fallback).
    ///
    /// - Parameter id: A `FirstRunSlide.id` from `FirstRunCatalog`.
    /// - Returns: `true` for every currently-registered slide id.
    static func hasLiveDemo(id: String) -> Bool {
        liveDemoIDs.contains(id)
    }

    private static let liveDemoIDs: Set<String> = [
        "songs-song-list", "songs-sort", "songs-navigation", "songs-filter", "songs-icons",
        "songs-metadata", "songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow",
        "songinfo-chart", "songinfo-bar-select", "songinfo-view-all", "songinfo-top-scores",
        "songinfo-paths", "songinfo-shop-button", "songinfo-new-in-shop",
        "songinfo-leaving-tomorrow",
        "playerhistory-score-list", "playerhistory-sort",
        "statistics-select-profile", "statistics-drill-down", "statistics-overview",
        "statistics-instrument-breakdown", "statistics-percentiles", "statistics-top-songs",
        "suggestions-category-card", "suggestions-global-filter",
        "suggestions-instrument-filter", "suggestions-infinite-scroll",
        "leaderboards-overview", "leaderboards-experimental-metrics", "leaderboards-your-rank",
        "compete-hub", "compete-leaderboards", "compete-rivals",
        "rivals-overview", "rivals-instruments", "rivals-detail",
        "shop-overview", "shop-highlighting", "shop-new-items", "shop-leaving-tomorrow",
    ]
}

// MARK: - Static fallback

/// A page-themed icon on a material card, standing in for a live demo where porting the web's
/// interactive preview 1:1 would be disproportionate to a first pass. The slide's real title and
/// description (shown below this view by `FirstRunCarouselView`) carry the actual explanation.
struct FirstRunStaticIllustration: View {
    let page: FirstRunPageKey

    var body: some View {
        Image(systemName: page.firstRunSymbolName)
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(BrandTokens.accentBlue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .festivalCard(cornerRadius: 20)
            .accessibilityHidden(true)
    }
}

extension FirstRunPageKey {
    /// A representative SF Symbol for this page's static first-run illustration.
    var firstRunSymbolName: String {
        switch self {
        case .songs: "music.note.list"
        case .songInfo: "chart.xyaxis.line"
        case .playerHistory: "clock.arrow.circlepath"
        case .statistics: "chart.pie.fill"
        case .suggestions: "sparkles"
        case .leaderboards: "trophy.fill"
        case .compete: "flag.checkered"
        case .rivals: "person.2.fill"
        case .shop: "cart.fill"
        }
    }
}
