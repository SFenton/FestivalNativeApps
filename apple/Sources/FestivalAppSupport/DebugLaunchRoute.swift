import FestivalCore

// MARK: - Debug launch routing

#if DEBUG
/// Parses `FST_DEBUG_TAB` / `FST_DEBUG_ROUTE` so `tools/ios_sim.py` can open any page directly.
///
/// Route syntax: `player:<accountId>`, `leaderboards`, `fullRankings:<Instrument rawValue>`,
/// `fullComboRankings:<Instrument rawValue>+<Instrument rawValue>[+…]`,
/// `shop`, `rivals`, `statistics`, `suggestions`, `compete`, `bands`, `licenses`,
/// `settingsTopic:<SettingsTopic rawValue>` (with `FST_DEBUG_TAB=settings`),
/// `allRivals:<scope>`, `rivalDetail:<rivalId>[:<scope>]`, `rivalry:<rivalId>:<mode>[:<scope>]`.
/// `<scope>` is `RivalScope.debugToken`: `song:<instrument>[,<instrument>…]`,
/// `leaderboard:<instrument>:<rankBy>` or `combo:<token>:<instrument>[,<instrument>…]`.
/// Song routes need a loaded `Song`; the Songs lane handles `FST_DEBUG_SONG` itself.
///
/// `FST_DEBUG_TAB=search` opens the Search tab over Songs (iPhone Duo's rail Search
/// button is not reachable by XCUITest taps on the inner display; Lane A11Y4).
///
/// Shell extras: `FST_DEBUG_DRAWER=1` opens the hamburger drawer, `FST_DEBUG_SHEET=profile`
/// opens profile selection, and `FST_DEBUG_PROFILE=<accountId>:<displayName>` selects a
/// player **in memory only** before the session loads (so profile-only tabs can be
/// captured) — it is never written to `UserDefaults`, so it cannot clobber another
/// lane's real persisted selection on the shared simulator.
/// `FST_DEBUG_BAND=<bandType>/<teamKey>/<displayName>` selects a band the same way
/// (issue #340; band selection has no user-facing entry yet) and wins over any player.
/// `FST_DEBUG_ANONYMOUS=1` ignores any stored profile for this launch without deleting it.
/// `FST_DEBUG_KEEP_PROFILE_ROUTES=1` keeps profile-only tabs and routes without a player
/// (read by `FestivalLaunch.keepsProfileRoutes`).
/// `FST_DEBUG_DRAWER_RADII=1` overlays the drawer panel's frame and resolved concentric
/// corner radii (read by the UIKit drawer, not here).
package struct DebugLaunchRoute {
    package let section: FestivalSection?
    /// `FST_DEBUG_TAB=search`: start on the Search tab.
    package let opensSearch: Bool
    package let route: AppRoute?
    package let opensDrawer: Bool
    package let opensProfileSheet: Bool
    package let profile: (accountId: String, displayName: String)?
    /// `FST_DEBUG_BAND`'s unvalidated parts.
    private let band: (bandType: String, teamKey: String, displayName: String)?
    package let anonymous: Bool

    /// Parse the launch environment.
    ///
    /// - Parameter environment: Process environment.
    package init(environment: [String: String]) {
        section = environment["FST_DEBUG_TAB"].flatMap(FestivalSection.init(rawValue:))
        opensSearch = environment["FST_DEBUG_TAB"] == "search"
        opensDrawer = environment["FST_DEBUG_DRAWER"] == "1"
        opensProfileSheet = environment["FST_DEBUG_SHEET"] == "profile"
        anonymous = environment["FST_DEBUG_ANONYMOUS"] == "1"
        if let raw = environment["FST_DEBUG_PROFILE"] {
            let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
            profile = parts.count == 2 ? (parts[0], parts[1]) : nil
        } else {
            profile = nil
        }
        let bandParts = environment["FST_DEBUG_BAND"]?
            .split(separator: "/", maxSplits: 2).map(String.init) ?? []
        band = bandParts.count == 3 ? (bandParts[0], bandParts[1], bandParts[2]) : nil
        guard let raw = environment["FST_DEBUG_ROUTE"] else {
            route = nil
            return
        }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : nil
        switch parts.first {
        case "player": route = arg.map { .player(accountId: $0, displayName: nil) }
        case "playerBands": route = arg.map { .playerBands(accountId: $0, displayName: nil) }
        case "leaderboards": route = .leaderboards
        case "fullRankings":
            route = .fullRankings(
                instrument: arg.flatMap(Instrument.init(rawValue:)) ?? .lead, rankBy: "totalscore"
            )
        case "bandRankings": route = .bandRankings(bandType: arg ?? "Band_Duets")
        case "fullComboRankings":
            // `fullComboRankings:Solo_Guitar+Solo_Bass` (issue #602).
            let instruments = (arg ?? "").split(separator: "+").compactMap { Instrument(rawValue: String($0)) }
            route = RankingCombo(instruments: instruments.isEmpty ? [.lead, .bass] : instruments)
                .map { .fullComboRankings(combo: $0, rankBy: "totalscore") }
        case "shop": route = .shop
        case "rivals": route = .rivals
        case "allRivals":
            route = arg.flatMap(RivalScope.init(debugToken:)).map { .allRivals(scope: $0) }
        case "rivalDetail":
            if let arg {
                let pieces = arg.split(separator: ":", maxSplits: 1).map(String.init)
                let scope = pieces.count > 1 ? RivalScope(debugToken: pieces[1]) : nil
                route = .rivalDetail(rivalId: pieces[0], name: nil, scope: scope)
            } else {
                route = nil
            }
        case "rivalry":
            if let arg {
                let pieces = arg.split(separator: ":", maxSplits: 2).map(String.init)
                if pieces.count >= 2 {
                    let scope = pieces.count > 2 ? RivalScope(debugToken: pieces[2]) : nil
                    route = .rivalry(rivalId: pieces[0], mode: pieces[1], name: nil, scope: scope)
                } else {
                    route = nil
                }
            } else {
                route = nil
            }
        case "statistics": route = .statistics
        case "suggestions": route = .suggestions
        case "compete": route = .compete
        case "bands": route = .bands
        case "band": route = arg.map { .band(bandId: $0, name: nil) }
        case "licenses": route = .licenses
        case "settingsTopic": route = arg.flatMap(SettingsTopic.init(rawValue:)).map { .settingsTopic($0) }
        default: route = nil
        }
    }

    /// Build the debug profile as an in-memory-only selected identity.
    ///
    /// Never touches `UserDefaults`: `FestivalSession(debugSelectedPlayer:)` seeds
    /// `selectedPlayer` directly, so this launch shows a selected state without
    /// reading or overwriting whatever another lane's process may have persisted
    /// to the shared simulator's real `UserDefaults.standard`.
    ///
    /// - Returns: A validated identity for a well-formed `FST_DEBUG_PROFILE`, else nil.
    package func debugSelectedPlayer() -> SelectedPlayerIdentity? {
        guard let profile else { return nil }
        return try? SelectedPlayerIdentity(
            searchResult: PlayerSearchResult(
                accountId: profile.accountId, displayName: profile.displayName
            )
        )
    }

    /// Build the debug band as an in-memory-only selected band.
    ///
    /// - Returns: A validated band for a well-formed `FST_DEBUG_BAND`, else nil.
    package func debugSelectedBand() -> SelectedBandIdentity? {
        guard let band, let type = BandType(rawValue: band.bandType) else { return nil }
        let identity = SelectedBandIdentity(
            bandType: type, teamKey: band.teamKey, displayName: band.displayName
        )
        return (try? identity.validate()) == nil ? nil : identity
    }
}
#endif
