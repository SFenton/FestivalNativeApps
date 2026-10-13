#if os(macOS)
import AppKit
import FestivalCore
import FestivalDesign
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Accessibility of the sheet-header fade (issue #447, for #94)

// Issue #94 (PR #182) made sheet content scroll under a glass-free sheet header and fade
// to clear before it (``ModalTopEdgeFadeModifier``). These tests cover what that change
// means for assistive technologies on the hosted macOS tree: the mask adds nothing
// readable, rows faded under the header keep their names, roles and order, and every
// transparency/contrast setting turns the ramp into a hard edge. Title, Close, Dynamic
// Type and target size on iPhone are covered by `ModalHeaderAccessibilityJourneyTests`.

/// Roles that only structure the tree and are never read on their own, including the
/// system scroller's value indicator.
private let structuralRoles: Set<String> = [
    "AXGroup", "AXScrollArea", "AXScrollBar", "AXOutline", "AXList", "AXValueIndicator",
]

/// The system scroller's arrow and page parts, named by their role description.
private let scrollerSubroles: Set<String> = ["AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage"]

/// What VoiceOver reads for one element: role, spoken name and identifier.
private struct ReadableNode: Equatable, CustomStringConvertible {
    let role: String
    let name: String
    let identifier: String

    var description: String { "\(role) '\(name)' #\(identifier)" }
}

/// The readable (non-structural) elements of `host`, in tree order.
@MainActor
private func readableNodes(_ host: NSView, navigationOrder: Bool = false) -> [ReadableNode] {
    macAccessibilityTree(host, navigationOrder: navigationOrder)
        .filter { $0.isElement && !structuralRoles.contains($0.role) && !scrollerSubroles.contains($0.subrole) }
        .map { ReadableNode(role: $0.role, name: $0.spokenName, identifier: $0.identifier) }
}

/// The harness's main scroll view: the largest one whose document runs past its height.
@MainActor
private func fadeScrollView(in view: NSView) -> NSScrollView? {
    var best: NSScrollView?
    func walk(_ view: NSView) {
        if let scroll = view as? NSScrollView, let document = scroll.documentView,
           document.frame.height > scroll.contentView.bounds.height + 100,
           scroll.frame.height > (best?.frame.height ?? 0) {
            best = scroll
        }
        view.subviews.forEach(walk)
    }
    walk(view)
    return best
}

/// Scroll so `offset` points of content sit above the resting top, and settle.
@MainActor
@discardableResult
private func fadeScroll(
    _ scrollView: NSScrollView, to offset: CGFloat, host: NSHostingView<some View>
) async throws -> CGImage {
    let clip = scrollView.contentView
    let documentHeight = scrollView.documentView?.frame.height ?? 0
    let top = offset - scrollView.contentInsets.top
    let y = clip.isFlipped ? top : documentHeight - top - clip.bounds.height
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
    return try await nativeHostedSettle(host)
}

/// Mean brightness (0–255) of the middle half of a horizontal strip, in host points.
private func stripBrightness(fromY minY: CGFloat, toY maxY: CGFloat, of image: CGImage, hostSize: CGSize) -> Double {
    let pixels = NativeHostedPixels(image)
    let scale = CGFloat(pixels.width) / hostSize.width
    let rows = max(0, Int(minY * scale))..<min(pixels.height, Int(maxY * scale))
    let columns = Int(hostSize.width * scale * 0.25)..<Int(hostSize.width * scale * 0.75)
    return pixels.withBytes { bytes in
        var total = 0.0, count = 0.0
        for y in rows {
            for x in columns {
                let pixel = (y * pixels.width + x) * 4
                total += Double(Int(bytes[pixel]) + Int(bytes[pixel + 1]) + Int(bytes[pixel + 2])) / 3
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }
}

// MARK: - Harnesses

/// A sheet body of a heading and named buttons, with or without the sheet-header fade.
private struct ReadableFadeHarness: View {
    let faded: Bool

    var body: some View {
        let content = ScrollView {
            VStack(spacing: 0) {
                Text("Fixture Section")
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                ForEach(0..<30, id: \.self) { index in
                    Button("Fixture Row \(index)") {}
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier("fst.tests.modalFade.row.\(index)")
                }
            }
        }
        .background(Color.black)
        if faded {
            content.modifier(ModalTopEdgeFadeModifier())
        } else {
            content
        }
    }
}

/// A setting that turns the sheet-header ramp into a hard edge (scroll-edge R7).
enum ModalFadeHardEdgeSetting: String, CaseIterable, CustomTestStringConvertible, Sendable {
    case none
    case systemReduceTransparency
    case systemIncreaseContrast
    case appLessTransparency
    case appMoreContrast

    var testDescription: String { rawValue }
}

/// White rows under the sheet-header fade on black, with one hard-edge setting applied.
private struct HardEdgeFadeHarness: View {
    let setting: ModalFadeHardEdgeSetting
    let defaults: UserDefaults

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<60, id: \.self) { _ in
                    Color.white.frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                }
            }
        }
        .modifier(ModalTopEdgeFadeModifier())
        .background(Color.black)
        .environment(\._accessibilityReduceTransparency, setting == .systemReduceTransparency)
        .environment(\._colorSchemeContrast, setting == .systemIncreaseContrast ? .increased : .standard)
        .defaultAppStorage(defaults)
    }
}

// MARK: - Tests

