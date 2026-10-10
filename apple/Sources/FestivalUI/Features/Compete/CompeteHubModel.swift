import SwiftUI
import FestivalCore

// MARK: - Page load key

/// What Compete's reads depend on: a change to any part reloads the page behind its
/// spinner, while a plain reappearance (Back from a pushed page) keeps the loaded page
/// (``ReappearanceLoadGate``, #39).
struct CompetePageLoadKey: Hashable, Sendable {
    let instruments: [Instrument]
    /// The page's leaderboards, in page order: per family, a within-group combo first,
    /// then each instrument (``RankingScope/supported(visible:)``, issue #602).
    let scopes: [RankingScope]
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
        scopes = RankingScope.supported(visible: instruments)
        accountId = session.selectedPlayer?.accountId
        publicationRevision = session.publicationRevision
    }
}

// MARK: - CompeteHubModel

/// Every read on Compete: one Top-5 leaderboard preview (with the selected player's own
/// rank when the top five lack it) and one rivals list per leaderboard scope (each visible
/// instrument and each family's within-group combo, web `resolveSupportedRankingScopes`), held for
/// the whole page so it loads behind one spinner (load-transition R1,
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
    /// Leaderboard preview per scope; missing means pending.
    private(set) var boards: [RankingScope: RankLoadState<RankingsPayload>] = [:]
    /// The selected player's own row per scope, read with its preview when the top
    /// five lack it (web `CompetePage` `playerEntry`). Missing when they are in the top
    /// five, unranked, or their rank could not be read: the web shows no row then.
    private(set) var spotlights: [RankingScope: AccountRankingEntry] = [:]
    /// Rivals list per scope; missing means pending.
    private(set) var rivals: [RankingScope: RivalsLoadState<RivalsListResponse>] = [:]
    @ObservationIgnored private var gate = ReappearanceLoadGate<CompetePageLoadKey>()
    /// Reads in flight, so a Retry while another read runs does not repeat it.
    @ObservationIgnored private var inFlight: Set<ReadID> = []

    /// Rows in each leaderboard preview (web Compete top five).
    static let previewCount = 5

    private enum ReadID: Hashable {
        case board(RankingScope)
        case rivals(RankingScope)
    }

    private enum Read: Sendable {
        case board(RankingScope, Result<RankingsPayload, any Error>, AccountRankingEntry?)
        case rivals(RankingScope, Result<RivalsListResponse, any Error>)
    }

    /// Where every read for `key` stands, in page order.
    ///
    /// - Parameter key: The page's current key.
    /// - Returns: All reads pending for a key this model has not started.
    func progress(for key: CompetePageLoadKey) -> CompeteLoadProgress {
        guard self.key == key else {
            return CompeteLoadProgress(
                boards: key.scopes.map { _ in .pending }, rivals: key.scopes.map { _ in .pending }
            )
        }
        return CompeteLoadProgress(
            boards: key.scopes.map { Self.readState(boards[$0]) },
            rivals: key.scopes.map { Self.readState(rivals[$0]) }
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
        for scope in key.scopes {
            if case let .failed(issue) = boards[scope] { return issue }
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
            spotlights = [:]
            rivals = [:]
            inFlight = []
        }
        var reads: [ReadID] = []
        for scope in key.scopes {
            if !Self.isLoaded(boards[scope]) { reads.append(.board(scope)) }
            if !Self.isLoaded(rivals[scope]) { reads.append(.rivals(scope)) }
        }
        reads.removeAll { inFlight.contains($0) }
        guard !reads.isEmpty else { return }
        for read in reads {
            inFlight.insert(read)
            switch read {
            case let .board(scope): boards[scope] = .loading
            case let .rivals(scope): rivals[scope] = .loading
            }
        }
        await withTaskGroup(of: Read.self) { group in
            for read in reads {
                switch read {
                case let .board(scope):
                    group.addTask { await Self.readBoard(session, scope, accountId: key.accountId) }
                case let .rivals(scope): group.addTask { await Self.readRivals(session, scope) }
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
        case let .board(scope, result, spotlight):
            inFlight.remove(.board(scope))
            switch result {
            case let .success(payload):
                spotlights[scope] = spotlight
                boards[scope] = .loaded(payload)
            case let .failure(error) where Self.isCancellation(error): boards[scope] = nil
            case let .failure(error): boards[scope] = .failed(ServiceIssue(error))
            }
        case let .rivals(scope, result):
            inFlight.remove(.rivals(scope))
            switch result {
            case let .success(response): rivals[scope] = .loaded(response)
            case let .failure(error) where Self.isCancellation(error): rivals[scope] = nil
            case let .failure(error): rivals[scope] = .failed(ServiceIssue(error))
            }
        }
    }

    /// Read one scope's Top 5, then the selected player's own row when the top five
    /// lack it, so the card reveals with it rather than growing afterwards.
    ///
    /// - Parameters:
    ///   - session: Shared app session.
    ///   - scope: The preview's instrument or combo.
    ///   - accountId: The selected player, if any.
    /// - Returns: The preview, with the player's row when it is shown apart.
    private static func readBoard(
        _ session: FestivalSession, _ scope: RankingScope, accountId: String?
    ) async -> Read {
        let metric = CompetePreviewSpotlight.metric
        let payload: RankingsPayload
        do {
            payload = try await session.rankings(scope: scope, rankBy: metric, page: 1, pageSize: previewCount)
        } catch {
            return .board(scope, .failure(error), nil)
        }
        guard let accountId, !payload.rankings.entries.contains(where: {
            $0.accountId.caseInsensitiveCompare(accountId) == .orderedSame
        }) else {
            return .board(scope, .success(payload), nil)
        }
        do {
            let ranking = try await session.playerRanking(scope: scope, accountId: accountId, rankBy: metric)
            let spotlight = RankingSpotlight.placement(
                selectedAccountId: accountId, visibleEntries: payload.rankings.entries,
                source: ranking.ranking.map { .available($0.entry) } ?? .unranked
            )
            guard case let .footer(entry) = spotlight else { return .board(scope, .success(payload), nil) }
            return .board(scope, .success(payload), entry)
        } catch let error where isCancellation(error) {
            // Left mid-read: stay pending, so the return reads the card again.
            return .board(scope, .failure(error), nil)
        } catch {
            // Web `CompetePage` shows no row when the player's own rank fails.
            return .board(scope, .success(payload), nil)
        }
    }

    /// Read one scope's rivals: an instrument's shared-song list, or a combo's
    /// server-computed list (web `getRivalsList(accountId, scope.queryValue)`).
    private static func readRivals(_ session: FestivalSession, _ scope: RankingScope) async -> Read {
        do {
            let response = switch scope {
            case let .instrument(instrument): try await session.rivalsList(instrument: instrument)
            case let .combo(combo): try await session.rivalsComboList(token: combo.comboId)
            }
            return .rivals(scope, .success(response))
        } catch {
            return .rivals(scope, .failure(error))
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
