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

private func launcherDefaults() -> UserDefaults {
    let name = "whats-new-launcher-\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
}

@MainActor
@Test func whatsNewLauncherPresentsOnceAndPersistsDismissal() {
    let store = ChangelogSeenStore(defaults: launcherDefaults())
    let center = FirstRunCenter(debugMode: .normal)
    let launcher = WhatsNewLauncher(store: store, environment: ["FST_DEBUG_WHATS_NEW": "on"], changelogHash: "abc")
    #expect(launcher.resolveIfNeeded())
    // A carousel holds the slot: wait.
    #expect(center.claim("songs"))
    #expect(!launcher.claim(in: center))
    #expect(launcher.pending)
    center.release("songs")
    #expect(launcher.claim(in: center))
    #expect(!launcher.pending)
    #expect(!launcher.claim(in: center))
    launcher.finish(in: center, version: "3.0")
    #expect(center.activeKey == nil)
    #expect(store.load()?.version == "3.0")
    // Next launch with the real gate: nothing owed.
    let next = WhatsNewLauncher(store: store, environment: ["FST_DEBUG_WHATS_NEW": "on"], changelogHash: "abc")
    #expect(!next.resolveIfNeeded())
    // A newly released version changes the hash: owed again. An empty changelog never is.
    #expect(WhatsNewLauncher(store: store, environment: ["FST_DEBUG_WHATS_NEW": "on"], changelogHash: "def")
        .resolveIfNeeded())
    #expect(!WhatsNewLauncher(
        store: ChangelogSeenStore(defaults: launcherDefaults()),
        environment: ["FST_DEBUG_WHATS_NEW": "on"],
        changelogHash: Changelog.emptyHash
    ).resolveIfNeeded())
}

@MainActor
@Test func whatsNewLauncherFreshResetsOnceAndOffNeverPresents() {
    let store = ChangelogSeenStore(defaults: launcherDefaults())
    store.markSeen(version: "1", hash: "abc")
    let fresh = WhatsNewLauncher(store: store, environment: ["FST_DEBUG_WHATS_NEW": "fresh"], changelogHash: "abc")
    #expect(fresh.resolveIfNeeded())
    #expect(fresh.resolved)
    store.markSeen(version: "1")
    #expect(fresh.resolveIfNeeded())  // resolved once; stays pending until claimed
    let off = WhatsNewLauncher(store: ChangelogSeenStore(defaults: launcherDefaults()), environment: [:])
    #expect(!off.resolveIfNeeded())
    #expect(!off.claim(in: FirstRunCenter(debugMode: .normal)))
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
    #expect(loading.lastPublished == nil)
    let failed = ServiceInfoRows.make(.failed)
    #expect(failed.processState == .stopped)
    #expect(failed.stateDescription == "Failed to load")
    #expect(failed.lastPublished == nil)
}

@Test func serviceInfoRowsForIdle() throws {
    let rows = ServiceInfoRows.make(try serviceInfoIdleSnapshot(), timeZone: utc, locale: enUS)
    #expect(rows.processState == .idle)
    #expect(rows.stateDescription == "Waiting for the Next Update")
    #expect(rows.phaseTitle == nil)
    #expect(rows.barPercent == nil)
    #expect(rows.progressText == nil)
    #expect(rows.freezeNotice == nil)
    #expect(rows.lastPublished?.contains("Jan 1, 2026") == true)
    #expect(rows.attemptText == nil)
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
    #expect(rows.attemptText == nil)
}

