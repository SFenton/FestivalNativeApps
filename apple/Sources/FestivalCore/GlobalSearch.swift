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
}
