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
