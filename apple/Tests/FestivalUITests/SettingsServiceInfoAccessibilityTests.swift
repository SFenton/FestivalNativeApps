#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Settings → Service Info accessibility (issue #399, for #22's Service Info polish)
//
// #22 added the registered-band discovery attempt line under the progress bar, showed only
// the state row until the first successful read, made the phase title semibold and stacked
// the state under its title at large text. These tests pin what VoiceOver and large text get
// from that card: each row is one static-text element (title as the label, the rest as the
// value), the attempt line is spoken with the phase row and never read on its own, the bar
// and spinner are hidden, the rows read in visual order (state → phase → last publication),
// loading and failed reads expose only the state row, and the phase title and attempt line
// wrap in a narrow column instead of truncating. macOS hosting does not scale Dynamic Type,
// so large text is reproduced with a narrow column (as in `SettingsVersionRowAccessibilityTests`).

private let stateID = "fst.settings.service-info.state"
private let phaseID = "fst.settings.service-info.phase"
private let lastPublishedID = "fst.settings.service-info.last-published"
private let discoveryAttempts = "1,310 attempted this pass · 70 temporarily unavailable · 1,240 of 5,000 completed"

/// Host the Service Info card at `width` in an offscreen window and return its settled tree
/// plus the roles VoiceOver can reach.
@MainActor
private func serviceInfoTree(
    _ phase: SettingsServiceInfoModel.Phase, width: CGFloat = 402, height: CGFloat = 520,
    until texts: [String], excluding: [String] = [], name: String
) async throws -> (nodes: [MacAXNode], reachable: [String]) {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: width, height: height)
    let host = nativeHostedView(
        SettingsServiceInfoSection(session: session, isVisible: false, initialPhase: phase)
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: texts, excluding: excluding)
    let nodes = macAccessibilityTree(host)
    macAccessibilityDump(nodes, name: name)
    return (nodes, reachableRoles(host))
}

/// Elements VoiceOver lands on, in reading order.
private func spokenElements(_ nodes: [MacAXNode]) -> [MacAXNode] {
    nodes.filter { $0.isElement && !$0.spokenName.isEmpty }
}

/// Roles VoiceOver can reach through `accessibilityChildren` alone. `macAccessibilityTree`
/// also walks AppKit subviews, which lists the spinner's backing `NSProgressIndicator` even
/// though the hosting view's accessibility children never include it.
@MainActor
private func reachableRoles(_ host: NSView) -> [String] {
    var roles: [String] = []
    func walk(_ node: Any, depth: Int) {
        guard depth < 40, let object = node as? NSObject else { return }
        roles.append(nativeHostedAccessibilityString(object, "accessibilityRole"))
        let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
            ? object.value(forKey: "accessibilityChildren") as? [Any] : nil
        for child in children ?? [] { walk(child, depth: depth + 1) }
    }
    walk(host, depth: 0)
    return roles
}

/// Decorative progress views: the bar and the "Updating"/"Loading" spinner.
private let progressRoles: Set<String> = ["AXProgressIndicator", "AXBusyIndicator", "AXLevelIndicator", "AXImage"]

/// Fitted size of `view` when offered `width`.
@MainActor
private func fittedSize<Content: View>(_ view: Content, width: CGFloat) -> CGSize {
    NSHostingController(rootView: view.preferredColorScheme(.dark))
        .sizeThatFits(in: CGSize(width: width, height: 10_000))
}

// MARK: - Labels, roles and values

