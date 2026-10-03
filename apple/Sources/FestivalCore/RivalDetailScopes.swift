import Foundation

// MARK: - Rival detail scope resolution (native port of `rivalRouteState.ts`/`comboUtils.ts`)

/// Resolves which server scopes a rival detail read queries, mirroring the web's
/// `resolveRivalCombos` (`FortniteFestivalWeb/src/pages/rivals/helpers/rivalRouteState.ts`)
/// and `deriveRivalScopesFromSettings` (`helpers/comboUtils.ts`).
///
/// Matching the web matters beyond parity. While the service publishes, its
/// `RivalsCache` answers `/rivals/{combo}/{rivalId}` only from entries stored
/// earlier in the same publication, keyed by the canonical combo, limit, offset,
/// sort and live-fallback flag (`FSTService/Api/RivalsEndpoints.cs`). Other
/// shapes get a 503 "Published data unavailable", so the app can reuse warm
/// entries only by asking for the same scope and query as the web.
public enum RivalDetailScopes {
    /// Fallback single scope when nothing is visible (web: `'Solo_Guitar'`).
    public static let defaultToken = Instrument.lead.rawValue

    private static let padGroup: [Instrument] = [.lead, .bass, .drums, .vocals]
    private static let proStringsGroup: [Instrument] = [.proLead, .proBass]
    private static let proDrumsFamily: [Instrument] = [.proCymbals, .proDrums]

    /// Server scope tokens to query for a rival route's scope.
    ///
    /// - `.combo(token, _)`: that token (web: `state.combo` from a combo list).
    /// - `.song([one])`: that instrument (web: All Rivals for one instrument).
    /// - `.song(many)`: Common Rivals, which the web opens with the Settings scope.
    /// - `nil` (Find Rival, deep link): every Settings group scope, like web Find
    ///   Rival's `comboScope: 'settings'`.
    /// - `.leaderboard`: not a combo scope; returns the instrument for completeness.
    ///
    /// - Parameters:
    ///   - scope: The route's carried scope, or `nil`.
    ///   - visible: Settings-visible instruments, in any order.
    /// - Returns: One or more unique, path-safe scope tokens.
    public static func tokens(for scope: RivalScope?, visible: [Instrument]) -> [String] {
        switch scope {
        case let .combo(token, _):
            return RivalsEndpoint.isValidComboToken(token) ? [token] : [settingsScope(visible: visible)]
        case let .song(raw):
            let instruments = canonical(raw.compactMap(Instrument.init(rawValue:)))
            if instruments.count == 1 { return [instruments[0].rawValue] }
            if instruments.isEmpty { return [settingsScope(visible: visible)] }
            return [settingsScope(visible: instruments)]
        case let .leaderboard(raw, _):
            return [Instrument(rawValue: raw)?.rawValue ?? settingsScope(visible: visible)]
        case nil:
            return settingsScopes(visible: visible)
        }
    }

    /// Whether the read should pass `allowLiveFallback=true`: only for a route with
    /// no list context (Find Rival/deep link), as the web does for Find Rival. The
    /// fallback is read-only (`RivalsCalculator.ComputeDirectSongSamples`).
    ///
    /// - Parameter scope: The route's carried scope, or `nil`.
    /// - Returns: `true` when the read may compute samples for an untracked rival.
    public static func allowsLiveFallback(for scope: RivalScope?) -> Bool {
        scope == nil
    }

    /// The single scope the web's Rivals hub opens every rival with
    /// (`deriveRivalScopeFromSettings ?? getEnabledInstruments[0] ?? 'Solo_Guitar'`).
    ///
    /// - Parameter visible: Settings-visible instruments, in any order.
    /// - Returns: A combo token, `pro_drums`, or one instrument's raw value.
    public static func settingsScope(visible: [Instrument]) -> String {
        if let combo = RivalCombo.deriveScope(visible: canonical(visible)) { return combo.token }
        return canonical(visible).first?.rawValue ?? defaultToken
    }

