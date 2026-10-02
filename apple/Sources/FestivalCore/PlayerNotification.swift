import Foundation

// MARK: - Wire model

/// One event inside a coalesced notification's payload, mirroring the web's
/// `ImprovementNotificationEventPayload` (`packages/core/src/api/serverTypes.ts`).
///
/// Decoding is lenient like the web's `normalizePayloadEvent` (`useProfileNotificationsFeed.tsx`):
/// numbers may arrive as numeric strings, booleans as `"true"`/`"false"`, and a field of an
/// unexpected type reads as nil instead of failing the whole feed.
public struct NotificationEventPayload: Sendable, Equatable {
    public let eventKind: String?
    public let instrument: String?
    public let metric: String?
    public let oldNumeric: Double?
    public let newNumeric: Double?
    public let oldRank: Double?
    public let newRank: Double?
    /// Display labels for difficulty bumps (`player_difficulty_bumped`), preferred over numerics.
    public var oldLabel: String? = nil
    public var newLabel: String? = nil
    /// Per-event score result, used to derive Full Combo / gold-star clauses.
    public var oldFullCombo: Bool? = nil
    public var newFullCombo: Bool? = nil
    public var oldStars: Double? = nil
    public var newStars: Double? = nil
}

/// The typed subset of `ImprovementNotificationPayload` the native app reads, decoded
/// leniently (see ``NotificationEventPayload``).
public struct NotificationPayloadFields: Sendable, Equatable {
    public let coalescedEvents: [NotificationEventPayload]?
    /// Every chart the coalesced row touched (service instrument keys), for the media rail.
    public var coalescedInstruments: [String]? = nil
    public let oldFullCombo: Bool?
    public let newFullCombo: Bool?
    public let oldStars: Double?
    public let newStars: Double?
    /// `service_new_shop_song` notifications embed the song's own title/art here
    /// (`FSTService/Persistence/ImprovementNotificationService.cs:526-529`) since
    /// they are not scoped to a signed-in player.
    public let songTitle: String?
    public let artist: String?
    public let albumArt: String?
}

/// `GET /api/player/{accountId}/notifications` row, mirroring `ImprovementNotificationDto`.
public struct ImprovementNotificationDto: Decodable, Sendable, Equatable, Identifiable {
    public let eventId: Int
    public let notificationGuid: String
    public let accountId: String?
    public let eventKind: String
    public let songId: String?
    public let instrument: String?
    public let metric: String?
    public let oldNumeric: Double?
    public let newNumeric: Double?
    public let oldRank: Int?
    public let newRank: Int?
    public let payload: NotificationPayloadFields?
    public let detectedAt: String
    public let expiresAt: String

    public var id: String { notificationGuid }
}

/// `GET /api/player/{accountId}/notifications` envelope, mirroring
/// `ImprovementNotificationsEnvelope`.
public struct ImprovementNotificationsEnvelope: Decodable, Sendable, Equatable {
    public let generatedAt: String
    public let expiresAfterHours: Double
    public let sourceRunId: Int?
    public let sourceCompletedAt: String?
    public let notificationsGenerated: Bool?
    public let items: [ImprovementNotificationDto]

    /// Whether the feed has ever been generated, distinct from "generated but empty".
    public var isGenerated: Bool {
        notificationsGenerated ?? (sourceRunId != nil || sourceCompletedAt != nil || !items.isEmpty)
    }
}

/// One notifications read, tagged with offline freshness like other public reads.
public struct PlayerNotificationsPayload: Sendable {
    public let envelope: ImprovementNotificationsEnvelope
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool
}

// MARK: - Ranking metric mapping

/// Port of `notificationRanking.ts`'s event-kind/metric → `RankingMetric` tables.
public enum NotificationRankingMetric {
    private static let byEventKind: [String: RankingMetric] = [
        "player_weighted_rank_improved": .weighted,
        "player_skill_rank_improved": .adjusted,
        "player_total_score_rank_improved": .totalscore,
        "player_fc_rate_rank_improved": .fcrate,
        "player_max_score_rank_improved": .maxscore,
    ]
    private static let byMetric: [String: RankingMetric] = [
        "weighted_rank": .weighted,
        "skill_rank": .adjusted,
        "adjusted_skill_rank": .adjusted,
        "total_score_rank": .totalscore,
        "fc_rate_rank": .fcrate,
        "max_score_rank": .maxscore,
        "max_score_percent_rank": .maxscore,
        "composite_rank": .adjusted,
        "composite_rank_weighted": .weighted,
        "composite_rank_total_score": .totalscore,
        "composite_rank_fc_rate": .fcrate,
        "composite_rank_max_score": .maxscore,
    ]

    /// Resolve the leaderboard metric a rank-improvement event refers to.
    ///
    /// - Parameters:
    ///   - eventKind: Notification (or coalesced sub-event) kind.
    ///   - metric: Raw service metric string, when present.
    /// - Returns: The matching rankings-board metric, or nil for a non-rank event.
    public static func metric(eventKind: String?, metric: String?) -> RankingMetric? {
        if let eventKind, let byKind = byEventKind[eventKind] { return byKind }
        guard let metric else { return nil }
        return byMetric[metric]
    }
}

// MARK: - Destination

