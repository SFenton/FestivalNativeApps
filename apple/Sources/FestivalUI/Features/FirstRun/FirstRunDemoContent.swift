import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Demo routing

/// Maps a slide id to its native demo preview, mirroring the web's per-slide `render()`.
///
/// Songs' 9 slides get full live native mini-demos built from real design primitives
/// (`InstrumentIcon`, `festivalGlass`, `BrandTokens`) with static, non-networked sample data —
/// matching the web's own hardcoded first-run demo pools. Every other page currently falls back
/// to ``FirstRunStaticIllustration``; porting each of those remaining ~31 demos 1:1 is tracked
/// as a follow-up (see `.agents/controls/first-run/ios.md`).
struct FirstRunDemoContent: View {
    let page: FirstRunPageKey
    let slide: FirstRunSlide

    var body: some View {
        switch slide.id {
        case "songs-song-list": FirstRunSongListDemo()
        case "songs-sort": FirstRunSortDemo()
        case "songs-navigation": FirstRunNavigationDemo()
        case "songs-filter": FirstRunFilterDemo()
        case "songs-icons": FirstRunSongIconsDemo()
        case "songs-metadata": FirstRunMetadataDemo()
        case "songs-shop-highlight": FirstRunShopBadgeDemo(kind: .highlight)
        case "songs-new-in-shop": FirstRunShopBadgeDemo(kind: .new)
        case "songs-leaving-tomorrow": FirstRunShopBadgeDemo(kind: .leaving)
        default: FirstRunStaticIllustration(page: page)
        }
    }
}

// MARK: - Static fallback

/// A page-themed icon on a glass card, standing in for a live demo where porting the web's
/// interactive preview 1:1 would be disproportionate to a first pass. The slide's real title and
/// description (shown below this view by `FirstRunCarouselView`) carry the actual explanation.
struct FirstRunStaticIllustration: View {
    let page: FirstRunPageKey

    var body: some View {
        Image(systemName: page.firstRunSymbolName)
            .font(.system(size: 64, weight: .semibold))
            .foregroundStyle(BrandTokens.accentBlue)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .festivalGlass(.card, cornerRadius: 20)
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
