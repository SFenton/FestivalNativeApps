import SwiftUI

// MARK: - Far list jumps

/// Programmatic list jumps that never build the rows in between.
///
/// An *animated* `ScrollViewProxy.scrollTo` across a lazy `List`/`LazyVStack` makes the
/// collection view lay out every row it passes, one display frame at a time: on the
/// iPad and iPhone Songs list a far jump built about 25 rows (~10 ms each), so each one
/// was a main-thread stall of 250–450 ms. An instant scroll places the target from
/// estimated row heights and builds only the rows that end up on screen.
///
/// Policy: a jump further than one screenful of rows is **far** and teleports (instant
/// scroll) behind a short opacity dip, so the content changes without a misleading
/// slide through rows that were never shown; a nearer jump may animate, because it
/// builds no more rows than the destination screen would anyway. Section-index and
/// Quick Links jumps are already instant teleports without a fade (operator batch 7)
/// and keep that behaviour. HIG Motion: "Add motion purposefully"; HIG Accessibility
/// (Reduce Motion): "replacing axis transitions with fades".
enum ListJump {
    /// The shortest row a list shows, in points; dividing the viewport by it
    /// over-estimates the rows on screen, so borderline jumps stay animated.
    static let minimumRowHeight: CGFloat = 56
    /// Opacity fade before the teleport, in seconds.
    static let fadeOut: Double = 0.07
    /// Opacity fade back in after it.
    static let fadeIn: Double = 0.16
    /// Pause before the corrective second scroll, once the target's rows exist.
    static let correction: Duration = .milliseconds(50)

    /// Rows that fit in a viewport of this height (at least one).
    ///
    /// - Parameter viewportHeight: The list's visible height in points.
    /// - Returns: The most rows of ``minimumRowHeight`` that can be on screen.
    static func visibleRows(viewportHeight: CGFloat) -> Int {
        guard viewportHeight.isFinite, viewportHeight > 0 else { return 1 }
        return max(1, Int((viewportHeight / minimumRowHeight).rounded(.up)))
    }

    /// True when a jump of `rowDistance` rows should teleport instead of animate.
    ///
    /// - Parameters:
    ///   - rowDistance: Rows between the current top row and the target (either sign).
    ///   - viewportHeight: The list's visible height in points.
    /// - Returns: True beyond one screenful of rows.
    static func isFar(rowDistance: Int, viewportHeight: CGFloat) -> Bool {
        abs(rowDistance) > visibleRows(viewportHeight: viewportHeight)
    }

    /// Teleport: fade the content out, scroll instantly (twice: the first lands on
    /// estimated heights, the second exactly once the target's rows are built), fade in.
    ///
    /// - Parameters:
    ///   - setOpacity: Writes the list's opacity (animated by the caller's transaction).
    ///   - scroll: The `scrollTo` call; it runs with animations disabled.
    @MainActor
    static func teleport(setOpacity: @escaping @MainActor (Double) -> Void,
                         scroll: @escaping @MainActor () -> Void) async {
        var instant = Transaction()
        instant.disablesAnimations = true
        withAnimation(.easeOut(duration: fadeOut)) { setOpacity(0) }
        try? await Task.sleep(for: .seconds(fadeOut))
        withTransaction(instant) { scroll() }
        try? await Task.sleep(for: correction)
        withTransaction(instant) { scroll() }
        withAnimation(.easeIn(duration: fadeIn)) { setOpacity(1) }
    }
}

// MARK: - Fade state

/// The list's teleport fade and visible height, owned by the list's screen.
///
/// Only ``ListJumpFadeEffect`` reads ``opacity``, so a fade re-renders that modifier,
/// not the screen's body; the height is never observed.
@MainActor
@Observable
final class ListJumpFade {
    /// Current list opacity (1 except during a teleport).
    var opacity: Double = 1
    /// The list's visible height in points.
    @ObservationIgnored var viewportHeight: CGFloat = 0

    init() {}

    /// True when a jump of `rowDistance` rows should teleport in this list.
    ///
    /// - Parameter rowDistance: Rows between the current top row and the target.
    /// - Returns: ``ListJump/isFar(rowDistance:viewportHeight:)`` for this list.
    func isFar(rowDistance: Int) -> Bool {
        ListJump.isFar(rowDistance: rowDistance, viewportHeight: viewportHeight)
    }

    /// Teleport this list (``ListJump/teleport(setOpacity:scroll:)``).
    ///
    /// - Parameter scroll: The `scrollTo` call.
    func teleport(_ scroll: @escaping @MainActor () -> Void) async {
        await ListJump.teleport(setOpacity: { [weak self] in self?.opacity = $0 }, scroll: scroll)
    }
}

/// Applies a ``ListJumpFade``'s opacity and records the list's visible height.
struct ListJumpFadeEffect: ViewModifier {
    let fade: ListJumpFade

    func body(content: Content) -> some View {
        content
            .opacity(fade.opacity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                fade.viewportHeight = height
            }
    }
}
