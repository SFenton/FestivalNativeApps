import Foundation
import Testing
@testable import FestivalCore

// MARK: - Ranking metric gate (web rankingHelpers.ts / bandRankingHelpers.ts)

@Test func experimentalRanksDefaultsOffUnderTheSettingsKey() {
    #expect(ExperimentalRanks.storageKey == "fst.settings.experimentalRanks")
    #expect(ExperimentalRanks.defaultValue == false)
}

@Test func accountMetricsNarrowToTotalScoreWhileOff() {
    #expect(RankingMetric.enabled(experimentalRanks: false) == [.totalscore])
    #expect(RankingMetric.enabled(experimentalRanks: true) == [.totalscore, .adjusted, .weighted, .fcrate, .maxscore])
    #expect(Set(RankingMetric.menuOrder) == Set(RankingMetric.allCases))
    #expect(RankingMetric.allCases.filter(\.isExperimental) == [.adjusted, .weighted, .fcrate, .maxscore])
}

@Test func savedOrDeepLinkedExperimentalMetricFallsBackToTotalScore() {
    for metric in RankingMetric.allCases {
        #expect(RankingMetric.coerced(metric.rawValue, experimentalRanks: false) == .totalscore)
        #expect(RankingMetric.coerced(metric.rawValue, experimentalRanks: true) == metric)
        #expect(metric.coerced(experimentalRanks: false) == .totalscore)
        #expect(metric.coerced(experimentalRanks: true) == metric)
    }
    #expect(RankingMetric.coerced("bogus", experimentalRanks: true) == .totalscore)
    #expect(RankingMetric.coerced(nil, experimentalRanks: true) == .totalscore)
}

@Test func bandMetricsNeverOfferMaxScoreAndNarrowWhileOff() {
    #expect(BandRankingMetric.enabled(experimentalRanks: false) == [.totalscore])
    #expect(BandRankingMetric.enabled(experimentalRanks: true) == [.totalscore, .adjusted, .weighted, .fcrate])
    #expect(Set(BandRankingMetric.menuOrder) == Set(BandRankingMetric.allCases))
    #expect(BandRankingMetric.coerced("maxscore", experimentalRanks: true) == .totalscore)
    #expect(BandRankingMetric.coerced("fcrate", experimentalRanks: true) == .fcrate)
    #expect(BandRankingMetric.coerced("fcrate", experimentalRanks: false) == .totalscore)
    #expect(BandRankingMetric.adjusted.coerced(experimentalRanks: false) == .totalscore)
}

@Test func bandDetailDefaultsToAdjustedOnlyWithExperimentalRanks() {
    #expect(BandRankingMetric.bandDetailDefault(experimentalRanks: true) == .adjusted)
    #expect(BandRankingMetric.bandDetailDefault(experimentalRanks: false) == .totalscore)
}

@Test func rivalMetricsAndLeaderboardScopesNarrowWhileOff() {
    #expect(RivalRankMetric.enabled(experimentalRanks: false) == [.totalscore])
    #expect(RivalRankMetric.enabled(experimentalRanks: true) == [.totalscore, .adjusted, .weighted, .fcrate, .maxscore])
    #expect(RivalRankMetric.weighted.coerced(experimentalRanks: false) == .totalscore)
    #expect(RivalRankMetric.weighted.coerced(experimentalRanks: true) == .weighted)

    let scope = RivalScope.leaderboard(instrument: "Solo_Guitar", rankBy: .fcrate)
    #expect(scope.coerced(experimentalRanks: false) == .leaderboard(instrument: "Solo_Guitar", rankBy: .totalscore))
    #expect(scope.coerced(experimentalRanks: true) == scope)
    let song = RivalScope.song(instruments: ["Solo_Guitar"])
    #expect(song.coerced(experimentalRanks: false) == song)
}

// MARK: - Notifications (web notificationSurface.ts projectExperimentalRankNotification)

private func event(_ kind: String, metric: String? = nil, oldRank: Double? = nil, newRank: Double? = nil) -> NotificationEventPayload {
    NotificationEventPayload(
        eventKind: kind, instrument: "Solo_Guitar", metric: metric,
        oldNumeric: nil, newNumeric: nil, oldRank: oldRank, newRank: newRank
    )
}

