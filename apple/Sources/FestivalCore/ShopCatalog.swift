import Foundation

/// Enriched song available through the public Item Shop feed.
public struct ShopSong: Decodable, Sendable, Identifiable {
    public let songId: String
    public let title: String
    public let artist: String
    public let year: Int?
    public let albumArt: String?
    public let shopUrl: URL
    public let leavingTomorrow: Bool
    public let isNew: Bool

    public var id: String { songId }
}

extension Song {
    /// A display-only song for a Shop offer the loaded catalogue does not list (or
    /// when the catalogue read failed), so the Shop can still draw the shared Song row.
    ///
    /// Carries only the offer's own presentation fields: no charts, duration, scores
    /// or path data. Never use it as a Song Detail route; only a real catalogue match
    /// may navigate.
    ///
    /// - Parameter offer: Validated public Shop offer.
    public init(shopOffer offer: ShopSong) {
        songId = offer.songId
        title = offer.title
        artist = offer.artist
        album = nil
        year = offer.year
        durationSeconds = nil
        albumArt = offer.albumArt
        difficulty = nil
        pathArtifactGenerationId = nil
        sig = nil
        maxScores = nil
        doubleBassSupported = nil
    }
}

/// Complete, publication-scoped `/api/shop` response.
public struct ShopResponse: Decodable, Sendable {
    public let count: Int
    public let songs: [ShopSong]
    public let newSongs: [String]?
    public let lastUpdated: String?

    /// Reject contradictory rows and untrusted outbound links.
    ///
    /// - Throws: `FestivalAPIError.invalidShop` for invalid cardinality, IDs or URLs.
    public func validate() throws {
        guard count >= 0, count <= 10_000, count == songs.count,
              Set(songs.map { $0.songId.lowercased() }).count == songs.count,
              songs.allSatisfy({ song in
                  !song.songId.isEmpty && !song.songId.contains("/")
                  && !song.title.isEmpty && !song.artist.isEmpty
                  && song.shopUrl.scheme == "https"
                  && song.shopUrl.host?.lowercased() == "www.fortnite.com"
                  && song.shopUrl.path.hasPrefix("/item-shop/jam-tracks/")
                  && song.shopUrl.path != "/item-shop/jam-tracks/"
                  && song.shopUrl.user == nil && song.shopUrl.password == nil
                  && song.shopUrl.port == nil && song.shopUrl.query == nil
                  && song.shopUrl.fragment == nil
              }) else {
            throw FestivalAPIError.invalidShop
        }
    }

    /// Retain deterministic title order independent of service iteration.
    ///
    /// - Returns: Current shop items in the source's title-first order.
    public func sortedSongs() -> [ShopSong] {
        songs.sorted { first, second in
            let order = first.title.localizedCompare(second.title)
            return order == .orderedSame
                ? first.songId < second.songId : order == .orderedAscending
        }
    }
}

/// One real Shop availability accent, not a fallback for missing feed data.
public enum ShopHighlight: String, Sendable, Equatable {
    case new
    case leavingTomorrow

    /// Announce badge meaning independently of the highlight color.
    ///
    /// - Returns: Readable availability state.
    public var label: String {
        switch self {
        case .new: "New"
        case .leavingTomorrow: "Leaving Tomorrow"
        }
    }
}

/// Share the effective hide/highlight policy across Shop, Songs and Detail.
public enum ShopPresentationPolicy {
    /// Preserve preference while suppressing every hidden or disabled highlight.
    ///
    /// - Parameters:
    ///   - offer: Validated current Shop row, nil until data exists or if absent.
    ///   - hidden: The app's Hide Item Shop setting.
    ///   - highlightingDisabled: The saved disable-highlighting preference.
    /// - Returns: Leaving Tomorrow, then New, or nil when no accent applies.
    public static func highlight(
        for offer: ShopSong?, hidden: Bool, highlightingDisabled: Bool
    ) -> ShopHighlight? {
        guard !hidden, !highlightingDisabled, let offer else { return nil }
        if offer.leavingTomorrow { return .leavingTomorrow }
        if offer.isNew { return .new }
        return nil
    }
}

/// Shop bytes decoded without treating an observed publication as response proof.
public struct ShopPayload: Sendable {
    public let shop: ShopResponse
    public let sortedSongs: [ShopSong]
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

extension FestivalAPI {
    /// Fetch typed public Shop data without a privileged key or disk cache.
    ///
    /// - Returns: Validated item rows, deterministic order and freshness provenance.
    /// - Throws: HTTP, publication, malformed-data or transport failures.
    public func shop() async throws -> ShopPayload {
        let payload = try await read(.shop)
        let shop: ShopResponse
        do {
            shop = try JSONDecoder().decode(ShopResponse.self, from: payload.data)
        } catch is DecodingError {
            throw FestivalAPIError.invalidShop
        }
        try shop.validate()
        try await rememberUnverified(payload, for: .shop)
        return ShopPayload(
            shop: shop, sortedSongs: shop.sortedSongs(),
            publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId,
            isStale: payload.isStale
        )
    }
}
