#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Reload gate accessibility (issue #71, backfilled by #431)

// #71 gave every reloading Apple page the web's load and reload sequence through one
// component, ``FestivalReloadGate`` (sequence: FestivalCore ``ReloadTransition``, unit
// tested in `ReloadTransitionTests`). These hosted checks (macOS host, `apple-ci`) pin
// what that sequence exposes to VoiceOver, Voice Control and Dynamic Type on every Apple
// platform, since the gate is the same SwiftUI on iPhone, iPad, iPhone Duo and Mac:
// one named spinner and no stale rows while loading, selectors that stay named, selected
// and pressable outside the gate, a retained header that stays readable, visual reading
// order after the reveal, 44 pt selector targets, text that grows whole at AX5 with the
// selectors still reachable and operable, and Reduce Motion's instant swap that still
// holds the spinner for its minimum (pattern `load-transition` R2, R4, R6).

// MARK: - Fixture

/// Fixture text at the iOS Dynamic Type point size for the environment's size.
///
/// HIG Typography: "macOS doesn't support Dynamic Type", so on this macOS host a text
/// style (and `@ScaledMetric`) renders the same at AX5 as at Large. The fixture reads the
/// environment's `dynamicTypeSize` **where it is drawn** (inside the gate for the header
/// and rows) and applies the HIG's iOS size table, so a gate that clamped Dynamic Type
/// or clipped its grown content fails the measured glyph growth here, as it would on
/// iPhone and iPad.
struct ReloadGateA11yText: View {
    /// The iOS text style the fixture stands in for.
    enum Style {
        /// Title 2, bold (the song leaderboard's header).
        case title2
        /// Body (rows and selectors).
        case body
    }

    let text: String
    let style: Style
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// HIG Typography, "iOS, iPadOS Dynamic Type sizes" (xS…xxxL, then AX1…AX5).
    private static let sizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]
    private static let title2Points: [CGFloat] = [19, 20, 21, 22, 24, 26, 28, 34, 39, 44, 50, 56]
    private static let bodyPoints: [CGFloat] = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]

    /// The iOS point size of `style` at `size`.
    ///
    /// - Parameters:
    ///   - style: The text style.
    ///   - size: A Dynamic Type size.
    /// - Returns: Its point size from the HIG table.
    static func points(_ style: Style, _ size: DynamicTypeSize) -> CGFloat {
        let index = sizes.firstIndex(of: size) ?? 3
        return (style == .title2 ? title2Points : bodyPoints)[index]
    }

    var body: some View {
        Text(text)
            .font(.system(size: Self.points(style, dynamicTypeSize), weight: style == .title2 ? .bold : .regular))
    }
}

/// What a page around the gate selects and whether its data is loading.
@MainActor @Observable
final class ReloadGateA11yModel {
    /// The selected option (an instrument, metric or page); a change reloads.
    var key = 0
    /// Whether the data for ``key`` is loading.
    var isLoading = true

    /// Choose an option the way a page's selector does: the new key and its request
    /// start in the same update.
    ///
    /// - Parameter option: The option's index.
    func select(_ option: Int) {
        key = option
        isLoading = true
    }
}

/// A page shaped like the gate's consumers: a selector row above the gate (Leaderboards'
/// instrument picker, Shop's view mode), and gated rows that read the **live** selection
/// lazily, as the real boards do, so a stale copy would show the new selection's labels.
/// `retainsFrame` uses the song leaderboard's form, whose header shares the rows' scroll
/// view and stays from the first reveal on (issue #316).
struct ReloadGateA11yPage: View {
    let model: ReloadGateA11yModel
    let retainsFrame: Bool

    static let options = ["Lead", "Bass"]
    static let rowCount = 3
    static let spinnerLabel = "Loading leaderboard"
    static let spinnerID = "fst.gate-a11y.loading"
    /// Long enough to wrap at AX5, as long song titles do, so a cut line shows.
    static let headerTitle = "Fixture Song With A Long Encore Title"
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    static let minimumTarget: CGFloat = 44