func serviceInfoDiscoverySnapshot() throws -> SettingsServiceInfoModel.Phase {
    let body = try info("""
    {"contractVersion":2,"lastCompletedUpdate":{"publishedAt":"2026-01-01T12:00:00Z"},
     "currentUpdate":{"status":"updating","scrapeId":3,"startedAt":"2026-01-01T13:00:00Z",
      "phase":"Post","subOperation":null,"operationId":"op",
      "phaseId":"post.registered_player_band_discovery","subphaseId":null,"phaseOrdinal":5,
      "phaseAttempt":1,"unitsKind":"accounts","unitsCompleted":1240,"unitsTotal":5000,
      "unitsTotalFinal":true,"phasePercent":24.8,
      "attemptProgress":{"schemaVersion":1,"attemptedThisPass":1310,"retryableUnavailableThisPass":70}},
     "workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """)
    let display = ServiceProgressReducer.reduce(nil, body).display
    return .loaded(ServiceInfoSnapshot(info: body, freezeReasonHeader: nil), display)
}

@Test func serviceInfoRowsShowDiscoveryAttemptsUnderTheBar() throws {
    let rows = ServiceInfoRows.make(try serviceInfoDiscoverySnapshot(), timeZone: utc, locale: enUS)
    #expect(rows.phaseTitle == "Registered Player Band Discovery")
    #expect(rows.barPercent == .some(24.8))
    #expect(rows.attemptText
        == "1,310 attempted this pass · 70 temporarily unavailable · 1,240 of 5,000 completed")
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

/// Only an unknown total sweeps, and system or in-app Reduce Motion (passed combined), an
/// inactive scene or hidden window, or the UI-test still override holds the track empty
/// (issue #399, load-transition R6, #556).
@Test func serviceProgressBarSweepsOnlyForUnknownTotalsWithMotion() {
    #expect(ServiceProgressBar.sweeps(percent: nil, reduceMotion: false, sceneActive: true, still: false))
    #expect(!ServiceProgressBar.sweeps(percent: nil, reduceMotion: true, sceneActive: true, still: false))
    #expect(!ServiceProgressBar.sweeps(percent: nil, reduceMotion: false, sceneActive: false, still: false))
    #expect(!ServiceProgressBar.sweeps(percent: nil, reduceMotion: false, sceneActive: true, still: true))
    #expect(!ServiceProgressBar.sweeps(percent: 42, reduceMotion: false, sceneActive: true, still: false))
}

