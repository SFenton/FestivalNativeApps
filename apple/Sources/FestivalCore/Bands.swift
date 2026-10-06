import Foundation

// MARK: - Player band group filter

/// The player-bands "group" query filter, mirroring the web client's
/// `PlayerBandListGroup` (`FortniteFestivalWeb/src/pages/band/PlayerBandsPage.tsx`).
///
/// Distinct from `BandType`: this is the segmented-control value sent as
/// `?group=`, while `BandType` is the server's `Band_Duets`/`Band_Trios`/`Band_Quad` key.
public enum PlayerBandGroup: String, CaseIterable, Sendable, Identifiable, Hashable {
    case all
    case duos
    case trios
    case quads

    public var id: String { rawValue }

    /// Present the same group names as the web client's filter sheet.
    public var label: String {
        switch self {
        case .all: "All"
        case .duos: "Duos"
        case .trios: "Trios"
        case .quads: "Quads"
        }
    }
}

// MARK: - Band member

/// One band member as embedded in player-bands, band-profile or song-band-leaderboard
/// rows. Fields beyond `accountId`/`instruments` are only populated where the source
/// endpoint carries per-song stats (song-band-leaderboard members), and are nil elsewhere
/// (player-bands and band-profile members carry identity and role only).
public struct BandMember: Decodable, Sendable, Equatable, Identifiable {
    public let accountId: String
    public let displayName: String?
    public let instruments: [String]
    public let score: Int?
    public let accuracy: Int?
    public let isFullCombo: Bool?
    public let stars: Int?
    public let difficulty: Int?
    public let season: Int?

    public var id: String { accountId }

    /// Instruments this member is charted on, dropping any the app doesn't render.
    public var chartedInstruments: [Instrument] {
        instruments.compactMap(Instrument.init(rawValue:))
    }

    /// A readable member name, matching the web client's account-id fallback.
    public var resolvedName: String {
        displayName.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown User"
    }
}

// MARK: - Player bands

/// One of a player's deduplicated bands, matching `PlayerBandEntryDto`
/// (`FSTService/Persistence/DataTransferObjects.cs:352`).
public struct PlayerBandEntry: Decodable, Sendable, Equatable, Identifiable {
    public let bandId: String
    public let teamKey: String
    public let bandType: String
    public let appearanceCount: Int
    public let members: [BandMember]

    public var id: String { bandId.isEmpty ? teamKey : bandId }

    /// Joined member names, matching the web client's `formatPlayerBandNames`.
    public var membersLabel: String {
        var seen = Set<String>()
        let names = members.filter { seen.insert($0.accountId).inserted }.map(\.resolvedName)
        return names.joined(separator: " + ")
    }
}

/// Response for `/api/player/{accountId}/bands` (all groups) and
/// `/api/player/{accountId}/bands/{bandType}` (one group), matching
/// `PlayerBandListResponseDto`/`PlayerBandTypeResponseDto`. Both share this shape;
/// the by-type response additionally echoes `bandType`/`comboId`, which this app
/// does not need since the caller already knows what it requested.
public struct PlayerBandListResponse: Decodable, Sendable, Equatable {
    public let accountId: String
    public let totalCount: Int
    public let entries: [PlayerBandEntry]

    /// Pages of `pageSize` rows, always at least one even for an empty list.
    ///
    /// - Parameter pageSize: Rows requested per page.
    /// - Returns: Total page count for that page size.
    public func pageCount(pageSize: Int) -> Int {
        let size = max(1, pageSize)
        return totalCount <= 0 ? 1 : (totalCount - 1) / size + 1
    }
}

