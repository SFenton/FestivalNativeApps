import Foundation
import Testing
import FestivalCore
@testable import FestivalUI

// MARK: - NotificationRoute

/// Issue #75: a tapped notification resolves to the route the main app shows after the
/// sheet closes (web `notificationDestination.ts` → `App.tsx` `handleNotificationOpen`).

private func fixtureSong() throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Fixture Pulse","artist":"Test Ensemble","year":2026}
    """.utf8))
}

private struct LookupFailure: Error {}

@MainActor
@Test func songNotificationOpensSongDetail() async throws {
    let song = try fixtureSong()
    var requested: [String] = []
    let route = await NotificationRoute.resolve(.song(songId: "fixture-pulse", instrument: .lead)) { id in
        requested.append(id)
        return song
    }
    #expect(route == .songDetail(song))
    #expect(requested == ["fixture-pulse"])
}

@MainActor
@Test func songMissingFromCatalogueDoesNotNavigate() async {
    let route = await NotificationRoute.resolve(.song(songId: "gone", instrument: nil)) { _ in nil }
    #expect(route == nil)
}

@MainActor
@Test func failedSongLookupDoesNotNavigate() async {
    let route = await NotificationRoute.resolve(.song(songId: "fixture-pulse", instrument: nil)) { _ in
        throw LookupFailure()
    }
    #expect(route == nil)
}

@MainActor
@Test(arguments: RankingMetric.allCases)
func rankNotificationWithInstrumentOpensFullRankings(metric: RankingMetric) async {
    let route = await NotificationRoute.resolve(.rankings(instrument: .drums, metric: metric)) { _ in
        Issue.record("A rank row must not look up a song")
        return nil
    }
    #expect(route == .fullRankings(instrument: .drums, rankBy: metric.rawValue))
}

@MainActor
@Test func rankNotificationWithoutInstrumentOpensLeaderboards() async {
    let route = await NotificationRoute.resolve(.rankings(instrument: nil, metric: .weighted)) { _ in nil }
    #expect(route == .leaderboards)
}

@MainActor
@Test func rowWithoutDestinationDoesNotNavigate() async {
    let route = await NotificationRoute.resolve(nil) { _ in
        Issue.record("A row without a destination must not look up a song")
        return nil
    }
    #expect(route == nil)
}
