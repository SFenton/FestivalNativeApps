import Foundation
#if os(macOS)
import AppKit
#endif
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - What's New gate

@Test func whatsNewDebugModeResolvesFromEnvironment() {
    #expect(WhatsNewDebugMode.resolve(environment: [:]) == .off)
    #expect(WhatsNewDebugMode.resolve(environment: ["FST_DEBUG_WHATS_NEW": "on"]) == .normal)
    #expect(WhatsNewDebugMode.resolve(environment: ["FST_DEBUG_WHATS_NEW": "fresh"]) == .fresh)
    #expect(WhatsNewDebugMode.resolve(environment: ["FST_DEBUG_WHATS_NEW": "force"]) == .force)
    #expect(WhatsNewDebugMode.resolve(environment: ["FST_DEBUG_WHATS_NEW": "bogus"]) == .off)
}

@Test func whatsNewPendingFollowsModeAndSeenState() {
    #expect(!WhatsNewGate.isPending(mode: .off, hasUnseenChangelog: true))
    #expect(WhatsNewGate.isPending(mode: .force, hasUnseenChangelog: false))
    #expect(WhatsNewGate.isPending(mode: .normal, hasUnseenChangelog: true))
    #expect(!WhatsNewGate.isPending(mode: .normal, hasUnseenChangelog: false))
    #expect(WhatsNewGate.isPending(mode: .fresh, hasUnseenChangelog: true))
}

@Test func whatsNewVersionAndTitle() {
    #expect(WhatsNewGate.appVersion(["CFBundleShortVersionString": "2.1"]) == "2.1")
    #expect(WhatsNewGate.appVersion(nil) == "")
    #expect(WhatsNewSheet.title(version: "2.1") == "What's New · 2.1")
    #expect(WhatsNewSheet.title(version: "") == "What's New")
}

/// The What's New sheet shares the first-run "one sheet at a time" slot.
@MainActor
@Test func whatsNewSlotExcludesFirstRunCarousels() {
    let center = FirstRunCenter(debugMode: .normal)
    #expect(center.claim("songs"))
    #expect(!center.claim(WhatsNewGate.slotKey))
    center.release("songs")
    #expect(center.claim(WhatsNewGate.slotKey))
    #expect(!center.claim("songs"))
    center.release(WhatsNewGate.slotKey)
    #expect(center.activeKey == nil)
}

// MARK: - First Run Guides order

@MainActor
@Test func firstRunGuidesFollowWebOrderAndLabels() {
    #expect(FirstRunSettingsSection.settingsOrder.map(FirstRunSettingsSection.rowLabel) == [
        "Songs", "Song Info", "Statistics", "Suggestions", "Score History",
        "Leaderboards", "Compete", "Rivals", "Item Shop",
    ])
    #expect(Set(FirstRunSettingsSection.settingsOrder) == Set(FirstRunPageKey.allCases))
}

// MARK: - Service Info rows

private func info(_ json: String) throws -> ServiceInfo {
    try JSONDecoder().decode(ServiceInfo.self, from: Data(json.utf8))
}

private let utc = TimeZone(identifier: "UTC")!
private let enUS = Locale(identifier: "en_US")

