import Foundation

// MARK: - Rival suggestion data index

/// Summary info about one rival, ported from the web `RivalInfo`
/// (`packages/core/src/suggestions/types.ts`). Always describes a per-song rival here:
/// `RivalDataIndex.build(from:)` only derives from `GET /rivals/all`, which is the web's
/// `source: "song"` case. The web's separate leaderboard-neighborhood merge
/// (`source: "leaderboard"`, its `lb_rival_*` filter category) has no native data source
/// wired up, and — see `RivalDataIndex`'s note below — no web pipeline actually emits it
/// either, so it is not represented here.
public struct RivalInfo: Sendable, Equatable {
    public let accountId: String
    public let displayName: String
    /// `"above"` (ranked ahead of the player on the songs sampled) or `"below"`.
    public let direction: String
    public let sharedSongCount: Int
    public let aheadCount: Int
    public let behindCount: Int
}

/// One per-song, per-chart comparison between the selected player and a rival
/// (web `RivalSongMatch`).
public struct RivalSongMatch: Sendable, Equatable {
    public let rival: RivalInfo
    public let songId: String
    public let instrument: Instrument
    public let userRank: Int
    public let rivalRank: Int
    /// `userRank - rivalRank`; negative means the rival ranks ahead of the player.
    public let rankDelta: Int
    public let userScore: Int?
    public let rivalScore: Int?
}

/// Indexed lookup structure feeding `SuggestionGenerator`'s `song_rival_*` families,
/// ported from the web `buildRivalDataIndexFromRivalsAll`
/// (`FortniteFestivalWeb/src/utils/suggestionAdapter.ts`). Built once from a
/// `RivalsAllResponse` (`GET /api/player/{accountId}/rivals/all`, `FestivalAPI.rivalsAll(accountId:)`)
/// and handed to `SuggestionGenerator.setRivalData(_:)`.
///
/// **`lb_rival_*` is not ported.** The web's `suggestionFilterConfig.ts` reserves a
/// "Leaderboard Rivals" filter type for an `lb_rival_*` category-key prefix, and
/// `RivalDataIndex` on the web carries a matching `leaderboardRivals`/`leaderboardRivalIndex`
/// pair. But `buildRivalDataIndexFromRivalsAll` always leaves those empty (`/rivals/all` only
/// carries per-song rivals), and `SuggestionGenerator.rivalPipelines()` never calls anything
/// that produces an `lb_rival_*` key — searching the web `suggestionGenerator.ts` source for
/// `lb_rival` or a `leaderboardRival*` builder finds none. That filter category is
/// consequently dead in the web app too (nothing can ever populate it), so only the fields
/// this port actually consumes — `songRivals`, `byRival`, `closestRivalBySong` — are
/// represented here.
public struct RivalDataIndex: Sendable, Equatable {
    /// Top rivals kept (`limit` per direction, ahead entries first then behind).
    public let songRivals: [RivalInfo]
    /// Every song/chart match for a rival, keyed by `RivalInfo.accountId`; a rival appearing
    /// in more than one combo has its matches merged into one array.
    public let byRival: [String: [RivalSongMatch]]
    /// Closest match (smallest `|rankDelta|`) per song/chart, keyed by `closestKey(_:_:)`.
    public let closestRivalBySong: [String: RivalSongMatch]

    /// An index with no rivals, used when `/rivals/all` returned nothing or the read failed.
    public static let empty = RivalDataIndex(songRivals: [], byRival: [:], closestRivalBySong: [:])

    /// The key `closestRivalBySong` uses for one song/chart pairing (web `${songId}:${instrument}`).
    ///
    /// - Parameters:
    ///   - songId: Catalogue song ID.
    ///   - instrument: Chart the match is on.
    /// - Returns: A stable lookup key.
    public static func closestKey(_ songId: String, _ instrument: Instrument) -> String {
        "\(songId):\(instrument.rawValue)"
    }