    /// The route scope the Rivals hub attaches to every rival it opens, so a tap
    /// queries the same detail as the web (`RivalsPage.navigateToRival`).
    ///
    /// - Parameter visible: Settings-visible instruments, in any order.
    /// - Returns: A `.combo` scope for a supported combo, else `.song` for the
    ///   first visible instrument.
    public static func hubScope(visible: [Instrument]) -> RivalScope {
        let ordered = canonical(visible)
        if let combo = RivalCombo.deriveScope(visible: ordered) {
            return .combo(token: combo.token, instruments: combo.instruments.map(\.rawValue))
        }
        return .song(instruments: [ordered.first?.rawValue ?? defaultToken])
    }

    /// Every Settings group's scope (`deriveRivalScopesFromSettings`): the pad
    /// combo, the Pro Strings combo and the Pro Drums family when each has enough
    /// visible instruments, else the first visible instrument.
    ///
    /// - Parameter visible: Settings-visible instruments, in any order.
    /// - Returns: One or more scope tokens.
    public static func settingsScopes(visible: [Instrument]) -> [String] {
        let ordered = canonical(visible)
        let set = Set(ordered)
        var scopes: [String] = []
        let pad = padGroup.filter(set.contains)
        if pad.count >= 2 { scopes.append(RivalCombo.comboId(for: pad)) }
        let proStrings = proStringsGroup.filter(set.contains)
        if proStrings.count >= 2 { scopes.append(RivalCombo.comboId(for: proStrings)) }
        if proDrumsFamily.allSatisfy(set.contains) { scopes.append(RivalCombo.proDrumsToken) }
        if !scopes.isEmpty { return scopes }
        return [ordered.first?.rawValue ?? defaultToken]
    }

    /// The instruments a scope token covers, matching the service's
    /// `TryResolveRivalCombo`: one instrument, a hex bitmask or the Pro Drums family.
    ///
    /// - Parameter token: Instrument raw value, hex combo ID or `pro_drums`.
    /// - Returns: Instruments in canonical order, or `nil` for an unknown token.
    public static func instruments(forToken token: String) -> [Instrument]? {
        if let instrument = Instrument(rawValue: token) { return [instrument] }
        if token == RivalCombo.proDrumsToken { return proDrumsFamily }
        guard RivalsEndpoint.isValidComboToken(token), let mask = Int(token, radix: 16), mask > 0 else {
            return nil
        }
        let instruments = Instrument.allCases.enumerated()
            .filter { mask & (1 << $0.offset) != 0 }
            .map(\.element)
        return instruments.isEmpty ? nil : instruments
    }

    /// Whether a scope token names a single solo instrument (sent through the
    /// per-instrument endpoint case) rather than a combo.
    ///
    /// - Parameter token: Scope token.
    /// - Returns: The instrument, or `nil` for a combo/Pro Drums family token.
    public static func soloInstrument(forToken token: String) -> Instrument? {
        Instrument(rawValue: token)
    }

    private static func canonical(_ instruments: [Instrument]) -> [Instrument] {
        let set = Set(instruments)
        return Instrument.allCases.filter(set.contains)
    }
}

// MARK: - Combined detail (native port of `rivalDetailFetch.ts`)