/// A player-bands page together with its offline freshness.
public struct PlayerBandListPayload: Sendable {
    public let page: Int
    public let list: PlayerBandListResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

// MARK: - Player bands preview (profile page)

/// The player profile's inline bands section, porting the web client's
/// `buildPlayerBandsItems` (`FortniteFestivalWeb/src/pages/player/components/PlayerBandsSection.tsx`):
/// Duos, Trios and Quads, each with up to ``previewCount`` band cards and its total.
///
/// The web reads these previews from player stats, which native clients must not call
/// (its GET may store tiers); each group here is instead the first page of the keyless
/// `GET /api/player/{accountId}/bands?group=` list.
public struct PlayerBandsPreview: Sendable, Equatable {
    /// Band cards per group, the service's `GetPlayerBands(previewCount = 6)`.
    public static let previewCount = 6
    /// Groups shown, in the web's order (no "All" preview).
    public static let groups: [PlayerBandGroup] = [.duos, .trios, .quads]

    /// One band size's preview.
    public struct Group: Sendable, Equatable, Identifiable {
        public let group: PlayerBandGroup
        /// At most ``PlayerBandsPreview/previewCount`` bands, in service order.
        public let entries: [PlayerBandEntry]
        /// Every band of this size the player has, not just the previewed ones.
        public let totalCount: Int

        public var id: PlayerBandGroup { group }

        /// The web's `totalCount > entries.length`: the group has a "View all bands" card.
        public var hasMore: Bool { totalCount > entries.count }

        /// Build one group's preview, trimming the page to the preview size.
        ///
        /// - Parameters:
        ///   - group: Band size the page was read for.
        ///   - response: That group's first page.
        public init(group: PlayerBandGroup, response: PlayerBandListResponse) {
            self.group = group
            entries = Array(response.entries.prefix(PlayerBandsPreview.previewCount))
            totalCount = max(response.totalCount, entries.count)
        }
    }

    /// Duos, Trios and Quads, always all three (an empty group shows "No Bands Yet").
    public let groups: [Group]

    /// Assemble the preview from each group's first page.
    ///
    /// - Parameter responses: First page per group; a missing group previews as empty.
    public init(responses: [PlayerBandGroup: PlayerBandListResponse]) {
        groups = Self.groups.map { group in
            Group(
                group: group,
                response: responses[group] ?? PlayerBandListResponse(accountId: "", totalCount: 0, entries: [])
            )
        }
    }
}

// MARK: - Band profile (safe read: rankings board filtered to one team)

/// One instrument-combo configuration observed for a band, matching
/// `BandConfigurationDto`. Only ever populated for `Band_Duets` with an explicit
/// `combo` filter (`ShouldAttachBandRankingConfigurations`,
/// `FSTService/Persistence/MetaDatabase.cs:16565`); empty otherwise.
public struct BandConfiguration: Decodable, Sendable, Equatable, Identifiable {
    public let rawInstrumentCombo: String
    public let comboId: String
    public let instruments: [String]
    public let assignmentKey: String
    public let appearanceCount: Int
    public let memberInstruments: [String: String]

    public var id: String { assignmentKey }

    public var chartedInstruments: [Instrument] {
        instruments.compactMap(Instrument.init(rawValue:))
    }
}

/// One band's full ranking row, decoded from the `selectedBandEntry` field of
/// `GET /api/rankings/bands/{bandType}?teamKey=` — the same pure-read board used
/// by `BandRankingsScreen`, never `/api/bands/{bandId}`.
///
/// `/api/bands/{bandId}` is not called from this app: its handler unconditionally
/// calls `GlobalLeaderboardPersistence.GetBandConfigurations`, which rebuilds
/// (`DELETE`+`INSERT`) `band_team_configurations` rows on a cache miss
/// (`EnsureBandTeamConfigurations`, `GlobalLeaderboardPersistence.cs:4192-4206`) —
/// a write side effect from a GET, in the same family as the blocked band-search
/// fallback and band sync-status reads (see `.agents/platforms/service-safety.md`).
/// `metaDb.GetBandTeamRanking` (used here) has no such fallback: it only ever
/// `SELECT`s, including its own `AttachBandRankingConfigurations` read
/// (`MetaDatabase.cs:16512`).
///
/// One consequence: a bare `bandId` (a one-way SHA-256 hash of `bandType:teamKey`,
/// see `FSTService/Persistence/BandIdentity.cs`) cannot be resolved to a `bandType`
/// and `teamKey` by any safe endpoint. Band Detail therefore needs the `bandType`
/// and `teamKey` carried from the row that linked to it (rankings, player bands or
/// a song band leaderboard all know both); a bare `bandId` deep link cannot be
/// resolved and the screen shows an explicit "open from a band list" state.
public struct BandDetail: Decodable, Sendable, Equatable, Identifiable {
    public let bandId: String
    public let comboId: String?
    public let teamKey: String
    public let members: [BandMember]
    public let configurations: [BandConfiguration]
    public let songsPlayed: Int
    public let totalChartedSongs: Int
    public let coverage: Double
    public let rawSkillRating: Double
    public let adjustedSkillRating: Double
    public let adjustedSkillRank: Int
    public let weightedRating: Double
    public let weightedRank: Int
    public let fcRate: Double
    public let fcRateRank: Int
    public let totalScore: Int
    public let totalScoreRank: Int
    public let avgAccuracy: Double
    public let fullComboCount: Int
    public let avgStars: Double
    public let bestRank: Int
    public let avgRank: Double
    public let rawWeightedRating: Double?
    public let computedAt: String?

