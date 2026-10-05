import Foundation
import SwiftUI

// MARK: - Page scroll stress pass (Debug)

/// Debug-only in-app scroll stress pass for card pages (Leaderboards, Profile,
/// Settings), the counterpart of ``SongsScrollStress`` (issue #291).
///
/// With `FST_DEBUG_PAGE_SCROLL_STRESS=1` the page's vertical scroll view replays
/// ``plan()`` once, ``initialDelay`` seconds after it appears (live data has loaded by
/// then): animated scrolls to the bottom and back to the top. It records the same
/// ``MainThreadStallMonitor`` marks as the Songs pass, so
/// `tools/apple_perf.py ipad|mac --tab <page> --stress --env FST_DEBUG_PAGE_SCROLL_STRESS=1`
/// reports the pass's main-thread CPU (`main_cpu_s`) and stalls. Pair it with
/// `FST_DEBUG_ROW_CARD_AB` to compare the material card with the Liquid Glass card in
/// one binary.
enum PageScrollStress {
    /// Environment key that starts the pass.
    static let environmentKey = "FST_DEBUG_PAGE_SCROLL_STRESS"
    /// Start mark; shared with the Songs pass because `apple_perf.py` reads it.
    static let startCounter = SongsScrollStress.startCounter
    /// End mark; shared with the Songs pass because `apple_perf.py` waits for it.
    static let endCounter = SongsScrollStress.endCounter
    /// Seconds between the page appearing and the first scroll.
    static let initialDelay: Double = 8
    /// Passes through the pattern.
    static let rounds = 6

    /// One animated scroll.
    struct Step: Equatable {
        /// Edge to scroll to.
        let edge: VerticalEdge
        /// Seconds the animated scroll lasts.
        let duration: Double
        /// Seconds to wait after the scroll ends.
        let pause: Double
    }

    /// True when the launch environment asks for a pass.
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    /// The scrolls: each round goes to the bottom and back to the top, a little
    /// faster each time.
    ///
    /// - Returns: ``rounds`` × 2 steps, alternating bottom and top.
    static func plan() -> [Step] {
        (0..<rounds).flatMap { round -> [Step] in
            let duration = Double(max(6, 16 - round * 2)) / 10
            return [
                Step(edge: .bottom, duration: duration, pause: 0.5),
                Step(edge: .top, duration: duration, pause: 0.5),
            ]
        }
    }
}

extension View {
    /// Replay ``PageScrollStress`` on this vertical scroll view when the launch
    /// environment asks for it (Debug builds, iOS 18 / macOS 15+); otherwise returns
    /// the view unchanged.
    ///
    /// - Returns: The scroll view, driven by the stress pass when requested.
    @ViewBuilder
    func debugPageScrollStress() -> some View {
        #if DEBUG
        if PageScrollStress.isRequested, #available(iOS 18.0, macOS 15.0, *) {
            modifier(PageScrollStressModifier())
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
/// Drives the scroll view's position through ``PageScrollStress/plan()``.
@available(iOS 18.0, macOS 15.0, *)
private struct PageScrollStressModifier: ViewModifier {
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .task {
                try? await Task.sleep(for: .seconds(PageScrollStress.initialDelay))
                guard !Task.isCancelled else { return }
                MainThreadStallMonitor.count(PageScrollStress.startCounter)
                for step in PageScrollStress.plan() {
                    withAnimation(.easeInOut(duration: step.duration)) {
                        position.scrollTo(edge: step.edge == .bottom ? .bottom : .top)
                    }
                    try? await Task.sleep(for: .seconds(step.duration + step.pause))
                    guard !Task.isCancelled else { return }
                }
                MainThreadStallMonitor.count(PageScrollStress.endCounter)
            }
    }
}
#endif
