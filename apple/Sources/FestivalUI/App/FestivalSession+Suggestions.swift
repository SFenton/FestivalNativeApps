import Foundation
import Observation
import FestivalCore

// MARK: - Suggestions view state

/// Incremental load state for `SuggestionsScreen`, independent of `SelectedPlayerLoadState`
/// (which tracks the profile's score index, not the generated categories).
enum SuggestionsLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(ServiceIssue)
}

/// Owns one `SuggestionGenerator` for the current (selected player, catalogue publication)
/// pair, the incrementally-loaded category list, and the persisted filter draft.
///
/// A fresh `SuggestionsViewModel` belongs to one `SuggestionsScreen` instance (created as
/// `@State`); it is not shared across tabs. Regenerating categories (a new player, a new
/// catalogue publication, or "Start New Mix") replaces the generator and clears the list;
/// changing the filter only re-derives which already-generated categories are visible.
@MainActor
@Observable
final class SuggestionsViewModel {
    /// Categories generated so far, oldest first (before filtering).
    private(set) var categories: [SuggestionCategory] = []
    private(set) var loadState: SuggestionsLoadState = .idle
    private(set) var isLoadingMore = false
    /// Effective current season for the loaded source (row season pills highlight it).
    private(set) var currentSeason: Int?
    /// False once a `getNext` call returns nothing more for the current mix.
    private(set) var hasMore = true
    /// Counts generated pages; each new page fades in once (issue #30).
    private(set) var batchGeneration = 0
    /// IDs of the newest generated page: the only categories that may fade in.
    @ObservationIgnored
    private(set) var latestBatchIds: Set<String> = []
    var filter: SuggestionFilterSettings

    /// One page of newly generated categories per `loadMore()` call.
    static let pageSize = 10

    /// When set, the generator considers only these catalogue songs (the Item Shop
    /// suggestions region on iPhone Duo, `SuggestionsDualSource.swift`); nil = every song.
    @ObservationIgnored
    private(set) var candidateSongIds: Set<String>?
    /// Observed publication the candidate IDs were read from; the catalogue must match it.
    @ObservationIgnored
    private var candidatePublicationId: Int?
    /// True while the candidate feed and the catalogue come from different publications:
    /// nothing is generated until they match again (paused, never re-labelled).
    private(set) var candidatesPaused = false
    @ObservationIgnored
    private var generator: SuggestionGenerator?
    @ObservationIgnored
    private var sourceIdentity: String?

    /// Start with a previously saved (or default) filter draft.
    ///
    /// - Parameter filter: Persisted `SuggestionFilterSettings`.
    init(filter: SuggestionFilterSettings) {
        self.filter = filter
    }

    /// Restrict (or stop restricting) the generator's candidate songs, rebuilding it
    /// on the next `ensureLoaded` when the set actually changed.
    ///
    /// The caller proves the IDs come from a feed of the same observed publication as
    /// the catalogue (Shop invariant, `AGENTS.md`).
    ///
    /// - Parameters:
    ///   - songIds: Candidate song IDs, or nil for the whole catalogue.
    ///   - publicationId: Observed publication of the feed the IDs came from.
    func restrictCandidates(to songIds: Set<String>?, publicationId: Int?) {
        guard songIds != candidateSongIds || publicationId != candidatePublicationId else { return }
        candidateSongIds = songIds
        candidatePublicationId = songIds == nil ? nil : publicationId
        invalidate()
    }

    /// Identity of the (player, catalogue) pair the current generator was built from.
    ///
    /// - Parameters:
    ///   - accountId: Selected player's account ID.
    ///   - observedPublicationId: Catalogue generation the scores must match.
    private static func identity(accountId: String, observedPublicationId: Int) -> String {
        "\(accountId)|\(observedPublicationId)"
    }

