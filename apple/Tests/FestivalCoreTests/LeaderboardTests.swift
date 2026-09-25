import Foundation
import Testing
@testable import FestivalCore

/// A 25-row response with 26 local entries must still expose page two.
@Test func localTotalsControlPageCount() throws {
    let items = (1...25).map { rank in
        """
        {"accountId":"fixture-\(rank)","displayName":"Player \(rank)",
        "score":\(100000 - rank),"rank":\(rank)}
        """
    }.joined(separator: ",")
    let data = Data("""
    {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":25,
    "localEntries":26,"totalEntries":40,"entries":[\(items)]}
    """.utf8)
    let result = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
    try result.validate(songId: "fixture-pulse", instrument: .lead)
    #expect(result.pageCount == 2)
    #expect(result.entries.count == 25)
    #expect(result.entries[24].rank == 25)
}

/// Old responses without localEntries use totalEntries, including an empty list.
@Test func missingLocalTotalAndBadCount() throws {
    let data = Data("""
    {"songId":"fixture-pulse","instrument":"Solo_Guitar",
    "count":0,"totalEntries":26,"entries":[]}
    """.utf8)
    let result = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
    #expect(result.pageCount == 2)
    #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try result.validate(songId: "wrong-song", instrument: .lead)
    }
}

/// Explicit pages win even when cached navigation would select another row.
@Test func deepLinkOverridesCachedPageAndOutOfRangeIsCorrected() {
    #expect(LeaderboardPaging.initial(explicitPage: 2, cachedPage: 3) == 2)
    #expect(LeaderboardPaging.initial(explicitPage: nil, cachedPage: 3) == 3)
    #expect(LeaderboardPaging.initial(explicitPage: 0, cachedPage: nil) == 1)
    #expect(LeaderboardPaging.corrected(requested: 99, totalPages: 2) == 2)
    #expect(LeaderboardPaging.corrected(requested: -1, totalPages: 2) == 1)
}
