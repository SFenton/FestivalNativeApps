import SwiftUI

// MARK: - Selected row reveal

/// Brings the selected profile's row into view once a song leaderboard page opened for it
/// has loaded: the web `navToPlayer` scroll (`LeaderboardPage.tsx`, `scrollIntoView` with
/// `block: 'center'`), used by the solo and band boards and Full Rankings (issues #307,
/// #318).
///
/// Like the web, the scroll waits for the row's own entrance to finish (web waits
/// `(playerIndex + 1) × STAGGER_INTERVAL` plus the fade), so it never carries the reader
/// past rows that are still fading in; if the page is still fading anywhere, the scroll
/// rushes those fades through the page's ``FestivalFadeInScope``, and rows the scroll
/// realizes (a row past the first screen, revealed as the stagger ends) fade in together
/// rather than appear opaque (``FestivalFadeInScope/prepareForAutomaticScroll(lasting:)``,
/// issue #323). Until the scroll starts, rows past the first screen that the list builds
/// early are held for it (``FestivalFadeInScope/expectAutomaticScroll()``), so the rows it
/// reaches have not spent their entrance unseen. Pass the page's scope and the row's
/// stagger index. It also waits, however long that takes, for a reload gate inside the
/// page's scroll view to finish growing the content to the rows' height
/// (``FestivalFadeInScope/contentRevealed()``): `scrollTo` stops at the content's end of
/// the moment and does not follow it as it grows, so on a starved main actor, where that
/// 400 ms reveal can run for seconds, the band board's scroll stopped a few rows down
/// for good (issue #327). A reader
/// who scrolls first cancels it (web `userScrolledRef`). A page holds at most 25 rows, so
/// the scroll never builds more than a screenful or two of rows. It is animated only
/// without Reduce Motion, and then waits only for layout (HIG Accessibility: "When Reduce
/// Motion is on, reduce automatic and repetitive animation").
@MainActor
enum SelectedRowReveal {
    /// Pause after the rows appear, so the list has laid them out before scrolling.
    static let settle: Duration = .milliseconds(200)

    /// Length of the animated scroll, in seconds.
    static let scrollDuration: TimeInterval = 0.35

    /// How long to wait after the rows are revealed before scrolling.
    ///
    /// - Parameters:
    ///   - staggerIndex: The row's stagger position, or nil when the page fades as one
    ///     block.
    ///   - animates: Whether fades and the scroll animate (no Reduce Motion, fades on).
    /// - Returns: The layout settle, or the end of the row's entrance when that is later.
    static func wait(staggerIndex: Int?, animates: Bool) -> Duration {
        guard animates else { return settle }
        let entrance = Duration.milliseconds(Int((FestivalFadeIn.entranceEnd(forIndex: staggerIndex) * 1000).rounded()))
        return max(settle, entrance)
    }

    /// Whether the in-app Reduce Motion setting is on (Settings, `fst.accessibility.reduceMotion`).
    static var appReduceMotion: Bool {
        UserDefaults.standard.bool(forKey: "fst.accessibility.reduceMotion")
    }

    /// Whether the pages' load fades play: off when UI tests freeze animations
    /// (`detailFadeTestSafe()`), unless `FST_DEBUG_KEEP_FADES` keeps them for recordings.
    static var loadFadesPlay: Bool {
        !DebugAnimationOverride.stillBackground || DebugAnimationOverride.keepFades
    }

    /// Scroll a loaded page to a row and centre it, once its entrance has finished.
    ///
    /// - Parameters:
    ///   - id: The row's `id` in the page's `ForEach`.
    ///   - proxy: The page's scroll proxy.
    ///   - reduceMotion: Whether the system Reduce Motion is on (with the in-app setting,
    ///     the scroll is instant and does not wait for fades).
    ///   - staggerIndex: The row's stagger position, or nil for a block-fade page.
    ///   - fadesEnabled: Whether the page's load fades play (off in frozen UI-test runs).
    ///   - scope: The page's fade scope: a reader who already scrolled cancels the reveal,
    ///     rows the scroll realizes fade in with its rush, and the scroll waits for the
    ///     page's content reveal to end.
    /// - Returns: False when the reveal was cancelled before scrolling.
    @discardableResult
    static func reveal<ID: Hashable>(
        _ id: ID, proxy: ScrollViewProxy, reduceMotion: Bool, staggerIndex: Int? = nil,
        fadesEnabled: Bool = loadFadesPlay, scope: FestivalFadeInScope? = nil
    ) async -> Bool {
        let instant = reduceMotion || appReduceMotion
        let animates = fadesEnabled && !instant
        // Rows past the first screen that the list builds early wait for this scroll.
        let expectation = animates ? scope?.expectAutomaticScroll() : nil
        try? await Task.sleep(for: wait(staggerIndex: staggerIndex, animates: animates))
        // The rows' full height: a scroll to a row past the content's current end stops
        // short and stays there.
        await scope?.contentRevealed()
        guard !Task.isCancelled else {
            scope?.endAutomaticScrollExpectation(expectation)
            return false
        }
        // The reader scrolled while the page was fading in: leave them where they are.
        if scope?.hasScrolled == true {
            scope?.endAutomaticScrollExpectation(expectation)
            return true
        }
        if !animates {
            scope?.endAutomaticScrollExpectation(expectation)
        }
        if instant {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(id, anchor: .center) }
        } else {
            scope?.prepareForAutomaticScroll(lasting: scrollDuration)
            withAnimation(.easeInOut(duration: scrollDuration)) { proxy.scrollTo(id, anchor: .center) }
        }
        return true
    }
}
