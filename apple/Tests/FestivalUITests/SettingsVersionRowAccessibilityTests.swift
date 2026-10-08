#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Settings → Version accessibility (issue #387, for #3's App Version commit)
//
// #3 appended the release commit to Settings → App Version (`0.1.0 (42) · 42edc57`). These
// tests pin what VoiceOver and large text get from that region: each Version row is one
// static-text element read title → value (pattern `settings-value-row` R3), the App Version
// value names its build and commit instead of reading the parentheses and `·`, the rows read
// in visual order, and the value stacks under the title instead of squeezing it when the
// row is too narrow (R1). macOS hosting does not scale Dynamic Type, so large text is
// reproduced with a column narrower than the title, gap and value (the fit rule is
// width-based, so this is the same decision AX5 makes on an iPhone).

private var stampedInfo: [String: Any] { [
    "CFBundleShortVersionString": "2610.08.01", "CFBundleVersion": "42",
    AppBuildInfo.gitSHAKey: "42edc57a1b2c3d4e5f60718293a4b5c6d7e8f901",
] }

/// Host `content` in an offscreen window and return its settled accessibility tree.
@MainActor
private func versionTree<Content: View>(
    _ content: Content, size: CGSize, until texts: [String], name: String
) async throws -> [MacAXNode] {
    let host = nativeHostedView(
        content
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(BrandTokens.cardBackground)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: texts)
    let nodes = macAccessibilityTree(host)
    macAccessibilityDump(nodes, name: name)
    return nodes
}

/// Fitted height of `view` when offered `width`.
@MainActor
private func fittedSize<Content: View>(_ view: Content, width: CGFloat) -> CGSize {
    NSHostingController(rootView: view.preferredColorScheme(.dark))
        .sizeThatFits(in: CGSize(width: width, height: 10_000))
}

// MARK: - Labels, roles and values

@MainActor
@Test func appVersionRowIsOneStaticTextNamingBuildAndCommit() async throws {
    let nodes = try await versionTree(
        SettingsAppVersionRow(info: stampedInfo).padding(16), size: CGSize(width: 402, height: 200),
        until: ["App Version"], name: "app-version-stamped"
    )
    let row = try #require(nodes.first { $0.identifier == "fst.settings.app-version" })
    #expect(row.isElement)
    #expect(row.role == "AXStaticText")
    #expect(row.label == "App Version")
    #expect(row.value == "2610.08.01, build 42, commit 42edc57")
    // One element: neither the title nor the printed value is read again on its own.
    let elements = nodes.filter { $0.isElement && !$0.spokenName.isEmpty }
    #expect(elements.count == 1, "\(elements)")
    #expect(!elements.contains { $0.spokenName.contains("·") || $0.value.contains("·") })
    #expect(macAccessibilityFindings(nodes).isEmpty)
}

@MainActor
@Test func unstampedAppVersionRowReadsNoCommit() async throws {
    var dev = stampedInfo
    dev[AppBuildInfo.gitSHAKey] = "dev"
    let nodes = try await versionTree(
        SettingsAppVersionRow(info: dev).padding(16), size: CGSize(width: 402, height: 200),
        until: ["App Version"], name: "app-version-dev"
    )
    let row = try #require(nodes.first { $0.identifier == "fst.settings.app-version" })
    #expect(row.value == "2610.08.01, build 42")
}

// MARK: - Reading order

@MainActor
@Test func versionSectionReadsEachRowOnceInVisualOrder() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let storage = UserDefaults(suiteName: "fst.tests.settings-version.\(UUID().uuidString)")!
    let nodes = try await versionTree(
        NavigationStack { SettingsScreen(session: session, topic: .version) }.defaultAppStorage(storage),
        size: CGSize(width: 402, height: 700), until: ["App Version", "Unavailable"],
        name: "version-section"
    )
    let order = ["fst.settings.app-version", "fst.settings.build", "fst.settings.service-version", "fst.settings.whats-new"]
    let found = nodes.filter { order.contains($0.identifier) }.map(\.identifier)
    #expect(found == order)
    let build = try #require(nodes.first { $0.identifier == "fst.settings.build" })
    #expect(build.role == "AXStaticText" && build.label == "Build Configuration" && build.value == "Debug")
    let service = try #require(nodes.first { $0.identifier == "fst.settings.service-version" })
    #expect(service.role == "AXStaticText" && service.label == "Service Version" && service.value == "Unavailable")
    // No row title is also exposed as a separate text element.
    for title in ["App Version", "Build Configuration", "Service Version"] {
        #expect(nodes.filter { $0.isElement && $0.spokenName == title }.count == 1, "\(title) read more than once")
    }
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
}

