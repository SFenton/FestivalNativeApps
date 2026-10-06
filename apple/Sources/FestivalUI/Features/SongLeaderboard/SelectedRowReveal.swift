import SwiftUI

// MARK: - Selected row reveal

/// Brings the selected profile's row into view once a song leaderboard page opened for it
/// has loaded: the web `navToPlayer` scroll (`LeaderboardPage.tsx`, `scrollIntoView` with
/// `block: 'center'`), used by the solo and band boards alike (issue #307).
///
/// A page holds at most 25 rows, so the scroll never builds more than a screenful or
/// two of rows. It is animated only without Reduce Motion (HIG Accessibility: "When
/// Reduce Motion is on, reduce automatic and repetitive animation").
@MainActor
enum SelectedRowReveal {
    /// Pause after the rows appear, so the list has laid them out before scrolling.
    static let settle: Duration = .milliseconds(200)

    /// Scroll a loaded page to a row and centre it.
    ///
    /// - Parameters:
    ///   - id: The row's `id` in the page's `ForEach`.
    ///   - proxy: The page's scroll proxy.
    ///   - reduceMotion: Whether Reduce Motion is on (scrolls instantly).
    /// - Returns: False when the reveal was cancelled before scrolling.
    @discardableResult
    static func reveal<ID: Hashable>(_ id: ID, proxy: ScrollViewProxy, reduceMotion: Bool) async -> Bool {
        try? await Task.sleep(for: settle)
        guard !Task.isCancelled else { return false }
        if reduceMotion {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { proxy.scrollTo(id, anchor: .center) }
        } else {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
        }
        return true
    }
}
