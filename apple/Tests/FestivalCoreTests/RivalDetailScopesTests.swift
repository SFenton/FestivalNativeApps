import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

private let base = URL(string: "https://festivalscoretracker.com")!

/// Query items of a built URL, in wire order.
private func queryItems(_ url: URL) -> [URLQueryItem] {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
}

/// One compared song for merge tests.
private func comparison(_ songId: String, _ instrument: Instrument, delta: Int = 1) -> RivalSongComparison {
    RivalSongComparison(
        songId: songId, title: nil, artist: nil, instrument: instrument.rawValue,
        userInstrument: nil, rivalInstrument: nil, userRank: 10, rivalRank: 10 + delta,
        rankDelta: delta, userScore: nil, rivalScore: nil
    )
}

/// One detail response for merge tests.
private func detail(_ songs: [RivalSongComparison], name: String? = nil, combo: String) -> RivalDetailResponse {
    RivalDetailResponse(
        rival: RivalIdentity(accountId: "rival", displayName: name), combo: combo, instrument: nil,
        rankBy: nil, source: "precomputed", totalSongs: songs.count, offset: 0, limit: 0,
        sort: "closest", songs: songs, songsToCompete: nil, yourExclusiveSongs: nil
    )
}

/// One `/rivals/all` sample wire record (`{s, i, ur, rr, us, rs}`).
private func sample(_ songIndex: Int, _ instrument: Instrument, ur: Int, rr: Int) -> [String: Any] {
    ["s": songIndex, "i": instrument.rawValue, "ur": ur, "rr": rr, "us": 1000, "rs": 900]
}

/// Decode a `/rivals/all` payload with one `01` combo holding the given entries.
private func rivalsAll(songs: [String], entries: [[String: Any]], extra: [[String: Any]] = []) throws -> RivalsAllResponse {
    let dict: [String: Any] = [
        "accountId": "player", "songs": songs,
        "combos": [
            ["combo": "01", "above": entries, "below": []],
            ["combo": "02", "above": [], "below": extra],
        ],
    ]
    return try JSONDecoder().decode(RivalsAllResponse.self, from: JSONSerialization.data(withJSONObject: dict))
}

/// One `/rivals/all` rival entry.
private func entry(_ accountId: String, name: String? = nil, samples: [[String: Any]]) -> [String: Any] {
    var record: [String: Any] = [
        "accountId": accountId, "direction": "above", "sharedSongCount": samples.count,
        "aheadCount": 0, "behindCount": 0, "rivalScore": 1.0, "samples": samples,
    ]
    if let name { record["displayName"] = name }
    return record
}

// MARK: - Detail query shape

@Test func rivalDetailQueryMatchesWebShape() throws {
    let url = try RivalsEndpoint.detail(
        accountId: "abc123", instrument: .lead, rivalId: "def456", sort: "closest", limit: 0, offset: 0
    ).url(relativeTo: base)
    #expect(url.path == "/api/player/abc123/rivals/Solo_Guitar/def456")
    #expect(queryItems(url).map(\.name) == ["limit", "sort"])
    #expect(url.query == "limit=0&sort=closest")
}

@Test func rivalComboDetailQueryAddsLiveFallbackAndNonZeroOffset() throws {
    let url = try RivalsEndpoint.comboDetail(
        accountId: "abc123", token: "0f", rivalId: "def456", sort: "closest", limit: 50, offset: 100,
        allowLiveFallback: true
    ).url(relativeTo: base)
    #expect(url.path == "/api/player/abc123/rivals/0f/def456")
    #expect(url.query == "limit=50&sort=closest&offset=100&allowLiveFallback=true")
}

@Test func rivalDetailQueryOmitsLiveFallbackByDefault() {
    let items = RivalsEndpoint.detailQuery(sort: "closest", limit: 0, offset: 0, allowLiveFallback: false)
    #expect(items.map(\.0) == ["limit", "sort"])
    #expect(items.map(\.1) == ["0", "closest"])
}

// MARK: - Scope resolution

