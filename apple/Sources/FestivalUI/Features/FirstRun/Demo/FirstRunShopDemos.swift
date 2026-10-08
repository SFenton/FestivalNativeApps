import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - shop-overview

/// Ported from `pages/shop/firstRun/demo/ShopOverviewDemo.tsx`: a grid of Item Shop album-art
/// tiles from current Shop songs (catalogue songs with art as fallback, like the web's
/// `useItemShopDemoSongs`); muted placeholder tiles until the catalogue answers.
struct FirstRunShopOverviewDemo: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        FirstRunCatalogueSongs(count: 6, source: .itemShop) { songs, session in
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            GeometryReader { proxy in
                                FirstRunSongArt(song: song, session: session, size: proxy.size.width)
                            }
                        }
                        // Web `ShopOverviewDemo` `delay={i * 60}`.
                        .firstRunStagger(index, interval: FirstRunMotion.tileStaggerSeconds)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shop rows (highlighting / new items / leaving tomorrow)

/// One phase of the web shop demos' row cycle (`ShopHighlightingDemo`, `ShopNewItemsDemo`,
/// `ShopLeavingTomorrowDemo`).
enum FirstRunShopRowPhase: Equatable {
    /// No highlight.
    case plain
    /// In the shop: green pulse.
    case inShop
    /// New or leaving tomorrow: gold or red pulse.
    case highlighted(ShopHighlight)

    /// The phases the web demo cycles each row through by index.
    ///
    /// - Parameters:
    ///   - index: Row position.
    ///   - highlight: The slide's badge (`nil`: the highlighting slide's green/plain pairs).
    /// - Returns: `index % 2` green/plain without a badge; otherwise `index % 3`
    ///   badge/green/plain.
    static func phase(at index: Int, highlight: ShopHighlight?) -> Self {
        guard let highlight else { return index.isMultiple(of: 2) ? .inShop : .plain }
        switch index % 3 {
        case 0: return .highlighted(highlight)
        case 1: return .inShop
        default: return .plain
        }
    }
}

/// The Songs/Item Shop list's real rows (``FirstRunSongRow`` over ``SongRowView``) in the
/// web demo's highlight cycle, cascading in 80 ms apart like its `FadeIn delay={i * 80}`.
private struct FirstRunShopRows: View {
    let count: Int
    /// The slide's badge, or nil for the plain highlighting slide.
    let highlight: ShopHighlight?

    var body: some View {
        FirstRunCatalogueSongs(count: count, source: .itemShop) { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    let phase = FirstRunShopRowPhase.phase(at: index, highlight: highlight)
                    FirstRunSongRow(
                        song: song, session: session,
                        highlight: { if case let .highlighted(badge) = phase { badge } else { nil } }(),
                        inShop: phase != .plain
                    )
                    .firstRunStagger(index, interval: FirstRunMotion.rowStaggerSeconds)
                }
            }
        }
        .firstRunInert()
    }
}

// MARK: - shop-highlighting

/// Ported from `pages/shop/firstRun/demo/ShopHighlightingDemo.tsx`: rows alternate a pulsing
/// green highlight and no highlight, to contrast shop vs. non-shop songs.
struct FirstRunShopHighlightingDemo: View {
    var body: some View {
        FirstRunShopRows(count: 4, highlight: nil)
    }
}

// MARK: - shop-new-items

/// Ported from `pages/shop/firstRun/demo/ShopNewItemsDemo.tsx`: rows cycle gold (new), green
/// (regular shop), and no highlight.
struct FirstRunShopNewItemsDemo: View {
    var body: some View {
        FirstRunShopRows(count: 6, highlight: .new)
    }
}

// MARK: - shop-leaving-tomorrow

/// Ported from `pages/shop/firstRun/demo/ShopLeavingTomorrowDemo.tsx`: rows cycle red (leaving),
/// green (regular shop), and no highlight.
struct FirstRunShopLeavingTomorrowDemo: View {
    var body: some View {
        FirstRunShopRows(count: 6, highlight: .leavingTomorrow)
    }
}
