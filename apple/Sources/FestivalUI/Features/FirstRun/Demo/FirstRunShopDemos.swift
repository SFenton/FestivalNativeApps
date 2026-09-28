import SwiftUI
import FestivalDesign

// MARK: - shop-overview

/// Ported from `pages/shop/firstRun/demo/ShopOverviewDemo.tsx`: a grid of Item Shop tiles, using
/// `FirstRunAlbumArtPlaceholder`-style placeholders in place of network album art.
struct FirstRunShopOverviewDemo: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(FirstRunDemoPool.songs) { _ in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(BrandTokens.accentPurple.opacity(0.35))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(BrandTokens.textSecondary)
                    )
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Shop row primitive (highlighting / new items / leaving tomorrow)

private struct FirstRunShopRow: View {
    let song: FirstRunDemoPool.DemoSong
    /// `nil` renders a flat row with no pulse, matching the web's "no highlight" phase.
    let pulseTint: Color?

    var body: some View {
        HStack(spacing: 12) {
            FirstRunAlbumArtPlaceholder()
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                Text(song.artist).font(.caption)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .festivalGlass(.card, cornerRadius: 12)
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
        VStack(spacing: 8) {
            ForEach(Array(FirstRunDemoPool.songs.prefix(4).enumerated()), id: \.element.id) { index, song in
                FirstRunShopRow(song: song, pulseTint: index.isMultiple(of: 2) ? BrandTokens.statusGreenStroke : nil)
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
        VStack(spacing: 8) {
            ForEach(Array(FirstRunDemoPool.songs.prefix(6).enumerated()), id: \.element.id) { index, song in
                FirstRunShopRow(song: song, pulseTint: tint(for: index))
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
        VStack(spacing: 8) {
            ForEach(Array(FirstRunDemoPool.songs.prefix(6).enumerated()), id: \.element.id) { index, song in
                FirstRunShopRow(song: song, pulseTint: tint(for: index))
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
