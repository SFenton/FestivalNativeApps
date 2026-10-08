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

/// The Item Shop's New / Available / Leaving Tomorrow filter (issues #19, #376).
///
/// Each switch is an independent include toggle, like the Songs Item Shop filter
/// (``SongShopFilter``): all on (the default) lists every offer, and turning a switch off
/// hides that group. An offer shows while any of its groups is on, so an offer flagged
/// both New and Leaving Tomorrow hides only when both are off; all off shows nothing.
public struct ShopOfferFilter: Sendable, Equatable {
    public var new: Bool
    public var available: Bool
    public var leavingTomorrow: Bool

    /// Create a filter; all on (the default) shows every offer.
    ///
    /// - Parameters:
    ///   - new: Show offers the feed marks New.
    ///   - available: Show offers that are neither New nor Leaving Tomorrow.
    ///   - leavingTomorrow: Show offers the feed marks Leaving Tomorrow.
    public init(new: Bool = true, available: Bool = true, leavingTomorrow: Bool = true) {
        self.new = new
        self.available = available
        self.leavingTomorrow = leavingTomorrow
    }

    /// Whether any switch is off, so the filter hides offers.
    public var isActive: Bool { !(new && available && leavingTomorrow) }

    /// The groups whose switch is on, in display order.
    public var selected: [ShopAvailability] {
        ShopAvailability.allCases.filter(includes)
    }

    /// The groups whose switch is off, in display order.
    public var hidden: [ShopAvailability] {
        ShopAvailability.allCases.filter { !includes($0) }
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
    /// - Returns: True when any of the offer's groups is switched on.
    public func matches(_ offer: ShopSong) -> Bool {
        ShopAvailability.groups(of: offer).contains(where: includes)
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

// MARK: - Saved preference

extension ShopOfferFilter {
    /// Saved hidden groups (issue #376); empty means the default or not yet saved.
    public static let storageKey = "fst.shop.offerFilter"
    /// Older "show only" New switch (issue #19), read only to migrate once.
    public static let legacyNewKey = "fst.shop.filterNew"
    /// Older "show only" Available switch (issue #19), read only to migrate once.
    public static let legacyAvailableKey = "fst.shop.filterAvailable"
    /// Older "show only" Leaving Tomorrow switch (issue #19), read only to migrate once.
    public static let legacyLeavingTomorrowKey = "fst.shop.filterLeavingTomorrow"

    /// Longest saved value accepted: every group name plus separators, with headroom.
    static let maxSavedLength = 128

    /// Store the switched-off groups as comma-separated raw values, or "" for the default.
    ///
    /// Every switch off is stored explicitly, so it stays distinct from the default.
    ///
    /// - Returns: Deterministic text in display order.
    public func encoded() -> String {
        hidden.map(\.rawValue).joined(separator: ",")
    }

    /// Decode a saved filter, migrating the older "show only" switches once.
    ///
    /// Before issue #376 the switches chose which groups to show and all off showed every
    /// offer. Both readings list the same offers once all-off becomes all-on, so nobody's
    /// Shop changes on update.
    ///
    /// - Parameters:
    ///   - saved: Text from ``encoded()``; empty for the default or never saved.
    ///   - legacyNew: Older New switch, read only when `saved` is empty.
    ///   - legacyAvailable: Older Available switch, read only when `saved` is empty.
    ///   - legacyLeavingTomorrow: Older Leaving Tomorrow switch, read only when `saved` is empty.
    /// - Returns: The filter to apply. Oversized or unreadable text falls back to the
    ///   all-on default, which hides nothing.
    public static func decodeSaved(
        _ saved: String, legacyNew: Bool = false, legacyAvailable: Bool = false,
        legacyLeavingTomorrow: Bool = false
    ) -> ShopOfferFilter {
        guard !saved.isEmpty else {
            guard legacyNew || legacyAvailable || legacyLeavingTomorrow else { return Self() }
            return Self(
                new: legacyNew, available: legacyAvailable, leavingTomorrow: legacyLeavingTomorrow
            )
        }
        guard saved.count <= maxSavedLength else { return Self() }
        var filter = Self()
        for token in saved.split(separator: ",") {
            guard let group = ShopAvailability(rawValue: String(token)) else { return Self() }
            filter = filter.setting(group, included: false)
        }
        return filter
    }
}
