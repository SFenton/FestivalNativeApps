import Foundation
import SwiftUI
import FestivalCore

// MARK: - Model

/// State for one global-search surface (the iOS 26 search tab or the search sheet).
///
/// Songs filter the local catalogue as soon as it is loaded; players and bands wait for
/// the web's 250 ms debounce, then call the allowlisted account and band searches in
/// parallel whatever the scope (web `useUnifiedSearch`; the scope only filters what
/// shows), each section settling on its own. Each new query cancels the previous run
/// (the view drives ``search(session:)`` from `.task(id: query)`), so older responses
/// never replace newer ones.
@MainActor @Observable
final class GlobalSearchModel {
    /// Load state of one result section.
    enum SectionState: Equatable {
        case idle
        case loading
        case ready
        case failed(ServiceIssue)
    }

    /// Text in the search field.
    var query = ""
    /// Active scope; "All" by default (HIG: start broad).
    var scope: GlobalSearchScope = .all

    private(set) var songs: [Song] = []
    private(set) var songState = SectionState.idle
    private(set) var players: [PlayerSearchResult] = []
    private(set) var playerState = SectionState.idle
    private(set) var bands: [PlayerBandEntry] = []
    private(set) var bandState = SectionState.idle
    /// Bumped to rerun the same query (keyboard Search after a failure, or a
    /// service-status automatic retry).
    private(set) var retryRevision = 0
    private var catalogue: [Song]?
    /// Publication the catalogue was read under; a new publication reloads it.
    private var catalogueRevision: Int?

    /// Identity of one search run for `.task(id:)`.
    struct RunKey: Hashable {
        let query: String
        let retry: Int
    }

    /// Current run identity.
    var runKey: RunKey { RunKey(query: query, retry: retryRevision) }

    /// True once the query is long enough to search.
    var hasQuery: Bool { GlobalSearch.effectiveQuery(query) != nil }

    /// Clear the query and results (the web resets on close).
    func reset() {
        query = ""
        scope = .all
        clearResults()
    }

    /// Run the search again after a failure.
    func retry() {
        retryRevision += 1
    }

    /// The field's Search key was pressed: rerun a failed or empty search (issue #299,
    /// no Retry button), leaving settled results and in-flight searches alone.
    func submit() {
        guard hasQuery, GlobalSearch.submitReruns(scope: scope, outcomes: outcomes) else { return }
        retry()
    }

    /// One centred spinner replaces the results while a shown section is pending.
    var isSearching: Bool {
        hasQuery && GlobalSearch.isSearching(scope: scope, outcomes: outcomes)
    }

    /// A finished network section for the current run.
    private enum NetworkResult: Sendable {
        case players(Result<[PlayerSearchResult], any Error>)
        case bands(Result<[PlayerBandEntry], any Error>)
    }

    /// Search songs, players and bands for the current query.
    ///
    /// - Parameter session: Shared app session (catalogue and API client).
    func search(session: FestivalSession) async {
        guard let query = GlobalSearch.effectiveQuery(query) else {
            clearResults()
            return
        }
        await searchSongs(query, session: session)
        playerState = .loading
        bandState = .loading
        do {
            try await Task.sleep(for: GlobalSearch.debounce)
        } catch {
            return
        }
        let client: FestivalAPI
        do {
            client = try session.client()
        } catch {
            apply(Result<[PlayerSearchResult], any Error>.failure(error), rows: &players, state: &playerState)
            apply(Result<[PlayerBandEntry], any Error>.failure(error), rows: &bands, state: &bandState)
            return
        }
        await withTaskGroup(of: NetworkResult.self) { group in
            group.addTask {
                await .players(Self.capture {
                    try await client.searchPlayers(query: query, limit: GlobalSearch.playerLimit).results
                })
            }
            group.addTask {
                await .bands(Self.capture {
                    try await client.searchBands(query: query, pageSize: GlobalSearch.bandLimit).results
                })
            }
            for await result in group {
                guard !Task.isCancelled else { return }
                switch result {
                case let .players(outcome):
                    apply(outcome, rows: &players, state: &playerState)
                case let .bands(outcome):
                    apply(outcome, rows: &bands, state: &bandState)
                }
            }
        }
    }

    /// Run one network read, capturing its error as a value.
    private nonisolated static func capture<Row: Sendable>(
        _ read: @Sendable () async throws -> [Row]
    ) async -> Result<[Row], any Error> {
        do {
            return .success(try await read())
        } catch {
            return .failure(error)
        }
    }

    /// Settle one network section, ignoring cancellation of a superseded run.
    private func apply<Row>(
        _ outcome: Result<[Row], any Error>, rows: inout [Row], state: inout SectionState
    ) {
        switch outcome {
        case let .success(values):
            rows = values
            state = .ready
        case let .failure(error):
            if error is CancellationError { return }
            if let error = error as? URLError, error.code == .cancelled { return }
            rows = []
            state = .failed(ServiceIssue(error))
        }
    }

    /// Filter the local catalogue, loading it once per surface and publication.
    private func searchSongs(_ query: String, session: FestivalSession) async {
        if catalogue == nil || catalogueRevision != session.publicationRevision {
            songState = .loading
            do {
                catalogue = try await session.catalog().catalog.songs
                // Read after the load: `catalog()` may itself observe a new publication.
                catalogueRevision = session.publicationRevision
            } catch {
                guard !Task.isCancelled else { return }
                songs = []
                songState = .failed(ServiceIssue(error))
                return
            }
        }
        songs = GlobalSearch.songs(in: catalogue ?? [], matching: query)
        songState = .ready
    }

    /// VoiceOver's result-count summary once the current query's results settle, or nil.
    var resultAnnouncement: String? {
        guard hasQuery else { return nil }
        return GlobalSearch.resultAnnouncement(scope: scope, outcomes: outcomes)
    }

    /// Every section's outcome for the shared rules.
    private var outcomes: GlobalSearch.Outcomes {
        GlobalSearch.Outcomes(
            songs: Self.outcome(songState, count: songs.count),
            players: Self.outcome(playerState, count: players.count),
            bands: Self.outcome(bandState, count: bands.count)
        )
    }

    /// Map a section state to its outcome for the shared rules.
    private static func outcome(_ state: SectionState, count: Int) -> GlobalSearch.SectionOutcome {
        switch state {
        case .idle, .loading: .pending
        case .failed: .failed
        case .ready: .found(count)
        }
    }

    private func clearResults() {
        songs = []
        players = []
        bands = []
        songState = .idle
        playerState = .idle
        bandState = .idle
    }
}
