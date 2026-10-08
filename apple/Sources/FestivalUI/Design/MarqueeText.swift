import SwiftUI

// MARK: - Marquee text

/// Auto-scrolling single-line text, native port of the web app's
/// `MarqueeText.tsx`/`MarqueeText.module.css`.
///
/// Renders a plain `Text` when the string fits. When it does not, a two-copy track
/// scrolls left by `textWidth + gap` on a fixed cycle (8 s by default) with a 5%
/// dwell at each end (the web `@keyframes marqueeScroll` 0–5% / 95–100% holds), then
/// jumps back seamlessly and repeats while visible.
///
/// **Layout.** Sized like a plain one-line `Text` (never greedy), so swapping a
/// `Text` for a `MarqueeText` keeps the row layout. A `ViewThatFits` picks the
/// natural one-line text when it fits; otherwise a tail-truncating copy takes the
/// offered width (visible while static, hidden while scrolling) and the scrolling
/// track is drawn in its overlay, so the track never changes the size.
///
/// **Cost.** Nothing here keeps SwiftUI state: no geometry observers, preferences or
/// per-frame updates. A Songs row used to measure both widths with
/// `onGeometryChange` and share them through a preference, so every newly built row
/// laid out again after writing that state (most of the Mac Songs scroll stalls).
/// The track (``MarqueeTrackLayer``) measures and scrolls itself with Core
/// Animation. Nothing animates while the text fits, the window is hidden or the
/// scene inactive, the container turns it off
/// (``SwiftUI/EnvironmentValues/marqueeAnimationEnabled``), or Reduce Motion (system
/// or in-app) is on; those show the tail-truncated text, like the web's
/// `prefers-reduced-motion` ellipsis.
///
/// Also static under `DebugAnimationOverride.stillBackground`
/// (`FST_DEBUG_STILL_BACKGROUND=1`): XCUITest waits for the app to idle before each
/// action, and a forever-repeating animation never idles.
///
/// **Sync.** Inside a ``SwiftUI/View/marqueeSync(gap:)`` container, two or more
/// overflowing marquees scroll the same distance (widest text + gap) so they move
/// in lockstep, like the web's `useMarqueeSync` (song rows and the song header).
///
/// **Accessibility sizes.** The text wraps instead (no scrolling, no truncation)
/// unless ``SwiftUI/EnvironmentValues/marqueeWrapsAtAccessibilitySizes`` is false.
///
/// VoiceOver reads the full, untruncated `text` as one element in every form.
public struct MarqueeText: View {
    private let text: String
    private let font: Font?
    private let gap: CGFloat
    private let cycleDuration: Double

