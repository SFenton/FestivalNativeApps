import Foundation
import SwiftUI
import FestivalCore

// MARK: - Model

/// State for one global-search surface (the iOS 26 search tab or the search sheet).
///
/// Songs filter the local catalogue as soon as it is loaded; players wait for the web's
/// 250 ms debounce, then call the allowlisted account search. Each new query cancels the
/// previous run (the view drives ``search(session:)`` from `.task(id: query)`), so older
/// responses never replace newer ones. Band search is never sent
/// (`.agents/platforms/service-safety.md`).
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
    /// Bumped by Retry to rerun the same query.
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

    /// Search songs and players for the current query.
    ///
    /// - Parameter session: Shared app session (catalogue and API client).
    func search(session: FestivalSession) async {
        guard let query = GlobalSearch.effectiveQuery(query) else {
            clearResults()
            return
        }
        await searchSongs(query, session: session)
        playerState = .loading
        do {
            try await Task.sleep(for: GlobalSearch.debounce)
            let response = try await session.client().searchPlayers(
                query: query, limit: GlobalSearch.playerLimit
            )
            try Task.checkCancellation()
            players = response.results
            playerState = .ready
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            players = []
            playerState = .failed(ServiceIssue(error))
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

    private func clearResults() {
        songs = []
        players = []
        songState = .idle
        playerState = .idle
    }
}
