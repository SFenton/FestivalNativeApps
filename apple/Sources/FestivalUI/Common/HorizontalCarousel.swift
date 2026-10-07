import SwiftUI
import FestivalDesign

// MARK: - Paging logic

/// Pure paging rules for ``HorizontalCarousel`` (unit-tested in `HorizontalCarouselTests`).
enum CarouselPaging {
    /// Most cards visible side by side, however wide the region.
    static let maximumColumns = 3
    /// Largest item count shown as dots; longer carousels show "n of N".
    static let maximumDots = 10
    /// Load the next page once a card this close to the end appears.
    static let loadMoreThreshold = 2
    /// Gap between cards, in points.
    static let spacing: CGFloat = 12
    /// Leading/trailing content margin, in points.
    static let margin: CGFloat = 16

    /// How many cards fit side by side.
    ///
    /// - Parameters:
    ///   - width: Carousel width in points.
    ///   - minimumCardWidth: Narrowest readable card.
    ///   - spacing: Gap between cards.
    ///   - margin: Leading/trailing content margin.
    /// - Returns: At least one, at most ``maximumColumns``.
    static func columns(width: CGFloat, minimumCardWidth: CGFloat, spacing: CGFloat, margin: CGFloat) -> Int {
        let usable = width - margin * 2
        guard usable > 0, minimumCardWidth > 0 else { return 1 }
        let fit = Int(((usable + spacing) / (minimumCardWidth + spacing)).rounded(.down))
        return min(max(fit, 1), maximumColumns)
    }

    /// How many cards a ``HorizontalCarousel`` of this width shows side by side, with its
    /// own spacing and margins.
    ///
    /// - Parameters:
    ///   - width: Carousel width in points.
    ///   - minimumCardWidth: Narrowest readable card.
    /// - Returns: At least one, at most ``maximumColumns``.
    static func columns(width: CGFloat, minimumCardWidth: CGFloat) -> Int {
        columns(width: width, minimumCardWidth: minimumCardWidth, spacing: spacing, margin: margin)
    }

    /// The page an adjustable (VoiceOver swipe up/down) or button step lands on.
    ///
    /// - Parameters:
    ///   - index: Current page.
    ///   - count: Pages loaded.
    ///   - forward: True for next, false for previous.
    /// - Returns: The new page, clamped to the loaded range (no wrap: VoiceOver users
    ///   should hear the ends).
    static func step(from index: Int, count: Int, forward: Bool) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + (forward ? 1 : -1), 0), count - 1)
    }

    /// Whether a card appearing should request the next page of an endless source.
    ///
    /// - Parameters:
    ///   - index: Index of the card that appeared.
    ///   - count: Cards loaded.
    ///   - hasMore: Whether the source can produce more.
    /// - Returns: True within ``loadMoreThreshold`` of the end.
    static func shouldLoadMore(appearing index: Int, count: Int, hasMore: Bool) -> Bool {
        hasMore && count > 0 && index >= count - 1 - loadMoreThreshold
    }

    /// Whether the indicator draws dots (short, finite carousels) or a counter.
    ///
    /// - Parameters:
    ///   - count: Cards loaded.
    ///   - hasMore: Whether more may load.
    /// - Returns: True for 2…``maximumDots`` finite cards.
    static func usesDots(count: Int, hasMore: Bool) -> Bool {
        !hasMore && count > 1 && count <= maximumDots
    }

    /// Visible counter text ("3 / 12", "3 / 12+").
    ///
    /// - Parameters:
    ///   - index: Current page.
    ///   - count: Cards loaded.
    ///   - hasMore: Whether more may load.
    /// - Returns: Short counter.
    static func counter(index: Int, count: Int, hasMore: Bool) -> String {
        "\(min(index + 1, max(count, 1))) / \(count)\(hasMore ? "+" : "")"
    }

    /// VoiceOver value for the adjustable page indicator.
    ///
    /// - Parameters:
    ///   - index: Current page.
    ///   - count: Cards loaded.
    ///   - hasMore: Whether more may load.
    /// - Returns: "Page 3 of 12" (", more available" for an endless source).
    static func accessibilityValue(index: Int, count: Int, hasMore: Bool) -> String {
        let page = "Page \(min(index + 1, max(count, 1))) of \(count)"
        return hasMore ? page + ", more available" : page
    }
}

// MARK: - Carousel

/// A horizontally swipeable, snapping row of cards for a dual-source secondary region
/// (and anywhere else a short set of peers reads better side by side).
///
/// - Snaps card by card (`.viewAligned`); as many cards as fit at `minimumCardWidth`
///   show side by side (one on the outer display, two on the inner display).
/// - Each card fills the carousel's height and scrolls vertically when taller.
/// - Endless sources pass `hasMore` and `onNearEnd` to load the next page as the
///   player approaches the last card.
/// - VoiceOver: cards stay individually navigable; the page indicator is one
///   adjustable element ("Suggestions, Page 3 of 12") that pages with swipe up/down.
/// - Reduce Motion (system or the app's setting): programmatic paging jumps without
///   animation.
/// - Entrance: the carousel fades in when it appears; with `entranceIndex`, inside a page's
///   fade scope, its cards instead fade in on the page's reading-order stagger, and a
///   swipe (or a card's own scroll) rushes the page's pending fades like a page scroll
///   (load-transition R5).
struct HorizontalCarousel<Item: Identifiable, Card: View>: View {
    private let title: String
    private let items: [Item]
    private let minimumCardWidth: CGFloat
    private let hasMore: Bool
    private let onNearEnd: (() -> Void)?
    private let entranceIndex: Int?
    private let card: (Item) -> Card