/// Where tapping a notification should navigate, independent of `AppRoute`
/// (this module cannot see the UI layer's route type).
public enum AppNotificationDestination: Sendable, Equatable {
    /// A song-scoped event; `instrument` is nil when multiple charts coalesced.
    case song(songId: String, instrument: Instrument?)
    /// A global rank-improvement event.
    case rankings(instrument: Instrument?, metric: RankingMetric)
}

/// Player-scoped event kinds that resolve to a song, per `notificationDestination.ts`.
private let songEventKinds: Set<String> = [
    "service_new_shop_song", "player_first_score", "player_score_pb",
    "player_song_rank_improved", "player_stars_improved", "player_gold_stars_achieved",
    "player_fc_achieved", "player_difficulty_bumped",
]

/// Port of `getNotificationDestination` for the player-scoped feed (band grouping is
/// web-only; a coalesced row navigates by its top-level kind, song and instrument).
public enum NotificationDestinationResolver {
    /// Resolve a tap destination for one notification row.
    ///
    /// - Parameter dto: Decoded notification.
    /// - Returns: A song or rankings destination, or nil when the row has neither.
    public static func destination(for dto: ImprovementNotificationDto) -> AppNotificationDestination? {
        let instrument = dto.instrument.flatMap(Instrument.init(rawValue:))
        if let songId = dto.songId, songEventKinds.contains(dto.eventKind) {
            return .song(songId: songId, instrument: instrument)
        }
        if let metric = NotificationRankingMetric.metric(eventKind: dto.eventKind, metric: dto.metric) {
            return .rankings(instrument: instrument, metric: metric)
        }
        return nil
    }
}

// MARK: - Lenient payload decoding

extension NotificationEventPayload: Decodable {
    private enum CodingKeys: String, CodingKey {
        case eventKind, instrument, metric, oldNumeric, newNumeric, oldRank, newRank
        case oldLabel, newLabel, oldFullCombo, newFullCombo, oldStars, newStars
    }

    /// Decode one coalesced event, reading malformed fields as nil.
    ///
    /// - Parameter decoder: JSON decoder positioned on one `coalescedEvents` element.
    /// - Throws: Only when the element is not a JSON object.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventKind = container.lenientString(.eventKind)
        instrument = container.lenientString(.instrument)
        metric = container.lenientString(.metric)
        oldNumeric = container.lenientNumber(.oldNumeric)
        newNumeric = container.lenientNumber(.newNumeric)
        oldRank = container.lenientNumber(.oldRank)
        newRank = container.lenientNumber(.newRank)
        oldLabel = container.lenientString(.oldLabel)
        newLabel = container.lenientString(.newLabel)
        oldFullCombo = container.lenientBool(.oldFullCombo)
        newFullCombo = container.lenientBool(.newFullCombo)
        oldStars = container.lenientNumber(.oldStars)
        newStars = container.lenientNumber(.newStars)
    }
}

extension NotificationPayloadFields: Decodable {
    private enum CodingKeys: String, CodingKey {
        case coalescedEvents, coalescedInstruments, oldFullCombo, newFullCombo, oldStars, newStars
        case songTitle, artist, albumArt
    }

    /// Decode the payload subset, reading malformed fields as nil.
    ///
    /// - Parameter decoder: JSON decoder positioned on a notification's `payload`.
    /// - Throws: Only when the payload is not a JSON object.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coalescedEvents = try? container.decodeIfPresent(
            [NotificationEventPayload].self, forKey: .coalescedEvents
        )
        coalescedInstruments = (try? container.decodeIfPresent(
            [LenientString].self, forKey: .coalescedInstruments
        ))?.compactMap(\.value)
        oldFullCombo = container.lenientBool(.oldFullCombo)
        newFullCombo = container.lenientBool(.newFullCombo)
        oldStars = container.lenientNumber(.oldStars)
        newStars = container.lenientNumber(.newStars)
        songTitle = container.lenientString(.songTitle)
        artist = container.lenientString(.artist)
        albumArt = container.lenientString(.albumArt)
    }
}

/// One array element that is a non-empty string, else nil (never throws).
private struct LenientString: Decodable {
    let value: String?

    /// - Parameter decoder: Decoder positioned on one array element.
    init(from decoder: Decoder) throws {
        let raw = try? decoder.singleValueContainer().decode(String.self)
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        value = trimmed?.isEmpty == false ? trimmed : nil
    }
}

extension KeyedDecodingContainer {
    /// A trimmed, non-empty string, else nil (web `stringValue`).
    ///
    /// - Parameter key: Field to read.
    /// - Returns: The string, or nil when absent, empty or another type.
    func lenientString(_ key: Key) -> String? {
        guard let raw = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A finite number, or a numeric string (web `numberValue`).
    ///
    /// - Parameter key: Field to read.
    /// - Returns: The value, or nil when absent, non-finite or not numeric.
    func lenientNumber(_ key: Key) -> Double? {
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number.isFinite ? number : nil
        }
        guard let text = try? decodeIfPresent(String.self, forKey: key),
              let parsed = Double(text.trimmingCharacters(in: .whitespaces)), parsed.isFinite
        else { return nil }
        return parsed
    }

    /// A boolean, or `"true"`/`"false"` in any case (web `booleanValue`).
    ///
    /// - Parameter key: Field to read.
    /// - Returns: The value, or nil when absent or not boolean-like.
    func lenientBool(_ key: Key) -> Bool? {
        if let flag = try? decodeIfPresent(Bool.self, forKey: key) { return flag }
        guard let text = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
}
