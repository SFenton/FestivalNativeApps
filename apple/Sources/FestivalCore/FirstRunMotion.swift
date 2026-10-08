import Foundation

// MARK: - Slide entrance

/// The web first-run carousel's entrance choreography (`FirstRunCarousel.tsx`,
/// `SlideContent`), ported so native slides play the same cascade (issue #380).
///
/// Each time a slide becomes the visible page, the web remounts it: its demo rows cascade in
/// with their own `FadeIn` delays, then the title fades up after `contentStaggerCount`
/// stagger steps and the description one step later. The counts are the web catalogue's
/// per-slide `contentStaggerCount`; a slide without one has no text delay.
public enum FirstRunMotion {
    /// The web's `STAGGER_INTERVAL` between cascade steps, in seconds.
    public static let staggerSeconds: Double = 0.125
    /// Row cascade of leaderboard, rival and Item Shop row demos (web `delay={i * 80}`).
    public static let rowStaggerSeconds: Double = 0.08
    /// Album-art cascade of the Item Shop overview grid (web `delay={i * 60}`).
    public static let tileStaggerSeconds: Double = 0.06
    /// Row cascade of the Rivals detail demo (web `delay={(i + 1) * 100}`).
    public static let detailStaggerSeconds: Double = 0.1
    /// Fade-out of a slide's content as it leaves (web `FAST_FADE_MS` 200 ms ease-in).
    public static let exitSeconds: Double = 0.2

    /// Whether entrances animate.
    ///
    /// - Parameters:
    ///   - reduceMotion: System or app Reduce Motion.
    ///   - stillBackground: The UI-test still-animation override.
    /// - Returns: False shows every slide's content at rest, with no fade or rise.
    public static func entranceAnimates(reduceMotion: Bool, stillBackground: Bool) -> Bool {
        !reduceMotion && !stillBackground
    }

    /// Number of demo cascade steps that play before a slide's title, from the web catalogue
    /// (`pages/*/firstRun/index.ts`, `contentStaggerCount`).
    public static let contentStaggerCounts: [String: Int] = [
        "songs-song-list": 4, "songs-sort": 3, "songs-navigation": 3, "songs-filter": 3,
        "songs-icons": 4, "songs-metadata": 4, "songs-shop-highlight": 3,
        "songs-new-in-shop": 3, "songs-leaving-tomorrow": 3,
        "songinfo-chart": 3, "songinfo-bar-select": 3, "songinfo-view-all": 5,
        "songinfo-top-scores": 6, "songinfo-paths": 3, "songinfo-shop-button": 3,
        "songinfo-new-in-shop": 3, "songinfo-leaving-tomorrow": 3,
        "playerhistory-score-list": 5, "playerhistory-sort": 3,
        "statistics-select-profile": 1, "statistics-drill-down": 2, "statistics-overview": 3,
        "statistics-instrument-breakdown": 3, "statistics-percentiles": 2,
        "statistics-top-songs": 3,
        "suggestions-category-card": 2, "suggestions-global-filter": 3,
        "suggestions-instrument-filter": 3, "suggestions-infinite-scroll": 1,
        "leaderboards-overview": 4, "leaderboards-experimental-metrics": 6,
        "leaderboards-your-rank": 7,
        "compete-hub": 1, "compete-leaderboards": 6, "compete-rivals": 4,
        "rivals-overview": 4, "rivals-instruments": 6, "rivals-detail": 4,
        "shop-overview": 6, "shop-views": 4, "shop-highlighting": 5, "shop-new-items": 5,
        "shop-leaving-tomorrow": 5,
    ]

    /// Delays of a slide's title and description after it becomes visible
    /// (web `<FadeIn delay={contentStaggerCount * STAGGER_INTERVAL}>` and one step more).
    ///
    /// - Parameter slideId: Catalogue slide id.
    /// - Returns: Title and description delays in seconds; 0 and one step for a slide
    ///   without a count, as the web's `0 * STAGGER_INTERVAL`.
    public static func textDelays(slideId: String) -> (title: Double, description: Double) {
        let count = Double(contentStaggerCounts[slideId] ?? 0)
        return (count * staggerSeconds, (count + 1) * staggerSeconds)
    }
}

// MARK: - Auto-scroll

/// The Suggestions "infinite scroll" demo's motion (web `InfiniteScrollDemo.tsx`): the card
/// track glides upward at a constant speed, starts over at the top once its end reaches the
/// viewport's bottom, and the viewport fades whichever edge still hides content.
public enum FirstRunAutoScroll {
    /// Glide speed in points per second (web `SCROLL_SPEED = 30` px/s).
    public static let pointsPerSecond: Double = 30
    /// Pause before the glide starts, in seconds (web 100 ms).
    public static let startDelay: Double = 0.1
    /// Height of each edge fade in points (web `fadeTop`/`fadeBottom`: 36 px, the same
    /// distance as `useScrollFade`'s `DEFAULT_DISTANCE`).
    public static let edgeFade: Double = 36

    /// Which edges of the viewport fade (web `fadeTop`, `fadeBottom`, `fadeBoth`).
    public struct Edges: Equatable, Sendable {
        /// Content is hidden above: fade the top edge.
        public let top: Bool
        /// Content is hidden below: fade the bottom edge.
        public let bottom: Bool

        /// - Parameters:
        ///   - top: Fade the top edge.
        ///   - bottom: Fade the bottom edge.
        public init(top: Bool, bottom: Bool) {
            self.top = top
            self.bottom = bottom
        }
    }

    /// Upward offset of the track at a time since the glide was scheduled.
    ///
    /// - Parameters:
    ///   - elapsed: Seconds since the slide became visible.
    ///   - maxOffset: Track height minus viewport height (0 or less: nothing to scroll).
    /// - Returns: Offset in `0...maxOffset`, wrapping back to 0 at the end like the web's
    ///   `if (offset >= maxOffset) offset = 0`.
    public static func offset(elapsed: Double, maxOffset: Double) -> Double {
        guard maxOffset > 0 else { return 0 }
        let travelled = max(0, elapsed - startDelay) * pointsPerSecond
        return travelled.truncatingRemainder(dividingBy: maxOffset)
    }

    /// The edge fades for a track position (web `atTop = offset <= 0`,
    /// `atBottom = offset >= maxOffset - 1`).
    ///
    /// - Parameters:
    ///   - offset: Current upward offset.
    ///   - maxOffset: Largest offset.
    /// - Returns: No fades when nothing scrolls; otherwise the edges hiding content.
    public static func edges(offset: Double, maxOffset: Double) -> Edges {
        guard maxOffset > 0 else { return Edges(top: false, bottom: false) }
        return Edges(top: offset > 0, bottom: offset < maxOffset - 1)
    }
}
