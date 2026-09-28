import SwiftUI

// MARK: - Marquee text

/// Auto-scrolling single-line text, native port of the web app's
/// `MarqueeText.tsx`/`MarqueeText.module.css`.
///
/// Renders a plain, tail-truncated `Text` when the string fits its container.
/// Once the container is measured narrower than the text, it instead scrolls a
/// two-copy track left on a fixed cycle with a dwell pause at each end (mirroring
/// the web `@keyframes marqueeScroll` 0–5% / 95–100% holds), looping forever while
/// visible. `Reduce Motion` always keeps the static truncated form: the web
/// equivalent turns its animation off under `prefers-reduced-motion: reduce` and
/// falls back to `text-overflow: ellipsis`, which native `.truncationMode(.tail)`
/// already reproduces.
///
/// The scrolling copy is driven by a `TimelineView(.animation)`, which only ticks
/// while this view is actually being drawn — combined with an explicit pause on
/// `onDisappear` (e.g. a `List` row scrolled off-screen) and on the scene going
/// inactive, this keeps no timer running for offscreen or backgrounded instances.
/// VoiceOver reads the full, untruncated `text` as one element regardless of
/// whether the visual form is scrolling or static.
///
/// Also stops under `DebugAnimationOverride.stillBackground`
/// (`FST_DEBUG_STILL_BACKGROUND=1`), the same override the shared artwork
/// background and `FirstRunPulse` honor: a continuously-ticking
/// `TimelineView(.animation)` never lets XCUITest's app-idle wait settle
/// (`.agents/workflow/simulator-driver.md`'s "Simulator queue stall"), and any
/// row whose title/artist/year overflows (e.g. Songs rows, ported 2026-09-28)
/// would otherwise hang every subsequent synthetic action for the rest of the
/// journey — found while investigating `SongsJourneyTests`/`SuggestionsJourneyTests`
/// hangs against the shared simulator.
public struct MarqueeText: View {
    private let text: String
    private let font: Font
    private let gap: CGFloat
    private let cycleDuration: Double

    @State private var availableWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var isOnScreen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// Create a marquee text view.
    ///
    /// - Parameters:
    ///   - text: Full string to display; VoiceOver always speaks this in full.
    ///   - font: Font applied to both the static and scrolling presentations.
    ///   - gap: Space between the looping copies, in points (web default 28px).
    ///   - cycleDuration: Seconds for one full scroll-and-reset cycle (web default 8s).
    public init(
        _ text: String, font: Font = .body,
        gap: CGFloat = 28, cycleDuration: Double = 8
    ) {
        self.text = text
        self.font = font
        self.gap = gap
        self.cycleDuration = cycleDuration
    }

    private var overflows: Bool {
        availableWidth > 0 && textWidth > availableWidth + 0.5
    }

    private var scrolls: Bool {
        overflows && !reduceMotion && isOnScreen && scenePhase == .active
            && !DebugAnimationOverride.stillBackground
    }

    public var body: some View {
        Group {
            if scrolls {
                TimelineView(.animation(paused: false)) { context in
                    let translate = textWidth + gap
                    let phase = cyclePhase(at: context.date)
                    let offset = -translate * dwellCurve(phase)
                    HStack(spacing: gap) {
                        Text(text).font(font).fixedSize()
                        Text(text).font(font).fixedSize()
                    }
                    .offset(x: offset)
                }
            } else {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        // Both measurements ride in `.background`, never a `ZStack` sibling: a
        // `ZStack` sizes itself to the *union* of its children, so a `fixedSize`
        // hidden copy of the full, untruncated text would force this view (and
        // its row) wide enough to fit the whole string — defeating truncation
        // entirely. `.background` content is drawn behind the view above without
        // ever enlarging its reported size, which is exactly what an invisible
        // measuring copy needs.
        .background(
            Text(text).font(font)
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background(WidthReader(width: $textWidth))
        )
        .background(WidthReader(width: $availableWidth))
        .onDisappear { isOnScreen = false }
        .onAppear { isOnScreen = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    /// Elapsed fraction of one scroll cycle, anchored to a fixed epoch so every
    /// marquee on screen stays in phase with each other (mirrors the web's shared
    /// `MARQUEE_EPOCH`, which keeps multiple cards' marquees visually synchronized).
    ///
    /// - Parameter date: Current timeline tick.
    /// - Returns: A value in `0..<1`.
    private func cyclePhase(at date: Date) -> Double {
        MarqueeTiming.phase(
            elapsed: date.timeIntervalSinceReferenceDate, cycleDuration: cycleDuration
        )
    }

    /// Reproduce the web keyframe's 5% dwell at each end with a linear scroll between.
    ///
    /// - Parameter phase: Position within the cycle, `0..<1`.
    /// - Returns: Normalized scroll progress, `0...1`.
    private func dwellCurve(_ phase: Double) -> Double {
        MarqueeTiming.progress(atPhase: phase)
    }
}

// MARK: - Pure timing

/// Cycle math factored out of ``MarqueeText`` so it can be unit tested without a
/// hosted SwiftUI render.
enum MarqueeTiming {
    /// Web keyframe dwell fraction at each end of the cycle (`0%–5%`, `95%–100%`).
    static let dwellFraction = 0.05

    /// Position within a repeating cycle, given elapsed absolute time.
    ///
    /// - Parameters:
    ///   - elapsed: Seconds since any fixed epoch (the view uses
    ///     `Date.timeIntervalSinceReferenceDate`, shared by every instance so
    ///     concurrent marquees stay in phase with each other).
    ///   - cycleDuration: Seconds for one full cycle; non-positive returns `0`.
    /// - Returns: A value in `0..<1`.
    static func phase(elapsed: TimeInterval, cycleDuration: Double) -> Double {
        guard cycleDuration > 0 else { return 0 }
        let remainder = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return remainder < 0 ? remainder + 1 : remainder
    }

    /// Normalized scroll progress for a phase, holding at each end for
    /// ``dwellFraction`` and scrolling linearly in between (the web keyframe has
    /// only two interior stops, so the browser's default interpolation between
    /// them is already linear).
    ///
    /// - Parameter phase: Position within the cycle, `0..<1`.
    /// - Returns: Normalized scroll progress, `0...1`.
    static func progress(atPhase phase: Double) -> Double {
        if phase <= dwellFraction { return 0 }
        if phase >= 1 - dwellFraction { return 1 }
        return (phase - dwellFraction) / (1 - 2 * dwellFraction)
    }
}

/// Reports a view's rendered width without influencing layout.
private struct WidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newValue in width = newValue }
        }
    }
}