@Test func settingsScopeUsesComboThenFirstInstrumentThenGuitar() {
    #expect(RivalDetailScopes.settingsScope(visible: [.drums, .lead, .bass, .vocals]) == "0f")
    #expect(RivalDetailScopes.settingsScope(visible: [.proBass, .proLead]) == "30")
    #expect(RivalDetailScopes.settingsScope(visible: [.proDrums, .proCymbals]) == "pro_drums")
    // A cross-group mix has no combo: the first visible instrument in canonical order.
    #expect(RivalDetailScopes.settingsScope(visible: [.proLead, .bass]) == "Solo_Bass")
    #expect(RivalDetailScopes.settingsScope(visible: [.vocals]) == "Solo_Vocals")
    #expect(RivalDetailScopes.settingsScope(visible: []) == "Solo_Guitar")
}

@Test func hubScopeIsTheSettingsScopeAsARouteScope() {
    #expect(RivalDetailScopes.hubScope(visible: [.bass, .lead]) == .combo(
        token: "03", instruments: ["Solo_Guitar", "Solo_Bass"]
    ))
    #expect(RivalDetailScopes.hubScope(visible: [.proCymbals, .proDrums]) == .combo(
        token: "pro_drums", instruments: ["Solo_PeripheralCymbals", "Solo_PeripheralDrums"]
    ))
    #expect(RivalDetailScopes.hubScope(visible: [.karaoke]) == .song(instruments: ["Solo_PeripheralVocals"]))
    #expect(RivalDetailScopes.hubScope(visible: [.vocals, .proLead]) == .song(instruments: ["Solo_Vocals"]))
    #expect(RivalDetailScopes.hubScope(visible: []) == .song(instruments: ["Solo_Guitar"]))
}

@Test func settingsScopesPortsWebGroups() {
    #expect(RivalDetailScopes.settingsScopes(visible: Instrument.allCases) == ["0f", "30", "pro_drums"])
    #expect(RivalDetailScopes.settingsScopes(visible: [.lead, .vocals, .proDrums]) == ["09"])
    #expect(RivalDetailScopes.settingsScopes(visible: [.karaoke, .proDrums]) == ["Solo_PeripheralVocals"])
    #expect(RivalDetailScopes.settingsScopes(visible: []) == ["Solo_Guitar"])
}

@Test func tokensResolveEveryRouteScope() {
    let visible: [Instrument] = [.lead, .bass, .drums, .vocals]
    #expect(RivalDetailScopes.tokens(for: .combo(token: "03", instruments: []), visible: visible) == ["03"])
    #expect(RivalDetailScopes.tokens(for: .combo(token: "../x", instruments: []), visible: visible) == ["0f"])
    #expect(RivalDetailScopes.tokens(for: .song(instruments: ["Solo_Bass"]), visible: visible) == ["Solo_Bass"])
    // Common Rivals carries every visible instrument: the web opens it with the Settings scope.
    #expect(RivalDetailScopes.tokens(
        for: .song(instruments: visible.map(\.rawValue)), visible: visible
    ) == ["0f"])
    #expect(RivalDetailScopes.tokens(for: .song(instruments: ["bogus"]), visible: visible) == ["0f"])
    #expect(RivalDetailScopes.tokens(
        for: .leaderboard(instrument: "Solo_Drums", rankBy: .totalscore), visible: visible
    ) == ["Solo_Drums"])
    #expect(RivalDetailScopes.tokens(for: nil, visible: Instrument.allCases) == ["0f", "30", "pro_drums"])
}

@Test func onlyANilScopeAllowsLiveFallback() {
    #expect(RivalDetailScopes.allowsLiveFallback(for: nil))
    #expect(!RivalDetailScopes.allowsLiveFallback(for: .song(instruments: ["Solo_Guitar"])))
    #expect(!RivalDetailScopes.allowsLiveFallback(for: .combo(token: "03", instruments: [])))
}

@Test func instrumentsForTokenDecodesInstrumentsMasksAndProDrums() {
    #expect(RivalDetailScopes.instruments(forToken: "Solo_Bass") == [.bass])
    #expect(RivalDetailScopes.instruments(forToken: "0f") == [.lead, .bass, .drums, .vocals])
    #expect(RivalDetailScopes.instruments(forToken: "30") == [.proLead, .proBass])
    #expect(RivalDetailScopes.instruments(forToken: "pro_drums") == [.proCymbals, .proDrums])
    #expect(RivalDetailScopes.instruments(forToken: "00") == nil)
    #expect(RivalDetailScopes.instruments(forToken: "nope") == nil)
    #expect(RivalDetailScopes.soloInstrument(forToken: "Solo_Drums") == .drums)
    #expect(RivalDetailScopes.soloInstrument(forToken: "0f") == nil)
}

