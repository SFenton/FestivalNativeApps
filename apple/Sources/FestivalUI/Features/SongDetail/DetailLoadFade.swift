import SwiftUI

// MARK: - Load-in fade helpers for Song Detail, Shop and song leaderboards

extension View {
    /// Disable the shared load-in fade under `FST_DEBUG_STILL_BACKGROUND`, so UI-test
    /// accessibility audits never sample a half-faded frame (a mid-fade Shop row failed
    /// the contrast audit). Apply once at a screen root.
    ///
    /// `FST_DEBUG_KEEP_FADES=1` keeps the fade for recordings.
    ///
    /// - Returns: The view with `festivalFadeInEnabled` off while animations are frozen.
    func detailFadeTestSafe() -> some View {
        environment(
            \.festivalFadeInEnabled,
            !DebugAnimationOverride.stillBackground || DebugAnimationOverride.keepFades
        )
    }

    /// Staggered web `fadeInUp` for a row of a recycling list (`List` / `LazyVStack`).
    ///
    /// Rows recreated after the first reveal (scrolled away and back) must not fade
    /// again, so once `settled` they pass no index and appear instantly.
    ///
    /// - Parameters:
    ///   - index: Zero-based render position.
    ///   - settled: True once the first screenful's stagger has finished.
    /// - Returns: The row with a one-time staggered reveal.
    func detailStaggeredFadeIn(index: Int, settled: Bool) -> some View {
        festivalFadeIn(isLoaded: true, index: FadeStagger.index(index, settled: settled))
    }
}

/// When a screen's first staggered reveal is over.
enum FadeStagger {
    /// Index to hand the shared fade: the real one during the first reveal, -1 after.
    ///
    /// - Parameters:
    ///   - index: Zero-based render position.
    ///   - settled: Whether the first reveal has finished.
    /// - Returns: `index`, or -1 (instant) once settled.
    static func index(_ index: Int, settled: Bool) -> Int { settled ? -1 : index }

    /// Stagger indexes for an appending feed where only the newest batch fades in.
    ///
    /// - Parameters:
    ///   - order: Displayed item IDs, top to bottom.
    ///   - batch: IDs of the newest loaded batch.
    ///   - settled: Whether that batch's stagger has finished.
    /// - Returns: Each displayed batch item's position among the displayed batch items;
    ///   empty once settled. Items missing from the result appear without a fade.
    static func batchIndexes<ID: Hashable>(order: [ID], batch: Set<ID>, settled: Bool) -> [ID: Int] {
        guard !settled else { return [:] }
        var indexes: [ID: Int] = [:]
        for id in order where batch.contains(id) && indexes[id] == nil {
            indexes[id] = indexes.count
        }
        return indexes
    }

    /// Wait for a first screenful of `count` rows to finish fading, then mark it settled.
    ///
    /// - Parameters:
    ///   - count: Rows revealed together.
    ///   - settle: Called on completion (not called if cancelled).
    @MainActor
    static func settle(afterRevealing count: Int, _ settle: () -> Void) async {
        let delay = FestivalFadeIn.completionDelay(itemCount: count)
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled else { return }
        settle()
    }
}
