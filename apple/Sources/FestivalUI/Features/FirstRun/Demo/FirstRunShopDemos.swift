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
                ForEach(songs) { song in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            GeometryReader { proxy in
                                FirstRunSongArt(song: song, session: session, size: proxy.size.width)
                            }
                        }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shop row primitive (highlighting / new items / leaving tomorrow)

private struct FirstRunShopRow: View {
    let song: Song
    let session: FestivalSession?
    /// `nil` renders a flat row with no pulse, matching the web's "no highlight" phase.
    let pulseTint: Color?

    var body: some View {
        HStack(spacing: 12) {
            FirstRunSongArt(song: song, session: session)
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(song.title).font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                MarqueeText(song.artist).font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(FestivalText.primary)
            .firstRunRedacted(song)
            Spacer(minLength: 0)
        }
        .padding(10)
        .festivalCard(cornerRadius: 12)
        .modifier(OptionalPulse(tint: pulseTint))
    }
}

private struct OptionalPulse: ViewModifier {
    let tint: Color?
    func body(content: Content) -> some View {
        if let tint { content.firstRunPulse(tint) } else { content }
    }
}

// MARK: - shop-highlighting

/// Ported from `pages/shop/firstRun/demo/ShopHighlightingDemo.tsx`: rows alternate a pulsing
/// green highlight and no highlight, to contrast shop vs. non-shop songs.
struct FirstRunShopHighlightingDemo: View {
    var body: some View {
        FirstRunCatalogueSongs(count: 4, source: .itemShop) { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    FirstRunShopRow(
                        song: song, session: session,
                        pulseTint: index.isMultiple(of: 2) ? BrandTokens.statusGreenStroke : nil
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - shop-new-items

/// Ported from `pages/shop/firstRun/demo/ShopNewItemsDemo.tsx`: rows cycle gold (new), green
/// (regular shop), and no highlight.
struct FirstRunShopNewItemsDemo: View {
    var body: some View {
        FirstRunCatalogueSongs(count: 6, source: .itemShop) { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    FirstRunShopRow(song: song, session: session, pulseTint: tint(for: index))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func tint(for index: Int) -> Color? {
        switch index % 3 {
        case 0: BrandTokens.gold
        case 1: BrandTokens.statusGreenStroke
        default: nil
        }
    }
}

// MARK: - shop-leaving-tomorrow

/// Ported from `pages/shop/firstRun/demo/ShopLeavingTomorrowDemo.tsx`: rows cycle red (leaving),
/// green (regular shop), and no highlight.
struct FirstRunShopLeavingTomorrowDemo: View {
    var body: some View {
        FirstRunCatalogueSongs(count: 6, source: .itemShop) { songs, session in
            VStack(spacing: 8) {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    FirstRunShopRow(song: song, session: session, pulseTint: tint(for: index))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func tint(for index: Int) -> Color? {
        switch index % 3 {
        case 0: BrandTokens.statusRed
        case 1: BrandTokens.statusGreenStroke
        default: nil
        }
    }
}