extension RivalDetailResponse {
    /// Merge several scopes' detail responses like the web's
    /// `fetchCombinedRivalDetail`: songs deduplicated by song, instrument and
    /// cross-instrument pair, the first non-empty display name, and the scopes
    /// joined into `combo`.
    ///
    /// - Parameters:
    ///   - responses: Successful per-scope responses, in request order.
    ///   - scopes: Every requested scope token.
    /// - Returns: The merged response, or `nil` when `responses` is empty.
    public static func combined(_ responses: [RivalDetailResponse], scopes: [String]) -> RivalDetailResponse? {
        guard let first = responses.first else { return nil }
        if responses.count == 1, scopes.count == 1 { return first }
        var seen = Set<String>()
        var songs: [RivalSongComparison] = []
        for response in responses {
            for song in response.songs where seen.insert(song.id).inserted {
                songs.append(song)
            }
        }
        let displayName = responses.compactMap(\.rival.displayName).first ?? first.rival.displayName
        return RivalDetailResponse(
            rival: RivalIdentity(accountId: first.rival.accountId, displayName: displayName),
            combo: scopes.joined(separator: ","), instrument: first.instrument, rankBy: first.rankBy,
            source: first.source, totalSongs: songs.count, offset: first.offset, limit: first.limit,
            sort: first.sort, songs: songs,
            songsToCompete: first.songsToCompete, yourExclusiveSongs: first.yourExclusiveSongs
        )
    }
}

// MARK: - Publish-time fallback from `/rivals/all`

/// Builds a rival detail from the precomputed `/rivals/all` payload when the
/// detail endpoint is unavailable during a publish.
///
/// The service precomputes `/rivals/all` and keeps serving it while public reads
/// are frozen. Each rival entry embeds every stored song sample for that rival
/// (`MetaDatabase.GetAllRivalSongSamplesForUser`). The detail endpoint returns
/// the same `rival_song_samples` rows filtered to the scope's instruments
/// (`GetRivalSongSamples` per instrument), with `rankDelta = rivalRank - userRank`.
public enum RivalDetailFallback {
    /// Source tag for a detail built from `/rivals/all`.
    public static let source = "rivals-all"

    /// Rebuild a `closest`-sorted detail for one rival and scope set.
    ///
    /// - Parameters:
    ///   - all: The player's `/rivals/all` response.
    ///   - rivalId: Target rival's account ID.
    ///   - scopes: Scope tokens the detail read asked for.
    ///   - songInfo: Title and artist for a song ID, from the loaded catalogue.
    /// - Returns: The detail, empty when the rival has samples only outside these
    ///   scopes (the endpoint's 404), or `nil` when `/rivals/all` has no samples for
    ///   this rival, so the caller keeps its original error.
    public static func detail(
        from all: RivalsAllResponse, rivalId: String, scopes: [String],
        songInfo: (String) -> (title: String, artist: String)? = { _ in nil }
    ) -> RivalDetailResponse? {
        let entries = all.combos.flatMap { $0.above + $0.below }
            .filter { $0.accountId.caseInsensitiveCompare(rivalId) == .orderedSame }
        guard let entry = entries.first(where: { !$0.samples.isEmpty }) else { return nil }
        let instruments = Set(scopes.compactMap(RivalDetailScopes.instruments(forToken:)).flatMap { $0 }.map(\.rawValue))
        let displayName = entries.compactMap(\.displayName).first

        var seen = Set<String>()
        let songs: [RivalSongComparison] = entry.samples.compactMap { sample in
            guard instruments.contains(sample.instrument), let songId = all.songId(for: sample) else { return nil }
            let info = songInfo(songId)
            let song = RivalSongComparison(
                songId: songId, title: info?.title, artist: info?.artist, instrument: sample.instrument,
                userInstrument: nil, rivalInstrument: nil,
                userRank: sample.userRank, rivalRank: sample.rivalRank,
                rankDelta: sample.rivalRank - sample.userRank,
                userScore: sample.userScore, rivalScore: sample.rivalScore
            )
            return seen.insert(song.id).inserted ? song : nil
        }
        let sorted = songs.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (abs(lhs.element.rankDelta), abs(rhs.element.rankDelta))
                return l == r ? lhs.offset < rhs.offset : l < r
            }
            .map(\.element)

        return RivalDetailResponse(
            rival: RivalIdentity(accountId: entry.accountId, displayName: displayName),
            combo: scopes.joined(separator: ","), instrument: nil, rankBy: nil, source: source,
            totalSongs: sorted.count, offset: 0, limit: 0, sort: "closest", songs: sorted,
            songsToCompete: [], yourExclusiveSongs: []
        )
    }
}
