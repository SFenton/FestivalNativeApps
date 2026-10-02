import Foundation
import Testing
@testable import FestivalCore

// MARK: - Helpers

/// Replies with one canned response per path and records requests.
private actor CannedTransport: HTTPTransport {
    private let replies: [String: HTTPResult]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [String: HTTPResult]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        requests.append(request)
        guard let reply = replies[request.url?.path ?? ""] else { throw URLError(.badURL) }
        return reply
    }
}

private func decode(_ json: String) throws -> ServiceInfo {
    try JSONDecoder().decode(ServiceInfo.self, from: Data(json.utf8))
}

private let idleJSON = """
{"contractVersion":2,
 "phasePlan":{"version":"p1","phases":[{"id":"scrape.leaderboards","label":"Scrape"}]},
 "lastCompletedUpdate":{"scrapeId":1,"startedAt":"2026-01-01T11:00:00Z",
   "completedAt":"2026-01-01T11:30:00Z","publishedAt":"2026-01-01T12:00:00.1234567Z"},
 "currentUpdate":{"status":"idle","startedAt":null,"phase":null,"subOperation":null},
 "publication":{"publishedScrapeId":1,"publishedAt":"2026-01-01T12:00:00Z",
   "publicReadsFrozen":false,"frozenAt":null,"frozenScrapeId":null,"freezeReason":null},
 "workerStatus":{"workerKey":"w","status":"online"},
 "postgresConnectionTarget":{"host":"h","port":1,"database":"d","username":"u",
   "defaultTransactionReadOnlyOption":true},
 "nextScheduledUpdateAt":null}
"""

/// An updating body with the given progress knobs.
private func updating(
    scrapeId: Int = 9, phaseId: String = "scrape.leaderboards", attempt: Int = 1,
    ordinal: Int = 1, phasePercent: Double = 40, subphase: String? = "fetching_leaderboards",
    subProgress: String? = nil, lastProgressAt: String = "2026-01-01T12:00:10Z",
    worker: String = "online"
) throws -> ServiceInfo {
    let sub = subphase.map { "\"\($0)\"" } ?? "null"
    let progress = subProgress ?? "null"
    return try decode("""
    {"contractVersion":2,"lastCompletedUpdate":null,
     "currentUpdate":{"status":"updating","scrapeId":\(scrapeId),"startedAt":"2026-01-01T12:00:00Z",
      "phase":"Scraping","subOperation":"fetching_leaderboards","operationId":"op",
      "phaseId":"\(phaseId)","subphaseId":\(sub),"phasePlanVersion":"p1",
      "phaseOrdinal":\(ordinal),"phaseAttempt":\(attempt),"unitsKind":"leaderboards",
      "unitsCompleted":400,"unitsTotal":1000,"unitsTotalFinal":true,"phasePercent":\(phasePercent),
      "subphaseProgress":\(progress),"lastProgressAt":"\(lastProgressAt)"},
     "workerStatus":{"workerKey":"w","status":"\(worker)"},"nextScheduledUpdateAt":null}
    """)
}

private func subProgress(
    id: String = "fetching_leaderboards", sequence: Int, percent: Double, kind: String = "exact",
    final: Bool = true, completed: Int = 10, total: Int = 100, schema: Int = 1
) -> String {
    """
    {"schemaVersion":\(schema),"id":"\(id)","epoch":0,"sequence":\(sequence),"kind":"\(kind)",
     "unitsKind":"leaderboards","unitsCompleted":\(completed),"unitsTotal":\(total),
     "unitsTotalFinal":\(final),"percent":\(percent)}
    """
}

// MARK: - API

