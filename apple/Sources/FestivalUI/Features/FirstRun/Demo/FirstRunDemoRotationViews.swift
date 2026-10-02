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
    /// by ``SwiftUI/View/firstRunSwapRow(_:key:rise:)``.
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

// MARK: - Ticker

/// Calls `tick` every `interval` while the demo's slide is visible and active, standing in
/// for the web demos' `setInterval`. Never runs off-screen, in the background, under the Debug
/// still-animation override (`FST_DEBUG_STILL_BACKGROUND=1`, so XCUITest can idle) or, for
/// demos that load album art, under Low Data Mode.
private struct FirstRunDemoTicker: ViewModifier {
    let interval: Duration
    let enabled: Bool
    let usesArtwork: Bool
    let tick: @MainActor @Sendable () async -> Void
    @Environment(\.firstRunDemoActive) private var active

    func body(content: Content) -> some View {
        let constrained = usesArtwork && ArtworkNetworkStatus.shared.isConstrained
        let running = active && enabled && !constrained && !DebugAnimationOverride.stillBackground
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
    /// Under Reduce Motion the data changes in one cross-fade instead (HIG Accessibility:
    /// "reduce automatic and repetitive animation… replacing axis transitions with fades"),
    /// with no rise; rows using ``SwiftUI/View/firstRunSwapRow(_:key:rise:)`` cross-fade by
    /// identity.
    ///
    /// - Parameters:
    ///   - reduceMotion: The environment's Reduce Motion setting.
    ///   - seconds: Each fade's duration; the web's 400 ms by default.
    ///   - fadeOut: Marks the changing rows faded (animated).
    ///   - update: Changes the data (not animated, except as the Reduce Motion cross-fade).
    ///   - fadeIn: Clears the faded rows (animated).
    static func run(
        reduceMotion: Bool, seconds: Double = FirstRunDemoTiming.fadeSeconds,
        fadeOut: () -> Void, update: () -> Void, fadeIn: () -> Void
    ) async {
        if reduceMotion {
            withAnimation(.easeInOut(duration: seconds)) { update() }
            return
        }
        withAnimation(.firstRunFade(seconds)) { fadeOut() }
        // A cancelled sleep (the page left mid-fade) still completes the swap, so rows are
        // never left hidden.
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1_000)))
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { update() }
        withAnimation(.firstRunFade(seconds)) { fadeIn() }
    }
}

// MARK: - Swapping row

/// Fades a demo row (or group) out while its position is in ``EnvironmentValues/firstRunFadingRows``.
/// Under Reduce Motion the row instead cross-fades whenever its `key` changes, with no rise.
private struct FirstRunSwapRow: ViewModifier {
    let slot: Int
    let key: AnyHashable
    let rise: CGFloat
    @Environment(\.firstRunFadingRows) private var fading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            ZStack { content.id(key).transition(.opacity) }
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
    ///   - key: The content's identity, for the Reduce Motion cross-fade.
    ///   - rise: How far the row drops while faded (the web's rival rows use 4-8 px); 0 for a
    ///     plain fade.
    /// - Returns: The view, faded while its slot swaps.
    func firstRunSwapRow(_ slot: Int, key: some Hashable, rise: CGFloat = 0) -> some View {
        modifier(FirstRunSwapRow(slot: slot, key: AnyHashable(key), rise: rise))
    }
}
