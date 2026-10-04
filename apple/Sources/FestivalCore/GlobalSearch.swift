import Foundation

// MARK: - Scope

/// Which result kinds global search shows (web `SearchTarget` chips plus the combined view).
///
/// The web's chips start unselected, meaning "everything"; natively that is `.all`,
/// the first segment of a scope bar (HIG: default to the broader scope).
public enum GlobalSearchScope: String, CaseIterable, Sendable, Identifiable {
    case all
    case songs
    case players
    case bands

    public var id: Self { self }

    /// Scope-bar label.
    public var title: String {
        switch self {
        case .all: "All"
        case .songs: "Songs"
        case .players: "Players"
        case .bands: "Bands"
        }
    }

    /// Result sections shown for this scope, in the web's fixed order. "All" omits Bands:
    /// band search is never sent natively, so it has no results to group.
    public var sections: [GlobalSearchScope] {
        self == .all ? [.songs, .players] : [self]
    }
}

// MARK: - Rules

/// Pure global-search rules ported from the web `useUnifiedSearch`
/// (`FortniteFestivalWeb/src/hooks/data/useUnifiedSearch.ts`).
///
/// Songs filter the local catalogue; players use the allowlisted
/// `GET /api/account/search`. Band search is never sent: its server fallback writes
/// (`.agents/platforms/service-safety.md`), so the Bands scope explains that instead.
public enum GlobalSearch {
    /// Queries shorter than this show the hint and fetch nothing.
    public static let minimumQueryLength = 2
    /// Web `DEBOUNCE_MS`.
    public static let debounce: Duration = .milliseconds(250)
    /// Web song result limit.
    public static let songLimit = 20
    /// Web player result limit (also the account-search maximum).
    public static let playerLimit = 10

    /// The trimmed query when it is long enough to search.
    ///
    /// - Parameter raw: Text typed in the search field.
    /// - Returns: The trimmed query, or nil below ``minimumQueryLength``.
    public static func effectiveQuery(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumQueryLength ? trimmed : nil
    }

    /// Catalogue songs whose title or artist contains the query, in catalogue order.
    ///
    /// The web does not rank: it keeps the first ``songLimit`` matches in catalogue order.
    ///
    /// - Parameters:
    ///   - songs: Loaded catalogue rows.
    ///   - query: Raw query text.
    ///   - limit: Maximum rows to return.
    /// - Returns: Matching songs, empty below the minimum query length.
    public static func songs(in songs: [Song], matching query: String, limit: Int = songLimit) -> [Song] {
        guard let query = effectiveQuery(query) else { return [] }
        var matches: [Song] = []
        for song in songs where SongSearch.matches(song, query: query) {
            matches.append(song)
            if matches.count == limit { break }
        }
        return matches
    }

    /// Search-field prompt for the scopes shown (web `search.placeholders.*`).
    ///
    /// - Parameter scope: Active scope.
    /// - Returns: The English prompt.
    public static func prompt(for scope: GlobalSearchScope) -> String {
        switch scope {
        // Bands are never searched natively, so "All" names only the live scopes.
        case .all: "Search songs or players"
        case .songs: "Search songs"
        case .players: "Search players"
        case .bands: "Search bands"
        }
    }

    // MARK: - Empty state

    /// Copy for the centred empty state below the scope bar (issue #99): a title, a
    /// subtitle naming the query, and whether Retry is offered.
    public struct EmptyState: Equatable, Sendable {
        /// Title Case heading, e.g. "No Players Found".
        public let title: String
        /// Sentence naming the query and the next step.
        public let subtitle: String
        /// True when players were searched: an empty account-search envelope can be a
        /// server timeout (`.agents/platforms/service-safety.md`), so it gets Retry.
        public let offersRetry: Bool

        /// One VoiceOver label for the whole state: title, subtitle, then "Retry".
        public var accessibilityLabel: String {
            let text = "\(title). \(subtitle)"
            return offersRetry ? "\(text) Retry" : text
        }
    }

    /// Empty state for a scope whose shown sections all finished with no results.
    ///
    /// In "All", a single empty section is hidden instead (web `SearchModal` renders only
    /// sections with results or an error); this is for when every section is empty.
    ///
    /// - Parameters:
    ///   - scope: Active scope.
    ///   - query: Raw query text; a query under two characters has no empty state.
    /// - Returns: The copy (subtitles are the cross-platform contract text in
    ///   `.agents/controls/global-search/spec.md`), or nil for Bands (never searched)
    ///   and short queries.
    public static func emptyState(scope: GlobalSearchScope, query: String) -> EmptyState? {
        guard effectiveQuery(query) != nil else { return nil }
        switch scope {
        case .bands:
            return nil
        case .all:
            return EmptyState(
                title: "No Results Found",
                subtitle: "Check the spelling or try a different song, artist or player.",
                offersRetry: true
            )
        case .songs:
            return EmptyState(
                title: "No Songs Found",
                subtitle: "Check the spelling or try a different song or artist.",
                offersRetry: false
            )
        case .players:
            return EmptyState(
                title: "No Players Found",
                subtitle: "Check the spelling or try a different player name.",
                offersRetry: true
            )
        }
    }

    // MARK: - Result-count announcement

    /// Where one result section stands, for the VoiceOver result-count announcement.
    public enum SectionOutcome: Equatable, Sendable {
        /// Still searching (or not searched yet).
        case pending
        /// The search failed; the section shows Retry.
        case failed
        /// Finished with this many results.
        case found(Int)
    }

    /// What VoiceOver announces once the results for a query settle (web live region
    /// equivalent): nil while a section the scope shows is still pending, and for
    /// Bands (never searched).
    ///
    /// - Parameters:
    ///   - scope: Active scope.
    ///   - songs: Songs section outcome.
    ///   - players: Players section outcome.
    /// - Returns: "3 songs, 1 player", "No results found.", …, or nil.
    public static func resultAnnouncement(
        scope: GlobalSearchScope, songs: SectionOutcome, players: SectionOutcome
    ) -> String? {
        func count(_ outcome: SectionOutcome, _ one: String, _ many: String) -> String? {
            switch outcome {
            case .pending: nil
            case .failed: "\(many.capitalized) unavailable"
            case let .found(value): "\(value) \(value == 1 ? one : many)"
            }
        }
        switch scope {
        case .bands:
            return nil
        case .songs:
            if songs == .found(0) { return "No songs found." }
            return count(songs, "song", "songs")
        case .players:
            if players == .found(0) { return "No players found." }
            return count(players, "player", "players")
        case .all:
            guard songs != .pending, players != .pending else { return nil }
            if songs == .found(0) && players == .found(0) { return "No results found." }
            return [count(songs, "song", "songs"), count(players, "player", "players")]
                .compactMap { $0 }.joined(separator: ", ")
        }
    }
}
