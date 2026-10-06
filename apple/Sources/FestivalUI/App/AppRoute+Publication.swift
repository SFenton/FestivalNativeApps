import FestivalCore

// MARK: - Song-valued routes across publications (issue #304)

extension AppRoute {
    /// The song a Songs route carries from the catalogue it was opened from, or nil.
    var song: Song? {
        switch self {
        case let .songDetail(song), let .songLeaderboard(song, _, _, _),
             let .songBandLeaderboard(song, _, _, _), let .playerHistory(song, _):
            song
        default:
            nil
        }
    }

    /// The same route with its song re-read from a newer catalogue, so a page refreshed
    /// for a new publication never shows the old catalogue's song with new scores.
    ///
    /// - Parameter song: The same song (by ID) from the current catalogue.
    /// - Returns: The route with `song` replaced; other routes are unchanged.
    func replacingSong(_ song: Song) -> AppRoute {
        switch self {
        case .songDetail: .songDetail(song)
        case let .songLeaderboard(_, instrument, page, focusSelected):
            .songLeaderboard(song, instrument, page, focusSelected: focusSelected)
        case let .songBandLeaderboard(_, bandType, page, focus):
            .songBandLeaderboard(song, bandType: bandType, page: page, focus: focus)
        case let .playerHistory(_, instrument): .playerHistory(song, instrument)
        default: self
        }
    }
}

/// A Songs route's song after a publication change.
enum RouteSongRefresh: Equatable {
    /// The song the route was opened with (no publication change since).
    case route
    /// The same song from the current catalogue.
    case current(Song)
    /// The current catalogue no longer has the song.
    case missing
    /// The current catalogue could not be read.
    case failed(ServiceIssue)

    /// Re-resolve a song ID against a catalogue read for the session's publication.
    ///
    /// - Parameters:
    ///   - songId: The route's song ID.
    ///   - payload: The catalogue just read.
    ///   - publicationId: The session's current publication.
    /// - Returns: The current song, ``missing``, or ``failed(_:)`` when the catalogue
    ///   belongs to another publication (never mix generations).
    static func resolve(songId: String, in payload: CatalogPayload, publicationId: Int?) -> RouteSongRefresh {
        guard payload.observedPublicationId == publicationId else {
            return .failed(ServiceIssue(FestivalAPIError.invalidPublication))
        }
        return payload.catalog.songs.first { $0.songId == songId }.map(RouteSongRefresh.current) ?? .missing
    }
}
