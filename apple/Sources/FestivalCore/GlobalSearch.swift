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

    /// Result sections shown for this scope, in the web's fixed order (songs, players,
    /// bands; issue #320 added bands to "All").
    public var sections: [GlobalSearchScope] {
        self == .all ? [.songs, .players, .bands] : [self]
    }
}

// MARK: - Rules

/// Pure global-search rules ported from the web `useUnifiedSearch`
/// (`FortniteFestivalWeb/src/hooks/data/useUnifiedSearch.ts`).
///
/// Songs filter the local catalogue; players use the allowlisted
/// `GET /api/account/search` and bands `GET /api/bands/search` (read-only since issue
/// #320, `.agents/platforms/service-safety.md`).
public enum GlobalSearch {
    /// Queries shorter than this show the hint and fetch nothing.
    public static let minimumQueryLength = 2
    /// Web `DEBOUNCE_MS`.
    public static let debounce: Duration = .milliseconds(250)
    /// Web song result limit.
    public static let songLimit = 20
    /// Web player result limit (also the account-search maximum).
    public static let playerLimit = 10
    /// Web band result limit (`useUnifiedSearch` `bandLimit`, `pageSize=10`).
    public static let bandLimit = 10

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
        case .all: "Search songs, players, or bands"
        case .songs: "Search songs"
        case .players: "Search players"
        case .bands: "Search bands"
        }
    }

    /// Centred hint shown while the query is under ``minimumQueryLength`` (issue #299):
    /// it names what the active scope searches.
    ///
    /// - Parameter scope: Active scope.
    /// - Returns: The English hint.
    public static func enterQueryHint(for scope: GlobalSearchScope) -> String {
        let prefix = "Enter at least two characters to search for"
        return switch scope {
        case .all: "\(prefix) songs, players, or bands."
        case .songs: "\(prefix) songs."
        case .players: "\(prefix) players."
        case .bands: "\(prefix) bands."
        }
    }

    /// Fallback title for a failed section whose issue has no title of its own: with no
    /// section headings (issue #299), the row names what failed.
    ///
    /// - Parameter section: `.songs`, `.players` or `.bands`.
    /// - Returns: "Songs unavailable", "Players unavailable" or "Bands unavailable" (the
    ///   announcement's words).
    public static func unavailableTitle(for section: GlobalSearchScope) -> String {
        "\(section.title) unavailable"
    }

    /// Whether the one centred spinner shows instead of results (issue #299, web
    /// `SearchModal` parity): All waits until Songs, Players and Bands have all settled;
    /// a single scope waits only for itself (Songs never waits for the network).
    ///
    /// - Parameters:
    ///   - scope: Active scope.
    ///   - outcomes: Every section's outcome.
    /// - Returns: True while any section the scope shows is still pending.
    public static func isSearching(scope: GlobalSearchScope, outcomes: Outcomes) -> Bool {
        scope.sections.contains { outcomes[$0] == .pending }
    }

    /// Whether pressing Search on the keyboard re-runs the current query.
    ///
    /// With no Retry button (issue #299), submitting the same text again is how a
    /// failed search, or an empty player search that may be a server timeout
    /// (`.agents/platforms/service-safety.md`), is retried. Settled results with rows
    /// and in-flight searches are not re-sent.
    ///
    /// - Parameters:
    ///   - scope: Active scope.
    ///   - outcomes: Every section's outcome.
    /// - Returns: True when a shown section failed, or players or bands finished empty.
    public static func submitReruns(scope: GlobalSearchScope, outcomes: Outcomes) -> Bool {
        scope.sections.contains { section in
            switch outcomes[section] {
            case .failed: true
            // A network section's empty envelope may be a server timeout; local song
            // matches are exact.
            case .found(0): section != .songs
            default: false
            }
        }
    }

    // MARK: - Empty state

    /// Copy for the centred empty state below the scope bar (issue #99): a title and a
    /// subtitle with the next step. No Retry (issue #299): pressing Search re-runs it.
    public struct EmptyState: Equatable, Sendable {
        /// Title Case heading, e.g. "No Players Found".
        public let title: String
        /// Sentence naming the next step.
        public let subtitle: String

        /// One VoiceOver label for the whole state: title, then subtitle.
        public var accessibilityLabel: String {
            "\(title). \(subtitle)"
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
    ///   `.agents/controls/global-search/spec.md`), or nil for short queries.
    public static func emptyState(scope: GlobalSearchScope, query: String) -> EmptyState? {
        guard effectiveQuery(query) != nil else { return nil }
        switch scope {
        case .bands:
            return EmptyState(
                title: "No Bands Found",
                subtitle: "Check the spelling or try a different band member's name."
            )
        case .all:
            return EmptyState(
                title: "No Results Found",
                subtitle: "Check the spelling or try a different song, artist, player or band."
            )
        case .songs:
            return EmptyState(
                title: "No Songs Found",
                subtitle: "Check the spelling or try a different song or artist."
            )
        case .players:
            return EmptyState(
                title: "No Players Found",
                subtitle: "Check the spelling or try a different player name."
            )
        }
    }

    // MARK: - Result-count announcement

    /// Where one result section stands, for the VoiceOver result-count announcement.
    public enum SectionOutcome: Equatable, Sendable {
        /// Still searching (or not searched yet).
        case pending
        /// The search failed; the section shows why, without Retry (issue #299).
        case failed
        /// Finished with this many results.
        case found(Int)
    }

    /// The outcome of each result section for one query.
    public struct Outcomes: Equatable, Sendable {
        public var songs: SectionOutcome
        public var players: SectionOutcome
        public var bands: SectionOutcome

        /// Create the outcomes.
        ///
        /// - Parameters:
        ///   - songs: Songs section outcome.
        ///   - players: Players section outcome.
        ///   - bands: Bands section outcome.
        public init(songs: SectionOutcome, players: SectionOutcome, bands: SectionOutcome) {
            self.songs = songs
            self.players = players
            self.bands = bands
        }

        /// One section's outcome; `.all` is not a section and reads as pending.
        public subscript(section: GlobalSearchScope) -> SectionOutcome {
            switch section {
            case .songs: songs
            case .players: players
            case .bands: bands
            case .all: .pending
            }
        }
    }

    /// What VoiceOver announces once the results for a query settle (web live region
    /// equivalent): nil while a section the scope shows is still pending.
    ///
    /// - Parameters:
    ///   - scope: Active scope.
    ///   - outcomes: Every section's outcome.
    /// - Returns: "3 songs, 1 player, 2 bands", "No results found.", …, or nil.
    public static func resultAnnouncement(scope: GlobalSearchScope, outcomes: Outcomes) -> String? {
        let shown = scope.sections
        guard !isSearching(scope: scope, outcomes: outcomes) else { return nil }
        if shown.allSatisfy({ outcomes[$0] == .found(0) }) {
            return scope == .all ? "No results found." : "No \(scope.title.lowercased()) found."
        }
        return shown.compactMap { section -> String? in
            let many = section.title.lowercased()
            switch outcomes[section] {
            case .pending: return nil
            case .failed: return "\(section.title) unavailable"
            case let .found(value): return "\(value) \(value == 1 ? String(many.dropLast()) : many)"
            }
        }.joined(separator: ", ")
    }
}