    /// Build an index from one combined `/rivals/all` read, ported from the web
    /// `buildRivalDataIndexFromRivalsAll`: dedup rivals by account ID (first occurrence wins,
    /// scanning combos in response order), keep the top `limit` per direction across the
    /// selected combos, then resolve every sampled song/chart match for those kept rivals
    /// via `response.songs`.
    ///
    /// - Parameters:
    ///   - response: `FestivalAPI.rivalsAll(accountId:)` result.
    ///   - combo: Restrict to one `RivalsAllCombo.combo` hex token, or nil for every combo
    ///     (the native Suggestions caller always passes nil — no combo/instrument picker yet).
    ///   - limit: Rivals kept per direction (web default, and this port's default, is 5).
    /// - Returns: The indexed structure `SuggestionGenerator.setRivalData(_:)` expects.
    public static func build(from response: RivalsAllResponse, combo: String? = nil, limit: Int = 5) -> RivalDataIndex {
        let comboData = combo.map { token in response.combos.filter { $0.combo == token } } ?? response.combos

        var aboveOrder: [String] = []
        var aboveInfo: [String: RivalInfo] = [:]
        var belowOrder: [String] = []
        var belowInfo: [String: RivalInfo] = [:]

        for comboEntry in comboData {
            for entry in comboEntry.above where aboveInfo[entry.accountId] == nil {
                aboveOrder.append(entry.accountId)
                aboveInfo[entry.accountId] = RivalInfo(
                    accountId: entry.accountId, displayName: entry.displayName ?? "Unknown", direction: "above",
                    sharedSongCount: entry.sharedSongCount, aheadCount: entry.aheadCount, behindCount: entry.behindCount
                )
            }
            for entry in comboEntry.below where belowInfo[entry.accountId] == nil {
                belowOrder.append(entry.accountId)
                belowInfo[entry.accountId] = RivalInfo(
                    accountId: entry.accountId, displayName: entry.displayName ?? "Unknown", direction: "below",
                    sharedSongCount: entry.sharedSongCount, aheadCount: entry.aheadCount, behindCount: entry.behindCount
                )
            }
        }

        let topAbove = aboveOrder.prefix(limit).compactMap { aboveInfo[$0] }
        let topBelow = belowOrder.prefix(limit).compactMap { belowInfo[$0] }
        let songRivals = Array(topAbove) + Array(topBelow)
        let rivalSet = Set(songRivals.map(\.accountId))

        var byRival: [String: [RivalSongMatch]] = [:]
        var closestRivalBySong: [String: RivalSongMatch] = [:]

        for comboEntry in comboData {
            for group in [comboEntry.above, comboEntry.below] {
                for entry in group {
                    guard rivalSet.contains(entry.accountId),
                          let info = aboveInfo[entry.accountId] ?? belowInfo[entry.accountId] else { continue }
                    var matches: [RivalSongMatch] = []
                    for sample in entry.samples {
                        guard let songId = response.songId(for: sample),
                              let instrument = Instrument(rawValue: sample.instrument) else { continue }
                        let match = RivalSongMatch(
                            rival: info, songId: songId, instrument: instrument,
                            userRank: sample.userRank, rivalRank: sample.rivalRank,
                            rankDelta: sample.userRank - sample.rivalRank,
                            userScore: sample.userScore, rivalScore: sample.rivalScore
                        )
                        matches.append(match)
                        let key = closestKey(songId, instrument)
                        if let existing = closestRivalBySong[key] {
                            if abs(match.rankDelta) < abs(existing.rankDelta) { closestRivalBySong[key] = match }
                        } else {
                            closestRivalBySong[key] = match
                        }
                    }
                    // Same rival may appear in more than one combo; merge rather than overwrite.
                    byRival[entry.accountId, default: []].append(contentsOf: matches)
                }
            }
        }

        return RivalDataIndex(songRivals: songRivals, byRival: byRival, closestRivalBySong: closestRivalBySong)
    }
}
