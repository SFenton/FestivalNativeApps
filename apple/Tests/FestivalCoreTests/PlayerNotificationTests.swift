import Foundation
import Testing
@testable import FestivalCore

/// Build a minimal fixture DTO, overriding only the fields a test needs.
private func dto(
    eventKind: String, songId: String? = nil, instrument: String? = Instrument.lead.rawValue,
    metric: String? = nil, oldRank: Int? = nil, newRank: Int? = nil,
    newNumeric: Double? = nil, oldNumeric: Double? = nil
) -> ImprovementNotificationDto {
    ImprovementNotificationDto(
        eventId: 1, notificationGuid: "guid-1", accountId: "acc-1", eventKind: eventKind,
        songId: songId, instrument: instrument, metric: metric, oldNumeric: oldNumeric,
        newNumeric: newNumeric, oldRank: oldRank, newRank: newRank, payload: nil,
        detectedAt: "2024-01-01T00:00:00Z", expiresAt: "2024-02-01T00:00:00Z"
    )
}

// MARK: - Ranking metric mapping

@Test func rankMetricResolvesFromEventKindBeforeMetricString() {
    #expect(NotificationRankingMetric.metric(
        eventKind: "player_weighted_rank_improved", metric: nil
    ) == .weighted)
    #expect(NotificationRankingMetric.metric(
        eventKind: "player_skill_rank_improved", metric: "ignored"
    ) == .adjusted)
    #expect(NotificationRankingMetric.metric(eventKind: nil, metric: "fc_rate_rank") == .fcrate)
    #expect(NotificationRankingMetric.metric(eventKind: "player_score_pb", metric: nil) == nil)
}

// MARK: - Destination

@Test func songEventResolvesToSongDestination() {
    let event = dto(eventKind: "player_score_pb", songId: "song-1", instrument: "Solo_Bass")
    guard case let .song(songId, instrument) = NotificationDestinationResolver.destination(for: event) else {
        Issue.record("Expected a song destination")
        return
    }
    #expect(songId == "song-1")
    #expect(instrument == .bass)
}

@Test func rankEventResolvesToRankingsDestination() {
    let event = dto(eventKind: "player_weighted_rank_improved", instrument: "Solo_Guitar")
    guard case let .rankings(instrument, metric) = NotificationDestinationResolver.destination(for: event) else {
        Issue.record("Expected a rankings destination")
        return
    }
    #expect(instrument == .lead)
    #expect(metric == .weighted)
}

@Test func unknownEventHasNoDestination() {
    let event = dto(eventKind: "player_total_score_improved", songId: nil)
    #expect(NotificationDestinationResolver.destination(for: event) == nil)
}

// MARK: - Text

@Test func formatsSongRankImprovedWithRanksAndSong() {
    let event = dto(
        eventKind: "player_song_rank_improved", songId: "song-1",
        instrument: "Solo_Guitar", oldRank: 42, newRank: 10
    )
    let formatted = NotificationText.format(event, songTitle: "Fixture Song")
    #expect(formatted.summary.contains("#42"))
    #expect(formatted.summary.contains("#10"))
    #expect(formatted.summary.contains("Fixture Song"))
    #expect(formatted.title == "Fixture Song")
    #expect(formatted.badge == "Rank Up")
}

@Test func formatsUnknownEventKindWithGenericFallback() {
    let event = dto(eventKind: "some_future_event_kind")
    let formatted = NotificationText.format(event, songTitle: nil)
    #expect(formatted.summary == "New improvement detected.")
}

@Test func formatsShopSongWithoutInstrumentContext() {
    let event = dto(eventKind: "service_new_shop_song", songId: "song-2", instrument: nil)
    let formatted = NotificationText.format(event, songTitle: "New Track")
    #expect(formatted.summary == "New in the Item Shop")
    #expect(formatted.title == "New Track")
}