    public var id: String { bandId.isEmpty ? teamKey : bandId }

    /// Rank column for the currently selected metric, matching `BandRankingEntry`.
    ///
    /// - Parameter metric: Selected band rank-by metric.
    /// - Returns: 1-based rank for that metric only.
    public func rank(for metric: BandRankingMetric) -> Int {
        switch metric {
        case .adjusted: adjustedSkillRank
        case .weighted: weightedRank
        case .fcrate: fcRateRank
        case .totalscore: totalScoreRank
        }
    }

    /// Raw value backing the displayed rating for the selected metric.
    ///
    /// - Parameter metric: Selected band rank-by metric.
    /// - Returns: Percentile fraction, score total or full-combo fraction.
    public func ratingValue(for metric: BandRankingMetric) -> Double {
        switch metric {
        case .adjusted: rawSkillRating
        case .weighted: rawWeightedRating ?? weightedRating
        case .fcrate: totalChartedSongs > 0 ? Double(fullComboCount) / Double(totalChartedSongs) : 0
        case .totalscore: Double(totalScore)
        }
    }
}

/// Envelope returned by `GET /api/rankings/bands/{bandType}`; only the
/// `selectedBandEntry` field (present when `teamKey` matched a team) is needed here.
struct BandProfileEnvelope: Decodable {
    let bandType: String
    let selectedBandEntry: BandDetail?
}

/// A band profile lookup together with its offline freshness.
public struct BandDetailPayload: Sendable {
    public let detail: BandDetail
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

// MARK: - Band rank history

/// One daily rank snapshot, matching `BandRankHistoryDto`.
public struct BandRankHistoryEntry: Decodable, Sendable, Equatable, Identifiable {
    public let snapshotDate: String
    public let snapshotTakenAt: String?
    public let adjustedSkillRank: Int
    public let weightedRank: Int
    public let fcRateRank: Int
    public let totalScoreRank: Int
    public let adjustedSkillRating: Double?
    public let weightedRating: Double?
    public let fcRate: Double?
    public let totalScore: Int?
    public let songsPlayed: Int?
    public let totalChartedSongs: Int?
    public let totalRankedTeams: Int?

    public var id: String { snapshotDate }

