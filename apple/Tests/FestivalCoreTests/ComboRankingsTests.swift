import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

/// A locally authored `/api/rankings/combo` page in the live wire shape (probed
/// 2026-10-10), never a captured production payload (`.agents/platforms/service-safety.md`).
private let comboBoardWire = """
{"comboId":"03","rankBy":"totalscore","page":1,"pageSize":5,"totalAccounts":2,"entries":[
 {"rank":1,"accountId":"fixture-player-1","displayName":"Fixture Player 1","adjustedRating":0.04,
  "weightedRating":0.05,"fcRate":0.5,"totalScore":178000000,"maxScorePercent":0.96,
  "songsPlayed":80,"totalChartedSongs":100,"fullComboCount":40,"computedAt":"2026-10-10T00:00:00Z"},
 {"rank":2,"accountId":"fixture-player-2","displayName":null,"adjustedRating":0.03,
  "weightedRating":0.04,"fcRate":0.25,"totalScore":176000000,"maxScorePercent":0.94,
  "songsPlayed":40,"totalChartedSongs":100,"fullComboCount":10,"computedAt":"2026-10-10T00:00:00Z"}
]}
"""

/// A locally authored `/api/rankings/combo/{accountId}` envelope.
private let comboOwnRowWire = """
{"rank":1234,"accountId":"fixture-player-1","displayName":"Fixture Player 1","adjustedRating":0.01,
 "weightedRating":0.02,"fcRate":0.1,"totalScore":12000000,"maxScorePercent":0.8,
 "songsPlayed":50,"totalChartedSongs":100,"fullComboCount":5,"computedAt":"2026-10-10T00:00:00Z",
 "comboId":"03","rankBy":"totalscore","totalAccounts":5000}
"""

private let comboPublicationJSON = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
 "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

private func comboReply(_ status: Int, _ wire: String, headers: [String: String] = [:]) -> HTTPResult {
    HTTPResult(status: status, data: Data(wire.utf8), headers: headers)
}

private let leadBass = RankingCombo(instruments: [.bass, .lead])!

// MARK: - Scopes (web `resolveSupportedRankingScopes`)

@Test func comboNeedsTwoInstrumentsOfOneComboFamily() throws {
    let combo = try #require(RankingCombo(instruments: [.bass, .lead]))
    #expect(combo.instruments == [.lead, .bass])
    #expect(combo.comboId == "03")
    #expect(combo.label == "Lead + Bass")
    #expect(RankingCombo(instruments: [.lead, .bass, .drums, .vocals])?.comboId == "0f")
    #expect(RankingCombo(instruments: [.proLead, .proBass])?.comboId == "30")
    #expect(RankingCombo(instruments: [.lead]) == nil)
    #expect(RankingCombo(instruments: [.lead, .lead]) == nil)
    #expect(RankingCombo(instruments: [.lead, .proBass]) == nil)
    #expect(RankingCombo(instruments: [.karaoke, .proDrums]) == nil)
}

@Test func supportedScopesPutEachFamilysComboBeforeItsInstruments() {
    #expect(RankingScope.supported(visible: []).isEmpty)
    #expect(RankingScope.supported(visible: [.lead]) == [.instrument(.lead)])
    #expect(RankingScope.supported(visible: [.bass, .lead]) == [
        .combo(leadBass), .instrument(.lead), .instrument(.bass),
    ])
    let all = RankingScope.supported(visible: Instrument.allCases)
    #expect(all.map(\.id) == [
        "0f", "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals",
        "30", "Solo_PeripheralGuitar", "Solo_PeripheralBass",
        "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums",
    ])
    // The peripherals never combine.
    #expect(RankingScope.supported(visible: [.karaoke, .proCymbals, .proDrums]).allSatisfy {
        if case .instrument = $0 { true } else { false }
    })
    #expect(RankingScope.combo(leadBass).label == "Lead + Bass")
    #expect(RankingScope.instrument(.drums).label == "Drums")
}

// MARK: - Wire and mapping

@Test func comboRowMapsOntoTheInstrumentRankingRow() throws {
    let response = try JSONDecoder().decode(ComboRankingsResponse.self, from: Data(comboBoardWire.utf8))
    try response.validate(combo: leadBass)
    let rows = response.rankings(metric: .totalscore)
    #expect(rows.instrument == "03")
    #expect(rows.totalAccounts == 2)
    let first = try #require(rows.entries.first)
    #expect(first.rank(for: .totalscore) == 1)
    #expect(first.rank(for: .adjusted) == 1)
    #expect(first.totalScore == 178_000_000)
    #expect(first.songsPlayed == 80)
    #expect(first.totalChartedSongs == 100)
    #expect(first.adjustedSkillRating == 0.04)
    #expect(rows.entries[1].displayName == nil)
    // FC Rate's songs column reads full combos over songs played (web combo label).
    let fc = response.rankings(metric: .fcrate).entries[0]
    #expect(fc.totalChartedSongs == 80)
    #expect(fc.fullComboCount == 40)
}

@Test func comboResponseForAnotherComboIsRejected() throws {
    let response = try JSONDecoder().decode(ComboRankingsResponse.self, from: Data(comboBoardWire.utf8))
    let other = try #require(RankingCombo(instruments: [.lead, .drums]))
    #expect(throws: FestivalAPIError.invalidLeaderboard) { try response.validate(combo: other) }
}

// MARK: - Client reads

@Test func comboBoardReadIsKeylessAndQueriesTheCombo() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: comboPublicationJSON),
        comboReply(200, comboBoardWire, headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.comboRankings(combo: leadBass, rankBy: .totalscore, page: 1, pageSize: 5)
    #expect(payload.rankings.entries.count == 2)
    #expect(payload.observedPublicationId == 7)

    let request = try #require(await transport.recorded().last)
    #expect(request.httpMethod == "GET")
    #expect(request.url?.path == "/api/rankings/combo")
    let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") }) == [
        "combo": "03", "rankBy": "totalscore", "page": "1", "pageSize": "5",
    ])
    #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
    #expect(request.allHTTPHeaderFields?.keys.contains { $0.lowercased().hasPrefix("x-fst-selected-") } != true)
}

@Test func comboOwnRowReadMapsTheRankAndTreats404AsUnranked() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: comboPublicationJSON),
        comboReply(200, comboOwnRowWire, headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let payload = try await client.playerComboRanking(
        combo: leadBass, accountId: "fixture-player-1", rankBy: .totalscore
    )
    #expect(payload.state == .available)
    #expect(payload.ranking?.entry.rank(for: .totalscore) == 1234)
    #expect(payload.ranking?.totalRankedAccounts == 5000)
    let request = try #require(await transport.recorded().last)
    #expect(request.url?.path == "/api/rankings/combo/fixture-player-1")
    #expect(request.url?.query?.contains("combo=03") == true)
    #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)

    let unranked = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: comboPublicationJSON),
        comboReply(404, #"{"error":"not ranked"}"#),
    ]))
    let missing = try await unranked.playerComboRanking(
        combo: leadBass, accountId: "fixture-player-1", rankBy: .totalscore
    )
    #expect(missing.state == .unranked)
    #expect(missing.ranking == nil)

    let mismatched = try FestivalAPI(transport: FixtureTransport([
        HTTPResult(status: 200, data: comboPublicationJSON),
        comboReply(200, comboOwnRowWire, headers: ["X-FST-Publication-Id": "7"]),
    ]))
    await #expect(throws: FestivalAPIError.invalidLeaderboard) {
        try await mismatched.playerComboRanking(
            combo: leadBass, accountId: "fixture-player-2", rankBy: .totalscore
        )
    }
}