@MainActor
@Test func serviceInfoDiscoveryRowsAreStaticTextsWithTheAttemptLineSpoken() async throws {
    let phase = try serviceInfoDiscoverySnapshot()
    let rows = ServiceInfoRows.make(phase)
    let (nodes, reachable) = try await serviceInfoTree(
        phase, until: ["Leaderboard Service State", "Registered Player Band Discovery", "Last Successful Publication"],
        name: "service-info-discovery"
    )

    let state = try #require(nodes.first { $0.identifier == stateID })
    #expect(state.isElement && state.role == "AXStaticText")
    #expect(state.label == "Leaderboard Service State, Registered Player Band Discovery")
    #expect(state.value == ServiceProcessState.updating.label)

    // The phase row: its title is the label; percent, units and the #22 attempt line are its value.
    let phaseRow = try #require(nodes.first { $0.identifier == phaseID })
    #expect(phaseRow.isElement && phaseRow.role == "AXStaticText", "\(phaseRow)")
    #expect(phaseRow.label == "Registered Player Band Discovery")
    let progress = try #require(rows.progressText)
    #expect(phaseRow.value.hasPrefix(progress), "\(phaseRow.value)")
    if let units = rows.unitsText { #expect(phaseRow.value.contains(units), "\(phaseRow.value)") }
    #expect(phaseRow.value.hasSuffix(discoveryAttempts), "\(phaseRow.value)")

    let published = try #require(nodes.first { $0.identifier == lastPublishedID })
    #expect(published.isElement && published.role == "AXStaticText", "\(published)")
    let date = try #require(rows.lastPublished)
    // `.combine` of the title and date: macOS puts the joined text in the static text's value,
    // iOS in its label; either way it reads title then date, once.
    #expect(published.spokenName == "\(ServiceInfoText.lastPublishedTitle), \(date)", "\(published)")

    // Nothing inside a row is read again on its own: not the titles, the attempt line, the
    // bar or the spinner.
    let spoken = spokenElements(nodes)
    for text in ["Leaderboard Service State", "Registered Player Band Discovery", "Last Successful Publication"] {
        #expect(spoken.filter { $0.spokenName.hasPrefix(text) }.count == 1, "\(text) read twice: \(spoken)")
    }
    #expect(!spoken.contains { $0.identifier != phaseID && ($0.spokenName + $0.value).contains("attempted this pass") })
    #expect(progressRoles.isDisjoint(with: reachable), "\(reachable)")
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
}

@MainActor
@Test func serviceInfoUpdatingPhaseRowSpeaksPercentAndUnits() async throws {
    let phase = try serviceInfoUpdatingSnapshot()
    let (nodes, _) = try await serviceInfoTree(
        phase, until: ["Scraping Leaderboard Scores · Fetching Leaderboards"], name: "service-info-updating"
    )
    let phaseRow = try #require(nodes.first { $0.identifier == phaseID })
    #expect(phaseRow.role == "AXStaticText")
    #expect(phaseRow.label == "Scraping Leaderboard Scores · Fetching Leaderboards")
    #expect(phaseRow.value == "42.0%. 420 of 1,000 leaderboards completed")
    #expect(!phaseRow.value.contains("attempted this pass"))
}

// MARK: - Loading and failed: only the state row

@MainActor
@Test(arguments: [true, false])
func serviceInfoBeforeTheFirstReadExposesOnlyTheStateRow(loading: Bool) async throws {
    let phase: SettingsServiceInfoModel.Phase = loading ? .loading : .failed
    let description = loading ? "Loading" : "Failed to load"
    let state: ServiceProcessState = loading ? .loading : .stopped
    let (nodes, reachable) = try await serviceInfoTree(
        phase, until: ["Leaderboard Service State, \(description)"], excluding: ["Last Successful Publication"],
        name: "service-info-\(description.lowercased().replacingOccurrences(of: " ", with: "-"))"
    )
    let row = try #require(nodes.first { $0.identifier == stateID })
    #expect(row.isElement && row.role == "AXStaticText")
    #expect(row.label == "Leaderboard Service State, \(description)")
    #expect(row.value == state.label)
    #expect(!nodes.contains { $0.identifier == phaseID || $0.identifier == lastPublishedID })
    // The loading spinner is decoration: the state is already spoken as the row's value.
    #expect(progressRoles.isDisjoint(with: reachable), "\(reachable)")
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
}

// MARK: - Reading order

@MainActor
@Test func serviceInfoReadsHeadingThenStatePhaseAndPublicationInVisualOrder() async throws {
    let (nodes, _) = try await serviceInfoTree(
        try serviceInfoDiscoverySnapshot(),
        until: ["Leaderboard Service State", "Registered Player Band Discovery", "Last Successful Publication"],
        name: "service-info-order"
    )
    let order = [stateID, phaseID, lastPublishedID]
    #expect(nodes.filter { order.contains($0.identifier) }.map(\.identifier) == order)
    // The section title and its hint come before the rows.
    let spoken = spokenElements(nodes).map(\.spokenName)
    let heading = try #require(spoken.firstIndex(of: ServiceInfoText.title), "\(spoken)")
    let stateIndex = try #require(spokenElements(nodes).firstIndex { $0.identifier == stateID })
    #expect(heading < stateIndex)
}

// MARK: - Text scaling (narrow column)

@MainActor
@Test(arguments: [CGFloat(220), 150])
func serviceInfoPhaseRowWrapsInsteadOfTruncatingInANarrowColumn(_ width: CGFloat) async throws {
    let phase = try serviceInfoDiscoverySnapshot()
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let card = SettingsServiceInfoSection(session: session, isVisible: false, titled: false, initialPhase: phase)
    let narrow = fittedSize(card, width: width)
    let wide = fittedSize(card, width: 402)
    #expect(narrow.width <= width, "card overflows its column: \(narrow)")
    // The attempt line and phase title wrap onto more lines rather than being cut off.
    let attemptOneLine = fittedSize(Text(discoveryAttempts).font(.subheadline), width: 10_000)
    #expect(attemptOneLine.width > width, "fixture must not fit on one line")
    let attemptWrapped = fittedSize(Text(discoveryAttempts).font(.subheadline), width: width - 64)
    #expect(narrow.height - wide.height >= attemptWrapped.height - attemptOneLine.height - 1, "\(narrow) vs \(wide)")

    // Still the same elements with the full spoken text.
    let (nodes, _) = try await serviceInfoTree(
        phase, width: width + 32, height: 1_200,
        until: ["Registered Player Band Discovery"], name: "service-info-narrow-\(Int(width))"
    )
    let phaseRow = try #require(nodes.first { $0.identifier == phaseID })
    #expect(phaseRow.value.hasSuffix(discoveryAttempts))
    let state = try #require(nodes.first { $0.identifier == stateID })
    #expect(state.label == "Leaderboard Service State, Registered Player Band Discovery")
}

// MARK: - Reduce Motion (the indeterminate bar)

/// A scrape subphase with no progress: the bar has no known total (web
/// `settings-progress-indeterminate`).
private func serviceInfoIndeterminateSnapshot() throws -> SettingsServiceInfoModel.Phase {
    let body = try JSONDecoder().decode(ServiceInfo.self, from: Data("""
    {"lastCompletedUpdate":{"publishedAt":"2026-01-01T12:00:00Z"},
     "currentUpdate":{"status":"updating","startedAt":null,"phase":"Scraping",
      "subOperation":null,"phaseId":"scrape.leaderboards","subphaseId":"deep_scraping"},
     "workerStatus":{"status":"online"},"nextScheduledUpdateAt":null}
    """.utf8))
    return .loaded(
        ServiceInfoSnapshot(info: body, freezeReasonHeader: nil),
        ServiceProgressReducer.reduce(nil, body).display
    )
}

/// Pixels of the sweeping segment's fill (`BrandTokens.accentPurple` #7C3AED, antialiased)
/// and of the muted track (`BrandTokens.surfaceMuted` #223047) in a bar capture.
private func barPixels(_ image: CGImage) -> (segment: Int, track: Int) {
    NativeHostedPixels(image).withBytes { bytes in
        var segment = 0, track = 0
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 200 {
            let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
            if b > 170, r > 80, b - g > 100 { segment += 1 }
            if abs(r - 34) < 12, abs(g - 48) < 12, abs(b - 71) < 12 { track += 1 }
        }
        return (segment, track)
    }
}

/// One capture of the bar: segment and track pixels plus the frame's signature.
private typealias BarSample = (segment: Int, track: Int, signature: Int)

/// A bar sampling journey's captures and the phase row VoiceOver reads.
private struct BarJourney {
    var samples: [BarSample] = []
    let phase: MacAXNode
    let reachable: [String]
    /// Whether the render-server sweep was mounted.
    let sweepMounted: Bool
    /// Why the host was too starved for its frames to show motion, or nil when responsive.
    var starved: String?
}

/// Host the card with an indeterminate bar under the given Reduce Motion settings and sample
/// the bar's rect every 50 ms until `done` holds, inside one `NativeHostedEvidenceDeadline`.
/// An expired deadline is recorded (`nativeHostedRecordExpired`: a starved host is an
/// intermittent known issue, a responsive one fails) and returns nil.
@MainActor
private func indeterminateBarJourney(
    system: Bool, app: Bool, name: String, done: ([BarSample], Duration) -> Bool
) async throws -> BarJourney? {
    let suiteName = "fst-service-info-motion-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(app, forKey: "fst.accessibility.reduceMotion")
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 402, height: 400)
    let host = nativeHostedView(
        SettingsServiceInfoSection(session: session, isVisible: false, initialPhase: try serviceInfoIndeterminateSnapshot())
            .environment(\._accessibilityReduceMotion, system)
            .environment(\.scenePhase, .active)
            .defaultAppStorage(storage)
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: [ServiceInfoText.progressIndeterminate])
    let nodes = macAccessibilityTree(host)
    macAccessibilityDump(nodes, name: name)
    var journey = BarJourney(
        phase: try #require(nodes.first { $0.identifier == phaseID }), reachable: reachableRoles(host),
        sweepMounted: !sweepViews(in: host).isEmpty
    )
    // The bar is the phase row's last 10 pt (no attempt line in this phase).
    let row = try #require(nativeHostedAccessibilityFrame(phaseID, in: host))
    let bar = CGRect(x: row.minX, y: row.maxY - 10, width: row.width, height: 10)
    var deadline = NativeHostedEvidenceDeadline()
    do {
        try await deadline.awaitResponsiveMainActor()
        let start = ContinuousClock.now
        while !done(journey.samples, ContinuousClock.now - start) {
            let image = try nativeHostedImage(host, in: bar)
            let pixels = barPixels(image)
            journey.samples.append((pixels.segment, pixels.track, nativeHostedSignature(image)))
            try deadline.check("\(name) took \(journey.samples.count) bar samples")
            try await deadline.sleep(for: .milliseconds(50))
        }
    } catch let expired as NativeHostedEvidenceExpired {
        nativeHostedRecordExpired(expired)
        return nil
    }
    journey.starved = deadline.starved
    return journey
}