    /// Rank column for the currently selected metric, matching `BandDetail.rank(for:)`.
    ///
    /// - Parameter metric: Selected band rank-by metric.
    /// - Returns: 1-based rank for that metric only.
    public func rank(for metric: BandRankingMetric) -> Int {
        switch metric {
        case .adjusted: adjustedSkillRank
        case .weighted: weightedRank
        case .fcrate: fcRateRank
        case .totalscore: totalScoreRank
        }
    }
}

/// Response for `/api/rankings/bands/{bandType}/{teamKey}/history`.
public struct BandRankHistoryResponse: Decodable, Sendable, Equatable {
    public let bandType: String
    public let teamKey: String
    public let days: Int
    public let history: [BandRankHistoryEntry]
    public let historyStatus: String?
    public let historyMessage: String?
}

/// A rank-history read together with its offline freshness.
public struct BandRankHistoryPayload: Sendable {
    public let response: BandRankHistoryResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

// MARK: - Band best/worst songs

/// One song performance, matching `BandSongPerformanceDto`.
public struct BandSongPerformanceEntry: Decodable, Sendable, Equatable, Identifiable {
    public let songId: String
    public let comboId: String?
    public let rank: Int
    public let totalEntries: Int
    public let percentile: Double
    public let score: Int
    public let accuracy: Int?
    public let isFullCombo: Bool?
    public let stars: Int?
    public let season: Int?
    public let endTime: String?

    public var id: String { songId }
}

/// Response for `/api/rankings/bands/{bandType}/{teamKey}/songs`.
public struct BandSongExtremesResponse: Decodable, Sendable, Equatable {
    public let bandType: String
    public let teamKey: String
    public let limit: Int
    public let best: [BandSongPerformanceEntry]
    public let worst: [BandSongPerformanceEntry]
}

/// A best/worst-songs read together with its offline freshness.
public struct BandSongExtremesPayload: Sendable {
    public let response: BandSongExtremesResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

// MARK: - Per-song band leaderboard

/// One band's score on a song-scoped band leaderboard, matching
/// `SongBandLeaderboardEntryDto`.
public struct SongBandLeaderboardEntry: Decodable, Sendable, Equatable, Identifiable {
    public let bandId: String
    public let bandType: String
    public let teamKey: String
    public let comboId: String?
    public let members: [BandMember]
    public let score: Int
    public let rank: Int
    public let accuracy: Int
    public let isFullCombo: Bool
    public let stars: Int
    public let season: Int
    public let difficulty: Int
    public let percentile: Double
    public let endTime: String?

    public var id: String { "\(bandId.isEmpty ? teamKey : bandId):\(rank)" }

    /// Joined member names, matching `PlayerBandEntry.membersLabel`.
    public var membersLabel: String {
        var seen = Set<String>()
        let names = members.filter { seen.insert($0.accountId).inserted }.map(\.resolvedName)
        return names.joined(separator: " + ")
    }

    /// This band score as a one-line leaderboard row, for the band leaderboard's pinned
    /// footer: the web footer draws a `LeaderboardEntry` named `formatBandTeamName(...)`
    /// (members joined with " + ", the team key when there are none) with the band's
    /// rank, score, accuracy, full combo, stars and season (issue #306).
    public var footerLeaderboardEntry: LeaderboardEntry {
        let label = membersLabel
        return LeaderboardEntry(
            accountId: "band-\(bandId.isEmpty ? teamKey : bandId)",
            displayName: label.isEmpty ? teamKey : label,
            score: score, rank: rank, localRank: nil,
            accuracy: Double(accuracy), isFullCombo: isFullCombo,
            stars: stars, season: season > 0 ? season : nil,
            difficulty: (0...3).contains(difficulty) ? Double(difficulty) : nil
        )
    }
}

/// Response for `/api/leaderboard/{songId}/bands/{bandType}`.
public struct SongBandLeaderboardResponse: Decodable, Sendable, Equatable {
    public let songId: String
    public let bandType: String
    public let count: Int
    public let totalEntries: Int
    public let localEntries: Int?
    public let entries: [SongBandLeaderboardEntry]
    /// The selected player's best band on this song and size, present when the request
    /// carried `accountId` and that player has a band score here.
    public var selectedPlayerEntry: SongBandLeaderboardEntry? = nil
    /// A selected band's own row (`teamKey` query); natives do not send that query yet,
    /// but decode it so a future selected-band identity needs no wire change.
    public var selectedBandEntry: SongBandLeaderboardEntry? = nil

