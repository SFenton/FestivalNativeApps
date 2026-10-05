import Foundation

// MARK: - SuggestionRowLayout

/// Which metadata a suggestion row shows beside its song, by category, ported from the
/// web `CategoryCard.getRowLayout` (`pages/suggestions/components/CategoryCard.tsx`).
///
/// The web varies the right-hand content per category family: nothing for discovery
/// lists, an accuracy badge for "finish the FC" lists, a season pill for stale scores, a
/// percentile pill for rank pushes, stars for star-gain lists, a rival badge for rival
/// lists and nine instrument status chips otherwise.
public enum SuggestionRowLayout: Equatable, Sendable {
    /// Nine instrument status chips (web `instrumentChips`).
    case instrumentChips
    /// The row's own instrument icon, plus stars on star-progress categories.
    case singleInstrument
    /// "Top N%" pill plus the row's instrument icon.
    case percentile
    /// The season the current score was set in.
    case season
    /// Accuracy badge (floored, capped at 99%) for a not-yet-FC score.
    case unfcAccuracy
    /// Song info only.
    case hidden
    /// Rival name badge (see `showsRivalName(categoryKey:)`), signed rank delta and the
    /// row's instrument icon.
    case rival

    /// Resolve the layout for a category key (case-insensitive prefixes, web order).
    ///
    /// - Parameter categoryKey: `SuggestionCategory.key`.
    /// - Returns: The metadata layout for every row in that category.
    public static func forCategory(_ categoryKey: String) -> SuggestionRowLayout {
        let k = categoryKey.lowercased()
        func starts(_ prefixes: String...) -> Bool { prefixes.contains { k.hasPrefix($0) } }
        if starts("band_unplayed") { return .hidden }
        if starts("band_near_fc") { return .unfcAccuracy }
        if starts("band_star_progress") { return .singleInstrument }
        if starts("band_pct_push", "band_rank_improve") { return .percentile }
        if starts("band_stale") { return .season }
        if starts("song_rival_", "lb_rival_") { return .rival }
        if starts("variety_pack", "artist_sampler_", "artist_unplayed_", "unplayed_")
            || (starts("samename_") && !starts("samename_nearfc_")) { return .hidden }
        if starts("unfc_") { return .unfcAccuracy }
        if starts("stale_") { return .season }
        if starts("almost_elite", "pct_push", "pct_improve", "same_pct", "improve_rankings") { return .percentile }
        if starts(
            "near_fc", "almost_six_star", "more_stars", "first_plays_mixed", "star_gains",
            "samename_nearfc_", "near_max_"
        ) { return .singleInstrument }
        return .instrumentChips
    }

    /// Whether rows draw their star count (web `showStars`): star-progress categories only.
    ///
    /// - Parameter categoryKey: `SuggestionCategory.key`.
    /// - Returns: True for `star_gains*` and `band_star_progress*`.
    public static func showsStars(categoryKey: String) -> Bool {
        forCategory(categoryKey) == .singleInstrument
            && (categoryKey.hasPrefix("star_gains") || categoryKey.hasPrefix("band_star_progress"))
    }

    /// Key prefixes of rival categories built around one rival, whose title already names
    /// that rival ("Rival Spotlight: {name}", "Close the Gap vs {name}", …).
    static let singleRivalPrefixes = [
        "song_rival_spotlight_", "song_rival_gap_", "song_rival_protect_",
        "song_rival_slipping_", "song_rival_dominate_",
    ]

    /// Whether a rival row draws the rival's name badge beside its rank difference.
    ///
    /// Single-rival categories name the rival in their title, so a per-row badge only
    /// repeats it (issue #29). Mixed-rival categories (Battleground and the cross-pollination
    /// families) keep it, because each row can be about a different rival.
    ///
    /// - Parameter categoryKey: `SuggestionCategory.key`.
    /// - Returns: False for single-rival categories, true otherwise.
    public static func showsRivalName(categoryKey: String) -> Bool {
        let k = categoryKey.lowercased()
        return !singleRivalPrefixes.contains { k.hasPrefix($0) }
    }

    /// VoiceOver label for a rival row's signed rank difference.
    ///
    /// - Parameters:
    ///   - delta: Player rank minus rival rank, signed so positive means the player leads.
    ///   - rivalName: The rival to name when no visible badge already does, else nil.
    /// - Returns: e.g. "3 ranks ahead of Name", "1 rank behind" or "Tied with Name".
    public static func rivalDeltaAccessibilityLabel(delta: Int, rivalName: String?) -> String {
        let magnitude = abs(delta)
        let ranks = magnitude == 1 ? "rank" : "ranks"
        guard let rivalName, !rivalName.isEmpty else {
            return delta == 0 ? "Tied" : "\(magnitude) \(ranks) \(delta > 0 ? "ahead" : "behind")"
        }
        if delta == 0 { return "Tied with \(rivalName)" }
        return "\(magnitude) \(ranks) \(delta > 0 ? "ahead of" : "behind") \(rivalName)"
    }

    /// Whether the metadata is only an icon or pill, which the web keeps on the song's
    /// line instead of wrapping to a second line on narrow screens (web `iconOnly`).
    ///
    /// - Parameter showsStars: Whether this row draws stars.
    public func isCompact(showsStars: Bool) -> Bool {
        switch self {
        case .singleInstrument: !showsStars
        case .season, .hidden: true
        case .instrumentChips, .percentile, .unfcAccuracy, .rival: false
        }
    }

    /// Whether a row puts its metadata under the song instead of beside it.
    ///
    /// Compact width stacks the wide layouts (web narrow screens); accessibility text
    /// sizes stack every layout with metadata at any width, where a regular-width row
    /// squeezed its pill until "Top 4%" read back as "Top…" (HIG Typography: "consider
    /// stacking text above secondary items").
    ///
    /// - Parameters:
    ///   - regularWidth: The row's horizontal size class is regular.
    ///   - accessibilitySize: The text size is an accessibility size.
    ///   - showsStars: Whether this row draws stars.
    /// - Returns: True for two rows.
    public func stacksMetadata(regularWidth: Bool, accessibilitySize: Bool, showsStars: Bool) -> Bool {
        guard self != .hidden else { return false }
        if accessibilitySize { return true }
        return !regularWidth && !isCompact(showsStars: showsStars)
    }

    /// The instrument a single-instrument category is about (web `getCatInstrument`),
    /// drawn beside the category title.
    ///
    /// - Parameter categoryKey: e.g. `unfc_Solo_Guitar`, `pct_improve_Solo_Bass_5`.
    /// - Returns: The instrument named right after a known prefix, else nil.
    public static func categoryInstrument(_ categoryKey: String) -> Instrument? {
        let prefixes = [
            "unfc_", "unplayed_", "almost_elite_", "pct_push_", "stale_", "pct_improve_",
            "improve_rankings_",
        ]
        guard let prefix = prefixes.first(where: categoryKey.hasPrefix) else { return nil }
        let remainder = categoryKey.dropFirst(prefix.count)
        return Instrument.allCases.first { remainder == $0.rawValue || remainder.hasPrefix($0.rawValue + "_") }
    }

    /// The web `unfcAccuracy` badge value: floor of the percent, capped at 99, in the
    /// service's ten-thousandths-of-a-percent scale; nil when there is no positive percent.
    ///
    /// - Parameter percent: Row accuracy as 0–100.
    public static func unfcAccuracy(percent: Double?) -> Double? {
        guard let percent, percent > 0 else { return nil }
        return Double(min(99, max(0, Int(percent.rounded(.down))))) * 10_000
    }
}
