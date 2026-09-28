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
    case failed(String)
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
    /// False once a `getNext` call returns nothing more for the current mix.
    private(set) var hasMore = true
    var filter: SuggestionFilterSettings

    /// One page of newly generated categories per `loadMore()` call.
    static let pageSize = 10

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
    /// - Parameter session: Shared app session (selected player, score index, catalogue).
    func ensureLoaded(session: FestivalSession) async {
        guard let player = session.selectedPlayer, session.playerLoadState == .available else { return }
        if categories.isEmpty, loadState != .loading { loadState = .loading }
        do {
            let payload = try await session.catalog()
            let identity = Self.identity(
                accountId: player.accountId, observedPublicationId: payload.observedPublicationId
            )
            if identity != sourceIdentity {
                sourceIdentity = identity
                let season = SuggestionSeason.effective(
                    currentSeason: payload.catalog.currentSeason, scores: session.selectedPlayerScores
                )
                let engine = SuggestionGenerator(options: .init(currentSeason: season))
                engine.setSource(songs: payload.catalog.songs, scoresIndex: session.selectedPlayerScores)
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
            loadState = .failed(error.localizedDescription)
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
