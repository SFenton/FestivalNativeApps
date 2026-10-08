import Foundation

// MARK: - Choice

/// The Item Shop's saved sort (issue #379, pattern `catalogue-sort` R3–R5): one of the
/// Songs catalogue modes Title, Artist, Year or Duration, and a direction.
///
/// It is a page preference, not a player setting: deselecting a player keeps it, and it
/// is saved apart from the Songs sort.
public struct ShopSortChoice: Sendable, Equatable {
    /// The modes the Item Shop offers, in sheet order (R3). No Item Shop, player or
    /// score modes: the Shop has no selected-player dimension.
    public static let modes: [SongSortMode] = [.title, .artist, .year, .duration]
    /// `UserDefaults` key of the saved mode (a ``SongSortMode`` raw value).
    public static let modeKey = "fst.shop.sortMode"
    /// `UserDefaults` key of the saved direction.
    public static let ascendingKey = "fst.shop.sortAscending"

    /// One of ``modes``.
    public let mode: SongSortMode
    /// True for A–Z / low to high.
    public let ascending: Bool

    /// Create a choice, normalizing a mode the Shop does not offer to Title.
    ///
    /// - Parameters:
    ///   - mode: Requested mode; anything outside ``modes`` becomes `.title`.
    ///   - ascending: Direction.
    public init(mode: SongSortMode = .title, ascending: Bool = true) {
        self.mode = Self.modes.contains(mode) ? mode : .title
        self.ascending = ascending
    }

    /// Whether this is the default and Reset choice, Title ascending (R4).
    public var isDefault: Bool { mode == .title && ascending }

    /// What the Sort button announces after its label (R4, the Songs vocabulary).
    ///
    /// - Parameter paused: The mode's data is missing, so Title order shows.
    /// - Returns: "Artist, descending", plus "paused; showing Title order" when paused.
    public func accessibilityValue(paused: Bool = false) -> String {
        "\(mode.label), \(ascending ? "ascending" : "descending")"
            + (paused ? ", paused; showing Title order" : "")
    }
}

// MARK: - Ordering

/// Orders Item Shop offers with the Songs comparator (``SongCatalogSort``, pattern
/// `catalogue-sort` R2): Title and Artist locale-aware, Year and Duration numeric with a
/// missing value as 0, ties by title, then song ID, all in the chosen direction.
public enum ShopOfferSort {
    /// Offers in display order, and whether the chosen mode had to pause.
    public struct Result: Sendable {
        /// Offers in the order every layout renders them (R6).
        public let offers: [ShopSong]
        /// True when Duration has no same-publication catalogue lengths, so the offers
        /// are in title order (in the chosen direction) instead (R7).
        public let paused: Bool
    }

    /// Order offers for a sort choice.
    ///
    /// - Parameters:
    ///   - offers: Offers after the Shop filter (the filter runs first).
    ///   - choice: The saved sort.
    ///   - durations: Catalogue lengths by song ID, only from a catalogue observed with
    ///     the Shop feed's publication; nil when unavailable. A matching catalogue that
    ///     lacks one offer's length sorts that offer as 0.
    /// - Returns: The ordered offers, paused to title order when Duration has no lengths.
    public static func sorted(
        _ offers: [ShopSong], by choice: ShopSortChoice, durations: [String: Int]?
    ) -> Result {
        let paused = choice.mode == .duration && durations == nil
        let mode = paused ? .title : choice.mode
        let keys = offers.map { offer in
            Song(shopOffer: offer, durationSeconds: durations?[offer.songId])
        }
        // Catalogue modes never throw: only Item Shop and player modes need extra data.
        let ordered = (try? SongCatalogSort.sorted(keys, mode: mode, ascending: choice.ascending))
            ?? keys
        let byId = Dictionary(offers.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first })
        return Result(offers: ordered.compactMap { byId[$0.songId] }, paused: paused)
    }

    /// Catalogue lengths the Duration sort may use.
    ///
    /// - Parameters:
    ///   - catalogue: Catalogue songs by ID, or nil when the catalogue read failed.
    ///   - catalogueObservation: Publication observed with the catalogue bytes.
    ///   - shopObservation: Publication observed with the Shop feed.
    ///   - currentObservation: The session's latest observed publication.
    /// - Returns: Lengths by song ID, or nil unless the catalogue loaded with the Shop's
    ///   publication (the publication-provenance invariant; never a guess).
    public static func durations(
        catalogue: [String: Song]?, catalogueObservation: Int?,
        shopObservation: Int?, currentObservation: Int?
    ) -> [String: Int]? {
        guard let catalogue, let catalogueObservation,
              SongShopPublicationPolicy.matches(
                catalogue: catalogueObservation, shop: shopObservation,
                current: currentObservation
              ) else { return nil }
        return catalogue.compactMapValues(\.durationSeconds)
    }
}
