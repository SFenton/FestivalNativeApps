import Foundation

/// Applied Item Shop filters retained independently of a selected player's scores.
public struct SongShopFilter: Sendable, Equatable {
    public let inShop: Bool
    public let leavingTomorrow: Bool

    /// Keep the two source toggles independent, including an inactive default.
    ///
    /// - Parameters:
    ///   - inShop: Require validated current Shop membership.
    ///   - leavingTomorrow: Require a validated offer leaving tomorrow.
    public init(inShop: Bool = false, leavingTomorrow: Bool = false) {
        self.inShop = inShop
        self.leavingTomorrow = leavingTomorrow
    }

    public var isActive: Bool { inShop || leavingTomorrow }

    /// Filter after catalogue search/chart selection without changing row order.
    ///
    /// - Parameters:
    ///   - songs: Validated catalogue rows in their current relative order.
    ///   - offersById: Only validated public Shop offers; nil means unavailable, not empty.
    /// - Returns: Matching rows, including an honest empty set for a validated empty Shop.
    /// - Throws: `FestivalAPIError.invalidShop` when an active filter lacks a validated feed.
    public func filtered(
        _ songs: [Song], offersById: [String: ShopSong]?
    ) throws -> [Song] {
        guard isActive else { return songs }
        guard let offersById else { throw FestivalAPIError.invalidShop }
        return songs.filter { song in
            guard let offer = offersById[song.songId] else { return false }
            return !leavingTomorrow || offer.leavingTomorrow
        }
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
