import Foundation

/// The General section's Item Shop availability choice (web `shopAvailability`), kept
/// independent of a selected player's scores.
///
/// Both categories default on. Turning one off hides that category; turning both off
/// hides every song, even before Shop data loads (web `useFilteredSongs`).
public struct SongShopFilter: Sendable, Equatable, Hashable {
    /// Include songs in the validated public Item Shop.
    public let available: Bool
    /// Include songs not in the validated public Item Shop.
    public let unavailable: Bool

    /// Keep the two source toggles independent; the default includes every song.
    ///
    /// - Parameters:
    ///   - available: Include songs available in the Item Shop.
    ///   - unavailable: Include songs not available in the Item Shop.
    public init(available: Bool = true, unavailable: Bool = true) {
        self.available = available
        self.unavailable = unavailable
    }

    /// Only songs available in the Item Shop: the migration target of the older
    /// In Shop / Leaving Tomorrow choices (web `loadSongSettings`).
    public static let availableOnly = SongShopFilter(available: true, unavailable: false)

    /// Whether this choice hides any song.
    public var isActive: Bool { !(available && unavailable) }

    /// Whether classifying songs needs a validated Shop feed (exactly one category on).
    public var needsShopFeed: Bool { available != unavailable }

    /// Filter after catalogue search/chart selection without changing row order.
    ///
    /// - Parameters:
    ///   - songs: Validated catalogue rows in their current relative order.
    ///   - offersById: Only validated public Shop offers; nil means unavailable, not empty.
    /// - Returns: Matching rows, including an honest empty set for a validated empty Shop.
    /// - Throws: `FestivalAPIError.invalidShop` when one category needs a missing feed.
    public func filtered(
        _ songs: [Song], offersById: [String: ShopSong]?
    ) throws -> [Song] {
        guard isActive else { return songs }
        guard available || unavailable else { return [] }
        guard let offersById else { throw FestivalAPIError.invalidShop }
        return songs.filter { (offersById[$0.songId] != nil) == available }
    }
}

/// One observed publication must own catalogue rows and their related data.
public enum SongRelatedPublicationPolicy {
    /// Reject data from a different observation, including a retained older catalogue.
    ///
    /// - Parameters:
    ///   - catalogueObservation: Generation observed when Songs bytes were validated.
    ///   - relatedObservation: Generation observed when related data was validated.
    ///   - currentObservation: Latest generation observed by the native session.
    /// - Returns: True only when all three observations are available and equal.
    public static func matches(
        catalogue catalogueObservation: Int,
        related relatedObservation: Int?,
        current currentObservation: Int?
    ) -> Bool {
        guard let relatedObservation, let currentObservation else { return false }
        return catalogueObservation == currentObservation
            && relatedObservation == currentObservation
    }
}

/// Shop filtering, sorting and badges share the catalogue's observed generation.
public enum SongShopPublicationPolicy {
    /// Keep validated empty offers eligible without crossing publications.
    ///
    /// - Parameters:
    ///   - catalogueObservation: Generation observed when Songs bytes were validated.
    ///   - shopObservation: Generation observed when Shop offers were validated.
    ///   - currentObservation: Latest generation observed by the native session.
    /// - Returns: True for matching observations, including a validated empty Shop feed.
    public static func matches(
        catalogue catalogueObservation: Int,
        shop shopObservation: Int?,
        current currentObservation: Int?
    ) -> Bool {
        SongRelatedPublicationPolicy.matches(
            catalogue: catalogueObservation, related: shopObservation,
            current: currentObservation
        )
    }
}