private func notification(
    kind: String, metric: String? = nil, oldRank: Int? = nil, newRank: Int? = nil,
    events: [NotificationEventPayload]? = nil
) -> ImprovementNotificationDto {
    ImprovementNotificationDto(
        eventId: 7, notificationGuid: "guid-7", accountId: "acc-1", eventKind: kind,
        songId: nil, instrument: "Solo_Guitar", metric: metric, oldNumeric: nil, newNumeric: nil,
        oldRank: oldRank, newRank: newRank,
        payload: events.map {
            NotificationPayloadFields(
                coalescedEvents: $0, coalescedInstruments: ["Solo_Guitar"],
                oldFullCombo: nil, newFullCombo: nil, oldStars: nil, newStars: nil,
                songTitle: nil, artist: nil, albumArt: nil
            )
        },
        detectedAt: "2026-10-01T00:00:00Z", expiresAt: "2026-10-08T00:00:00Z"
    )
}

@Test func notificationsAreUnchangedWithExperimentalRanksOn() {
    let row = notification(kind: "player_weighted_rank_improved", oldRank: 9, newRank: 4)
    #expect(NotificationExperimentalRanks.project(row, experimentalRanks: true) == row)
}

@Test func experimentalOnlyRankNotificationIsHiddenWhileOff() {
    let row = notification(kind: "player_skill_rank_improved", oldRank: 9, newRank: 4)
    #expect(NotificationExperimentalRanks.project(row, experimentalRanks: false) == nil)
    let byMetric = notification(kind: "rank_improved", metric: "fc_rate_rank", oldRank: 9, newRank: 4)
    #expect(NotificationExperimentalRanks.project(byMetric, experimentalRanks: false) == nil)
}

@Test func nonRankAndTotalScoreNotificationsStayWhileOff() {
    let pb = notification(kind: "player_score_pb")
    #expect(NotificationExperimentalRanks.project(pb, experimentalRanks: false) == pb)
    let total = notification(kind: "player_total_score_rank_improved", oldRank: 30, newRank: 20)
    #expect(NotificationExperimentalRanks.project(total, experimentalRanks: false) == total)
}

@Test func mixedCoalescedRankNotificationKeepsTotalScoreEventWhileOff() throws {
    let row = notification(
        kind: "player_weighted_rank_improved", oldRank: 9, newRank: 4,
        events: [
            event("player_weighted_rank_improved", oldRank: 9, newRank: 4),
            event("player_total_score_rank_improved", oldRank: 30.0, newRank: 20.0),
            event("player_max_score_rank_improved", oldRank: 12, newRank: 11),
        ]
    )
    let projected = try #require(NotificationExperimentalRanks.project(row, experimentalRanks: false))
    #expect(projected.eventKind == "player_total_score_rank_improved")
    #expect(projected.oldRank == 30)
    #expect(projected.newRank == 20)
    #expect(projected.payload?.coalescedEvents?.map(\.eventKind) == ["player_total_score_rank_improved"])
    #expect(projected.payload?.coalescedInstruments == ["Solo_Guitar"])
    #expect(projected.notificationGuid == row.notificationGuid)
    guard case let .rankings(_, metric) = NotificationDestinationResolver.destination(for: projected) else {
        Issue.record("Expected a rankings destination")
        return
    }
    #expect(metric == .totalscore)
}

@Test func coalescedNotificationOfOnlyExperimentalRanksIsHiddenWhileOff() {
    let row = notification(
        kind: "player_weighted_rank_improved",
        events: [event("player_weighted_rank_improved"), event("player_fc_rate_rank_improved")]
    )
    #expect(NotificationExperimentalRanks.project(row, experimentalRanks: false) == nil)
}

@Test func coalescedNotificationWithoutExperimentalRanksIsUnchangedWhileOff() {
    let row = notification(
        kind: "player_score_pb",
        events: [event("player_score_pb"), event("player_total_score_rank_improved", oldRank: 3, newRank: 2)]
    )
    #expect(NotificationExperimentalRanks.project(row, experimentalRanks: false) == row)
}