@Test func serviceInfoReadsKeylessOperationalEndpointWithFreezeHeader() async throws {
    let transport = CannedTransport([
        "/api/service-info": HTTPResult(
            status: 200, data: Data(idleJSON.utf8),
            headers: [ServiceFreezeReason.header: "scrape"]
        ),
        "/api/version": HTTPResult(status: 200, data: Data(#"{"version":"1.2.3+abc"}"#.utf8)),
    ])
    let api = try FestivalAPI(transport: transport)
    let snapshot = try await api.serviceInfo()
    #expect(snapshot.info.currentUpdate.status == "idle")
    #expect(snapshot.freezeReasonHeader == "scrape")
    #expect(try await api.serviceVersion() == "1.2.3+abc")
    let requests = await transport.requests
    #expect(requests.map { $0.url?.path } == ["/api/service-info", "/api/version"])
    for request in requests {
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil)
    }
}

@Test func serviceVersionRejectsEmptyOversizedOrNonPrintable() async throws {
    for body in [#"{"version":"  "}"#, #"{"version":"\#(String(repeating: "9", count: 65))"}"#,
                 #"{"version":"1\u0007"}"#, #"{"version":"é"}"#, #"{"nope":1}"#] {
        let api = try FestivalAPI(transport: CannedTransport([
            "/api/version": HTTPResult(status: 200, data: Data(body.utf8)),
        ]))
        await #expect(throws: FestivalAPIError.invalidResponse) { try await api.serviceVersion() }
    }
}

@Test func serviceInfoMalformedBodyAndOutageMapToErrors() async throws {
    let bad = try FestivalAPI(transport: CannedTransport([
        "/api/service-info": HTTPResult(status: 200, data: Data("{}".utf8)),
    ]))
    await #expect(throws: FestivalAPIError.invalidResponse) { try await bad.serviceInfo() }
    let down = try FestivalAPI(transport: CannedTransport([
        "/api/service-info": HTTPResult(status: 503, data: Data(), headers: ["Retry-After": "30"]),
    ]))
    await #expect(throws: FestivalAPIError.unavailable(retryAfter: "30")) { try await down.serviceInfo() }
}

// MARK: - Presentation

@Test func idleStatePresentation() throws {
    let info = try decode(idleJSON)
    let (display, memory) = ServiceProgressReducer.reduce(nil, info)
    #expect(display == ServiceProgressDisplay.empty)
    #expect(memory.operationIdentity == nil)
    #expect(ServiceInfoText.processState(info) == .idle)
    #expect(ServiceInfoText.serviceState(info, state: .idle) == "Waiting for the Next Update")
    #expect(ServiceInfoText.phaseLabel(info, display: display) == "Waiting for the next update")
    #expect(ServiceInfoText.subphaseLabel(info, display: display) == nil)
    let utc = TimeZone(identifier: "UTC")!
    let text = ServiceInfoText.lastPublished(info, timeZone: utc, locale: Locale(identifier: "en_US"))
    #expect(text.contains("Jan 1, 2026"))
    #expect(ServiceInfoText.freezeNotice(ServiceInfoSnapshot(info: info, freezeReasonHeader: nil)) == nil)
}

@Test func processAndServiceStatesCoverWorkerAndStatusCombinations() throws {
    #expect(ServiceInfoText.processState(try updating(worker: "stale")) == .stopped)
    #expect(ServiceInfoText.processState(try updating(worker: "starting")) == .updating)
    let stopped = try updating(worker: "offline")
    #expect(ServiceInfoText.serviceState(stopped, state: .stopped) == "Leaderboard Updater Unavailable")
    let failed = try decode("""
    {"lastCompletedUpdate":null,"currentUpdate":{"status":"failed","startedAt":null,
     "phase":"Publishing","subOperation":"failed"},"workerStatus":null,"nextScheduledUpdateAt":null}
    """)
    #expect(ServiceInfoText.processState(failed) == .stopped)
    #expect(ServiceInfoText.serviceState(failed, state: .stopped) == "Last Leaderboard Update Failed")
    let display = ServiceProgressReducer.reduce(nil, failed).display
    #expect(ServiceInfoText.phaseLabel(failed, display: display) == "Publishing")
    #expect(ServiceInfoText.subphaseLabel(failed, display: display) == nil)
    #expect(ServiceInfoText.lastPublished(failed) == ServiceInfoText.publicationUnavailable)
    let odd = try decode("""
    {"lastCompletedUpdate":null,"currentUpdate":{"status":"pausedForReview","startedAt":null,
     "phase":null,"subOperation":null},"workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    #expect(ServiceInfoText.serviceState(odd, state: .idle) == "Paused For Review")
    #expect(ServiceInfoText.phaseLabel(odd, display: .empty) == "Waiting for progress")
    #expect([ServiceProcessState.loading, .updating, .idle, .stopped].map(\.label) == ["Loading", "Updating", "Idle", "Stopped"])
}

@Test func updatingPhaseLabelsProgressAndUnits() throws {
    let info = try updating()
    let display = ServiceProgressReducer.reduce(nil, info).display
    let phase = ServiceInfoText.phaseLabel(info, display: display)
    #expect(phase == "Scraping Leaderboard Scores")
    let sub = ServiceInfoText.subphaseLabel(info, display: display)
    #expect(sub == "Fetching Leaderboards")
    #expect(ServiceInfoText.phaseTitle(phase: phase, subphase: sub)
        == "Scraping Leaderboard Scores · Fetching Leaderboards")
    #expect(ServiceInfoText.phaseTitle(phase: "A", subphase: " a ") == "A")
    #expect(ServiceInfoText.phaseTitle(phase: "A", subphase: nil) == "A")
    // No subphase progress: a legacy subphase id makes the bar indeterminate.
    #expect(display.barProgress?.kind == .indeterminate)
    #expect(ServiceInfoText.progressText(display.barProgress) == ServiceInfoText.progressIndeterminate)
    #expect(display.phasePercent == 40)

    let phaseOnly = try updating(subphase: nil)
    let bar = ServiceProgressReducer.reduce(nil, phaseOnly).display.barProgress
    #expect(bar?.kind == .exact)
    #expect(ServiceInfoText.progressText(bar) == "40.0%")
    #expect(ServiceInfoText.unitsText(bar) == "400 of 1,000 leaderboards completed")
}

@Test func unitsTextVariants() {
    func bar(_ kind: String?, completed: Double?, total: Double?) -> ServiceBarProgress {
        ServiceBarProgress(identity: "i", id: nil, sequence: 0, kind: .exact, percent: 1,
                           unitsKind: kind, unitsCompleted: completed, unitsTotal: total)
    }
    #expect(ServiceInfoText.unitsText(nil) == nil)
    #expect(ServiceInfoText.unitsText(bar("songs", completed: nil, total: 5)) == nil)
    #expect(ServiceInfoText.unitsText(bar("band_types", completed: 2, total: nil)) == "2 band types completed")
    #expect(ServiceInfoText.unitsText(bar(nil, completed: 1234, total: nil)) == "1,234 items completed")
    #expect(ServiceInfoText.unitsText(bar("weirdThings", completed: 1, total: 2))
        == "1 of 2 Weird Things completed")
}

@Test func unknownAndDynamicLabelsFallBack() throws {
    #expect(ServiceInfoText.fallbackLabel("post.someNewPhase_x") == "Post Some New Phase X")
    #expect(ServiceInfoText.fallbackLabel("") == "")
    #expect(ServiceInfoText.dynamicSubphaseLabel("cleanup_rank_history_Solo_Bass") == "Cleaning Bass Rank History")
    #expect(ServiceInfoText.dynamicSubphaseLabel("cleanup_band_rank_history_duos")
        == "Cleaning Duos Rank History")
    #expect(ServiceInfoText.dynamicSubphaseLabel("cleanup_rank_history_") == nil)
    #expect(ServiceInfoText.dynamicSubphaseLabel("other") == nil)

    let info = try updating(phaseId: "post.brand-new", subphase: "cleanup_rank_history_Solo_Drums")
    let display = ServiceProgressReducer.reduce(nil, info).display
    #expect(ServiceInfoText.phaseLabel(info, display: display) == "Scraping")
    #expect(ServiceInfoText.subphaseLabel(info, display: display) == "Cleaning Drums Rank History")
    let described = try decode("""
    {"phasePlan":{"version":"p","phases":[{"id":"x.y","label":"Plan Label"}]},"lastCompletedUpdate":null,
     "currentUpdate":{"status":"updating","startedAt":null,"phase":null,"subOperation":"updating",
      "phaseId":"x.y"},"workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    let describedDisplay = ServiceProgressReducer.reduce(nil, described).display
    #expect(ServiceInfoText.phaseLabel(described, display: describedDisplay) == "Plan Label")
    #expect(ServiceInfoText.subphaseLabel(described, display: describedDisplay) == nil)
    let bare = try decode("""
    {"lastCompletedUpdate":null,"currentUpdate":{"status":"updating","startedAt":null,"phase":null,
     "subOperation":"some_new_step","phaseId":"z"},"workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    let bareDisplay = ServiceProgressReducer.reduce(nil, bare).display
    #expect(ServiceInfoText.phaseLabel(bare, display: bareDisplay) == "Z")
    #expect(ServiceInfoText.subphaseLabel(bare, display: bareDisplay) == "Some New Step")
}

@Test func freezeNoticeUsesHeaderThenBody() throws {
    let info = try decode(idleJSON)
    let scrape = ServiceInfoSnapshot(info: info, freezeReasonHeader: "publish")
    #expect(ServiceInfoText.freezeNotice(scrape)?.contains("new scores") == true)
    let maintenance = ServiceInfoSnapshot(info: info, freezeReasonHeader: "max-score-maintenance:v1:x")
    #expect(ServiceInfoText.freezeNotice(maintenance)?.contains("maintenance") == true)
    let frozenBody = try decode(idleJSON.replacingOccurrences(
        of: #""publicReadsFrozen":false"#, with: #""publicReadsFrozen":true"#
    ).replacingOccurrences(of: #""freezeReason":null"#, with: #""freezeReason":"scrape""#))
    #expect(ServiceInfoText.freezeNotice(ServiceInfoSnapshot(info: frozenBody, freezeReasonHeader: " "))?
        .contains("new scores") == true)
    let frozenNoReason = try decode(idleJSON.replacingOccurrences(
        of: #""publicReadsFrozen":false"#, with: #""publicReadsFrozen":true"#
    ))
    #expect(ServiceInfoText.freezeNotice(ServiceInfoSnapshot(info: frozenNoReason, freezeReasonHeader: nil))?
        .contains("maintenance") == true)
}

@Test func parseDateToleratesDotNetPrecisionAndRejectsGarbage() {
    #expect(ServiceInfoText.parseDate("2026-01-01T12:00:00.1234567Z") != nil)
    #expect(ServiceInfoText.parseDate("2026-01-01T12:00:00.1Z") != nil)
    #expect(ServiceInfoText.parseDate("2026-01-01T12:00:00Z") != nil)
    #expect(ServiceInfoText.parseDate("2026-01-01T12:00:00.5+00:00") != nil)
    #expect(ServiceInfoText.parseDate("yesterday") == nil)
    #expect(ServiceInfoText.parseDate("") == nil)
    #expect(ServiceInfoText.parseDate(nil) == nil)
}

// MARK: - Reducer

@Test func phasePercentIsMonotonicWithinAPhaseAndResetsOnRestart() throws {
    let first = ServiceProgressReducer.reduce(nil, try updating(phasePercent: 50))
    #expect(first.display.phasePercent == 50)
    let lower = ServiceProgressReducer.reduce(
        first.memory, try updating(phasePercent: 30, lastProgressAt: "2026-01-01T12:00:20Z")
    )
    #expect(lower.display.phasePercent == 50)
    let restarted = ServiceProgressReducer.reduce(
        lower.memory, try updating(attempt: 2, phasePercent: 5, lastProgressAt: "2026-01-01T12:00:30Z")
    )
    #expect(restarted.display.restarted)
    #expect(restarted.display.phasePercent == 5)
    let ordinalBack = ServiceProgressReducer.reduce(
        restarted.memory,
        try updating(phaseId: "post.other", attempt: 2, ordinal: 0, phasePercent: 1,
                     lastProgressAt: "2026-01-01T12:00:40Z")
    )
    #expect(ordinalBack.display.restarted)
    let over = ServiceProgressReducer.reduce(nil, try updating(phasePercent: 180, subphase: nil))
    #expect(over.display.phasePercent == 100)
}

@Test func stalePayloadIsIgnoredWithinTheSameOperation() throws {
    let first = ServiceProgressReducer.reduce(nil, try updating(phasePercent: 50))
    let stale = ServiceProgressReducer.reduce(
        first.memory, try updating(phasePercent: 90, lastProgressAt: "2026-01-01T11:59:00Z")
    )
    #expect(stale.display.stalePayloadIgnored)
    #expect(stale.display.phasePercent == 50)
    #expect(stale.memory.lastProgressTimestamp == first.memory.lastProgressTimestamp)
    // A different scrape is a new operation: never stale.
    let other = ServiceProgressReducer.reduce(
        first.memory, try updating(scrapeId: 10, phasePercent: 10, lastProgressAt: "2026-01-01T11:59:00Z")
    )
    #expect(!other.display.stalePayloadIgnored)
    #expect(other.display.phasePercent == 10)
}

@Test func subphaseBarIsMonotonicAndIgnoresOutOfOrderSequences() throws {
    let a = ServiceProgressReducer.reduce(nil, try updating(subProgress: subProgress(sequence: 2, percent: 30)))
    #expect(a.display.barProgress?.kind == .exact)
    #expect(a.display.barProgress?.percent == 30)
    #expect(ServiceInfoText.unitsText(a.display.barProgress) == "10 of 100 leaderboards completed")
    let lowerPercent = ServiceProgressReducer.reduce(
        a.memory, try updating(subProgress: subProgress(sequence: 3, percent: 20),
                               lastProgressAt: "2026-01-01T12:00:20Z")
    )
    #expect(lowerPercent.display.barProgress?.percent == 30)
    let olderSequence = ServiceProgressReducer.reduce(
        lowerPercent.memory, try updating(subProgress: subProgress(sequence: 1, percent: 90),
                                          lastProgressAt: "2026-01-01T12:00:30Z")
    )
    #expect(olderSequence.display.barProgress?.sequence == 3)
}

@Test func subphaseBarDegradesToIndeterminateOnUntrustedInput() throws {
    let cases: [String] = [
        subProgress(sequence: 1, percent: 30, schema: 2),
        subProgress(id: "other", sequence: 1, percent: 30),
        subProgress(sequence: 1, percent: 30, final: false),
        subProgress(sequence: 1, percent: 30, completed: 200, total: 100),
        subProgress(sequence: 1, percent: 30, kind: "mystery"),
    ]
    for raw in cases {
        let bar = ServiceProgressReducer.reduce(nil, try updating(subProgress: raw)).display.barProgress
        #expect(bar?.kind == .indeterminate)
        #expect(bar?.percent == nil)
        #expect(bar?.unitsCompleted == nil)
    }
    let notApplicable = ServiceProgressReducer.reduce(
        nil, try updating(subProgress: subProgress(sequence: 1, percent: 0, kind: "not_applicable"))
    ).display.barProgress
    #expect(notApplicable?.kind == .notApplicable)
}

@Test func operationIdentityFallsBackThroughIds() throws {
    let noIds = try decode("""
    {"lastCompletedUpdate":null,"currentUpdate":{"status":"updating","startedAt":"t","phase":null,
     "subOperation":null},"activeScrapeId":null,"workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    #expect(ServiceProgressReducer.operationIdentity(noIds) == nil)
    let active = try decode("""
    {"phasePlan":{"version":"v9","phases":[]},"lastCompletedUpdate":null,
     "currentUpdate":{"status":"updating","startedAt":null,"phase":null,"subOperation":null},
     "activeScrapeId":12,"workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    #expect(ServiceProgressReducer.operationIdentity(active) == "12:legacy:v9")
    #expect(ServiceProgressReducer.format(1.5) == "1.5")
}

// MARK: - Registered-band discovery attempts

/// A registered-band discovery body with lookup counts (web commit 66556eaa).
private func discovery(
    attempted: String = "1310", unavailable: String = "70", schema: String = "1",
    completed: String = "1240", total: String = "5000", attempt: Int = 1,
    phaseId: String = "post.registered_player_band_discovery",
    lastProgressAt: String = "2026-01-01T12:00:10Z"
) throws -> ServiceInfo {
    try decode("""
    {"contractVersion":2,"lastCompletedUpdate":null,
     "currentUpdate":{"status":"updating","scrapeId":9,"startedAt":"2026-01-01T12:00:00Z",
      "phase":"Post","subOperation":null,"operationId":"op","phaseId":"\(phaseId)",
      "subphaseId":null,"phaseOrdinal":5,"phaseAttempt":\(attempt),"unitsKind":"accounts",
      "unitsCompleted":\(completed),"unitsTotal":\(total),"unitsTotalFinal":true,"phasePercent":24.8,
      "attemptProgress":{"schemaVersion":\(schema),"attemptedThisPass":\(attempted),
        "retryableUnavailableThisPass":\(unavailable)},
      "lastProgressAt":"\(lastProgressAt)"},
     "workerStatus":{"workerKey":"w","status":"online"},"nextScheduledUpdateAt":null}
    """)
}

@Test func discoveryAttemptTextMatchesWebCopyWithAndWithoutTotal() throws {
    let display = ServiceProgressReducer.reduce(nil, try discovery()).display
    #expect(display.attemptProgress == ServiceAttemptProgress(attemptedThisPass: 1310, retryableUnavailableThisPass: 70))
    #expect(display.unitsCompleted == 1240)
    #expect(display.unitsTotal == 5000)
    #expect(ServiceInfoText.discoveryAttemptText(display)
        == "1,310 attempted this pass · 70 temporarily unavailable · 1,240 of 5,000 completed")
    let noTotal = ServiceProgressReducer.reduce(nil, try discovery(completed: "null", total: "null")).display
    #expect(ServiceInfoText.discoveryAttemptText(noTotal)
        == "1,310 attempted this pass · 70 temporarily unavailable · 0 completed")
}

@Test func discoveryAttemptTextOnlyForTheDiscoveryPhase() throws {
    let other = ServiceProgressReducer.reduce(nil, try discovery(phaseId: "post.other")).display
    #expect(other.attemptProgress != nil)
    #expect(ServiceInfoText.discoveryAttemptText(other) == nil)
    let missing = ServiceProgressReducer.reduce(nil, try updating(phaseId: "post.registered_player_band_discovery"))
    #expect(missing.display.attemptProgress == nil)
    #expect(ServiceInfoText.discoveryAttemptText(missing.display) == nil)
}

@Test func discoveryAttemptProgressRejectsUntrustedCounts() throws {
    let invalid: [(attempted: String, unavailable: String, schema: String)] = [
        ("10", "1", "2"), ("10", "11", "1"), ("-1", "0", "1"), ("10", "-1", "1"),
        ("10.5", "1", "1"), ("10", "1.5", "1"), ("null", "1", "1"), ("10", "null", "1"),
        ("10", "1", "null"),
    ]
    for value in invalid {
        let display = ServiceProgressReducer.reduce(
            nil, try discovery(attempted: value.attempted, unavailable: value.unavailable, schema: value.schema)
        ).display
        #expect(display.attemptProgress == nil, "\(value)")
        #expect(ServiceInfoText.discoveryAttemptText(display) == nil)
    }
    let zero = ServiceProgressReducer.reduce(nil, try discovery(attempted: "0", unavailable: "0")).display
    #expect(zero.attemptProgress == ServiceAttemptProgress(attemptedThisPass: 0, retryableUnavailableThisPass: 0))
}

@Test func discoveryAttemptProgressIsMonotonicAndResetsOnRestart() throws {
    let first = ServiceProgressReducer.reduce(nil, try discovery(attempted: "100", unavailable: "10"))
    let lower = ServiceProgressReducer.reduce(
        first.memory, try discovery(attempted: "90", unavailable: "5", lastProgressAt: "2026-01-01T12:00:20Z")
    )
    #expect(lower.display.attemptProgress == ServiceAttemptProgress(attemptedThisPass: 100, retryableUnavailableThisPass: 10))
    let restarted = ServiceProgressReducer.reduce(
        lower.memory,
        try discovery(attempted: "3", unavailable: "1", attempt: 2, lastProgressAt: "2026-01-01T12:00:30Z")
    )
    #expect(restarted.display.restarted)
    #expect(restarted.display.attemptProgress == ServiceAttemptProgress(attemptedThisPass: 3, retryableUnavailableThisPass: 1))
    let hidden = ServiceProgressReducer.reduce(
        restarted.memory,
        try discovery(attempted: "1", unavailable: "2", attempt: 2, lastProgressAt: "2026-01-01T12:00:40Z")
    )
    #expect(hidden.display.attemptProgress == nil)
}