// MARK: - Combined detail

@Test func combinedDetailDedupesSongsAndJoinsScopes() throws {
    let first = detail([comparison("a", .lead), comparison("b", .lead)], combo: "0f")
    let second = detail([comparison("b", .lead), comparison("b", .proLead)], name: "Rival", combo: "30")
    let merged = try #require(RivalDetailResponse.combined([first, second], scopes: ["0f", "30", "pro_drums"]))
    #expect(merged.songs.map(\.id) == [
        comparison("a", .lead).id, comparison("b", .lead).id, comparison("b", .proLead).id,
    ])
    #expect(merged.totalSongs == 3)
    #expect(merged.combo == "0f,30,pro_drums")
    #expect(merged.rival.displayName == "Rival")
}

@Test func combinedDetailPassesASingleScopeThroughAndRejectsNone() {
    let only = detail([comparison("a", .lead)], combo: "Solo_Guitar")
    #expect(RivalDetailResponse.combined([only], scopes: ["Solo_Guitar"]) == only)
    #expect(RivalDetailResponse.combined([], scopes: ["Solo_Guitar"]) == nil)
}

// MARK: - `/rivals/all` fallback

@Test func fallbackRebuildsScopedClosestDetailFromRivalsAll() throws {
    let all = try rivalsAll(
        songs: ["s0", "s1", "s2", "s3"],
        entries: [entry("Rival-1", name: "That Rival", samples: [
            sample(0, .lead, ur: 10, rr: 40), // delta +30
            sample(1, .bass, ur: 50, rr: 45), // delta -5
            sample(2, .proLead, ur: 1, rr: 2), // outside the 03 scope
            sample(3, .lead, ur: 20, rr: 25), // delta +5, after s1 (stable)
            sample(9, .lead, ur: 1, rr: 2), // bad song index
        ])]
    )
    let result = try #require(RivalDetailFallback.detail(
        from: all, rivalId: "rival-1", scopes: ["03"],
        songInfo: { $0 == "s0" ? (title: "Song Zero", artist: "Band") : nil }
    ))
    #expect(result.songs.map(\.songId) == ["s1", "s3", "s0"])
    #expect(result.songs.map(\.rankDelta) == [-5, 5, 30])
    #expect(result.songs.last?.title == "Song Zero")
    #expect(result.songs.last?.artist == "Band")
    #expect(result.songs.last?.userScore == 1000)
    #expect(result.rival.accountId == "Rival-1")
    #expect(result.rival.displayName == "That Rival")
    #expect(result.source == RivalDetailFallback.source)
    #expect(result.combo == "03")
    #expect(result.totalSongs == 3)
    #expect(result.sort == "closest")
}

@Test func fallbackUsesTheEntryWithSamplesAndTakesANameFromAnyEntry() throws {
    let all = try rivalsAll(
        songs: ["s0"],
        entries: [entry("r", samples: [])],
        extra: [entry("r", name: "Named", samples: [sample(0, .bass, ur: 3, rr: 1)])]
    )
    let result = try #require(RivalDetailFallback.detail(from: all, rivalId: "r", scopes: ["Solo_Bass"]))
    #expect(result.songs.map(\.rankDelta) == [-2])
    #expect(result.rival.displayName == "Named")
}

@Test func fallbackIsEmptyOutsideScopeAndNilWithoutSamples() throws {
    let all = try rivalsAll(songs: ["s0"], entries: [
        entry("r", samples: [sample(0, .proDrums, ur: 1, rr: 2)]),
        entry("bare", samples: []),
    ])
    let outside = try #require(RivalDetailFallback.detail(from: all, rivalId: "r", scopes: ["0f"]))
    #expect(outside.songs.isEmpty)
    #expect(outside.totalSongs == 0)
    #expect(RivalDetailFallback.detail(from: all, rivalId: "bare", scopes: ["0f"]) == nil)
    #expect(RivalDetailFallback.detail(from: all, rivalId: "missing", scopes: ["0f"]) == nil)
    let proDrums = try #require(RivalDetailFallback.detail(from: all, rivalId: "r", scopes: ["pro_drums"]))
    #expect(proDrums.songs.count == 1)
}