// MARK: - Text scaling (fit rule)

@MainActor
@Test func appVersionValueStaysBesideTheTitleWhenItFits() async throws {
    let row = SettingsAppVersionRow(info: stampedInfo)
    let wide = fittedSize(row, width: 370)
    let titleOnly = fittedSize(Text("App Version").font(.body.weight(.semibold)), width: 370)
    #expect(wide.width <= 370)
    // One line: the value sits beside the title rather than under it.
    #expect(wide.height < titleOnly.height * 1.5, "inline row \(wide) vs one line \(titleOnly)")
}

@MainActor
@Test(arguments: [CGFloat(220), 150, 110])
func appVersionValueStacksAndWrapsInANarrowColumn(_ width: CGFloat) async throws {
    let row = SettingsAppVersionRow(info: stampedInfo)
    let narrow = fittedSize(row, width: width)
    let titleOnly = fittedSize(Text("App Version").font(.body.weight(.semibold)), width: 370)
    let value = fittedSize(Text(AppBuildInfo.versionText(stampedInfo)), width: 10_000)
    #expect(value.width > width - SettingsValueRowLayout.inlineGap - titleOnly.width, "fixture must not fit inline")
    #expect(narrow.width <= width, "row overflows its column: \(narrow)")
    // Title, 4 pt, then the whole value (wrapped, never truncated) under it.
    let valueWrapped = fittedSize(Text(AppBuildInfo.versionText(stampedInfo)), width: width)
    #expect(abs(narrow.height - (titleOnly.height + SettingsValueRowLayout.stackSpacing + valueWrapped.height)) < 1)

    // The stacked row stays one element with the full spoken value.
    let nodes = try await versionTree(row, size: CGSize(width: width, height: 300), until: ["App Version"], name: "app-version-narrow-\(Int(width))")
    let element = try #require(nodes.first { $0.identifier == "fst.settings.app-version" })
    #expect(element.value == "2610.08.01, build 42, commit 42edc57")
}

@Test func valueRowFitRuleCountsTitleGapAndValue() {
    #expect(SettingsValueRowLayout.fitsInline(titleWidth: 100, valueWidth: 188, available: 300))
    #expect(!SettingsValueRowLayout.fitsInline(titleWidth: 100, valueWidth: 189, available: 300))
    #expect(SettingsValueRowLayout.fitsInline(titleWidth: 500, valueWidth: 500, available: nil))
    #expect(SettingsValueRowLayout.fitsInline(titleWidth: 500, valueWidth: 500, available: .infinity))
    #expect(SettingsValueRowLayout.inlineGap == 12 && SettingsValueRowLayout.stackSpacing == 4)
}

@Test func valueRowLabelReadsTitleThenSupportingText() {
    #expect(SettingsValueRowLayout.spokenLabel(title: "App Version", detail: nil) == "App Version")
    #expect(SettingsValueRowLayout.spokenLabel(title: "App Version", detail: "") == "App Version")
    #expect(
        SettingsValueRowLayout.spokenLabel(title: "Leaderboard Service State", detail: "Loading")
            == "Leaderboard Service State, Loading"
    )
}

// MARK: - Service Info state row (same component)

@MainActor
@Test func serviceInfoStateRowIsOneStaticTextReadTitleDescriptionState() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let nodes = try await versionTree(
        SettingsServiceInfoSection(session: session, isVisible: false, initialPhase: .failed).padding(16),
        size: CGSize(width: 402, height: 300), until: ["Leaderboard Service State"], name: "service-info-state"
    )
    let row = try #require(nodes.first { $0.identifier == "fst.settings.service-info.state" })
    #expect(row.isElement && row.role == "AXStaticText")
    #expect(row.label == "Leaderboard Service State, Failed to load")
    #expect(row.value == ServiceProcessState.stopped.label)
}
#endif