    /// The selectors' identifiers, in reading order.
    static let optionIDs = options.indices.map { "fst.gate-a11y.option.\($0)" }
    static let headerID = "fst.gate-a11y.header"

    /// The identifier of a row of `option`'s board.
    static func rowID(_ option: Int, _ row: Int) -> String { "fst.gate-a11y.row.\(option).\(row)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Self.options.indices, id: \.self) { index in
                    Button { model.select(index) } label: {
                        ReloadGateA11yText(text: Self.options[index], style: .body)
                            .foregroundStyle(.white)
                            .frame(minWidth: Self.minimumTarget, minHeight: Self.minimumTarget)
                            .contentShape(Rectangle())
                    }
                        .accessibilityAddTraits(model.key == index ? .isSelected : [])
                        .accessibilityIdentifier("fst.gate-a11y.option.\(index)")
                }
            }
            if retainsFrame {
                FestivalReloadGate(
                    key: model.key, isLoading: model.isLoading,
                    spinnerLabel: Self.spinnerLabel, spinnerIdentifier: Self.spinnerID
                ) { reveal in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ReloadGateA11yText(text: Self.headerTitle, style: .title2)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("fst.gate-a11y.header")
                            if reveal.showsResult { rows }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                FestivalReloadGate(
                    key: model.key, isLoading: model.isLoading,
                    spinnerLabel: Self.spinnerLabel, spinnerIdentifier: Self.spinnerID
                ) {
                    if !model.isLoading {
                        ScrollView { rows.frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
            }
        }
        .buttonStyle(.borderless)
    }

    /// Rows that read the live selection when built (`LazyVStack`, like the boards).
    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(0..<Self.rowCount, id: \.self) { row in
                ReloadGateA11yText(text: "\(Self.options[model.key]) rank \(row + 1)", style: .body)
                    .accessibilityIdentifier(Self.rowID(model.key, row))
            }
        }
    }
}

// MARK: - Tests

/// Accessibility of the page load and reload sequence #71 added (``FestivalReloadGate``).
///
/// HIG VoiceOver: "be sure to keep labels current as interface and content change";
/// HIG Loading: "Keep it usable while loading"; HIG Accessibility: "When Reduce Motion is
/// on, reduce automatic and repetitive animation" and "Be cautious with fast-moving and
/// blinking effects"; HIG Accessibility: text enlargement "of at least 200%".
@MainActor
@Suite(.serialized)
struct ReloadGateAccessibilityTests {
    /// How a reveal moves: the fades the hosted root turns off, or Reduce Motion from the
    /// system or the in-app setting.
    enum Motion: String, CaseIterable, CustomTestStringConvertible {
        /// Fades off (the hosted default): every step is instant.
        case instant
        /// Fades on, system Reduce Motion.
        case systemReduceMotion
        /// Fades on, the app's own Reduce Motion setting.
        case appReduceMotion
        /// Fades on, no Reduce Motion.
        case animated

        var testDescription: String { rawValue }
    }