    @State private var position: Item.ID?
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false

    private let spacing = CarouselPaging.spacing
    private let margin = CarouselPaging.margin

    /// Create a carousel.
    ///
    /// - Parameters:
    ///   - title: Spoken name of the carousel (the page indicator's label).
    ///   - items: Cards, in order.
    ///   - minimumCardWidth: Narrowest card; decides how many show side by side.
    ///   - hasMore: True while an endless source can load more.
    ///   - onNearEnd: Called when a card near the end appears (load the next page).
    ///   - entranceIndex: The first card's position in the page's first-load stagger
    ///     (card `n` fades at `entranceIndex + n`, the indicator with the first card), or
    ///     nil to fade the whole carousel in when it appears.
    ///   - card: Builds one card's content (the carousel adds no card chrome, so pass
    ///     `FestivalGlassSection` or `festivalCard` cards).
    init(
        _ title: String, items: [Item], minimumCardWidth: CGFloat = 300,
        hasMore: Bool = false, onNearEnd: (() -> Void)? = nil, entranceIndex: Int? = nil,
        @ViewBuilder card: @escaping (Item) -> Card
    ) {
        self.title = title
        self.items = items
        self.minimumCardWidth = minimumCardWidth
        self.hasMore = hasMore
        self.onNearEnd = onNearEnd
        self.entranceIndex = entranceIndex
        self.card = card
    }

    private var columns: Int {
        CarouselPaging.columns(width: width, minimumCardWidth: minimumCardWidth, spacing: spacing, margin: margin)
    }

    private var index: Int {
        position.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
    }

    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    /// `fst.carousel.<title-slug>`, e.g. `fst.carousel.item-shop-picks` (UI automation).
    private var scrollIdentifier: String {
        "fst.carousel." + title.lowercased().split(separator: " ").joined(separator: "-")
    }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        ScrollView(.vertical) {
                            card(item)
                                .frame(maxWidth: .infinity, alignment: .top)
                                .festivalFadeInRushOnScroll(.vertical)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                        .festivalFadeIn(staggerIndex: entranceIndex.map { $0 + offset })
                        .containerRelativeFrame(.horizontal, count: columns, span: 1, spacing: spacing)
                        .onAppear {
                            if CarouselPaging.shouldLoadMore(appearing: offset, count: items.count, hasMore: hasMore) {
                                onNearEnd?()
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .festivalFadeInRushOnScroll(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position)
            .contentMargins(.horizontal, margin, for: .scrollContent)
            // Keep peeking cards out of the safe area (the Duo vertical bar): a
            // horizontal scroll view otherwise draws its content under it.
            .clipped()
            .accessibilityIdentifier(scrollIdentifier)
            .modifier(CarouselTrackEntrance(staggersCards: entranceIndex != nil))
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width.rounded() }) { width = $0 }

            if items.count > columns || hasMore {
                indicator
                    .festivalFadeIn(staggerIndex: entranceIndex)
            }
        }
    }

    // MARK: Indicator

    private var indicator: some View {
        HStack(spacing: 6) {
            if CarouselPaging.usesDots(count: items.count, hasMore: hasMore) {
                ForEach(0..<items.count, id: \.self) { dot in
                    Circle()
                        .fill(dot == index ? BrandTokens.textPrimary : BrandTokens.textPrimary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            } else {
                Text(CarouselPaging.counter(index: index, count: items.count, hasMore: hasMore))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BrandTokens.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 16)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(CarouselPaging.accessibilityValue(index: index, count: items.count, hasMore: hasMore))
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page(forward: true)
            case .decrement: page(forward: false)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("fst.carousel.indicator")
    }

    /// Move one card, honoring Reduce Motion.
    ///
    /// - Parameter forward: True for the next card.
    private func page(forward: Bool) {
        let target = CarouselPaging.step(from: index, count: items.count, forward: forward)
        guard items.indices.contains(target) else { return }
        if reduceMotion {
            position = items[target].id
        } else {
            withAnimation(.smooth) { position = items[target].id }
        }
    }
}

// MARK: - Entrance

/// The carousel track's own fade: the whole track when it appears, or none when its cards
/// carry the page's staggered entrances.
private struct CarouselTrackEntrance: ViewModifier {
    let staggersCards: Bool

    func body(content: Content) -> some View {
        if staggersCards {
            content
        } else {
            content.festivalFadeInOnAppear()
        }
    }
}
