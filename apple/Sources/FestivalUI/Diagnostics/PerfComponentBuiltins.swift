#if DEBUG && os(iOS)
import UIKit

// MARK: - Built-in component probes

/// Small DEBUG drivers for canonical components whose existing public renderers are
/// already attached to the front page.
@MainActor
enum PerfComponentBuiltins {
    private static weak var edgeScroll: UIScrollView?
    private static var edgeOriginal: CGPoint?
    private static let edgeTicker = FrameTicker()
    private static var edgeTarget: CGPoint?
    private static var edgeStableFrames = 0
    private static var edgeOpening = false
    private static var edgeSettled = false

    /// Moves the existing page scroll view through the real edge-fade renderer.
    static func startEdgeFade() {
        guard let scroll = ScrollCostDriver.frontScrollView() else { return }
        edgeScroll = scroll
        edgeOriginal = scroll.contentOffset
        edgeSettled = false
        edgeTicker.stop()
        let maximum = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height)
        let target = min(maximum, scroll.contentOffset.y + 80)
        guard abs(target - scroll.contentOffset.y) > 1 else {
            edgeScroll = nil
            edgeOriginal = nil
            return
        }
        moveEdge(to: CGPoint(x: scroll.contentOffset.x, y: target), opening: true)
    }

    /// Restores the page's original scroll position.
    static func stopEdgeFade() {
        guard edgeScroll != nil, let original = edgeOriginal else { return }
        moveEdge(to: original, opening: false)
    }

    /// The actual scroll transition has begun.
    static var edgeFadeReady: Bool {
        edgeSettled && edgeScroll?.window != nil
    }

    /// True only after the restore target has held for two display frames.
    static var edgeFadeRestored: Bool {
        !edgeOpening && edgeScroll == nil && edgeStableFrames >= 2
    }

    private static func moveEdge(to target: CGPoint, opening: Bool) {
        guard let scroll = edgeScroll else { return }
        edgeTicker.stop()
        edgeTarget = target
        edgeOpening = opening
        edgeStableFrames = 0
        scroll.setContentOffset(target, animated: true)
        edgeTicker.start { _ in
            guard let scroll = edgeScroll, scroll.window != nil, let target = edgeTarget else {
                edgeTicker.stop()
                edgeSettled = false
                edgeScroll = nil
                edgeOriginal = nil
                edgeTarget = nil
                return
            }
            let atTarget = abs(scroll.contentOffset.x - target.x) < 0.5
                && abs(scroll.contentOffset.y - target.y) < 0.5
            edgeStableFrames = atTarget ? edgeStableFrames + 1 : 0
            guard edgeStableFrames >= 2 else { return }
            edgeSettled = edgeOpening
            edgeTicker.stop()
            if !edgeOpening {
                edgeScroll = nil
                edgeOriginal = nil
                edgeTarget = nil
            }
        }
    }
}
#endif