/// The fade is a mask with hidden geometry readers: VoiceOver reads the same elements,
/// names and order with it as without it, at rest and with content under the header.
@MainActor
@Test
func modalTopFadeAddsNothingReadable() async throws {
    let size = CGSize(width: 420, height: 640)
    var trees: [[ReadableNode]] = []
    for faded in [false, true] {
        let host = nativeHostedView(
            ReadableFadeHarness(faded: faded).frame(width: size.width, height: size.height),
            size: size, forceGlassFallback: false
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Fixture Section"])
        let rest = readableNodes(host)
        let scrollView = try #require(fadeScrollView(in: host))
        try await fadeScroll(scrollView, to: 400, host: host)
        let scrolled = readableNodes(host)
        #expect(rest == scrolled, "scrolling under the header (faded: \(faded)) removes or reorders nothing")
        let findings = macAccessibilityFindings(macAccessibilityTree(host))
        #expect(findings.isEmpty, "\(findings)")
        trees.append(scrolled)
    }
    #expect(trees[0] == trees[1], "the fade adds or hides readable elements:\n\(trees[0])\n\(trees[1])")
    #expect(trees[1].first == ReadableNode(role: "AXHeading", name: "Fixture Section", identifier: ""))
    #expect(trees[1].filter { $0.role == "AXButton" }.count == 30)
}

/// Notifications (the issue's sheet): every row keeps its name, button role and
/// identifier, in visual order, when it scrolls under the faded header, and the
/// "Older" heading still separates the sections. The pinned "New" heading moves in
/// AppKit's tree order as it pins, so only its presence is asserted.
@MainActor
@Test
func notificationsRowsStayReadableUnderTheSheetHeader() async throws {
    let (session, accountId) = await scrollingNotificationsSession(newCount: 8, olderCount: 24)
    defer { forgetScrollingAccount(accountId) }
    let size = CGSize(width: 420, height: 640)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["New"])
    let rowPrefix = "fst.notifications.row.\(accountId)-"

    func check(_ nodes: [ReadableNode], _ state: String) {
        let rows = nodes.filter { $0.identifier.hasPrefix(rowPrefix) }
        // The List realizes rows lazily; those it realized, including every row scrolled
        // under the header, are read from the first one in visual order.
        let expectedRows = (0..<rows.count).map { "\(rowPrefix)\($0)" }
        #expect(rows.count >= 20, "rows \(state): only \(rows.count) realized")
        #expect(rows.map(\.identifier) == expectedRows, "rows \(state) are all read, in visual order")
        #expect(rows.allSatisfy { $0.role == "AXButton" }, "rows \(state) are buttons")
        #expect(rows.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }, "rows \(state) are named")
        #expect(nodes.contains { $0.role == "AXHeading" && $0.name == "New" }, "New heading \(state)")
        let withoutNew = nodes.filter { !($0.role == "AXHeading" && $0.name == "New") }
        let older = withoutNew.firstIndex { $0.role == "AXHeading" && $0.name == "Older" }
        let lastNew = withoutNew.firstIndex { $0.identifier == "\(rowPrefix)7" }
        let firstOlder = withoutNew.firstIndex { $0.identifier == "\(rowPrefix)8" }
        #expect(older != nil && lastNew != nil && firstOlder != nil && lastNew! < older! && older! < firstOlder!,
                "Older heading \(state) is read between the sections")
    }

    let rest = readableNodes(host, navigationOrder: true)
    check(rest, "at rest")
    let scrollView = try #require(listScrollView(in: host))
    let clip = scrollView.contentView
    clip.scroll(to: NSPoint(x: 0, y: 400 - scrollView.contentInsets.top))
    scrollView.reflectScrolledClipView(clip)
    try await nativeHostedSettle(host)
    let scrolled = readableNodes(host, navigationOrder: true)
    check(scrolled, "under the header")
    let tree = macAccessibilityTree(host, navigationOrder: true)
    #expect(macAccessibilityFindings(tree).isEmpty, "\(macAccessibilityFindings(tree))")
    macAccessibilityDump(tree, name: "modal-fade-notifications-scrolled")

    // Visible rows keep at least macOS's 28 pt control size (HIG Accessibility).
    for index in 8..<12 {
        let frame = try #require(nativeHostedAccessibilityFrame("\(rowPrefix)\(index)", in: host))
        #expect(frame.height >= 28, "row \(index) is \(frame.height) pt tall")
    }
}

/// Reduce Transparency and Increase Contrast, from the system or the app's Accessibility
/// settings, turn the sheet-header ramp into a hard edge (scroll-edge R7): with content
/// scrolled under the header, rows are drawn fully up to it instead of fading out.
@MainActor
@Test(arguments: ModalFadeHardEdgeSetting.allCases)
func modalTopFadeIsAHardEdgeUnderTransparencyAndContrastSettings(setting: ModalFadeHardEdgeSetting) async throws {
    let suite = "fst.tests.modalFadeHardEdge.\(setting.rawValue).\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(setting == .appLessTransparency, forKey: "fst.accessibility.lessTransparency")
    defaults.set(setting == .appMoreContrast, forKey: "fst.accessibility.moreContrast")
    let size = CGSize(width: 420, height: 640)
    let host = nativeHostedView(
        HardEdgeFadeHarness(setting: setting, defaults: defaults).frame(width: size.width, height: size.height),
        size: size, forceGlassFallback: false
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host)
    let scrollView = try #require(fadeScrollView(in: host))
    let scrolled = try await fadeScroll(scrollView, to: 400, host: host)
    let edge = stripBrightness(fromY: 1, toY: 5, of: scrolled, hostSize: size)
    if setting == .none {
        #expect(edge < 60, "content fades out under the header by default (\(edge))")
    } else {
        #expect(edge > 240, "\(setting.rawValue) draws content fully up to the header (\(edge))")
    }
    #expect(stripBrightness(fromY: 44, toY: 60, of: scrolled, hostSize: size) > 240, "opaque past the ramp")
}
#endif