/// Under system or in-app Reduce Motion an unknown total holds a still, empty track for
/// longer than one 1.25 s sweep: no segment, the same frame every time, while VoiceOver
/// still hears that the total isn't known (#22's bar; load-transition R6; HIG Accessibility
/// "reduce automatic and repetitive animation"). A still view can't look still by accident
/// of starvation the wrong way, so the frames are judged strictly.
@MainActor
@Test(arguments: [(system: true, app: false), (system: false, app: true)])
func serviceInfoIndeterminateBarHoldsStillUnderReduceMotion(setting: (system: Bool, app: Bool)) async throws {
    let name = "service-info-indeterminate-reduce-motion-\(setting.system ? "system" : "app")"
    guard let journey = try await indeterminateBarJourney(
        system: setting.system, app: setting.app, name: name,
        done: { samples, elapsed in samples.count >= 8 && elapsed >= .milliseconds(1_400) }
    ) else { return }
    let samples = journey.samples
    #expect(!journey.sweepMounted, "sweep mounted under Reduce Motion")
    #expect(samples.allSatisfy { $0.segment == 0 }, "segment drawn: \(samples.map(\.segment))")
    #expect(samples.allSatisfy { $0.track > 0 }, "track missing: \(samples.map(\.track))")
    #expect(Set(samples.map(\.signature)).count == 1, "bar moved under Reduce Motion")
    #expect(journey.phase.role == "AXStaticText")
    #expect(journey.phase.label == ServiceInfoRows.make(try serviceInfoIndeterminateSnapshot()).phaseTitle)
    #expect(journey.phase.value == ServiceInfoText.progressIndeterminate)
    #expect(progressRoles.isDisjoint(with: journey.reachable), "\(journey.reachable)")
}

