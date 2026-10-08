import SwiftUI
import FestivalCore

// MARK: - Environment

extension EnvironmentValues {
    /// Whether this demo's slide is the carousel's visible page in an active scene.
    ///
    /// The paged `TabView` mounts every slide, so demos rotate their data only while this is
    /// true (set by ``FirstRunCarouselView``); false elsewhere (hosted tests, previews), where
    /// demos stay on their first state.
    @Entry var firstRunDemoActive = false
    /// Positions (rows or groups) of the enclosing demo currently faded out for a swap; read
    /// by ``SwiftUI/View/firstRunSwapRow(_:rise:)``.
    @Entry var firstRunFadingRows: Set<Int> = []
    /// Swaps the enclosing ``FirstRunCatalogueSongs`` has completed, for demos whose other
    /// content advances with each swap (the web Rivals detail demo's category header).
    @Entry var firstRunSwapTick = 0
}

// MARK: - Fade curve

extension Animation {
    /// The web demos' swap fade, CSS `opacity 400ms ease` (`cubic-bezier(0.25, 0.1, 0.25, 1)`).
    ///
    /// - Parameter seconds: Fade duration; the web's `FADE_DURATION` by default.
    /// - Returns: The matching timing curve.
    static func firstRunFade(_ seconds: Double = FirstRunDemoTiming.fadeSeconds) -> Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: seconds)
    }
}

// MARK: - Reduce Motion

/// The guide's one Reduce Motion value: the system setting or the app's own
/// (`fst.accessibility.reduceMotion`), so every demo stops motion for either (issue #380,
/// load-transition R6).
@propertyWrapper
struct FirstRunReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @AppStorage("fst.accessibility.reduceMotion") private var app = false

    init() {}

    /// True when the system or the app asks for reduced motion.
    var wrappedValue: Bool { system || app }
}

// MARK: - Ticker

/// When a demo's swap clock may tick.
enum FirstRunDemoTickerPolicy {
    /// Whether the ticker runs.
    ///
    /// - Parameters:
    ///   - active: The demo's slide is the visible page in an active scene.
    ///   - enabled: The demo has something to rotate.
    ///   - constrained: The demo loads album art and Low Data Mode is on.
    ///   - reduceMotion: System or app Reduce Motion; the demo then rests on its first state,
    ///     as HIG Accessibility asks ("reduce automatic and repetitive animation").
    ///   - stillBackground: Debug override freezing decorative motion.
    /// - Returns: True only when nothing holds the demo still.
    static func runs(
        active: Bool, enabled: Bool, constrained: Bool, reduceMotion: Bool, stillBackground: Bool
    ) -> Bool {
        active && enabled && !constrained && !reduceMotion && !stillBackground
    }
}

/// Calls `tick` every `interval` while the demo's slide is visible and active, standing in
/// for the web demos' `setInterval`. Never runs off-screen, in the background, under Reduce
/// Motion (system or app), under the Debug still-animation override
/// (`FST_DEBUG_STILL_BACKGROUND=1`, so XCUITest can idle) or, for demos that load album art,
/// under Low Data Mode.
private struct FirstRunDemoTicker: ViewModifier {
    let interval: Duration
    let enabled: Bool
    let usesArtwork: Bool
    let tick: @MainActor @Sendable () async -> Void
    @Environment(\.firstRunDemoActive) private var active
    @FirstRunReduceMotion private var reduceMotion

    func body(content: Content) -> some View {
        let running = FirstRunDemoTickerPolicy.runs(
            active: active, enabled: enabled,
            constrained: usesArtwork && ArtworkNetworkStatus.shared.isConstrained,
            reduceMotion: reduceMotion, stillBackground: DebugAnimationOverride.stillBackground
        )
        content.task(id: running) {
            guard running else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                await tick()
            }
        }
    }
}

extension View {
    /// Run `tick` on the web demos' swap clock while this demo's slide is the visible page.
    ///
    /// - Parameters:
    ///   - interval: Time between ticks; the web's 5 s `DEMO_SWAP_INTERVAL_MS` by default.
    ///   - enabled: False to stop ticking (e.g. nothing to rotate yet).
    ///   - usesArtwork: Whether ticks show new album art; pauses under Low Data Mode.
    ///   - tick: The swap to run; awaited before the next interval starts.
    /// - Returns: The view, ticking while active.
    func firstRunDemoTicker(
        every interval: Duration = FirstRunDemoTiming.swapInterval, enabled: Bool = true,
        usesArtwork: Bool = false, _ tick: @escaping @MainActor @Sendable () async -> Void
    ) -> some View {
        modifier(FirstRunDemoTicker(interval: interval, enabled: enabled, usesArtwork: usesArtwork, tick: tick))
    }
}

// MARK: - Swap

/// The web demos' swap sequence: fade the changing rows out, replace their data while
/// invisible, fade them back in.
@MainActor
enum FirstRunDemoSwap {
    /// Perform one swap.
    ///
    /// The ticker never runs under Reduce Motion, so demos rest on their first state; should a
    /// swap still be asked for then, the data changes at once with no fade or rise.
    ///
    /// - Parameters:
    ///   - reduceMotion: System or app Reduce Motion (``FirstRunReduceMotion``).
    ///   - seconds: Each fade's duration; the web's 400 ms by default.
    ///   - fadeOut: Marks the changing rows faded (animated).
    ///   - update: Changes the data (not animated, except as the Reduce Motion cross-fade).
    ///   - fadeIn: Clears the faded rows (animated).
    static func run(
        reduceMotion: Bool, seconds: Double = FirstRunDemoTiming.fadeSeconds,
        fadeOut: () -> Void, update: () -> Void, fadeIn: () -> Void
    ) async {
        var instant = Transaction()
        instant.disablesAnimations = true
        if reduceMotion {
            withTransaction(instant) { update() }
            return
        }
        withAnimation(.firstRunFade(seconds)) { fadeOut() }
        // A cancelled sleep (the page left mid-fade) still completes the swap, so rows are
        // never left hidden.
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1_000)))
        withTransaction(instant) { update() }
        withAnimation(.firstRunFade(seconds)) { fadeIn() }
    }
}

// MARK: - Swapping row

/// Fades a demo row (or group) out while its position is in ``EnvironmentValues/firstRunFadingRows``.
/// Under Reduce Motion (system or app) the row is shown as is, with no fade, rise or transition.
private struct FirstRunSwapRow: ViewModifier {
    let slot: Int
    let rise: CGFloat
    @Environment(\.firstRunFadingRows) private var fading
    @FirstRunReduceMotion private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            let faded = fading.contains(slot)
            content
                .opacity(faded ? 0 : 1)
                .offset(y: faded ? rise : 0)
        }
    }
}

extension View {
    /// Take part in a demo swap as position `slot`.
    ///
    /// Use positional `ForEach` identity for swapping rows, so a row fades rather than being
    /// replaced by a new view.
    ///
    /// - Parameters:
    ///   - slot: The row or group position the demo fades.
    ///   - rise: How far the row drops while faded (the web's rival rows use 4-8 px); 0 for a
    ///     plain fade.
    /// - Returns: The view, faded while its slot swaps.
    func firstRunSwapRow(_ slot: Int, rise: CGFloat = 0) -> some View {
        modifier(FirstRunSwapRow(slot: slot, rise: rise))
    }
}