    /// One hosted page.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let model: ReloadGateA11yModel
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// The current tree, after one layout pass (no waiting, so no timed step runs).
        func tree() -> [MacAXNode] {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            return macAccessibilityTree(host)
        }
    }

    /// Host the fixture page on a phone-width window.
    ///
    /// - Parameters:
    ///   - retainsFrame: Use the retained-frame gate (song leaderboard header).
    ///   - typeSize: Dynamic Type size for the page.
    ///   - motion: Fade and Reduce Motion settings.
    /// - Returns: The host, its window and model; the first load is still running.
    static func host(
        retainsFrame: Bool = false, typeSize: DynamicTypeSize = .large, motion: Motion = .instant
    ) throws -> Hosted {
        let suiteName = "fst-reload-gate-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let model = ReloadGateA11yModel()
        let size = CGSize(width: 390, height: 700)
        let host = nativeHostedView(
            AnyView(
                ReloadGateA11yPage(model: model, retainsFrame: retainsFrame)
                    .environment(\.festivalFadeInEnabled, motion != .instant)
                    .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
                    .environment(\.dynamicTypeSize, typeSize)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        return Hosted(
            host: host, window: nativeHostedWindow(host, size: size), model: model,
            storage: storage, suiteName: suiteName
        )
    }

    /// Roles that only group or scroll other elements.
    static let containerRoles: Set<String> = ["AXGroup", "AXScrollArea", "AXScrollBar", "AXOpaqueProviderGroup"]

    /// The page's own elements VoiceOver lands on (selectors, header, spinner, rows), in
    /// reading order.
    static func elements(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.isElement && $0.identifier.hasPrefix("fst.gate-a11y.") }
    }

    /// Every element that is not a container: each needs a name.
    static func leaves(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.isElement && !$0.role.isEmpty && !containerRoles.contains($0.role) }
    }

    /// The elements assistive technology reaches from `root` through
    /// `accessibilityChildren` alone (the path VoiceOver walks), unlike
    /// ``macAccessibilityTree(_:)``, which also descends AppKit subviews and so meets
    /// the unexposed `NSProgressIndicator` backing a SwiftUI `ProgressView`.
    static func reachable(_ root: NSView) -> [MacAXNode] {
        var found: [MacAXNode] = []
        var seen = Set<ObjectIdentifier>()
        func read(_ object: NSObject, _ key: String) -> Any? {
            object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
        }
        func string(_ object: NSObject, _ key: String) -> String {
            switch read(object, key) {
            case let text as String: text
            case let number as NSNumber: number.stringValue
            default: ""
            }
        }
        func walk(_ node: Any, depth: Int) {
            guard depth < 90, let object = node as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return }
            if (read(object, "isAccessibilityElement") as? Bool) == true {
                found.append(MacAXNode(
                    depth: depth, role: string(object, "accessibilityRole"), subrole: "",
                    label: string(object, "accessibilityLabel"), title: string(object, "accessibilityTitle"),
                    value: string(object, "accessibilityValue"), identifier: string(object, "accessibilityIdentifier"),
                    selected: false, help: "", isElement: true
                ))
            }
            for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return found
    }

    /// Every busy indicator in `nodes`, named or not.
    static func busyIndicators(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.isElement && $0.role == "AXBusyIndicator" }
    }

    /// The board rows in `nodes`, of any option.
    static func rows(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.identifier.hasPrefix("fst.gate-a11y.row.") }
    }

    /// The spinner elements in `nodes`.
    static func spinners(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.identifier == ReloadGateA11yPage.spinnerID }
    }

    /// Wait until `option`'s rows are in the tree and the spinner has left it.
    static func settleOnRows(_ hosted: Hosted, option: Int, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30), sourceLocation: sourceLocation) {
            let nodes = macAccessibilityTree(hosted.host)
            return rows(nodes).count == ReloadGateA11yPage.rowCount
                && rows(nodes).allSatisfy { $0.identifier.hasPrefix("fst.gate-a11y.row.\(option).") }
                && spinners(nodes).isEmpty
        }
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    // MARK: Measurement

    /// Expect each selector's accessibility frame to be at least a 44×44 pt target lying
    /// wholly on the page (not pushed off it or clipped by the gate below).
    ///
    /// - Parameters:
    ///   - hosted: The hosted page.
    ///   - context: The state being checked, for failure messages.
    static func expectSelectorTargets(
        _ hosted: Hosted, _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        hosted.host.layoutSubtreeIfNeeded()
        let page = hosted.host.bounds.insetBy(dx: -0.5, dy: -0.5)
        for id in ReloadGateA11yPage.optionIDs {
            guard let frame = nativeHostedAccessibilityFrame(id, in: hosted.host) else {
                Issue.record("\(context): \(id) has no accessibility frame", sourceLocation: sourceLocation)
                continue
            }
            let minimum = ReloadGateA11yPage.minimumTarget - 0.5
            #expect(frame.width >= minimum && frame.height >= minimum,
                    "\(context): \(id) is a 44×44 pt target: \(frame)", sourceLocation: sourceLocation)
            #expect(page.contains(frame), "\(context): \(id) lies wholly on the page: \(frame)", sourceLocation: sourceLocation)
        }
    }

    /// Height, in points, of the text ink (bright pixels) inside `rect` of a capture.
    ///
    /// - Parameters:
    ///   - hosted: The hosted page.
    ///   - rect: An element's frame, in the host's top-left points.
    /// - Returns: From the first to the last pixel row holding ink; 0 without ink.
    /// - Throws: An unavailable capture.
    static func inkHeight(_ hosted: Hosted, in rect: CGRect) throws -> CGFloat {
        let image = try nativeHostedImage(hosted.host, in: rect)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn, "capture of \(rect)")
        var first: Int?
        var last = 0
        for y in 0..<height {
            for x in 0..<width {
                let pixel = (y * width + x) * 4
                if Int(bytes[pixel]) + Int(bytes[pixel + 1]) + Int(bytes[pixel + 2]) > 3 * 150 {
                    first = first ?? y
                    last = y
                    break
                }
            }
        }
        guard let first else { return 0 }
        return CGFloat(last - first + 1) * rect.height / CGFloat(height)
    }

    /// The size `text` needs to show whole in `style` at `typeSize`.
    ///
    /// - Parameters:
    ///   - text: The string.
    ///   - style: Its fixture style.
    ///   - typeSize: Dynamic Type size.
    ///   - width: The width it is offered, or nil for one unbounded line.
    /// - Returns: Its ideal size.
    static func idealSize(
        _ text: String, _ style: ReloadGateA11yText.Style, _ typeSize: DynamicTypeSize, width: CGFloat? = nil
    ) -> CGSize {
        NSHostingController(
            rootView: ReloadGateA11yText(text: text, style: style).environment(\.dynamicTypeSize, typeSize)
        ).sizeThatFits(in: CGSize(width: width ?? 10_000, height: 10_000))
    }

    /// The page's texts once option 0 has loaded: the selectors (outside the gate), the
    /// retained header and the rows (inside it).
    static func texts(retainsFrame: Bool) -> [(id: String, text: String, style: ReloadGateA11yText.Style)] {
        let selectors = ReloadGateA11yPage.options.indices.map {
            (id: ReloadGateA11yPage.optionIDs[$0], text: ReloadGateA11yPage.options[$0], style: ReloadGateA11yText.Style.body)
        }
        let header = retainsFrame
            ? [(id: ReloadGateA11yPage.headerID, text: ReloadGateA11yPage.headerTitle, style: ReloadGateA11yText.Style.title2)]
            : []
        let rows = (0..<ReloadGateA11yPage.rowCount).map {
            (id: ReloadGateA11yPage.rowID(0, $0), text: "Lead rank \($0 + 1)", style: ReloadGateA11yText.Style.body)
        }
        return selectors + header + rows
    }

    /// Expect the element `id` showing `text` to have the whole height its text needs at
    /// its width (wrapped, never cut to fewer lines) and to lie wholly on the page.
    static func expectWhole(
        _ hosted: Hosted, _ item: (id: String, text: String, style: ReloadGateA11yText.Style),
        typeSize: DynamicTypeSize, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> CGRect {
        let frame = try #require(nativeHostedAccessibilityFrame(item.id, in: hosted.host),
                                 "\(item.id) has a frame", sourceLocation: sourceLocation)
        let needed = idealSize(item.text, item.style, typeSize, width: frame.width)
        #expect(frame.height >= needed.height - 0.5,
                "\(item.id) is untruncated: \(frame) for \(needed)", sourceLocation: sourceLocation)
        #expect(hosted.host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                "\(item.id) lies wholly on the page: \(frame)", sourceLocation: sourceLocation)
        return frame
    }

    // MARK: First load

    /// While the first load runs the content area is one named spinner: no rows, no
    /// unnamed element, and the selectors above it read first as named buttons with the
    /// current one selected. After the load the spinner leaves the tree and the rows read
    /// top to bottom, after the selectors. Same at the largest accessibility text size.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func firstLoadReadsOneNamedSpinnerThenRowsInOrder(_ typeSize: DynamicTypeSize) async throws {
        let hosted = try Self.host(typeSize: typeSize)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            !Self.spinners(macAccessibilityTree(hosted.host)).isEmpty
        }

        let tree = hosted.tree()
        let loading = Self.elements(tree)
        // One element: the system busy indicator carrying the page's name, not a
        // role-less wrapper beside an unnamed indicator.
        let reachable = Self.reachable(hosted.host)
        let spinner = try #require(Self.busyIndicators(reachable).only,
                                   "one busy indicator:\n\(Self.dump(tree))")
        #expect(Self.busyIndicators(tree).contains { $0.identifier == ReloadGateA11yPage.spinnerID }, "\(Self.dump(tree))")
        #expect(spinner.identifier == ReloadGateA11yPage.spinnerID, "\(spinner)")
        #expect(spinner.label == ReloadGateA11yPage.spinnerLabel, "\(spinner)")
        #expect(Self.rows(tree).isEmpty, "no rows under the first-load spinner:\n\(Self.dump(tree))")
        #expect(Self.leaves(reachable).allSatisfy { !$0.label.isEmpty || !$0.title.isEmpty },
                "nothing unnamed:\n\(Self.dump(reachable))")
        let order = loading.map(\.identifier)
        #expect(order == ["fst.gate-a11y.option.0", "fst.gate-a11y.option.1", ReloadGateA11yPage.spinnerID],
                "selectors, then the spinner:\n\(Self.dump(loading))")
        let options = loading.filter { $0.identifier.hasPrefix("fst.gate-a11y.option.") }
        #expect(options.allSatisfy { $0.role == "AXButton" }, "\(options)")
        #expect(options.map(\.spokenName) == ReloadGateA11yPage.options)
        #expect(options.map(\.selected) == [true, false], "the current selector is selected: \(options)")
        Self.expectSelectorTargets(hosted, "\(typeSize) first load")

        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)
        Self.expectSelectorTargets(hosted, "\(typeSize) loaded")
        let loaded = Self.elements(hosted.tree())
        #expect(Self.spinners(loaded).isEmpty, "the spinner leaves the tree:\n\(Self.dump(loaded))")
        #expect(loaded.map(\.identifier) == ["fst.gate-a11y.option.0", "fst.gate-a11y.option.1"]
            + (0..<ReloadGateA11yPage.rowCount).map { ReloadGateA11yPage.rowID(0, $0) },
            "selectors, then rows in order:\n\(Self.dump(loaded))")
        #expect(Self.rows(loaded).map(\.spokenName) == ["Lead rank 1", "Lead rank 2", "Lead rank 3"])
        let tops = Self.rows(loaded).compactMap { node in
            nativeHostedAccessibilityFrame(node.identifier, in: hosted.host)?.minY
        }
        #expect(tops.count == ReloadGateA11yPage.rowCount && tops == tops.sorted(),
                "reading order follows the rows top to bottom: \(tops)")
    }

    // MARK: Reload

    /// A new selection removes the old rows from the tree in the same update (the
    /// lazily built rows would otherwise read the new instrument over the old board), and
    /// the spinner takes their place. The selectors stay named buttons outside the gate,
    /// the new one selected, and pressing one while the spinner shows restarts the reload
    /// for that choice; only that choice's rows are revealed.
    @Test func reloadDropsStaleRowsAtOnceAndKeepsSelectorsUsable() async throws {
        let hosted = try Self.host()
        defer { hosted.close() }
        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)

        hosted.model.select(1)
        let reloading = Self.elements(hosted.tree())
        #expect(Self.rows(reloading).isEmpty, "no stale or relabelled rows:\n\(Self.dump(reloading))")
        #expect(Self.spinners(reloading).count == 1, "the spinner replaces them:\n\(Self.dump(reloading))")
        #expect(reloading.map(\.identifier) == ["fst.gate-a11y.option.0", "fst.gate-a11y.option.1", ReloadGateA11yPage.spinnerID],
                "\(Self.dump(reloading))")
        #expect(reloading.filter { $0.identifier.hasPrefix("fst.gate-a11y.option.") }.map(\.selected) == [false, true])
        Self.expectSelectorTargets(hosted, "reloading")

        // A newer choice during the spinner: the selector is still pressable.
        let lead = try #require(nativeHostedAccessibilityElement("fst.gate-a11y.option.0", in: hosted.host))
        let press = NSSelectorFromString("accessibilityPerformPress")
        #expect(lead.responds(to: press))
        _ = lead.perform(press)
        #expect(hosted.model.key == 0, "pressing Lead during the reload selects it")
        let restarted = Self.elements(hosted.tree())
        #expect(Self.rows(restarted).isEmpty && Self.spinners(restarted).count == 1, "\(Self.dump(restarted))")
        #expect(restarted.filter { $0.identifier.hasPrefix("fst.gate-a11y.option.") }.map(\.selected) == [true, false])

        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)
        #expect(Self.rows(Self.elements(hosted.tree())).map(\.spokenName) == ["Lead rank 1", "Lead rank 2", "Lead rank 3"])
    }

    /// A refetch of the same selection (a retry, a publication) is also a reload: the
    /// shown rows leave the tree and the named spinner takes their place until it ends.
    @Test func refetchHidesShownRowsBehindTheSpinner() async throws {
        let hosted = try Self.host()
        defer { hosted.close() }
        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)

        hosted.model.isLoading = true
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            !Self.spinners(macAccessibilityTree(hosted.host)).isEmpty
        }
        let reloading = Self.elements(hosted.tree())
        #expect(Self.rows(reloading).isEmpty, "\(Self.dump(reloading))")
        #expect(Self.spinners(reloading).only?.spokenName == ReloadGateA11yPage.spinnerLabel, "\(Self.dump(reloading))")

        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)
    }

    /// The song leaderboard's retained frame: once shown, its header stays in the tree
    /// as a heading through a page reload and reads before the spinner, while only the
    /// rows leave; the new page's rows return after the header. Same at AX5.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func retainedFrameKeepsItsHeadingReadableDuringAReload(_ typeSize: DynamicTypeSize) async throws {
        let hosted = try Self.host(retainsFrame: true, typeSize: typeSize)
        defer { hosted.close() }
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            !Self.spinners(macAccessibilityTree(hosted.host)).isEmpty
        }
        let first = Self.elements(hosted.tree())
        #expect(!first.contains { $0.identifier == "fst.gate-a11y.header" }, "no frame before the first reveal:\n\(Self.dump(first))")
        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)

        hosted.model.select(1)
        let reloading = Self.elements(hosted.tree())
        let header = try #require(reloading.first { $0.identifier == "fst.gate-a11y.header" }, "\(Self.dump(reloading))")
        #expect(header.spokenName == ReloadGateA11yPage.headerTitle, "\(header)")
        #expect(header.role == "AXHeading", "the header stays a heading: \(header)")
        #expect(Self.rows(reloading).isEmpty, "\(Self.dump(reloading))")
        let ids = reloading.map(\.identifier)
        let headerIndex = try #require(ids.firstIndex(of: "fst.gate-a11y.header"))
        let spinnerIndex = try #require(ids.firstIndex(of: ReloadGateA11yPage.spinnerID), "\(Self.dump(reloading))")
        #expect(headerIndex < spinnerIndex, "header, then the spinner:\n\(Self.dump(reloading))")
        Self.expectSelectorTargets(hosted, "\(typeSize) retained-frame reload")

        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 1)
        let shown = Self.elements(hosted.tree()).map(\.identifier)
        #expect(shown == ["fst.gate-a11y.option.0", "fst.gate-a11y.option.1", "fst.gate-a11y.header"]
            + (0..<ReloadGateA11yPage.rowCount).map { ReloadGateA11yPage.rowID(1, $0) }, "\(shown)")
    }

    // MARK: Text scaling

    /// At AX5 every text on the page grows (rendered glyphs over 1.35× their Large
    /// height), the rows and header inside the gate exactly as the selectors outside it,
    /// and each shows whole (no line cut off, nothing off the page). The selectors stay
    /// 44×44 pt targets on the page while the spinner shows and pressing each still
    /// selects it and restarts the reload; the retained header stays whole through it.
    @Test(arguments: [false, true])
    func textGrowsWholeAndSelectorsStayOperableAtAX5(_ retainsFrame: Bool) async throws {
        let texts = Self.texts(retainsFrame: retainsFrame)
        var baseline: [String: CGFloat] = [:]
        do {
            let hosted = try Self.host(retainsFrame: retainsFrame)
            defer { hosted.close() }
            hosted.model.isLoading = false
            try await Self.settleOnRows(hosted, option: 0)
            for item in texts {
                let frame = try Self.expectWhole(hosted, item, typeSize: .large)
                baseline[item.id] = try Self.inkHeight(hosted, in: frame)
            }
        }

        let hosted = try Self.host(retainsFrame: retainsFrame, typeSize: .accessibility5)
        defer { hosted.close() }
        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)
        Self.expectSelectorTargets(hosted, "AX5 shown")
        var grown: [String: CGFloat] = [:]
        for item in texts {
            let frame = try Self.expectWhole(hosted, item, typeSize: .accessibility5)
            let ink = try Self.inkHeight(hosted, in: frame)
            let base = try #require(baseline[item.id])
            #expect(base >= 8 && ink > base * 1.35, "\(item.id) glyphs grow at AX5: \(ink) pt from \(base) pt")
            grown[item.id] = ink
        }
        // "Lead" and "Lead rank 1" share their tallest glyphs: the gate passes the size through.
        let selector = try #require(grown[ReloadGateA11yPage.optionIDs[0]])
        let row = try #require(grown[ReloadGateA11yPage.rowID(0, 0)])
        #expect(abs(selector - row) <= 1.5, "rows in the gate scale as the selectors outside it: \(row) vs \(selector)")
        let lead = try #require(texts.first)
        let leadFrame = try #require(nativeHostedAccessibilityFrame(lead.id, in: hosted.host))
        #expect(leadFrame.width >= Self.idealSize(lead.text, lead.style, .accessibility5).width - 0.5,
                "the selector label keeps its whole line: \(leadFrame)")

        // Operable at AX5: each press reloads behind the named spinner, selectors intact.
        let press = NSSelectorFromString("accessibilityPerformPress")
        let bass = try #require(nativeHostedAccessibilityElement(ReloadGateA11yPage.optionIDs[1], in: hosted.host))
        #expect(bass.responds(to: press))
        _ = bass.perform(press)
        #expect(hosted.model.key == 1, "pressing Bass at AX5 selects it")
        let reloading = Self.elements(hosted.tree())
        #expect(Self.rows(reloading).isEmpty && Self.spinners(reloading).count == 1, "\(Self.dump(reloading))")
        #expect(reloading.filter { $0.identifier.hasPrefix("fst.gate-a11y.option.") }.map(\.selected) == [false, true])
        Self.expectSelectorTargets(hosted, "AX5 reloading")
        if retainsFrame, let header = texts.first(where: { $0.id == ReloadGateA11yPage.headerID }) {
            _ = try Self.expectWhole(hosted, header, typeSize: .accessibility5)
        }
        let leadElement = try #require(nativeHostedAccessibilityElement(ReloadGateA11yPage.optionIDs[0], in: hosted.host))
        _ = leadElement.perform(press)
        #expect(hosted.model.key == 0, "pressing Lead during the AX5 reload selects it")
        let restarted = Self.elements(hosted.tree())
        #expect(restarted.filter { $0.identifier.hasPrefix("fst.gate-a11y.option.") }.map(\.selected) == [true, false])
        Self.expectSelectorTargets(hosted, "AX5 restarted")
        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)
        for item in texts where item.id.hasPrefix("fst.gate-a11y.row.") {
            _ = try Self.expectWhole(hosted, item, typeSize: .accessibility5)
        }
    }

    // MARK: Reduce Motion

    /// With Reduce Motion (system or in-app) the swap has no fades, but the spinner still
    /// stays on screen and in the tree for its 400 ms minimum, so it never blinks for
    /// data that is already there; with motion the reveal also waits for the 500 ms
    /// spinner fade. (Durations are lower bounds, so a slow runner cannot fail them.)
    @Test(arguments: [Motion.systemReduceMotion, .appReduceMotion, .animated])
    func reloadHoldsTheSpinnerForItsMinimum(_ motion: Motion) async throws {
        let hosted = try Self.host(motion: motion)
        defer { hosted.close() }
        hosted.model.isLoading = false
        try await Self.settleOnRows(hosted, option: 0)

        let clock = ContinuousClock()
        let start = clock.now
        hosted.model.select(1)
        hosted.model.isLoading = false
        let reloading = Self.elements(hosted.tree())
        #expect(Self.spinners(reloading).count == 1 && Self.rows(reloading).isEmpty, "\(Self.dump(reloading))")
        try await Self.settleOnRows(hosted, option: 1)
        let elapsed = clock.now - start
        let timing = ReloadTransition.Timing.standard(reduceMotion: motion != .animated)
        #expect(elapsed >= timing.minimumSpinner + timing.spinnerOut, "revealed after \(elapsed)")
    }

    // MARK: A real page

    /// Item Shop's List/Grid switch reloads through the gate: the list rows leave the
    /// tree in the same update, one busy indicator named "Loading Item Shop" stands in
    /// for them for its Reduce Motion minimum, and then the grid's cards return with
    /// their full names and no list rows (the shipped #71 consumer, not the fixture).
    @Test func itemShopViewSwitchReadsOneNamedSpinnerThenTheGrid() async throws {
        let suiteName = "fst-reload-gate-shop-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        storage.set(ShopViewMode.list.rawValue, forKey: "fst.shop.viewMode")
        let transport = HostedShopTransport(
            scenario: .populated, offers: try shopFixtureBytes().offers, catalogue: try shopFixtureBytes().catalogue
        )
        let session = FestivalSession(factory: { try FestivalAPI(transport: transport) })
        let size = CGSize(width: 820, height: 1000)
        let host = nativeHostedView(
            AnyView(
                NavigationStack { ShopScreen(session: session, isVisible: true) }
                    .frame(width: size.width, height: size.height)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
                    .environment(\.horizontalSizeClass, .regular)
                    .environment(\.festivalFadeInEnabled, true)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let listRow = "fst.shop.song.fixture-pulse"
        let card = "fst.shop.external.fixture-pulse"
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityFrame(listRow, in: host) != nil
        }

        let clock = ContinuousClock()
        let start = clock.now
        storage.set(ShopViewMode.grid.rawValue, forKey: "fst.shop.viewMode")
        // Read in the same update, before any timer can run: polling under a loaded main
        // actor can miss the 400 ms spinner entirely.
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let reloading = Self.reachable(host)
        let spinner = try #require(Self.busyIndicators(reloading).only, "\(Self.dump(reloading))")
        #expect(spinner.label == "Loading Item Shop", "\(spinner)")
        #expect(!reloading.contains { $0.identifier.hasPrefix("fst.shop.song.") || $0.identifier.hasPrefix("fst.shop.external.") },
                "no list rows or cards behind the spinner:\n\(Self.dump(reloading))")

        try await nativeHostedSettle(host, timeout: .seconds(30)) {
            nativeHostedAccessibilityFrame(card, in: host) != nil
        }
        #expect(clock.now - start >= ReloadTransition.Timing.standard(reduceMotion: true).minimumSpinner)
        let grid = Self.reachable(host)
        #expect(Self.busyIndicators(grid).isEmpty, "the spinner leaves:\n\(Self.dump(grid))")
        #expect(!grid.contains { $0.identifier.hasPrefix("fst.shop.song.") }, "no list rows:\n\(Self.dump(grid))")
        let named = try #require(grid.first { $0.identifier == card }, "\(Self.dump(grid))")
        #expect(named.label.hasSuffix("Open Official Item Shop") && named.label.contains("Fixture Pulse"), "\(named)")
    }
}

private extension Array {
    /// The single element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
#endif