    /// Create a page, e.g. for tests.
    ///
    /// - Parameters:
    ///   - songId: Song of the board.
    ///   - bandType: Wire band-size key.
    ///   - count: Rows on this page.
    ///   - totalEntries: Ranked bands of this size on the song.
    ///   - localEntries: Rankable bands, when the service reports them.
    ///   - entries: Page rows.
    ///   - selectedPlayerEntry: Selected player's best band row, if any.
    ///   - selectedBandEntry: Selected band's row, if any.
    public init(
        songId: String, bandType: String, count: Int, totalEntries: Int, localEntries: Int?,
        entries: [SongBandLeaderboardEntry],
        selectedPlayerEntry: SongBandLeaderboardEntry? = nil,
        selectedBandEntry: SongBandLeaderboardEntry? = nil
    ) {
        self.songId = songId
        self.bandType = bandType
        self.count = count
        self.totalEntries = totalEntries
        self.localEntries = localEntries
        self.entries = entries
        self.selectedPlayerEntry = selectedPlayerEntry
        self.selectedBandEntry = selectedBandEntry
    }

    /// The pinned footer's row: a selected band's row wins over the selected player's
    /// best band, like the web `SongBandLeaderboardPage` (`selectedBandEntry ??
    /// selectedPlayerEntry`).
    public var selectedEntry: SongBandLeaderboardEntry? {
        selectedBandEntry ?? selectedPlayerEntry
    }

    /// Whether a page row is the selected band, for the purple row highlight.
    ///
    /// - Parameter entry: A page row.
    /// - Returns: True when it is the same band as ``selectedEntry``.
    public func isSelected(_ entry: SongBandLeaderboardEntry) -> Bool {
        guard let selected = selectedEntry else { return false }
        return SongBandLeaderboardPreview.isSameBand(entry, selected)
    }

    /// Pages of 25 rows, matching `LeaderboardResponse.pageCount`.
    public var pageCount: Int {
        let total = max(0, localEntries ?? totalEntries)
        return total == 0 ? 1 : (total - 1) / 25 + 1
    }

    /// Reject a response for the wrong song or band size, an impossible row count, or a
    /// selected row filed under another band size.
    ///
    /// - Parameters:
    ///   - songId: Requested song.
    ///   - bandType: Requested band size.
    /// - Throws: `FestivalAPIError.invalidBandProfile` on a mismatched or corrupt response.
    public func validate(songId: String, bandType: BandType) throws {
        let selectedRows = [selectedPlayerEntry, selectedBandEntry].compactMap { $0 }
        guard self.songId == songId, self.bandType == bandType.rawValue,
              count == entries.count, count >= 0, totalEntries >= 0,
              selectedRows.allSatisfy({ $0.bandType == bandType.rawValue && $0.rank > 0 }) else {
            throw FestivalAPIError.invalidBandProfile
        }
    }
}

/// A song band leaderboard page together with its offline freshness.
public struct SongBandLeaderboardPayload: Sendable {
    public let page: Int
    public let leaderboard: SongBandLeaderboardResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

// MARK: - Song Detail band previews

/// One band size's preview inside `GET /api/leaderboard/{songId}/bands/all`, matching
/// the service's `BuildSongBandLeaderboardsPayload` item
/// (`FSTService/Api/LeaderboardEndpoints.cs`): the top rows plus, when the request
/// carried `accountId`, the selected player's best band row for that size.
public struct SongBandLeaderboardPreview: Decodable, Sendable, Equatable {
    public let bandType: String
    public let count: Int
    public let totalEntries: Int
    public let localEntries: Int?
    public let entries: [SongBandLeaderboardEntry]
    /// The selected player's best band on this song and size (`accountId` query).
    public let selectedPlayerEntry: SongBandLeaderboardEntry?
    /// A selected band's own row (`selectedTeamKey` query); natives do not send that
    /// query yet, but decode it so a future selected-band identity needs no wire change.
    public let selectedBandEntry: SongBandLeaderboardEntry?