/// The indeterminate segment plays the web keyframes (`translateX(-110%) → 165% → 300%` of
/// a 38 % segment, `ease-in-out` per half, 1.25 s, infinite) on the render server, phased on
/// the shared wall clock so re-adding it after a re-host resumes mid-sweep (issue #556).
@Test func serviceProgressSweepAnimationFollowsTheWebKeyframes() throws {
    let width: CGFloat = 300
    let segment = width * 0.38
    let date = Date(timeIntervalSinceReferenceDate: 1000.5)
    let animation = ServiceProgressSweep.animation(trackWidth: width, mediaTime: 50, date: date)
    #expect(animation.keyPath == "transform.translation.x")
    let values = try #require(animation.values as? [NSNumber]).map(\.doubleValue)
    #expect(values.count == 3)
    for (value, expected) in zip(values, [-1.1 * segment, 1.65 * segment, 3.0 * segment]) {
        #expect(abs(value - Double(expected)) < 1e-9)
    }
    #expect(values[0] + Double(segment) <= 0, "starts fully left of the track")
    #expect(values[2] >= Double(width), "ends fully right of the track")
    #expect(animation.keyTimes?.map(\.doubleValue) == [0, 0.5, 1])
    let timing = try #require(animation.timingFunctions)
    #expect(timing.count == 2)
    for function in timing {
        var c1: [Float] = [0, 0], c2: [Float] = [0, 0]
        function.getControlPoint(at: 1, values: &c1)
        function.getControlPoint(at: 2, values: &c2)
        #expect(c1 == [0.42, 0] && c2 == [0.58, 1], "not CSS ease-in-out: \(c1) \(c2)")
    }
    #expect(animation.duration == 1.25)
    #expect(animation.repeatCount == .infinity)
    #expect(!animation.isRemovedOnCompletion)
    // 1000.5 s is 0.5 s into a 1.25 s cycle (800 whole cycles), so it began 0.5 s ago.
    #expect(abs(animation.beginTime - 49.5) < 1e-9)
    #expect(ServiceProgressSweep.restingOffset(trackWidth: width) == -1.1 * segment)
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
/// Two versions, as a release build's generated `WhatsNew.json` would list them.
private let sampleWhatsNewEntries = [
    ChangelogEntry(version: "2610.01.02", released: false, heading: "Version 2610.01.02", sections: [
        ChangelogSection(title: "Songs", items: ["Rows load faster."]),
        ChangelogSection(title: "Rivals", items: ["Rivals refresh correctly."]),
        ChangelogSection(title: "Other", items: ["Fixed a crash."]),
    ]),
    ChangelogEntry(version: "2610.01.01", heading: "Version 2610.01.01", sections: [
        ChangelogSection(title: "", items: ["The first release of Festival Score Tracker for iPhone."]),
    ]),
]

@MainActor
@Test func whatsNewSheetRendersVersionAndCategoryHeadingsAndDismiss() async throws {
    let size = CGSize(width: 402, height: 874)
    let host = nativeHostedView(
        WhatsNewSheet(version: "2610.01.02", entries: Changelog.displayEntries(sampleWhatsNewEntries)) {}
            .frame(width: size.width, height: size.height)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["Version 2610.01.02", "Songs", "Rivals", "Other", "Version 2610.01.01", "Dismiss"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    _ = try nativeHostedPNG(image, filename: "whats-new.png", environment: "FST_WHATS_NEW_RENDER_OUT")
    assertRendersContent(host, image: image, containing: expected)
}

/// `/duo` M1: on the iPhone Duo vertical bar the sheet keeps only its Close (in the
/// sheet's side bar); the custom Dismiss bar is dropped. Rendered at the folded size.
@MainActor
@Test func whatsNewSheetDropsDismissBesideTheVerticalBar() async throws {
    let size = CGSize(width: 466, height: 678)
    let folded = DeviceLayout.resolve(LayoutSignals(
        size: size, widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    ))
    #expect(!WhatsNewSheet.showsDismissBar(folded))
    #expect(WhatsNewSheet.showsDismissBar(.standardPhone))
    let host = nativeHostedView(
        WhatsNewSheet(version: "2610.01.02", entries: Changelog.displayEntries(sampleWhatsNewEntries)) {}
            .environment(\.deviceLayout, folded)
            .frame(width: size.width, height: size.height)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["Version 2610.01.02", "Songs"]
    let image = try await nativeHostedSettle(host, untilText: expected, excluding: ["Dismiss"])
    _ = try nativeHostedPNG(image, filename: "duo-m1-whats-new-folded.png", environment: "FST_WHATS_NEW_RENDER_OUT")
    assertRendersContent(host, image: image, containing: expected, notContaining: ["Dismiss"])
}

@MainActor
@Test func whatsNewSheetShowsNoNotesWhileTheChannelIsPending() async throws {
    let size = CGSize(width: 402, height: 600)
    let host = nativeHostedView(
        WhatsNewSheet(version: "2610.01.02", entries: nil) {}
            .frame(width: size.width, height: size.height)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Dismiss"])
    // Only the title, a spinner and Dismiss: a deliberately sparse page.
    assertRendersContent(
        host, image: image, minimumInkFraction: 0.0005, containing: ["Dismiss"], notContaining: ["Version 2610.01.02"]
    )
}

@MainActor
@Test func serviceInfoSectionRendersUpdatingState() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 402, height: 520)
    let host = nativeHostedView(
        SettingsServiceInfoSection(
            session: session, isVisible: false, initialPhase: try serviceInfoUpdatingSnapshot()
        )
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

@MainActor
@Test func serviceInfoSectionRendersDiscoveryAttemptsAndLoadingStateOnly() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 402, height: 520)
    let host = nativeHostedView(
        SettingsServiceInfoSection(
            session: session, isVisible: false, initialPhase: try serviceInfoDiscoverySnapshot()
        )
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    // The attempt line is the phase element's value (`SettingsServiceInfoAccessibilityTests`
    // pins it); `serviceInfoRowsShowDiscoveryAttemptsUnderTheBar` pins its text.
    let expected = ["Registered Player Band Discovery", "Last Successful Publication"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    _ = try nativeHostedPNG(image, filename: "service-info-discovery.png", environment: "FST_SETTINGS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: expected)

    let loadingHost = nativeHostedView(
        SettingsServiceInfoSection(session: session, isVisible: false, initialPhase: .loading)
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let loadingWindow = nativeHostedWindow(loadingHost, size: size)
    defer { loadingWindow.orderOut(nil) }
    let loadingExpected = ["Leaderboard Service State", "Loading"]
    let loadingImage = try await nativeHostedSettle(
        loadingHost, untilText: loadingExpected, excluding: ["Last Successful Publication"]
    )
    assertRendersContent(loadingHost, image: loadingImage, containing: loadingExpected)
    #expect(!nativeHostedAccessibility(loadingHost).contains("Last Successful Publication"))
}
@MainActor
@Test func settingsChoiceRowRendersInlineOptions() async throws {
    let size = CGSize(width: 402, height: 300)
    var mode = PathDisplayMode.text
    let binding = Binding(get: { mode }, set: { mode = $0 })
    let host = nativeHostedView(
        VStack {
            SettingsChoiceRow(
                title: "CHOpt Path Default View",
                detail: "Choose whether CHOpt paths open as an image or text table by default.",
                options: PathDisplayMode.allCases, label: \.label, selection: binding,
                identifier: "fst.settings.path-default-view", initiallyExpanded: true
            )
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.cardBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let expected = ["CHOpt Path Default View", "Image", "Text"]
    let image = try await nativeHostedSettle(host, untilText: expected)
    assertRendersContent(host, image: image, containing: expected)
}

@Test func settingsChoiceAccessibilityValueSpeaksSelectionAndState() {
    #expect(SettingsChoiceAccessibility.value(selected: "Image", isExpanded: false) == "Image, Collapsed")
    #expect(SettingsChoiceAccessibility.value(selected: "Text", isExpanded: true) == "Text, Expanded")
}

@MainActor
@Test func firstRunStarsUseWebArtwork() async throws {
    #expect(FirstRunStar.assetName(gold: true) == "star_gold")
    #expect(FirstRunStar.assetName(gold: false) == "star_white")
    let size = CGSize(width: 200, height: 60)
    let host = nativeHostedView(
        HStack { FirstRunStarRow(count: 6); FirstRunStarRow(count: 3); FirstRunStarRow(count: 0) }
            .frame(width: size.width, height: size.height)
            .background(BrandTokens.cardBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    #expect(image.width > 0)
}
@MainActor
@Test func whatsNewModifierPresentsFromInjectedLauncher() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let launcher = WhatsNewLauncher(
        store: ChangelogSeenStore(defaults: launcherDefaults()),
        environment: ["FST_DEBUG_WHATS_NEW": "force"]
    )
    let size = CGSize(width: 300, height: 200)
    let host = nativeHostedView(
        Text("Root").modifier(WhatsNewLaunchModifier(session: session, launcher: launcher))
            .frame(width: size.width, height: size.height),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    for _ in 0..<40 where launcher.pending || !launcher.resolved {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(launcher.resolved)
    #expect(!launcher.pending)
    #expect(session.firstRunCenter.activeKey == WhatsNewGate.slotKey)

    // The app-root form uses the shared launcher, which stays off under the test environment.
    let rootHost = nativeHostedView(Text("Root").whatsNew(session: session), size: size)
    let rootWindow = nativeHostedWindow(rootHost, size: size)
    defer { rootWindow.orderOut(nil) }
    rootHost.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    #expect(WhatsNewLauncher.shared.pending == false)
}
#endif