/// Every indeterminate sweep host under `view` (the AppKit side of `ServiceProgressSweep`).
@MainActor
private func sweepViews(in view: NSView) -> [ServiceProgressSweepView] {
    (view as? ServiceProgressSweepView).map { [$0] } ?? view.subviews.flatMap(sweepViews(in:))
}

/// The one running sweep under `host`, or nil when none is mounted or it isn't animating.
@MainActor
private func runningSweep(in host: NSView) -> CAAnimation? {
    host.layoutSubtreeIfNeeded()
    let views = sweepViews(in: host)
    guard views.count == 1, let view = views.first else { return nil }
    return view.segmentLayer.animation(forKey: ServiceProgressSweepView.animationKey)
}

/// The contrast case: with motion allowed the same card mounts the render-server sweep and
/// it is animating, so the still track above is Reduce Motion's doing and not a bar that
/// never sweeps; VoiceOver still hears the unknown total and never reaches the bar.
@MainActor
@Test func serviceInfoIndeterminateBarSweepsWithMotion() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 402, height: 400)
    let host = nativeHostedView(
        SettingsServiceInfoSection(session: session, isVisible: false, initialPhase: try serviceInfoIndeterminateSnapshot())
            .environment(\._accessibilityReduceMotion, false)
            .environment(\.scenePhase, .active)
            .padding(16)
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: [ServiceInfoText.progressIndeterminate])
    let animation = try #require(runningSweep(in: host), "no running sweep")
    #expect((animation as? CAKeyframeAnimation)?.keyPath == "transform.translation.x")
    #expect(animation.repeatCount == .infinity)
    let nodes = macAccessibilityTree(host)
    let phase = try #require(nodes.first { $0.identifier == phaseID })
    #expect(phase.role == "AXStaticText")
    #expect(phase.value == ServiceInfoText.progressIndeterminate)
    #expect(progressRoles.isDisjoint(with: reachableRoles(host)), "\(reachableRoles(host))")
}

