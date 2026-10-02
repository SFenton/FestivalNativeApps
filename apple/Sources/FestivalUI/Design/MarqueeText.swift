import SwiftUI

// MARK: - Marquee text

/// Auto-scrolling single-line text, native port of the web app's
/// `MarqueeText.tsx`/`MarqueeText.module.css`.
///
/// Renders a plain, tail-truncated `Text` when the string fits. Once the text is
/// measured wider than its container, a two-copy track scrolls left by
/// `textWidth + gap` on a fixed cycle (8 s by default) with a 5% dwell at each
/// end (the web `@keyframes marqueeScroll` 0–5% / 95–100% holds), then jumps back
/// seamlessly and repeats while visible.
///
/// **Layout.** Sized like a plain one-line `Text` (never greedy), so swapping a
/// `Text` for a `MarqueeText` keeps the row layout. The width comes from a
/// truncating copy of the text (the visible text while static, transparent while
/// scrolling), never from the scrolling track: the track is drawn in an overlay,
/// so its full width can never widen the row or feed back into the overflow
/// check. (The previous version measured the container around the track itself, so starting
/// to scroll made the container "fit" again and the view fell back to the static,
/// truncated form: it never visibly scrolled.)
///
/// **Cost.** The scroll is a `phaseAnimator` over an `offset`, so SwiftUI only
/// interpolates one animatable value per frame; no `TimelineView` re-runs a body
/// per frame, and nothing animates while the text fits, is off screen, the scene
/// is inactive, or Reduce Motion (system or in-app) is on. Those fall back to
/// tail truncation, like the web's `prefers-reduced-motion` ellipsis.
///
/// Also static under `DebugAnimationOverride.stillBackground`
/// (`FST_DEBUG_STILL_BACKGROUND=1`): XCUITest waits for the app to idle before each
/// action, and a forever-repeating animation never idles.
///
/// **Sync.** Inside a ``SwiftUI/View/marqueeSync(gap:)`` container, two or more
/// overflowing marquees scroll the same distance (widest text + gap) so they move
/// in lockstep, like the web's `useMarqueeSync` (song rows and the song header).
///
/// VoiceOver reads the full, untruncated `text` as one element in every form.
public struct MarqueeText: View {
    private let text: String
    private let font: Font?
    private let gap: CGFloat
    private let cycleDuration: Double

    @State private var availableWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var isOnScreen = true
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.marqueeSyncDistance) private var syncDistance

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

    private var overflows: Bool {
        MarqueeTiming.overflows(textWidth: textWidth, available: availableWidth)
    }

    private var scrolls: Bool {
        overflows && !reduceMotion && !appReduceMotion && isOnScreen
            && scenePhase == .active && !DebugAnimationOverride.stillBackground
    }

    public var body: some View {
        // Sizing base: one line, tail-truncating, sized exactly like a plain `Text`
        // (its natural width, or the offered width when that is narrower). While
        // static it is also the visible text, so a static row lays out one text
        // fewer; while scrolling it turns transparent (keeping its size) and the
        // track is drawn in the overlay, so the track never changes this size.
        Text(text)
            .marqueeFont(font)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(scrolls ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                availableWidth = width
            }
            .overlay(alignment: .leading) {
                if scrolls { scrollingTrack }
            }
            .clipped()
            .background(alignment: .leading) {
                // Natural (untruncated) width; `.background` never enlarges the view.
                Text(text)
                    .marqueeFont(font)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { width in
                        textWidth = width
                    }
            }
            .preference(key: MarqueeOverflowWidthsKey.self, value: overflows ? [textWidth] : [])
            .onDisappear { isOnScreen = false }
            .onAppear { isOnScreen = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    /// The scrolling two-copy track, shown only while ``scrolls`` is true.
    private var scrollingTrack: some View {
        let distance = MarqueeTiming.distance(
            textWidth: textWidth, gap: gap, syncDistance: syncDistance
        )
        return HStack(spacing: distance - textWidth) {
            Text(text).marqueeFont(font)
            Text(text).marqueeFont(font)
        }
        .fixedSize()
        .phaseAnimator(MarqueePhase.allCases) { track, phase in
            track.offset(x: phase == .scrolled ? -distance : 0)
        } animation: { phase in
            MarqueeTiming.animation(to: phase, cycleDuration: cycleDuration)
        }
        // A new distance or cycle restarts the loop cleanly from the start.
        .id(MarqueeLoopKey(distance: distance, cycleDuration: cycleDuration))
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

/// Restart identity for a marquee loop.
private struct MarqueeLoopKey: Hashable {
    let distance: CGFloat
    let cycleDuration: Double
}

// MARK: - Phases and pure timing

/// The two ends of one marquee cycle.
enum MarqueePhase: CaseIterable {
    /// First copy at the leading edge.
    case rest
    /// Track moved left by one copy (second copy now where the first started).
    case scrolled
}

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

    /// Animation into a phase: hold, then scroll linearly (to `.scrolled`), or
    /// hold, then jump back instantly (to `.rest`), so one loop is exactly
    /// `cycleDuration` long.
    ///
    /// - Parameters:
    ///   - phase: Phase being entered.
    ///   - cycleDuration: Full cycle length.
    /// - Returns: The phase animation.
    static func animation(to phase: MarqueePhase, cycleDuration: Double) -> Animation {
        let dwell = dwellDuration(cycleDuration: cycleDuration)
        switch phase {
        case .scrolled:
            return .linear(duration: scrollDuration(cycleDuration: cycleDuration)).delay(dwell)
        case .rest:
            return .linear(duration: 0.0001).delay(dwell)
        }
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

/// Natural widths of the overflowing marquees below a view.
struct MarqueeOverflowWidthsKey: PreferenceKey {
    static let defaultValue: [CGFloat] = []

    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value.append(contentsOf: nextValue())
    }
}

extension EnvironmentValues {
    /// Shared scroll distance for marquees inside a ``SwiftUI/View/marqueeSync(gap:)`` group.
    @Entry var marqueeSyncDistance: CGFloat?
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

/// Collects overflow widths and hands the shared distance back down.
private struct MarqueeSyncModifier: ViewModifier {
    let gap: CGFloat
    @State private var distance: CGFloat?

    func body(content: Content) -> some View {
        content
            .environment(\.marqueeSyncDistance, distance)
            .onPreferenceChange(MarqueeOverflowWidthsKey.self) { widths in
                let next = MarqueeTiming.syncDistance(widths: widths, gap: gap)
                if next != distance { distance = next }
            }
            // A group is self-contained: its members never join an outer group.
            .transformPreference(MarqueeOverflowWidthsKey.self) { $0 = [] }
    }
}
