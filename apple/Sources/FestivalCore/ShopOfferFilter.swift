import Foundation

// MARK: - Shop availability

/// One availability group an Item Shop offer belongs to, read from the feed's own
/// `isNew` / `leavingTomorrow` flags (never from the effective highlight, which Settings
/// can hide).
public enum ShopAvailability: String, CaseIterable, Sendable, Identifiable {
    case new
    case available
    case leavingTomorrow

    public var id: String { rawValue }

    /// Readable filter name, also spoken by VoiceOver.
    public var label: String {
        switch self {
        case .new: "New"
        case .available: "Available"
        case .leavingTomorrow: "Leaving Tomorrow"
        }
    }

    /// The groups an offer is in.
    ///
    /// "Available" is every offer that is neither New nor Leaving Tomorrow, so the three
    /// groups together cover the whole Shop; an offer flagged both New and Leaving
    /// Tomorrow is in both of those groups.
    ///
    /// - Parameter offer: Validated public Shop offer.
    /// - Returns: One or two groups; never empty.
    public static func groups(of offer: ShopSong) -> Set<ShopAvailability> {
        var groups = Set<ShopAvailability>()
        if offer.isNew { groups.insert(.new) }
        if offer.leavingTomorrow { groups.insert(.leavingTomorrow) }
        if groups.isEmpty { groups.insert(.available) }
        return groups
    }
}

// MARK: - Filter

/// The Item Shop's New / Available / Leaving Tomorrow filter (issue #19).
///
/// Each switch is independent. With none on the filter is inactive and every offer
/// shows; otherwise an offer shows when it is in any selected group.
public struct ShopOfferFilter: Sendable, Equatable {
    public var new: Bool
    public var available: Bool
    public var leavingTomorrow: Bool

    /// Create a filter; all off (the default) shows every offer.
    ///
    /// - Parameters:
    ///   - new: Show offers the feed marks New.
    ///   - available: Show offers that are neither New nor Leaving Tomorrow.
    ///   - leavingTomorrow: Show offers the feed marks Leaving Tomorrow.
    public init(new: Bool = false, available: Bool = false, leavingTomorrow: Bool = false) {
        self.new = new
        self.available = available
        self.leavingTomorrow = leavingTomorrow
    }

    /// Whether any group is selected.
    public var isActive: Bool { new || available || leavingTomorrow }

    /// The selected groups, in display order.
    public var selected: [ShopAvailability] {
        ShopAvailability.allCases.filter(includes)
    }

    /// Whether a group's switch is on.
    ///
    /// - Parameter group: One availability group.
    /// - Returns: The switch state.
    public func includes(_ group: ShopAvailability) -> Bool {
        switch group {
        case .new: new
        case .available: available
        case .leavingTomorrow: leavingTomorrow
        }
    }

    /// A copy with one group's switch changed.
    ///
    /// - Parameters:
    ///   - group: The group to change.
    ///   - included: The new switch state.
    /// - Returns: The updated filter.
    public func setting(_ group: ShopAvailability, included: Bool) -> ShopOfferFilter {
        var copy = self
        switch group {
        case .new: copy.new = included
        case .available: copy.available = included
        case .leavingTomorrow: copy.leavingTomorrow = included
        }
        return copy
    }

    /// Whether an offer passes the filter.
    ///
    /// - Parameter offer: Validated public Shop offer.
    /// - Returns: True when inactive, or when the offer is in a selected group.
    public func matches(_ offer: ShopSong) -> Bool {
        guard isActive else { return true }
        return ShopAvailability.groups(of: offer).contains(where: includes)
    }

    /// Keep matching offers in their current order.
    ///
    /// - Parameter offers: Offers in display order.
    /// - Returns: The matching offers, or all of them when inactive.
    public func filtered(_ offers: [ShopSong]) -> [ShopSong] {
        guard isActive else { return offers }
        return offers.filter(matches)
    }
}