func serviceInfoUpdatingSnapshot() throws -> SettingsServiceInfoModel.Phase {
    let body = try info("""
    {"contractVersion":2,"lastCompletedUpdate":{"publishedAt":"2026-01-01T12:00:00Z"},
     "currentUpdate":{"status":"updating","scrapeId":3,"startedAt":"2026-01-01T13:00:00Z",
      "phase":"Scraping","subOperation":"fetching_leaderboards","operationId":"op",
      "phaseId":"scrape.leaderboards","subphaseId":"fetching_leaderboards",
      "subphaseProgress":{"schemaVersion":1,"id":"fetching_leaderboards","epoch":0,"sequence":4,
        "kind":"exact","unitsKind":"leaderboards","unitsCompleted":420,"unitsTotal":1000,
        "unitsTotalFinal":true,"percent":42}},
     "workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    let display = ServiceProgressReducer.reduce(nil, body).display
    return .loaded(ServiceInfoSnapshot(info: body, freezeReasonHeader: "scrape"), display)
}

func serviceInfoIdleSnapshot() throws -> SettingsServiceInfoModel.Phase {
    let body = try info("""
    {"lastCompletedUpdate":{"publishedAt":"2026-01-01T12:00:00Z"},
     "currentUpdate":{"status":"idle","startedAt":null,"phase":null,"subOperation":null},
     "workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    return .loaded(ServiceInfoSnapshot(info: body, freezeReasonHeader: nil), .empty)
}

@Test func serviceInfoRowsForLoadingAndFailure() {
    let loading = ServiceInfoRows.make(.loading)
    #expect(loading.processState == .loading)
    #expect(loading.phaseTitle == nil)
    #expect(loading.barPercent == nil)
    let failed = ServiceInfoRows.make(.failed)
    #expect(failed.processState == .stopped)
    #expect(failed.stateDescription == "Failed to load")
    #expect(failed.lastPublished == "Unavailable")
}

@Test func serviceInfoRowsForIdle() throws {
    let rows = ServiceInfoRows.make(try serviceInfoIdleSnapshot(), timeZone: utc, locale: enUS)
    #expect(rows.processState == .idle)
    #expect(rows.stateDescription == "Waiting for the Next Update")
    #expect(rows.phaseTitle == nil)
    #expect(rows.barPercent == nil)
    #expect(rows.progressText == nil)
    #expect(rows.freezeNotice == nil)
    #expect(rows.lastPublished.contains("Jan 1, 2026"))
}

@Test func serviceInfoRowsForUpdatingWithExactProgress() throws {
    let rows = ServiceInfoRows.make(try serviceInfoUpdatingSnapshot(), timeZone: utc, locale: enUS)
    #expect(rows.processState == .updating)
    #expect(rows.stateDescription == "Scraping Leaderboard Scores")
    #expect(rows.phaseTitle == "Scraping Leaderboard Scores · Fetching Leaderboards")
    #expect(rows.barPercent == .some(42))
    #expect(rows.progressText == "42.0%")
    #expect(rows.unitsText == "420 of 1,000 leaderboards completed")
    #expect(rows.freezeNotice?.contains("new scores") == true)
}

@Test func serviceInfoRowsForIndeterminateAndNotApplicableBars() throws {
    let indeterminate = try info("""
    {"lastCompletedUpdate":null,"currentUpdate":{"status":"updating","startedAt":null,"phase":"Scraping",
     "subOperation":null,"phaseId":"scrape.leaderboards","subphaseId":"deep_scraping"},
     "workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    let rows = ServiceInfoRows.make(.loaded(
        ServiceInfoSnapshot(info: indeterminate, freezeReasonHeader: nil),
        ServiceProgressReducer.reduce(nil, indeterminate).display
    ))
    #expect(rows.barPercent == .some(nil))
    #expect(rows.progressText == ServiceInfoText.progressIndeterminate)
    #expect(rows.lastPublished == ServiceInfoText.publicationUnavailable)

    let notApplicable = try info("""
    {"lastCompletedUpdate":null,"currentUpdate":{"status":"updating","startedAt":null,"phase":null,
     "subOperation":null,"phaseId":"publication.commit","subphaseId":"x",
     "subphaseProgress":{"schemaVersion":1,"id":"x","epoch":0,"sequence":1,"kind":"not_applicable",
       "unitsTotalFinal":false}},"workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    let naRows = ServiceInfoRows.make(.loaded(
        ServiceInfoSnapshot(info: notApplicable, freezeReasonHeader: nil),
        ServiceProgressReducer.reduce(nil, notApplicable).display
    ))
    #expect(naRows.phaseTitle?.hasPrefix("Publishing Leaderboard Update") == true)
    #expect(naRows.barPercent == nil)
}

// MARK: - Service Info model

private struct Boom: Error {}

@MainActor
@Test func serviceInfoModelAppliesReadsAndFailures() throws {
    let model = SettingsServiceInfoModel()
    #expect(model.phase == .loading)
    guard case let .loaded(snapshot, _) = try serviceInfoUpdatingSnapshot() else {
        Issue.record("fixture")
        return
    }
    model.apply(.success(snapshot))
    guard case let .loaded(_, display) = model.phase else {
        Issue.record("expected loaded")
        return
    }
    #expect(display.barProgress?.percent == 42)
    model.apply(.failure(Boom()))
    #expect(model.phase == .failed)
}

@MainActor
@Test func serviceInfoModelPollStopsOnCancellation() async throws {
    let model = SettingsServiceInfoModel()
    guard case let .loaded(snapshot, _) = try serviceInfoIdleSnapshot() else { return }
    let task = Task { await model.poll { snapshot } }
    for _ in 0..<50 where model.phase == .loading {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.phase != .loading)
    task.cancel()
    await task.value

    let failing = SettingsServiceInfoModel()
    let failTask = Task { await failing.poll { throw Boom() } }
    for _ in 0..<50 where failing.phase == .loading {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(failing.phase == .failed)
    failTask.cancel()
    await failTask.value

    let cancelled = SettingsServiceInfoModel()
    await cancelled.poll { throw CancellationError() }
    #expect(cancelled.phase == .loading)
    await cancelled.poll { throw URLError(.cancelled) }
    #expect(cancelled.phase == .loading)
}

// MARK: - Hosted renders

#if os(macOS)
@MainActor
@Test func whatsNewSheetRendersTitleCaseSectionsAndDismiss() async throws {
    let size = CGSize(width: 402, height: 874)
    let host = nativeHostedView(
        WhatsNewSheet(version: "1.0", entries: Changelog.displayEntries()) {}
            .frame(width: size.width, height: size.height)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["Item Shop", "Song Details", "Dismiss"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    _ = try nativeHostedPNG(image, filename: "whats-new.png", environment: "FST_WHATS_NEW_RENDER_OUT")
    assertRendersContent(host, image: image, containing: expected)
}

@MainActor
@Test func serviceInfoSectionRendersUpdatingState() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 402, height: 520)
    let host = nativeHostedView(
        SettingsServiceInfoSection(
            session: session, isVisible: false, initialPhase: try serviceInfoUpdatingSnapshot()
        ) { Text("Check Publication") }
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["Service Info", "Leaderboard Service State", "Last Successful Publication"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    _ = try nativeHostedPNG(image, filename: "service-info-updating.png", environment: "FST_SETTINGS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: expected)
}
#endif
