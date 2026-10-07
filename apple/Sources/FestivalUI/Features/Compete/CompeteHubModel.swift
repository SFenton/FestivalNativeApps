import SwiftUI
import FestivalCore

// MARK: - Page load key

/// What Compete's reads depend on: a change to any part reloads the page behind its
/// spinner, while a plain reappearance (Back from a pushed page) keeps the loaded page
/// (``ReappearanceLoadGate``, #39).
struct CompetePageLoadKey: Hashable, Sendable {
    let instruments: [Instrument]
    let accountId: String?
    let publicationRevision: Int

    /// Build the key from the visible instruments and the session's current state.
    ///
    /// - Parameters:
    ///   - instruments: Settings-visible instruments, in page order.
    ///   - session: Shared session; its selected account and publication revision.
    @MainActor
    init(instruments: [Instrument], session: FestivalSession) {
        self.instruments = instruments
        accountId = session.selectedPlayer?.accountId
        publicationRevision = session.publicationRevision
    }
}

// MARK: - CompeteHubModel

/// Every read on Compete: one Top-5 leaderboard preview and one rivals list per visible
/// instrument, held for the whole page so it loads behind one spinner (load-transition R1,
/// #354) like the web's `CompetePage`, instead of each card showing its own spinner under
/// its header.
///
/// The page reveals once ``progress`` is ready (``CompeteLoadProgress``). A card's Retry, or
/// a return after a failed read, re-reads only what did not load; the page's reload gate
/// then runs its spinner swap again, so no card ever spins under its header.
@MainActor
@Observable
final class CompeteHubModel {
    /// The key the states below belong to.
    private(set) var key: CompetePageLoadKey?
    /// Leaderboard preview per instrument; missing means pending.
    private(set) var boards: [Instrument: RankLoadState<RankingsPayload>] = [:]
    /// Rivals list per instrument; missing means pending.
    private(set) var rivals: [Instrument: RivalsLoadState<RivalsListResponse>] = [:]
    @ObservationIgnored private var gate = ReappearanceLoadGate<CompetePageLoadKey>()
    /// Reads in flight, so a Retry while another read runs does not repeat it.
    @ObservationIgnored private var inFlight: Set<ReadID> = []

    /// Rows in each leaderboard preview (web Compete top five).
    static let previewCount = 5

    private enum ReadID: Hashable {
        case board(Instrument)
        case rivals(Instrument)
    }

    private enum Read: Sendable {
        case board(Instrument, Result<RankingsPayload, any Error>)
        case rivals(Instrument, Result<RivalsListResponse, any Error>)
    }

    /// Where every read for `key` stands, in page order.
    ///
    /// - Parameter key: The page's current key.
    /// - Returns: All reads pending for a key this model has not started.
    func progress(for key: CompetePageLoadKey) -> CompeteLoadProgress {
        guard self.key == key else {
            return CompeteLoadProgress(
                boards: key.instruments.map { _ in .pending }, rivals: key.instruments.map { _ in .pending }
            )
        }
        return CompeteLoadProgress(
            boards: key.instruments.map { Self.readState(boards[$0]) },
            rivals: key.instruments.map { Self.readState(rivals[$0]) }
        )
    }

    /// Whether the page still shows its spinner for `key`.
    ///
    /// - Parameter key: The page's current key.
    /// - Returns: True until every read settled (or every leaderboard failed).
    func isLoading(for key: CompetePageLoadKey) -> Bool {
        !progress(for: key).isReady
    }

    /// The page-wide failure when every leaderboard failed (web `allLeaderboardsErrored`).
    ///
    /// - Parameter key: The page's current key.
    /// - Returns: The first leaderboard's issue, or nil when any leaderboard loaded.
    func fullPageIssue(for key: CompetePageLoadKey) -> ServiceIssue? {
        guard progress(for: key).everyBoardFailed else { return nil }
        for instrument in key.instruments {
            if case let .failed(issue) = boards[instrument] { return issue }
        }
        return nil
    }

    /// Read everything `key` still needs, all at once. A new key starts over; the same
    /// key re-reads only what is pending or failed, and a key that fully loaded is kept.
    ///
    /// - Parameters:
    ///   - key: The page's current key.
    ///   - session: Shared app session.
    func load(_ key: CompetePageLoadKey, session: FestivalSession) async {
        guard gate.needsLoad(for: key) else { return }
        if self.key != key {
            self.key = key
            boards = [:]
            rivals = [:]
            inFlight = []
        }
        var reads: [ReadID] = []
        for instrument in key.instruments {
            if !Self.isLoaded(boards[instrument]) { reads.append(.board(instrument)) }
            if !Self.isLoaded(rivals[instrument]) { reads.append(.rivals(instrument)) }
        }
        reads.removeAll { inFlight.contains($0) }
        guard !reads.isEmpty else { return }
        for read in reads {
            inFlight.insert(read)
            switch read {
            case let .board(instrument): boards[instrument] = .loading
            case let .rivals(instrument): rivals[instrument] = .loading
            }
        }
        await withTaskGroup(of: Read.self) { group in
            for read in reads {
                switch read {
                case let .board(instrument): group.addTask { await Self.readBoard(session, instrument) }
                case let .rivals(instrument): group.addTask { await Self.readRivals(session, instrument) }
                }
            }
            for await read in group where self.key == key {
                apply(read)
            }
        }
        guard self.key == key, progress(for: key).isComplete else { return }
        gate.markLoaded(key)
    }

    // MARK: Reads

    private func apply(_ read: Read) {
        switch read {
        case let .board(instrument, result):
            inFlight.remove(.board(instrument))
            switch result {
            case let .success(payload): boards[instrument] = .loaded(payload)
            case let .failure(error) where Self.isCancellation(error): boards[instrument] = nil
            case let .failure(error): boards[instrument] = .failed(ServiceIssue(error))
            }
        case let .rivals(instrument, result):
            inFlight.remove(.rivals(instrument))
            switch result {
            case let .success(response): rivals[instrument] = .loaded(response)
            case let .failure(error) where Self.isCancellation(error): rivals[instrument] = nil
            case let .failure(error): rivals[instrument] = .failed(ServiceIssue(error))
            }
        }
    }

    private static func readBoard(_ session: FestivalSession, _ instrument: Instrument) async -> Read {
        do {
            return .board(instrument, .success(try await session.rankings(
                instrument: instrument, rankBy: .totalscore, page: 1, pageSize: previewCount
            )))
        } catch {
            return .board(instrument, .failure(error))
        }
    }

    private static func readRivals(_ session: FestivalSession, _ instrument: Instrument) async -> Read {
        do {
            return .rivals(instrument, .success(try await session.rivalsList(instrument: instrument)))
        } catch {
            return .rivals(instrument, .failure(error))
        }
    }

    /// A read cut short by leaving the page stays pending, so the return reads it again.
    private static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    private static func isLoaded<Value>(_ state: RankLoadState<Value>?) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    private static func isLoaded<Value>(_ state: RivalsLoadState<Value>?) -> Bool {
        if case .loaded = state { return true }
        return false
    }

    private static func readState<Value>(_ state: RankLoadState<Value>?) -> CompeteReadState {
        switch state {
        case .loaded: .loaded
        case .failed: .failed
        case .loading, nil: .pending
        }
    }

    private static func readState<Value>(_ state: RivalsLoadState<Value>?) -> CompeteReadState {
        switch state {
        case .loaded: .loaded
        case .failed: .failed
        case .loading, nil: .pending
        }
    }
}
