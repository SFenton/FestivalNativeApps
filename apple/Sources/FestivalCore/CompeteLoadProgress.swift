import Foundation

// MARK: - CompeteLoadProgress

/// Where one Compete read stands: a leaderboard preview or a rivals list.
public enum CompeteReadState: Equatable, Sendable {
    /// Not answered yet (never started, in flight, or cancelled).
    case pending
    /// Answered with data (an empty result counts).
    case loaded
    /// Answered with an error.
    case failed
}

/// When Compete may leave its one page spinner (load-transition R1, #354).
///
/// Like the web's `CompetePage` (`usePageTransition` on
/// `(leaderboardReady && rivalsReady) || allLeaderboardsErrored`), the page waits for every
/// leaderboard preview and every rivals list to settle, loaded or failed, before it shows
/// any header or card; if every leaderboard fails, it shows the page-wide error at once.
/// Until then the page shows one centred spinner rather than headers with a spinner in
/// each card.
public struct CompeteLoadProgress: Equatable, Sendable {
    /// One state per leaderboard preview, in page order.
    public var boards: [CompeteReadState]
    /// One state per rivals list, in page order.
    public var rivals: [CompeteReadState]

    /// - Parameters:
    ///   - boards: One state per leaderboard preview, in page order.
    ///   - rivals: One state per rivals list, in page order.
    public init(boards: [CompeteReadState], rivals: [CompeteReadState]) {
        self.boards = boards
        self.rivals = rivals
    }

    /// Whether every leaderboard read failed (web `allLeaderboardsErrored`); false with no
    /// leaderboards, which shows the "enable an instrument" copy instead.
    public var everyBoardFailed: Bool {
        !boards.isEmpty && boards.allSatisfy { $0 == .failed }
    }

    /// Whether every read has answered, loaded or failed.
    public var isSettled: Bool {
        !boards.contains(.pending) && !rivals.contains(.pending)
    }

    /// Whether the page can fade its spinner out and reveal its content (web `isReady`).
    public var isReady: Bool {
        isSettled || everyBoardFailed
    }

    /// Whether every read loaded, so a plain reappearance keeps the page without reading
    /// again (``ReappearanceLoadGate``); a failed read retries on return.
    public var isComplete: Bool {
        boards.allSatisfy { $0 == .loaded } && rivals.allSatisfy { $0 == .loaded }
    }
}
