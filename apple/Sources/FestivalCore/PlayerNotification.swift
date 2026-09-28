import Foundation

// MARK: - Wire model

/// One event inside a coalesced notification's payload, mirroring the web's
/// `ImprovementNotificationEventPayload` (`packages/core/src/api/serverTypes.ts`).
public struct NotificationEventPayload: Decodable, Sendable, Equatable {
    public let eventKind: String?
    public let instrument: String?
    public let metric: String?
    public let oldNumeric: Double?
    public let newNumeric: Double?
    public let oldRank: Int?
    public let newRank: Int?
}

/// The typed subset of `ImprovementNotificationPayload` the native app reads.
public struct NotificationPayloadFields: Decodable, Sendable, Equatable {
    public let coalescedEvents: [NotificationEventPayload]?
    public let oldFullCombo: Bool?
    public let newFullCombo: Bool?
    public let oldStars: Int?
    public let newStars: Int?
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

/// Port of `getNotificationDestination` for the player-scoped feed (band grouping
/// and multi-event coalescing are handled by the web only; this app's feed reads
/// one player's own events, so every row already has a single kind/instrument).
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

// MARK: - Display text

/// One notification rendered for display, independent of the UI layer.
public struct AppNotification: Identifiable, Sendable, Equatable {
    public let id: String
    public let eventId: Int
    public let eventKind: String
    public let detectedAt: Date?
    public let title: String
    public let summary: String
    public let badge: String?
    public let songId: String?
    public let instrument: Instrument?
    public let destination: AppNotificationDestination?
}

/// Port of the player-scoped subset of `notificationText.ts`'s `copy.primary` templates
/// and `badges` (`FortniteFestivalWeb/src/i18n/en.json`); band, coalescing and flag-group
/// presentation are not ported natively this wave (see `.agents/controls/notifications/spec.md`).
public enum NotificationText {
    /// Compose the display title, summary and badge for one row.
    ///
    /// - Parameters:
    ///   - dto: Decoded notification.
    ///   - songTitle: Catalog title for `dto.songId`, when resolved.
    /// - Returns: Display-ready text; falls back to a generic sentence for unknown kinds.
    public static func format(_ dto: ImprovementNotificationDto, songTitle: String?) -> AppNotification {
        let instrument = dto.instrument.flatMap(Instrument.init(rawValue:))
        let instrumentLabel = instrument?.label ?? "this instrument"
        let song = songTitle ?? dto.songId ?? "this song"
        let oldStars = dto.payload?.oldStars
        let newStars = dto.payload?.newStars
        let title = songTitle ?? dto.songId ?? instrument?.label ?? "Notification"
        let destination = NotificationDestinationResolver.destination(for: dto)

        let summary: String
        switch dto.eventKind {
        case "service_new_shop_song":
            summary = "New in the Item Shop"
        case "player_first_score":
            summary = "Your first \(instrumentLabel) play on \(song) scored "
                + "\(formatted(dto.newNumeric)) points"
        case "player_score_pb":
            summary = "You set a new personal best on \(instrumentLabel) for \(song) with "
                + "\(formatted(dto.newNumeric)) points"
        case "player_song_rank_improved":
            summary = "You climbed from \(rank(dto.oldRank)) to \(rank(dto.newRank)) "
                + "on \(instrumentLabel) for \(song)"
        case "player_stars_improved":
            summary = "You improved from \(rank(oldStars)) to \(rank(newStars)) stars "
                + "on \(instrumentLabel) for \(song)"
        case "player_gold_stars_achieved":
            summary = "You earned gold stars on \(instrumentLabel) for \(song)"
        case "player_fc_achieved":
            summary = "You got a Full Combo on \(instrumentLabel) for \(song)"
        case "player_difficulty_bumped":
            summary = "You improved your difficulty on \(instrumentLabel) for \(song) from "
                + "\(formatted(dto.oldNumeric)) to \(formatted(dto.newNumeric))"
        case "player_weighted_rank_improved":
            summary = "You moved up from \(rank(dto.oldRank)) to \(rank(dto.newRank)) in "
                + "\(instrumentLabel) percentile rankings, weighted by number of entries"
        case "player_skill_rank_improved":
            summary = "You moved up from \(rank(dto.oldRank)) to \(rank(dto.newRank)) in "
                + "\(instrumentLabel) adjusted percentile rankings"
        case "player_total_score_rank_improved":
            summary = "You moved up from \(rank(dto.oldRank)) to \(rank(dto.newRank)) in "
                + "\(instrumentLabel) total score rankings"
        case "player_fc_rate_rank_improved":
            summary = "You moved up from \(rank(dto.oldRank)) to \(rank(dto.newRank)) in "
                + "\(instrumentLabel) Full Combo rankings"
        case "player_max_score_rank_improved":
            summary = "You moved up from \(rank(dto.oldRank)) to \(rank(dto.newRank)) in "
                + "\(instrumentLabel) max score rankings"
        case "player_total_score_improved":
            summary = "Your \(instrumentLabel) total score increased to "
                + "\(formatted(dto.newNumeric)) points"
        case "player_fc_count_improved":
            summary = "Your \(instrumentLabel) Full Combo count increased to "
                + "\(formatted(dto.newNumeric))"
        default:
            summary = "New improvement detected."
        }

        return AppNotification(
            id: dto.notificationGuid, eventId: dto.eventId, eventKind: dto.eventKind,
            detectedAt: ISO8601DateFormatter().date(from: dto.detectedAt), title: title,
            summary: summary, badge: badge(for: dto.eventKind), songId: dto.songId,
            instrument: instrument, destination: destination
        )
    }

    private static func rank(_ value: Int?) -> String {
        value.map { "#\($0)" } ?? "an unranked position"
    }

    private static func formatted(_ value: Double?) -> String {
        guard let value else { return "0" }
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    private static let badges: [String: String] = [
        "player_first_score": "First Score",
        "player_score_pb": "PB",
        "player_song_rank_improved": "Rank Up",
        "player_stars_improved": "Stars",
        "player_gold_stars_achieved": "Gold Stars",
        "player_fc_achieved": "Full Combo",
        "player_difficulty_bumped": "Difficulty",
        "player_weighted_rank_improved": "Weighted Percentile Rank",
        "player_skill_rank_improved": "Adjusted Percentile Rank",
        "player_total_score_rank_improved": "Total Score Rank",
        "player_fc_rate_rank_improved": "Full Combo Rank",
        "player_max_score_rank_improved": "Max Score Rank",
        "player_total_score_improved": "Total Score",
        "player_fc_count_improved": "Full Combos",
    ]

    private static func badge(for eventKind: String) -> String? { badges[eventKind] }
}