    /// Load the catalogue and (re)build the generator only when the player or the
    /// catalogue's observed publication has actually changed; otherwise a no-op.
    ///
    /// Also kicks off the selected player's own score fetch when nothing else has yet
    /// (e.g. arriving on this tab directly, without ever visiting Songs first — Songs
    /// opportunistically calls `refreshSelectedPlayer()` on `.loading`/`.failed`, but that
    /// is per-screen, not automatic; `PlayerProfileContent` similarly does its own fetch
    /// rather than depending on another screen to have populated the session first).
    ///
    /// Alongside the catalogue, also reads the player's combined `/rivals/all` (the source
    /// for `song_rival_*`) whenever the generator itself is being (re)built — not on every
    /// call, so an unchanged (player, publication) pair never refetches it. That read is
    /// best-effort (`rivalsAll(session:accountId:)`): a failure only skips the rival
    /// families, it never fails this whole page, matching every other optional annotation
    /// this app layers onto an otherwise-successful load.
    ///
    /// - Parameter session: Shared app session (selected player, score index, catalogue).
    func ensureLoaded(session: FestivalSession) async {
        guard let player = session.selectedPlayer else { return }
        switch session.playerLoadState {
        case .loading, .failed:
            await session.refreshSelectedPlayer()
        case .none, .available, .syncing:
            break
        }
        guard session.playerLoadState == .available else { return }
        if categories.isEmpty, loadState != .loading { loadState = .loading }
        do {
            let payload = try await session.catalog()
            if let required = candidatePublicationId, required != payload.observedPublicationId {
                generator = nil
                sourceIdentity = nil
                categories = []
                candidatesPaused = true
                loadState = .loaded
                return
            }
            candidatesPaused = false
            let identity = Self.identity(
                accountId: player.accountId, observedPublicationId: payload.observedPublicationId
            )
            if identity != sourceIdentity {
                sourceIdentity = identity
                let season = SuggestionSeason.effective(
                    currentSeason: payload.catalog.currentSeason, scores: session.selectedPlayerScores
                )
                currentSeason = season
                let engine = SuggestionGenerator(options: .init(currentSeason: season))
                let songs = candidateSongIds.map { ids in payload.catalog.songs.filter { ids.contains($0.songId) } }
                    ?? payload.catalog.songs
                engine.setSource(songs: songs, scoresIndex: session.selectedPlayerScores)
                if let rivalsAll = await rivalsAll(session: session, accountId: player.accountId) {
                    engine.setRivalData(RivalDataIndex.build(from: rivalsAll))
                }
                generator = engine
                categories = []
                hasMore = true
            }
            if categories.isEmpty {
                await loadMore()
            } else {
                loadState = .loaded
            }
        } catch {
            guard categories.isEmpty else { return }
            loadState = .failed(ServiceIssue(error))
        }
    }

    /// Generate and append one more page of categories.
    func loadMore() async {
        guard let generator, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = generator.getNext(Self.pageSize)
        if next.isEmpty {
            hasMore = false
        } else {
            latestBatchIds = Set(next.map(\.id))
            batchGeneration += 1
            categories.append(contentsOf: next)
        }
        loadState = .loaded
    }

    /// Discard emitted-category history and start over with the same source ("Start New Mix").
    func startNewMix() {
        guard let generator else { return }
        generator.resetForEndless()
        categories = []
        hasMore = true
    }

    /// Force a full reload on the next `ensureLoaded` (e.g. after a profile change).
    func invalidate() {
        generator = nil
        sourceIdentity = nil
        categories = []
        hasMore = true
        loadState = .idle
    }

    /// Categories currently eligible to display, in generated order.
    ///
    /// - Parameter appVisibleInstruments: Settings-visible charts.
    /// - Returns: Filtered (and possibly trimmed) categories; empty categories are dropped.
    func visibleCategories(appVisibleInstruments: Set<Instrument>) -> [SuggestionCategory] {
        let effective = filter.effectiveInstruments(appVisible: appVisibleInstruments)
        return categories.compactMap {
            SuggestionCategoryFilter.visible($0, effectiveInstruments: effective, filter: filter)
        }
    }
}

// MARK: - Rival data

/// Best-effort combined rivals read (`GET /api/player/{accountId}/rivals/all`) for the
/// `song_rival_*` pipelines (`RivalDataIndex.build(from:)`).
///
/// A pure, keyless, already-allowlisted read (`FestivalAPI.rivalsAll(accountId:)`), but never
/// load-bearing for the page: no rivals yet, a transient network failure, or a decode issue
/// all fall through to `nil` here, and `ensureLoaded` simply skips `setRivalData` in that
/// case — the score-only categories still load normally.
///
/// - Parameters:
///   - session: Shared app session (for its `FestivalAPI` client).
///   - accountId: Selected player's account ID.
/// - Returns: The decoded response, or nil if the read failed for any reason.
@MainActor
private func rivalsAll(session: FestivalSession, accountId: String) async -> RivalsAllResponse? {
    guard let client = try? session.client() else { return nil }
    return try? await client.rivalsAll(accountId: accountId)
}
