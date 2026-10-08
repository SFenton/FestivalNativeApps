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
#endif