    /// Create a preview, e.g. the empty one shown for a size the service omitted.
    ///
    /// - Parameters:
    ///   - bandType: Wire band-size key.
    ///   - totalEntries: Ranked bands of this size on the song.
    ///   - entries: Top rows.
    ///   - selectedPlayerEntry: Selected player's best band row, if any.
    ///   - selectedBandEntry: Selected band's row, if any.
    public init(
        bandType: String, totalEntries: Int = 0, entries: [SongBandLeaderboardEntry] = [],
        selectedPlayerEntry: SongBandLeaderboardEntry? = nil,
        selectedBandEntry: SongBandLeaderboardEntry? = nil
    ) {
        self.bandType = bandType
        self.count = entries.count
        self.totalEntries = totalEntries
        self.localEntries = totalEntries
        self.entries = entries
        self.selectedPlayerEntry = selectedPlayerEntry
        self.selectedBandEntry = selectedBandEntry
    }

    /// The highlighted row: a selected band's row wins over the selected player's
    /// best band, like the web `SongBandLeaderboardPreview`.
    public var selectedEntry: SongBandLeaderboardEntry? {
        selectedBandEntry ?? selectedPlayerEntry
    }

    /// Whether a top row is the selected row (same `bandId`, or same size and roster).
    ///
    /// - Parameter entry: A top row.
    /// - Returns: True when it should get the selected-row highlight.
    public func isSelected(_ entry: SongBandLeaderboardEntry) -> Bool {
        guard let selected = selectedEntry else { return false }
        return Self.isSameBand(entry, selected)
    }

    /// The selected row to append after the top rows, when they do not already show it.
    public var footerEntry: SongBandLeaderboardEntry? {
        guard let selected = selectedEntry,
              !entries.contains(where: { Self.isSameBand($0, selected) }) else { return nil }
        return selected
    }

    /// Web `isSameSongBandEntry`: equal non-empty `bandId`, or equal size and roster.
    ///
    /// - Parameters:
    ///   - lhs: First row.
    ///   - rhs: Second row.
    /// - Returns: True when both rows are the same band.
    public static func isSameBand(_ lhs: SongBandLeaderboardEntry, _ rhs: SongBandLeaderboardEntry) -> Bool {
        (!lhs.bandId.isEmpty && lhs.bandId == rhs.bandId)
            || (lhs.bandType == rhs.bandType && lhs.teamKey == rhs.teamKey)
    }
}

/// Response for `GET /api/leaderboard/{songId}/bands/all`: one preview per band size.
public struct SongBandLeaderboardsResponse: Decodable, Sendable, Equatable {
    public let songId: String
    public let showLeaderboardEntryTotals: Bool?
    public let bands: [SongBandLeaderboardPreview]

    /// The preview for one band size; a size the service omitted reads as empty, like
    /// the web's `createSongBandData` default.
    ///
    /// - Parameter bandType: Band size.
    /// - Returns: That size's preview.
    public func preview(for bandType: BandType) -> SongBandLeaderboardPreview {
        bands.first { $0.bandType == bandType.rawValue }
            ?? SongBandLeaderboardPreview(bandType: bandType.rawValue)
    }

    /// Reject a response for another song, an unknown or repeated band size, an
    /// impossible count, or a row filed under the wrong size.
    ///
    /// - Parameter songId: Requested song.
    /// - Throws: `FestivalAPIError.invalidBandProfile` on a mismatched or corrupt response.
    public func validate(songId: String) throws {
        guard self.songId == songId else { throw FestivalAPIError.invalidBandProfile }
        var seen = Set<String>()
        for band in bands {
            let rows = band.entries + [band.selectedPlayerEntry, band.selectedBandEntry].compactMap { $0 }
            guard BandType(rawValue: band.bandType) != nil, seen.insert(band.bandType).inserted,
                  band.count == band.entries.count, band.totalEntries >= 0,
                  rows.allSatisfy({ $0.bandType == band.bandType }) else {
                throw FestivalAPIError.invalidBandProfile
            }
        }
    }
}

/// Song Detail's band previews together with their publication provenance.
public struct SongBandLeaderboardsPayload: Sendable {
    public let response: SongBandLeaderboardsResponse
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}