    /// Whether the text overflows its width (from ``MarqueeFitLayout``'s probe).
    @State private var overflows = false
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.festivalWindowVisible) private var windowVisible
    @Environment(\.marqueeSyncGroup) private var syncGroup
    @Environment(\.marqueeAnimationEnabled) private var animationEnabled
    @Environment(\.marqueeWrapsAtAccessibilitySizes) private var wrapsAtAccessibilitySizes
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    /// Create a marquee text view.
    ///
    /// - Parameters:
    ///   - text: Full string to display; VoiceOver always speaks this in full.
    ///   - font: Font for every presentation; nil inherits the environment font, so
    ///     `Text(x).font(f)` call sites can swap to `MarqueeText(x).font(f)` unchanged.
    ///   - gap: Space between the looping copies, in points (web default 28px).
    ///   - cycleDuration: Seconds for one full scroll-and-reset cycle (web default 8s).
    public init(
        _ text: String, font: Font? = nil,
        gap: CGFloat = 28, cycleDuration: Double = 8
    ) {
        self.text = text
        self.font = font
        self.gap = gap
        self.cycleDuration = cycleDuration
    }

    /// Whether an overflowing text may scroll in this environment.
    private var mayScroll: Bool {
        animationEnabled && !reduceMotion && !appReduceMotion
            && AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible)
            && !DebugAnimationOverride.stillBackground
    }

    public var body: some View {
        let text = Text(text)
            .marqueeFont(font)
            .lineLimit(1)
            .truncationMode(.tail)
        Group {
            if wrapsAtAccessibilitySizes, dynamicTypeSize.isAccessibilitySize {
                Text(self.text)
                    .marqueeFont(font)
                    // Overrides a caller's `.lineLimit(1)` (written for the marquee).
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else if mayScroll {
                MarqueeFitLayout {
                    text.opacity(overflows ? 0 : 1)
                    // Proposed a non-zero width only while the text overflows.
                    Color.clear
                        .onGeometryChange(for: Bool.self) { $0.size.width > 0 } action: {
                            overflows = $0
                        }
                }
                .overlay(alignment: .leading) {
                    if overflows { track }
                }
                .clipped()
            } else {
                text
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.text)
        // `.ignore` drops the inner Text's role; keep every branch static text like the
        // wrapped one, so an unwrapped marquee is not an unknown element (macOS AXUnknown).
        .accessibilityAddTraits(.isStaticText)
    }

    /// The Core Animation track, built only for text that overflows.
    private var track: some View {
        MarqueeTrackLayer(
            track: AnyView(Text(text).marqueeFont(font).fixedSize()),
            renderKey: AnyHashable(MarqueeRenderKey(
                text: text, font: font.map { String(describing: $0) } ?? "inherited",
                displayScale: displayScale, dynamicTypeSize: dynamicTypeSize,
                colorScheme: colorScheme
            )),
            gap: gap, cycleDuration: cycleDuration, syncGroup: syncGroup
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Fit layout

/// Sizes like its first child, a one-line tail-truncating `Text` (natural width, or
/// the offered width when narrower), and proposes its second child, a probe, a
/// non-zero width only while that text's natural width overflows the bounds.
///
/// One cached text measurement replaces the former second, fixed-size copy of the
/// text and its geometry observer; the probe's one Bool changes only for text that
/// overflows, so a row whose texts fit is laid out once.
struct MarqueeFitLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let text = subviews.first else { return }
        text.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        guard subviews.count > 1 else { return }
        let natural = text.sizeThatFits(.unspecified).width
        let overflows = MarqueeTiming.overflows(textWidth: natural, available: bounds.width)
        subviews[1].place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: overflows ? 1 : 0, height: 0)
        )
    }
}

private extension View {
    /// Apply an explicit font, or keep the inherited one when nil.
    ///
    /// - Parameter font: Explicit font, if any.
    /// - Returns: The view with its font.
    @ViewBuilder func marqueeFont(_ font: Font?) -> some View {
        if let font { self.font(font) } else { self }
    }
}

/// Re-render identity of a marquee's text bitmap.
private struct MarqueeRenderKey: Hashable {
    let text: String
    let font: String
    let displayScale: CGFloat
    let dynamicTypeSize: DynamicTypeSize
    let colorScheme: ColorScheme
}

// MARK: - Pure timing

/// Cycle math factored out of ``MarqueeText`` so it can be unit tested without a
/// hosted SwiftUI render.
enum MarqueeTiming {
    /// Web keyframe dwell fraction at each end of the cycle (`0%–5%`, `95%–100%`).
    static let dwellFraction = 0.05

    /// Whether measured text is wider than its container (web: more than 1px wider).
    ///
    /// - Parameters:
    ///   - textWidth: Natural single-line width of the text.
    ///   - available: Container width.
    /// - Returns: True only once both are measured and the text does not fit.
    static func overflows(textWidth: CGFloat, available: CGFloat) -> Bool {
        available > 0 && textWidth > available + 1
    }

    /// Scroll distance per cycle: one copy plus the gap, or the sync group's
    /// shared distance when that is longer (web `syncDistance`).
    ///
    /// - Parameters:
    ///   - textWidth: Natural width of this text.
    ///   - gap: Minimum space between copies.
    ///   - syncDistance: Shared distance from a ``SwiftUI/View/marqueeSync(gap:)`` group.
    /// - Returns: Whole-point distance (the web rounds it too).
    static func distance(textWidth: CGFloat, gap: CGFloat, syncDistance: CGFloat?) -> CGFloat {
        max(textWidth + gap, syncDistance ?? 0).rounded()
    }