// MARK: - Sweep survives polls, re-hosting, tab switches and determinate phases (issue #556)

/// State the #556 journey drives: the bar's percent, the selected tab and a poll counter
/// that re-renders the card as each 5 s service-info read does.
@MainActor
@Observable
private final class SweepHarness {
    var percent: Double?
    var tab = 0
    var poll = 0
}

/// The bar inside a two-tab `TabView`, so switching away and back hides and shows it with
/// its state kept, like leaving Settings for another tab.
private struct SweepHarnessView: View {
    let harness: SweepHarness

    var body: some View {
        @Bindable var harness = harness
        TabView(selection: $harness.tab) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Poll \(harness.poll)")
                ServiceProgressBar(percent: harness.percent, reduceMotion: false)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .tabItem { Text("Settings") }
            .tag(0)
            Text("Songs tab")
                .tabItem { Text("Songs") }
                .tag(1)
        }
    }
}

/// With motion allowed, an unknown total keeps its sweep through everything the Settings
/// card lives through (issue #556: on iPhone the one-shot `repeatForever` sweep was dropped
/// when the lazily hosted card was realized or re-hosted, and the bar never moved):
/// - a poll re-renders the card without restarting the sweep;
/// - leaving the window drops the layer's animation and re-entering re-adds it;
/// - switching to another tab and back leaves a running sweep;
/// - a determinate phase shows only the fill (no sweep), and an unknown total again sweeps.
@MainActor
@Test func serviceInfoIndeterminateBarKeepsSweepingThroughPollsAndRehosting() async throws {
    let harness = SweepHarness()
    let size = CGSize(width: 402, height: 240)
    let host = nativeHostedView(
        SweepHarnessView(harness: harness)
            .environment(\._accessibilityReduceMotion, false)
            .environment(\.scenePhase, .active)
            .frame(width: size.width, height: size.height)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["Poll 0"])
    let first = try #require(runningSweep(in: host), "no sweep on first appearance")

    harness.poll += 1
    try await nativeHostedSettle(host, untilText: ["Poll 1"])
    let afterPoll = try #require(runningSweep(in: host), "sweep dropped by a poll")
    #expect(afterPoll.beginTime == first.beginTime, "a poll restarted the sweep")

    let sweepView = try #require(sweepViews(in: host).first)
    window.contentView = nil
    #expect(sweepView.segmentLayer.animation(forKey: ServiceProgressSweepView.animationKey) == nil)
    window.contentView = host
    #expect(runningSweep(in: host) != nil, "sweep not re-added after re-hosting")

    harness.tab = 1
    try await nativeHostedSettle(host, untilText: ["Songs tab"])
    harness.tab = 0
    try await nativeHostedSettle(host, untilText: ["Poll 1"])
    #expect(runningSweep(in: host) != nil, "sweep missing after returning from another tab")

    harness.percent = 42
    try await nativeHostedSettle(host, untilText: ["Poll 1"])
    #expect(sweepViews(in: host).isEmpty, "a determinate bar kept the sweep")

    harness.percent = nil
    try await nativeHostedSettle(host, untilText: ["Poll 1"])
    #expect(runningSweep(in: host) != nil, "no sweep after the total became unknown again")
}
#endif