/// Every remaining `NotificationText.format` case, its badge and the shared
/// `rank(_:)`/`formatted(_:)` helpers (unranked fallback, whole vs. fractional
/// numeric formatting) — these branches previously had no direct test.
@Test func formatsEveryRemainingEventKindWithItsBadgeAndNumericFormatting() {
    let firstScore = NotificationText.format(
        dto(eventKind: "player_first_score", songId: "song-1", newNumeric: 500_000),
        songTitle: "Fixture Song"
    )
    #expect(firstScore.summary.contains("first"))
    #expect(firstScore.summary.contains("500000 points"))
    #expect(firstScore.badge == "First Score")

    let pb = NotificationText.format(
        dto(eventKind: "player_score_pb", songId: "song-1", newNumeric: 750_500.4),
        songTitle: "Fixture Song"
    )
    #expect(pb.summary.contains("personal best"))
    #expect(pb.summary.contains("750500.4 points"))
    #expect(pb.badge == "PB")

    // No prior stars value: falls back to "an unranked position".
    let stars = NotificationText.format(
        dto(eventKind: "player_stars_improved", songId: "song-1"), songTitle: "Fixture Song"
    )
    #expect(stars.summary.contains("an unranked position"))
    #expect(stars.badge == "Stars")

    let gold = NotificationText.format(
        dto(eventKind: "player_gold_stars_achieved", songId: "song-1"), songTitle: "Fixture Song"
    )
    #expect(gold.summary == "You earned gold stars on Lead for Fixture Song")
    #expect(gold.badge == "Gold Stars")

    let fc = NotificationText.format(
        dto(eventKind: "player_fc_achieved", songId: "song-1"), songTitle: "Fixture Song"
    )
    #expect(fc.summary == "You got a Full Combo on Lead for Fixture Song")
    #expect(fc.badge == "Full Combo")

    let difficulty = NotificationText.format(
        dto(eventKind: "player_difficulty_bumped", songId: "song-1", newNumeric: 4, oldNumeric: 3),
        songTitle: "Fixture Song"
    )
    #expect(difficulty.summary.contains("from 3 to 4"))
    #expect(difficulty.badge == "Difficulty")

    let weighted = NotificationText.format(
        dto(eventKind: "player_weighted_rank_improved", oldRank: 50, newRank: 20),
        songTitle: nil
    )
    #expect(weighted.summary.contains("weighted by number of entries"))
    #expect(weighted.badge == "Weighted Percentile Rank")

    let skill = NotificationText.format(
        dto(eventKind: "player_skill_rank_improved", oldRank: 50, newRank: 20), songTitle: nil
    )
    #expect(skill.summary.contains("adjusted percentile rankings"))
    #expect(skill.badge == "Adjusted Percentile Rank")

    let totalScoreRank = NotificationText.format(
        dto(eventKind: "player_total_score_rank_improved", oldRank: 50, newRank: 20), songTitle: nil
    )
    #expect(totalScoreRank.summary.contains("total score rankings"))
    #expect(totalScoreRank.badge == "Total Score Rank")

    let fcRateRank = NotificationText.format(
        dto(eventKind: "player_fc_rate_rank_improved", oldRank: 50, newRank: 20), songTitle: nil
    )
    #expect(fcRateRank.summary.contains("Full Combo rankings"))
    #expect(fcRateRank.badge == "Full Combo Rank")

    let maxScoreRank = NotificationText.format(
        dto(eventKind: "player_max_score_rank_improved", oldRank: 50, newRank: 20), songTitle: nil
    )
    #expect(maxScoreRank.summary.contains("max score rankings"))
    #expect(maxScoreRank.badge == "Max Score Rank")

    let totalScore = NotificationText.format(
        dto(eventKind: "player_total_score_improved", newNumeric: 1_000_000), songTitle: nil
    )
    #expect(totalScore.summary.contains("1000000 points"))
    #expect(totalScore.badge == "Total Score")

    let fcCount = NotificationText.format(
        dto(eventKind: "player_fc_count_improved", newNumeric: 12), songTitle: nil
    )
    #expect(fcCount.summary.contains("increased to 12"))
    #expect(fcCount.badge == "Full Combos")

    // Unmapped kind: no badge.
    #expect(NotificationText.format(dto(eventKind: "totally_unknown"), songTitle: nil).badge == nil)
}