    /// Shared distance for a sync group: widest overflowing text plus the gap,
    /// only when at least two members overflow (web `useMarqueeSync`).
    ///
    /// - Parameters:
    ///   - widths: Natural widths of the overflowing members.
    ///   - gap: Space between copies.
    /// - Returns: Shared distance, or nil when fewer than two overflow.
    static func syncDistance(widths: [CGFloat], gap: CGFloat) -> CGFloat? {
        let overflowing = widths.filter { $0 > 0 }
        guard overflowing.count >= 2, let widest = overflowing.max() else { return nil }
        return widest + gap
    }

    /// Seconds of linear scrolling per cycle (the 90% between the two dwells).
    ///
    /// - Parameter cycleDuration: Full cycle length.
    /// - Returns: Scroll seconds.
    static func scrollDuration(cycleDuration: Double) -> Double {
        max(0, cycleDuration) * (1 - 2 * dwellFraction)
    }

    /// Seconds held at each end of a cycle.
    ///
    /// - Parameter cycleDuration: Full cycle length.
    /// - Returns: Dwell seconds.
    static func dwellDuration(cycleDuration: Double) -> Double {
        max(0, cycleDuration) * dwellFraction
    }

    /// Position within a repeating cycle, given elapsed absolute time.
    ///
    /// - Parameters:
    ///   - elapsed: Seconds since any fixed epoch.
    ///   - cycleDuration: Seconds for one full cycle; non-positive returns `0`.
    /// - Returns: A value in `0..<1`.
    static func phase(elapsed: TimeInterval, cycleDuration: Double) -> Double {
        guard cycleDuration > 0 else { return 0 }
        let remainder = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return remainder < 0 ? remainder + 1 : remainder
    }

    /// Normalized scroll progress for a phase, holding at each end for
    /// ``dwellFraction`` and scrolling linearly in between (the web keyframe has
    /// only two interior stops, so its interpolation between them is linear).
    ///
    /// - Parameter phase: Position within the cycle, `0..<1`.
    /// - Returns: Normalized scroll progress, `0...1`.
    static func progress(atPhase phase: Double) -> Double {
        if phase <= dwellFraction { return 0 }
        if phase >= 1 - dwellFraction { return 1 }
        return (phase - dwellFraction) / (1 - 2 * dwellFraction)
    }
}

// MARK: - Sync groups

extension EnvironmentValues {
    /// The ``MarqueeSyncGroup`` of the nearest ``SwiftUI/View/marqueeSync(gap:)``.
    @Entry var marqueeSyncGroup: MarqueeSyncGroup?

    /// False holds every ``MarqueeText`` below at rest (tail-truncated). Set it where a
    /// marquee is laid out but not seen, e.g. Song Detail's pinned toolbar title at
    /// opacity 0 while the hero title is visible.
    @Entry var marqueeAnimationEnabled = true

    /// True (default): at accessibility text sizes every ``MarqueeText`` below wraps onto
    /// as many lines as it needs instead of scrolling or truncating (HIG Typography: "Keep
    /// text truncation to a minimum as font size increases ... allowing as many lines as
    /// needed"; the iPad audit found Song Detail's artist cut to "Synthetic Qua…" at
    /// AX5). Set false where the text must stay on one line, e.g. a navigation-bar title.
    @Entry var marqueeWrapsAtAccessibilitySizes = true
}

public extension View {
    /// Scroll every overflowing ``MarqueeText`` inside this view the same distance,
    /// so two or more (e.g. a song's title and artist line) move in lockstep, like
    /// the web's `useMarqueeSync`.
    ///
    /// - Parameter gap: Space between copies (web default 28).
    /// - Returns: The view with a marquee sync group.
    func marqueeSync(gap: CGFloat = 28) -> some View {
        modifier(MarqueeSyncModifier(gap: gap))
    }
}

/// Owns one group for the lifetime of the container; members register themselves.
private struct MarqueeSyncModifier: ViewModifier {
    let gap: CGFloat
    @State private var group = MarqueeSyncGroup()

    func body(content: Content) -> some View {
        content.environment(\.marqueeSyncGroup, group.withGap(gap))
    }
}
